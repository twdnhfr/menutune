import AppKit
import Combine
import MenuTuneCore

@MainActor
final class AppModel: ObservableObject {
    enum PlaybackIndicator { case idle, paused, playing }
    @Published var input = ""
    @Published var queue: PlaybackQueue
    @Published var statusText = "Bereit für deine Musik"
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var playbackIndicator: PlaybackIndicator = .idle
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var errorMessage: String?
    @Published var storageWarning: String?
    @Published var shortcutWarning: String?
    @Published var clipboardSuggestion: String?
    @Published var isPoppedOut = false
    @Published var playerSize: PlayerSize {
        didSet { save() }
    }
    @Published var volume: Double {
        didSet {
            player.command("volume", arguments: [volume])
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.save()
            }
        }
    }
    let player = YouTubePlayer()
    var onCollapse: (() -> Void)?
    var onTogglePopOut: (() -> Void)?
    var currentItem: QueueItem? { queue.currentItem }
    var embeddedVideoHeight: Double { isPoppedOut ? 56 : playerSize.videoHeight }
    private let store: LibraryStore
    private var canSave = true
    private var ready = false
    private var token: String?
    private var pendingStart: Double = 0
    private var saveTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var titleTasks: [String: Task<Void, Never>] = [:]
    private var shouldPlay = false
    private var selectionLoaded = false
    private var selectionStarted = false
    private var playbackEnded = false
    private var playerNeedsReload = false
    private var clipboardVersion: Int?
    private var dismissedClipboardVersion: Int?
    var diagnosticEvent: ((String) -> Void)?

    init(fileURL: URL = LibraryStore.defaultFileURL) {
        store = LibraryStore(fileURL: fileURL)
        var snapshot = LibrarySnapshot()
        var loadError: String?
        do { snapshot = try store.load() }
        catch { loadError = error.localizedDescription }
        queue = snapshot.queue
        volume = snapshot.volume
        playerSize = snapshot.playerSize
        if let loadError {
            canSave = false
            storageWarning = "Die gespeicherte Liste konnte nicht gelesen werden. Sie bleibt unverändert; neue Änderungen werden vorerst nicht gespeichert. \(loadError)"
        }
        player.onEvent = { [weak self] in self?.handle($0) }
        player.initialize()
    }

    func addInput(playImmediately: Bool = false) {
        do {
            let id = try YouTubeLink.videoID(from: input)
            let start = YouTubeLink.startSeconds(from: input)
            let item = queue.append(videoID: id)
            input = ""
            errorMessage = nil
            save()
            fetchTitle(for: id)
            if playImmediately { play(item, startSeconds: start) }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Reads only when the user opens the popover, never in a polling loop.
    /// No clipboard content is fetched from YouTube until explicitly accepted.
    func inspectClipboard(_ pasteboard: NSPasteboard = .general) {
        let version = pasteboard.changeCount
        guard version != dismissedClipboardVersion else { clipboardSuggestion = nil; return }
        let suggestion = YouTubeLink.clipboardURL(from: pasteboard.string(forType: .string))
        guard version == pasteboard.changeCount else { clipboardSuggestion = nil; return }
        clipboardVersion = version
        clipboardSuggestion = suggestion
    }

    func acceptClipboardSuggestion() {
        guard let suggestion = clipboardSuggestion,
              let videoID = try? YouTubeLink.videoID(from: suggestion) else { return }
        let knownTitle = queue.items.first(where: { $0.videoID == videoID })?.title
        _ = queue.append(videoID: videoID, title: knownTitle)
        dismissClipboardSuggestion()
        save()
        fetchTitle(for: videoID)
    }

    func dismissClipboardSuggestion() {
        dismissedClipboardVersion = clipboardVersion
        clipboardSuggestion = nil
    }

    func play(_ item: QueueItem) { play(item, startSeconds: 0) }

    func play(_ item: QueueItem, startSeconds: Double) {
        guard queue.select(item.id) else { return }
        token = UUID().uuidString
        pendingStart = startSeconds
        shouldPlay = true
        selectionLoaded = false
        selectionStarted = false
        playbackEnded = false
        currentTime = startSeconds
        duration = 0
        isPlaying = false
        playbackIndicator = .idle
        isLoading = true
        errorMessage = nil
        statusText = "Wird geladen …"
        if ready { loadSelection() }
        else if playerNeedsReload {
            playerNeedsReload = false
            player.reload()
        } else { player.initialize() }
        armLoadingTimeout()
        fetchTitle(for: item.videoID)
        save()
    }

    private func loadSelection() {
        guard shouldPlay, let item = currentItem, let token else { return }
        selectionLoaded = true
        player.command("load", arguments: [["videoID": item.videoID, "token": token,
                                            "startSeconds": pendingStart, "volume": volume]])
    }

    private func prepareSavedSelection() {
        guard token == nil, let item = currentItem else { return }
        let session = UUID().uuidString
        token = session
        selectionLoaded = true
        player.command("cue", arguments: [["videoID": item.videoID, "token": session, "volume": volume]])
    }

    func togglePlayback() {
        if isPlaying || isLoading {
            shouldPlay = false
            loadTask?.cancel()
            isLoading = false
            player.command("pause")
            isPlaying = false
            playbackIndicator = selectionStarted ? .paused : .idle
            statusText = "Pausiert"
        } else if token == nil || errorMessage != nil || !selectionLoaded || playbackEnded || !ready || playerNeedsReload {
            if let item = currentItem ?? queue.items.first { play(item) }
        } else {
            shouldPlay = true
            player.command("play")
            armLoadingTimeout()
        }
    }

    func next() {
        if let item = queue.next(automatic: false) { play(item) }
    }

    func previous() {
        if currentTime > 3 { seek(to: 0) }
        else if let item = queue.previous() { play(item) }
    }

    func remove(_ item: QueueItem) {
        let removingCurrent = item.id == queue.currentItemID
        let wasActive = isPlaying || isLoading
        queue.remove(item.id)
        if removingCurrent {
            stop()
            if wasActive, let next = currentItem { play(next) }
        }
        save()
    }

    func move(_ item: QueueItem, by offset: Int) { queue.move(item.id, by: offset); save() }

    func cycleRepeat() {
        switch queue.repeatMode {
        case .off: queue.repeatMode = .all
        case .all: queue.repeatMode = .one
        case .one: queue.repeatMode = .off
        }
        save()
    }

    func seek(to value: Double) {
        guard value.isFinite, duration > 0 else { return }
        let time = min(max(0, value), duration)
        player.command("seek", arguments: [time])
        currentTime = time
    }

    func openCurrentOnYouTube() {
        guard let item = currentItem,
              let url = URL(string: "https://www.youtube.com/watch?v=\(item.videoID)") else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissError() { errorMessage = nil }

    private func stop() {
        shouldPlay = false
        selectionLoaded = false
        selectionStarted = false
        playbackEnded = false
        token = nil
        loadTask?.cancel()
        player.command("stop")
        isPlaying = false
        playbackIndicator = .idle
        isLoading = false
        currentTime = 0
        duration = 0
        statusText = "Bereit für deine Musik"
    }

    private func handle(_ event: [String: Any]) {
        guard let kind = event["kind"] as? String else { return }
        if kind != "progress" { diagnosticEvent?("event=\(kind) payload=\(event)") }
        switch kind {
        case "ready":
            ready = true
            playerNeedsReload = false
            if shouldPlay { loadSelection() }
            else { prepareSavedSelection() }
        case "resourceError", "networkError", "terminated":
            ready = false
            selectionLoaded = false
            playerNeedsReload = true
            fail(kind == "terminated" ? "Der Player wurde beendet. Mit Play kannst du ihn neu laden." : "YouTube konnte nicht geladen werden. Prüfe deine Internetverbindung und versuche Play erneut.")
        case "commandError":
            fail("Die Wiedergabe konnte nicht gesteuert werden. Bitte versuche Play erneut.")
        default:
            guard let eventToken = event["token"] as? String, eventToken == token else { return }
            switch kind {
            case "progress":
                if let time = event["time"] as? Double, time.isFinite { currentTime = max(0, time) }
                if let length = event["duration"] as? Double, length.isFinite { duration = max(0, length) }
                if selectionStarted, let level = event["volume"] as? Double, level.isFinite,
                   (0...1).contains(level), abs(level - volume) > 0.001 {
                    volume = level
                }
            case "state":
                switch event["state"] as? Int {
                case 1:
                    shouldPlay = true
                    selectionStarted = true
                    playbackEnded = false
                    errorMessage = nil
                    loadTask?.cancel()
                    isPlaying = true; isLoading = false; statusText = "Wird abgespielt"
                    playbackIndicator = .playing
                case 2:
                    shouldPlay = false
                    loadTask?.cancel()
                    isPlaying = false; isLoading = false; statusText = "Pausiert"
                    playbackIndicator = selectionStarted ? .paused : .idle
                case 3:
                    isLoading = true; statusText = "Puffert …"
                    playbackIndicator = .idle
                case 0:
                    isPlaying = false; isLoading = false
                    playbackIndicator = .idle
                    guard shouldPlay, selectionStarted else { return }
                    if let item = queue.next(automatic: true) { play(item) }
                    else { shouldPlay = false; playbackEnded = true; statusText = "Warteschlange beendet"; save() }
                default: break
                }
            case "error":
                let code = event["code"] as? Int ?? 0
                let explanation: String
                switch code {
                case 100: explanation = "Dieses Video ist privat, gelöscht oder nicht verfügbar."
                case 101, 150: explanation = "Dieses Video darf nur direkt auf YouTube abgespielt werden."
                case 153: explanation = "YouTube hat den eingebetteten Player nicht erkannt."
                case 5: explanation = "YouTube konnte dieses Video hier nicht abspielen."
                default: explanation = "Das Video konnte nicht geladen werden."
                }
                fail("\(explanation) (\(code))")
            case "blocked": fail("Drücke direkt im Video auf Play, um die Wiedergabe zu starten.")
            default: break
            }
        }
    }

    private func armLoadingTimeout() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, !self.isPlaying else { return }
            if !self.ready { self.playerNeedsReload = true }
            self.fail("Das Laden dauert ungewöhnlich lange. Versuche Play erneut oder öffne das Video auf YouTube.")
        }
    }

    private func fail(_ message: String) {
        loadTask?.cancel()
        isLoading = false
        isPlaying = false
        playbackIndicator = .idle
        errorMessage = message
        statusText = "Wiedergabe unterbrochen"
    }

    private func save() {
        guard canSave else { return }
        do { try store.save(LibrarySnapshot(queue: queue, volume: volume, playerSize: playerSize)); storageWarning = nil }
        catch { storageWarning = "Deine Liste konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }

    private func fetchTitle(for videoID: String) {
        guard titleTasks[videoID] == nil,
              let item = queue.items.first(where: { $0.videoID == videoID }), item.title == videoID else { return }
        titleTasks[videoID] = Task { [weak self] in
            defer { self?.titleTasks[videoID] = nil }
            var components = URLComponents(string: "https://www.youtube.com/oembed")!
            components.queryItems = [URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
                                     URLQueryItem(name: "format", value: "json")]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 12
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = object["title"] as? String, !title.isEmpty, !Task.isCancelled else { return }
            self?.queue.updateTitle(videoID: videoID, title: String(title.prefix(500)))
            self?.save()
        }
    }

    func shutdown() {
        saveTask?.cancel(); loadTask?.cancel()
        titleTasks.values.forEach { $0.cancel() }
        save()
        player.shutdown()
    }
}
