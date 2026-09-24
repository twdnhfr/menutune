import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private var clickMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?
    private var hotKey: GlobalHotKey?
    private let floating: FloatingPlayerController
    private var previousApplication: NSRunningApplication?
    private var iconState: (AppModel.PlaybackIndicator, Bool)?
    var isShown: Bool { popover.isShown }
    var onDidShow: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        floating = FloatingPlayerController(player: model.player)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 448, height: 580)
        let content = NSHostingController(rootView: PlayerView(model: model))
        popover.contentViewController = content
        model.onCollapse = { [weak self] in self?.hide(restoreFocus: true) }
        model.onTogglePopOut = { [weak self] in self?.togglePopOut() }
        if let button = item.button {
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
        hotKey = GlobalHotKey(action: { [weak self] in
            self?.toggle()
        }, onError: { [weak model] message in
            model?.shortcutWarning = message
        })
        hotKey?.register()
    }

    @objc private func clicked() {
        model.diagnosticEvent?("menu-click")
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            // Without this AppKit re-enables every item during popUp.
            menu.autoenablesItems = false
            let playing = model.isPlaying || model.isLoading
            let playback = NSMenuItem(title: playing ? "Pause" : "Play", action: #selector(togglePlayback), keyEquivalent: "")
            playback.target = self
            playback.isEnabled = !model.queue.items.isEmpty
            menu.addItem(playback)
            let next = NSMenuItem(title: "Next Track", action: #selector(nextTrack), keyEquivalent: "")
            next.target = self
            next.isEnabled = !model.queue.items.isEmpty
            menu.addItem(next)
            menu.addItem(.separator())
            let popOut = NSMenuItem(title: model.isPoppedOut ? "Put Video Back" : "Pop Video Out", action: #selector(togglePopOut), keyEquivalent: "")
            popOut.target = self
            popOut.isEnabled = model.isPoppedOut || model.currentItem != nil
            menu.addItem(popOut)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit MenuTune", action: #selector(quitApp), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
            hide()
            if let button = item.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else { toggle() }
    }

    func toggle() {
        if popover.isShown { hide(restoreFocus: true) }
        else { show() }
    }

    @objc func togglePopOut() {
        if model.isPoppedOut {
            floating.hide()
            model.isPoppedOut = false
            show()
        } else {
            guard model.currentItem != nil else { return }
            model.isPoppedOut = true
            floating.show(size: model.playerSize, screen: item.button?.window?.screen)
            hide(restoreFocus: true)
        }
    }

    func show() {
        guard !popover.isShown, let button = item.button else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        resize()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        model.diagnosticEvent?("popover-show")
        // Showing twice without an intervening hide would strand the old monitor.
        removeMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // The monitor also sees some clicks that land inside the popover
            // itself; closing on those swallows the click.
            guard let self, self.popover.contentViewController?.view.window?.frame
                .contains(NSEvent.mouseLocation) != true else { return }
            self.hide()
        }
    }

    func hide(restoreFocus: Bool = false) {
        let shouldRestore = restoreFocus && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        popover.performClose(nil)
        removeMonitor()
        // Without a live predecessor this accessory app would keep the focus and
        // the user would type into nothing, so hand it on explicitly.
        if shouldRestore {
            if let previousApplication, !previousApplication.isTerminated {
                previousApplication.activate(options: [])
            } else {
                NSApp.deactivate()
            }
        }
        // Intentionally keep both the hosting controller and WKWebView alive.
    }

    func popoverDidClose(_ notification: Notification) {
        model.diagnosticEvent?("popover-close")
        removeMonitor()
    }

    func popoverDidShow(_ notification: Notification) {
        model.diagnosticEvent?("popover-did-show")
        model.inspectClipboard()
        onDidShow?()
    }

    private func removeMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func refresh() {
        floating.updateSize(model.playerSize)
        resize()
        // This runs on every published change, several times per second while a
        // track plays, so nothing here may redraw or reassign unconditionally.
        let dark = item.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if iconState == nil || iconState! != (model.playbackIndicator, dark) {
            iconState = (model.playbackIndicator, dark)
            item.button?.image = Self.icon(indicator: model.playbackIndicator, dark: dark)
        }
        let title = model.currentItem?.title ?? "MenuTune"
        let toolTip = "\(title) · \(model.statusText) · ⌘⇧Y"
        if item.button?.toolTip != toolTip {
            item.button?.toolTip = toolTip
            item.button?.setAccessibilityLabel("MenuTune: \(model.statusText)")
        }
    }

    private static func icon(indicator: AppModel.PlaybackIndicator, dark: Bool) -> NSImage {
        let ink = dark ? NSColor.white : NSColor.black
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
        let waveform = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            waveform?.draw(in: NSRect(x: 1, y: 1, width: 18, height: 16))
            if indicator != .idle {
                let dot = NSBezierPath(ovalIn: NSRect(x: 15.5, y: 0.5, width: 6, height: 6))
                (dark ? NSColor.black : NSColor.white).setStroke()
                dot.lineWidth = 1.5
                dot.stroke()
                (indicator == .playing ? NSColor.systemGreen : NSColor.systemYellow).setFill()
                dot.fill()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "MenuTune"
        return image
    }

    /// The middle section reports its own height, so notices, the queue and the
    /// collapsed state need no duplicated constants here. In the mini size that
    /// section is not rendered and its reported height is zero.
    private func resize() {
        let available = item.button?.window?.screen?.visibleFrame.height ?? 800
        let content = model.showsContentSection ? model.contentHeight : 0
        let natural = model.embeddedVideoHeight + content + PlayerView.bottomBarHeight
        let size = NSSize(width: model.playerSize.width, height: min(available - 30, natural))
        if popover.contentSize != size { popover.contentSize = size }
    }

    @objc private func togglePlayback() { model.togglePlayback() }
    @objc private func nextTrack() { model.next() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func shutdown() {
        floating.shutdown()
        model.onTogglePopOut = nil
        hotKey?.unregister()
        hotKey = nil
        hide()
        subscription?.cancel()
        appearanceObservation?.invalidate()
        popover.contentViewController = nil
        NSStatusBar.system.removeStatusItem(item)
    }
}
