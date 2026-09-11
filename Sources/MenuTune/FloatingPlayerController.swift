import AppKit
import MenuTuneCore
import QuartzCore

@MainActor
private final class FloatingVideoPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPlayerController {
    private let player: YouTubePlayer
    private let panel = FloatingVideoPanel(contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let host = PlayerWebViewHost()
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var screenNumber: NSNumber?
    private var requestedSize: PlayerSize = .mini
    private var visibleFrame: NSRect?
    private var frames: [NSRect] = []
    private var avoidance = CursorAvoidance()
    private var previousPointer: NSPoint?
    private(set) var isShown = false

    init(player: YouTubePlayer) {
        self.player = player
        panel.title = "MenuTune · Pop-out"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        // The window must never intercept a click intended for the work below it.
        panel.ignoresMouseEvents = true
        host.wantsLayer = true
        host.layer?.cornerRadius = 10
        host.layer?.masksToBounds = true
        panel.contentView = host
    }

    func show(size: PlayerSize, screen: NSScreen?) {
        guard !isShown else { return }
        isShown = true
        requestedSize = size
        screenNumber = Self.number(of: screen)
        avoidance.reset()
        previousPointer = nil
        host.attach(player.webView)
        refreshGeometry(force: true)
        avoidPointer(animated: false)
        panel.orderFrontRegardless()

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.avoidPointer(animated: true) }
        }
        timer.tolerance = 0.01
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry(force: true) }
        }
    }

    func updateSize(_ size: PlayerSize) {
        guard isShown, requestedSize != size else { return }
        requestedSize = size
        refreshGeometry(force: true)
        avoidPointer(animated: false)
    }

    func hide() {
        isShown = false
        timer?.invalidate()
        timer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel.orderOut(nil)
        host.detach()
        previousPointer = nil
        visibleFrame = nil
        frames = []
    }

    /// AppKit identifies a display only through its device description.
    private static func number(of screen: NSScreen?) -> NSNumber? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first { Self.number(of: $0) == screenNumber }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    private func refreshGeometry(force: Bool = false) {
        guard isShown, let screen = currentScreen() else { return }
        guard force || visibleFrame != screen.visibleFrame else { return }
        screenNumber = Self.number(of: screen)
        visibleFrame = screen.visibleFrame
        let available = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let width = min(CGFloat(requestedSize.width), available.width, available.height * 16 / 9)
        guard width > 0 else { return }
        let size = NSSize(width: width, height: width * 9 / 16)
        let right = available.maxX - size.width
        // AppKit screen coordinates start at the bottom left.
        frames = [available.minY, available.midY - size.height / 2, available.maxY - size.height].map {
            NSRect(origin: NSPoint(x: right.rounded(), y: $0.rounded()), size: size)
        }
        avoidance.reset(activeIndex: min(avoidance.activeIndex, frames.count - 1))
        previousPointer = nil
        panel.setFrame(frames[avoidance.activeIndex], display: true)
    }

    private func avoidPointer(animated: Bool) {
        guard isShown else { return }
        refreshGeometry()
        let pointer = NSEvent.mouseLocation
        defer { previousPointer = pointer }
        guard let next = avoidance.nextPosition(frames: frames, pointer: pointer,
            previousPointer: previousPointer, now: ProcessInfo.processInfo.systemUptime) else { return }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frames[next], display: true)
            }
        } else {
            panel.setFrame(frames[next], display: true)
        }
    }

    func shutdown() {
        hide()
        panel.close()
    }
}
