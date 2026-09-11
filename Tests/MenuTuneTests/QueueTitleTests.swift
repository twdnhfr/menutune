import MenuTuneCore
import XCTest
@testable import MenuTune

final class QueueTitleTests: XCTestCase {
    func testSecondCopyFromInputKeepsTheResolvedTitle() async {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MenuTuneQueueTitleTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let model = AppModel(fileURL: directory.appendingPathComponent("library.json"), connectsToYouTube: false)

            defer {
                model.shutdown()
                try? FileManager.default.removeItem(at: directory)
            }

            // The first copy already carries a title, which is what the second
            // one has to inherit instead of falling back to the raw video id.
            var queue = PlaybackQueue()
            _ = queue.append(videoID: "czBc1UhZ3eU", title: "Ein Titel")
            model.queue = queue

            model.input = "https://www.youtube.com/watch?v=czBc1UhZ3eU"
            model.addInput()

            XCTAssertEqual(model.queue.items.count, 2)
            XCTAssertEqual(model.queue.items.map(\.title), ["Ein Titel", "Ein Titel"])
            XCTAssertEqual(model.input, "")
        }
    }
}
