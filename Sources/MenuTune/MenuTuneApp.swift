import AppKit
import MenuTuneCore

@main
enum MenuTuneApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.mainMenu = applicationMenu()
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    /// AppKit dispatches standard editing shortcuts through the responder chain.
    /// A pure status-item app still needs an Edit menu for Command-V in text fields.
    @MainActor private static func applicationMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MenuTune")
        appMenu.addItem(withTitle: "MenuTune beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Rückgängig", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einfügen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var status: StatusItemController?
    private var smokeTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Direct command-line launches should not create a second menu-bar player.
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "de.wdnhfr.menutune")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        let arguments = ProcessInfo.processInfo.arguments
        func argument(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let libraryURL = argument("--library").map { URL(fileURLWithPath: $0) } ?? LibraryStore.defaultFileURL
        let model = AppModel(fileURL: libraryURL)
        let status = StatusItemController(model: model)
        self.model = model
        self.status = status
        if arguments.contains("--smoke-test") {
            model.diagnosticEvent = { Self.log($0) }
        }
        // AppKit must finish launching before attaching the popover to the status
        // item; showing it synchronously can leave an invisible initial player.
        DispatchQueue.main.async { [weak self] in
            if let link = argument("--play-url") {
                status.onDidShow = { [weak self] in
                    status.onDidShow = nil
                    model.input = link
                    model.addInput(playImmediately: true)
                    if arguments.contains("--smoke-test") {
                        self?.smokeTask = Task { await PlaybackSmokeTest.run(model: model, status: status) }
                    }
                }
                status.show()
            } else if model.queue.items.isEmpty {
                status.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        status?.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        smokeTask?.cancel()
        model?.shutdown()
        status?.shutdown()
    }

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
