import AppKit
import MenuTuneCore

/// Opt-in live verification, launched only with --smoke-test and --play-url.
/// Writes playback evidence to stderr; never runs during normal app launches.
@MainActor
enum PlaybackSmokeTest {
    static func run(model: AppModel, status: StatusItemController) async {
        func wait(_ seconds: Double) async {
            try? await Task.sleep(for: .seconds(seconds))
        }
        func sample(_ phase: String) async {
            AppDelegate.log("sample phase=\(phase) visible=\(status.isShown) playing=\(model.isPlaying) indicator=\(model.playbackIndicator) time=\(model.currentTime) duration=\(model.duration) error=\(model.errorMessage ?? "none")")
            let state = await withCheckedContinuation { continuation in
                model.player.webView.requestMediaPlaybackState { continuation.resume(returning: $0) }
            }
            AppDelegate.log("media phase=\(phase) state=\(state.rawValue)")
        }
        for _ in 0..<45 {
            if model.isPlaying && model.duration > 0 { break }
            if Task.isCancelled { return }
            await wait(1)
        }
        guard model.isPlaying, model.duration > 0 else {
            await sample("failed-start")
            AppDelegate.log("SMOKE FAIL: playback did not start")
            return
        }
        await sample("visible")
        await wait(5)
        var visibleTime = model.currentTime
        status.hide()
        var hiddenSeconds = 0
        for _ in 0..<24 {
            await wait(5)
            if Task.isCancelled { return }
            if status.isShown {
                hiddenSeconds = 0
                visibleTime = model.currentTime
            } else { hiddenSeconds += 5 }
            await sample("hidden")
            if hiddenSeconds >= 30 { break }
        }
        let hiddenOK = hiddenSeconds >= 30 && model.isPlaying && model.currentTime > visibleTime + 20
        status.show()
        await wait(3)
        await sample("reopened")
        let originalVolume = model.volume
        model.player.command("volume", arguments: [0.12])
        await wait(2)
        let volumeOK = abs(model.volume - 0.12) < 0.01
        model.player.command("volume", arguments: [originalVolume])
        model.togglePlayback()
        await wait(2)
        let pausedTime = model.currentTime
        await wait(3)
        let pauseOK = !model.isPlaying && model.playbackIndicator == .paused && abs(model.currentTime - pausedTime) < 1
        await sample("paused")
        model.togglePlayback()
        await wait(3)
        let resumeOK = model.isPlaying && model.playbackIndicator == .playing && model.currentTime > pausedTime + 1
        // The handoff at the end of a track needs a successor. Queue entries are
        // unique, so this builds a second copy directly, which the interface
        // would refuse, rather than depending on a second video being playable.
        var nextOK = false
        var replayOK = false
        if let first = model.currentItem, model.duration > 15 {
            model.queue.items.append(QueueItem(videoID: first.videoID, title: first.fetchedTitle))
            model.seek(to: model.duration - 4)
            status.hide()
            for _ in 0..<20 {
                await wait(1)
                if model.currentItem?.id != first.id && model.isPlaying && model.currentTime > 1 {
                    nextOK = true
                    break
                }
            }
            nextOK = nextOK && !status.isShown
            await sample("automatic-next-hidden")
            // Leave one copy of the sample in the temporary test library.
            model.remove(first)
            model.seek(to: model.duration - 3)
            for _ in 0..<15 {
                await wait(1)
                if model.statusText == "End of queue" { break }
            }
            // Exercise the embedded player's replay action without native play().
            model.player.command("play")
            for _ in 0..<15 {
                await wait(1)
                if model.isPlaying && model.currentTime > 1 && model.currentTime < 20 {
                    replayOK = true
                    break
                }
            }
            await sample("embedded-replay")
        }
        // Inject the same bridge event as an iframe-script network failure, then
        // recover using a queue-row selection (not the native retry button).
        var recoveryOK = false
        if let item = model.currentItem {
            model.player.command("pause")
            await wait(1)
            _ = try? await model.player.webView.evaluateJavaScript("window.webkit.messageHandlers.menuTune.postMessage({kind:'networkError'})")
            await wait(1)
            model.play(item)
            for _ in 0..<25 {
                await wait(1)
                if model.isPlaying && model.errorMessage == nil && model.currentTime > 1 {
                    recoveryOK = true
                    break
                }
            }
            await sample("simulated-failure-recovery")
        }
        var dismissedRecoveryOK = false
        model.player.command("pause")
        await wait(1)
        _ = try? await model.player.webView.evaluateJavaScript("window.webkit.messageHandlers.menuTune.postMessage({kind:'terminated'})")
        await wait(1)
        model.dismissError()
        model.togglePlayback()
        for _ in 0..<25 {
            await wait(1)
            if model.isPlaying && model.errorMessage == nil && model.currentTime > 1 {
                dismissedRecoveryOK = true
                break
            }
        }
        await sample("dismissed-error-recovery")
        status.show()
        model.seek(to: 3)
        await sample("final")
        AppDelegate.log("SMOKE \(hiddenOK && pauseOK && resumeOK && nextOK && replayOK && recoveryOK && dismissedRecoveryOK && volumeOK ? "PASS" : "FAIL"): hidden=\(hiddenOK) pause=\(pauseOK) resume=\(resumeOK) automaticNext=\(nextOK) embeddedReplay=\(replayOK) recovery=\(recoveryOK) dismissedRecovery=\(dismissedRecoveryOK) nativeVolume=\(volumeOK)")
    }
}
