import MenuTuneCore
import XCTest
@testable import MenuTune

final class QueueTitleTests: XCTestCase {
    func testAddingAQueuedVideoAgainChangesNothingAndSaysSo() async {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MenuTuneQueueTitleTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let model = AppModel(fileURL: directory.appendingPathComponent("library.json"),
                                 connectsToYouTube: false)

            defer {
                model.shutdown()
                try? FileManager.default.removeItem(at: directory)
            }

            var queue = PlaybackQueue()
            let existing = queue.append(videoID: "czBc1UhZ3eU", title: "Ein Titel")
            model.queue = queue

            model.input = "https://www.youtube.com/watch?v=czBc1UhZ3eU"
            model.addInput()

            XCTAssertEqual(model.queue.items.count, 1)
            XCTAssertEqual(model.queue.items.first?.id, existing.id)
            XCTAssertEqual(model.queue.items.first?.title, "Ein Titel",
                           "Der bereits geladene Titel darf nicht durch die rohe Video-ID ersetzt werden.")
            XCTAssertEqual(model.input, "")
            XCTAssertNil(model.errorMessage, "Ein bekannter Titel ist kein Fehler.")
            XCTAssertEqual(model.statusText, "Steht schon in der Warteschlange")
        }
    }
}
