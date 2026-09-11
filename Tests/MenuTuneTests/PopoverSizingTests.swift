import AppKit
import MenuTuneCore
import SwiftUI
import XCTest
@testable import MenuTune

@MainActor
final class PopoverSizingTests: XCTestCase {
    func testContentHeightFollowsTheRealLayout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTunePopoverSizingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model = AppModel(fileURL: directory.appendingPathComponent("library.json"))

        defer {
            model.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        var queue = PlaybackQueue()
        for index in 0..<3 { _ = queue.append(videoID: "aaaaaaaaaa\(index)", title: "Titel \(index)") }
        model.queue = queue
        model.isQueueExpanded = false

        let hosting = NSHostingView(rootView: PlayerView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: model.playerSize.width, height: 700)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting

        let collapsed = try await settledContentHeight(hosting)
        XCTAssertGreaterThan(collapsed, 60, "Die zugeklappte Ansicht braucht Platz für Titel, Eingabe und Kopfzeile.")
        XCTAssertLessThan(collapsed, 300)

        model.isQueueExpanded = true
        let expanded = try await settledContentHeight(hosting)
        XCTAssertGreaterThan(expanded, collapsed + 40, "Die aufgeklappte Liste muss die gemessene Höhe erhöhen.")
    }

    /// SwiftUI reports the height through a preference, which reaches the model
    /// one main-actor hop later, so the value has to be polled until it rests.
    private func settledContentHeight(_ hosting: NSHostingView<PlayerView>) async throws -> Double {
        var previous = Double.nan
        for _ in 0..<60 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            let current = hosting.rootView.model.contentHeight
            if current == previous, current > 0 { return current }
            previous = current
        }
        return hosting.rootView.model.contentHeight
    }
}
