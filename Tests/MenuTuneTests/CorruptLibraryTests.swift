import MenuTuneCore
import XCTest
@testable import MenuTune

@MainActor
final class CorruptLibraryTests: XCTestCase {
    /// README promise: a damaged file stays as it is and later changes are not
    /// saved until the user has restored it.
    func testADamagedLibraryWarnsAndIsNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuTuneCorruptLibraryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        let damaged = Data("not json".utf8)
        try damaged.write(to: url)

        let model = AppModel(fileURL: url, connectsToYouTube: false)

        defer {
            model.shutdown()
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertNotNil(model.storageWarning)
        XCTAssertTrue(model.queue.items.isEmpty)

        model.input = "https://www.youtube.com/watch?v=czBc1UhZ3eU"
        model.addInput()
        model.setRepeat(.all)
        model.isQueueExpanded = true

        XCTAssertEqual(model.queue.items.count, 1, "Work continues in memory.")
        XCTAssertEqual(try Data(contentsOf: url), damaged, "The damaged file has to stay exactly as it was.")
    }
}
