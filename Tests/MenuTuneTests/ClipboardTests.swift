import AppKit
import XCTest
@testable import MenuTune

final class ClipboardTests: XCTestCase {
    func testClipboardSuggestionLifecycle() async {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MenuTuneClipboardTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let libraryURL = directory.appendingPathComponent("library.json")
            let pasteboard = NSPasteboard.withUniqueName()
            let model = AppModel(fileURL: libraryURL)

            defer {
                model.shutdown()
                pasteboard.clearContents()
                pasteboard.releaseGlobally()
                try? FileManager.default.removeItem(at: directory)
            }

            let url = "https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s"
            model.input = "typed input stays untouched"

            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
            model.inspectClipboard(pasteboard)

            XCTAssertEqual(model.clipboardSuggestion, url)
            XCTAssertTrue(model.queue.items.isEmpty)
            XCTAssertNil(model.queue.currentItemID)
            XCTAssertFalse(model.isPlaying)

            model.acceptClipboardSuggestion()

            XCTAssertNil(model.clipboardSuggestion)
            XCTAssertEqual(model.queue.items.count, 1)
            XCTAssertEqual(model.queue.items.first?.videoID, "czBc1UhZ3eU")
            XCTAssertEqual(model.input, "typed input stays untouched")
            XCTAssertNil(model.queue.currentItemID)
            XCTAssertFalse(model.isPlaying)

            model.acceptClipboardSuggestion()
            XCTAssertEqual(model.queue.items.count, 1)

            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
            model.inspectClipboard(pasteboard)
            XCTAssertEqual(model.clipboardSuggestion, url)

            model.dismissClipboardSuggestion()
            XCTAssertNil(model.clipboardSuggestion)
            model.inspectClipboard(pasteboard)
            XCTAssertNil(model.clipboardSuggestion)

            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
            model.inspectClipboard(pasteboard)
            XCTAssertEqual(model.clipboardSuggestion, url)

            pasteboard.clearContents()
            pasteboard.setString("ordinary text", forType: .string)
            model.inspectClipboard(pasteboard)
            XCTAssertNil(model.clipboardSuggestion)
        }
    }
}
