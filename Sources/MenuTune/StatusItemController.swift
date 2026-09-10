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
    var isShown: Bool { popover.isShown }
    var onDidShow: (() -> Void)?

    init(model: AppModel) {
        self.model = model
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
        model.onCollapse = { [weak self] in self?.hide() }
        if let button = item.button {
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    @objc private func clicked() {
        model.diagnosticEvent?("menu-click")
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let playback = NSMenuItem(title: model.isPlaying ? "Pausieren" : "Abspielen", action: #selector(togglePlayback), keyEquivalent: "")
            playback.target = self
            playback.isEnabled = !model.queue.items.isEmpty
            menu.addItem(playback)
            let next = NSMenuItem(title: "Nächster Titel", action: #selector(nextTrack), keyEquivalent: "")
            next.target = self
            menu.addItem(next)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "MenuTune beenden", action: #selector(quitApp), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
            hide()
            if let button = item.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else if popover.isShown { hide() }
        else { show() }
    }

    func show() {
        guard !popover.isShown, let button = item.button else { return }
        resize()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        model.diagnosticEvent?("popover-show")
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        popover.performClose(nil)
        removeMonitor()
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
        resize()
        let dark = item.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        item.button?.image = Self.icon(indicator: model.playbackIndicator, dark: dark)
        let title = model.currentItem?.title ?? "MenuTune"
        item.button?.toolTip = "\(title) · \(model.statusText)"
        item.button?.setAccessibilityLabel("MenuTune: \(model.statusText)")
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

    private func resize() {
        let available = item.button?.window?.screen?.visibleFrame.height ?? 800
        let queueHeight = model.queue.items.isEmpty ? 65 : min(150, Double(model.queue.items.count) * 42)
        let noticeHeight = (model.errorMessage == nil ? 0.0 : 80.0) + (model.storageWarning == nil ? 0.0 : 80.0)
            + (model.clipboardSuggestion == nil ? 0.0 : 40.0)
        let height = min(available - 30, 414 + queueHeight + noticeHeight)
        let size = NSSize(width: 448, height: max(400, height))
        if popover.contentSize != size { popover.contentSize = size }
    }

    @objc private func togglePlayback() { model.togglePlayback() }
    @objc private func nextTrack() { model.next() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    func shutdown() {
        hide()
        subscription?.cancel()
        appearanceObservation?.invalidate()
        popover.contentViewController = nil
        NSStatusBar.system.removeStatusItem(item)
    }
}
