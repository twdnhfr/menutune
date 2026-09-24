import Foundation
import XCTest
@testable import MenuTuneCore

final class YouTubeLinkTests: XCTestCase {
    func testAcceptedForms() throws {
        XCTAssertEqual(try YouTubeLink.videoID(from: "czBc1UhZ3eU"), "czBc1UhZ3eU")
        XCTAssertEqual(try YouTubeLink.videoID(from: " https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s "), "czBc1UhZ3eU")
        for link in [
            "https://youtube.com/shorts/czBc1UhZ3eU",
            "https://m.youtube.com/live/czBc1UhZ3eU",
            "https://music.youtube.com/embed/czBc1UhZ3eU",
            "https://youtube-nocookie.com/embed/czBc1UhZ3eU",
            "https://www.youtube-nocookie.com/embed/czBc1UhZ3eU",
            "https://youtu.be/czBc1UhZ3eU"
        ] {
            XCTAssertEqual(try YouTubeLink.videoID(from: link), "czBc1UhZ3eU", link)
        }
    }

    func testStartSeconds() {
        XCTAssertEqual(YouTubeLink.startSeconds(from: "https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s"), 3)
        XCTAssertEqual(YouTubeLink.startSeconds(from: "https://www.youtube.com/watch?v=x&t=3"), 3)
        XCTAssertEqual(YouTubeLink.startSeconds(from: "https://youtu.be/x?start=1m30s"), 90)
        XCTAssertEqual(YouTubeLink.startSeconds(from: "https://youtu.be/x?t=1h2m3s"), 3723)
        XCTAssertEqual(YouTubeLink.startSeconds(from: "https://youtu.be/x?t=-3"), 0)
        XCTAssertEqual(YouTubeLink.startSeconds(from: "https://youtu.be/x?t=garbage"), 0)
        XCTAssertEqual(YouTubeLink.startSeconds(from: "https://youtu.be/x?t=999999999"), 604800)
    }

    func testClipboardURLOnlyAcceptsValidHTTPURLs() {
        let url = "https://www.youtube.com/watch?v=czBc1UhZ3eU&t=3s"
        XCTAssertEqual(YouTubeLink.clipboardURL(from: "  \n\(url)  \t"), url)
        XCTAssertNil(YouTubeLink.clipboardURL(from: nil))
        XCTAssertNil(YouTubeLink.clipboardURL(from: "czBc1UhZ3eU"))
        XCTAssertNil(YouTubeLink.clipboardURL(from: "just ordinary text"))
        XCTAssertNil(YouTubeLink.clipboardURL(from: "https://youtube.com.evil.example/watch?v=czBc1UhZ3eU"))
        XCTAssertNil(YouTubeLink.clipboardURL(from: String(repeating: "x", count: 8_193)))

        // A valid link that only fails on length, so the limit itself is exercised.
        let prefix = "https://www.youtube.com/watch?v=czBc1UhZ3eU&pad="
        let atLimit = prefix + String(repeating: "x", count: 8_192 - prefix.utf8.count)
        XCTAssertEqual(atLimit.utf8.count, 8_192)
        XCTAssertEqual(YouTubeLink.clipboardURL(from: atLimit), atLimit)
        XCTAssertNil(YouTubeLink.clipboardURL(from: atLimit + "x"))
    }

    func testRejectsInvalidIDsAndDeceptiveHosts() {
        let rejected = [
            "https://youtube.com.evil.example/watch?v=czBc1UhZ3eU",
            "https://evil.youtube.com/watch?v=czBc1UhZ3eU",
            "javascript://youtube.com/watch?v=czBc1UhZ3eU",
            "https://youtu.be/czBc1UhZ3e",
            "https://youtube.com/watch?v=czBc1UhZ3eU!",
            "https://youtube.com/watch?v=czBc1UhZ3eU/extra"
        ]
        for link in rejected { XCTAssertThrowsError(try YouTubeLink.videoID(from: link), link) }
    }
}

final class PlaybackQueueTests: XCTestCase {
    private func queue() -> (PlaybackQueue, QueueItem, QueueItem, QueueItem) {
        var queue = PlaybackQueue()
        let first = queue.append(videoID: "aaaaaaaaaaa", title: "A")
        let second = queue.append(videoID: "bbbbbbbbbbb", title: "B")
        let third = queue.append(videoID: "ccccccccccc", title: "C")
        return (queue, first, second, third)
    }

    func testNextAndRepeat() {
        var (queue, first, second, third) = queue()
        XCTAssertEqual(queue.next(automatic: false), first)
        XCTAssertEqual(queue.next(automatic: false), second)
        XCTAssertEqual(queue.next(automatic: false), third)
        XCTAssertNil(queue.next(automatic: false))
        XCTAssertEqual(queue.currentItem, third)
        queue.repeatMode = .all
        XCTAssertEqual(queue.next(automatic: true), first)
        queue.repeatMode = .one
        XCTAssertEqual(queue.next(automatic: true), first)
        XCTAssertEqual(queue.next(automatic: false), second)
    }

    func testASecondCopyOfTheSameVideoIsNeverAdded() {
        var queue = PlaybackQueue()
        let first = queue.append(videoID: "aaaaaaaaaaa", title: "A")
        let again = queue.append(videoID: "aaaaaaaaaaa", title: "A different title")
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(again, first, "The existing entry is returned, not a new one.")
        XCTAssertEqual(queue.items.first?.title, "A", "The title already fetched is kept.")
        XCTAssertTrue(queue.contains(videoID: "aaaaaaaaaaa"))
        XCTAssertFalse(queue.contains(videoID: "bbbbbbbbbbb"))
    }

    func testMovingDownAndRemovingAnotherEntry() {
        var (queue, first, second, third) = queue()
        XCTAssertTrue(queue.select(first.id))

        queue.move(first.id, by: 1)
        XCTAssertEqual(queue.items.map(\.id), [second.id, first.id, third.id])
        queue.move(first.id, by: 10)
        XCTAssertEqual(queue.items.map(\.id), [second.id, third.id, first.id])

        // Removing some other entry must leave the current selection alone.
        queue.remove(third.id)
        XCTAssertEqual(queue.items.map(\.id), [second.id, first.id])
        XCTAssertEqual(queue.currentItemID, first.id)
    }

    func testRemovingTheCurrentLastEntryFallsBackToItsPredecessor() {
        var (queue, first, second, third) = queue()
        XCTAssertTrue(queue.select(third.id))
        queue.remove(third.id)
        XCTAssertEqual(queue.items.map(\.id), [first.id, second.id])
        XCTAssertEqual(queue.currentItemID, second.id)
    }

    func testEdgesWithoutRepeatAndOnAnEmptyQueue() {
        var (queue, _, _, third) = queue()
        XCTAssertTrue(queue.select(third.id))
        XCTAssertNil(queue.next(automatic: true), "Without repeat, the last track must not wrap to the start.")
        XCTAssertEqual(queue.currentItemID, third.id)

        var empty = PlaybackQueue()
        XCTAssertNil(empty.next(automatic: false))
        XCTAssertNil(empty.currentItem)
    }

    func testRemovalReorderAndTitleUpdates() {
        var (queue, first, second, third) = queue()
        XCTAssertTrue(queue.select(second.id))
        queue.remove(second.id)
        XCTAssertEqual(queue.currentItemID, third.id)
        queue.move(third.id, by: -10)
        XCTAssertEqual(queue.items.map(\.id), [third.id, first.id])
        queue.updateTitle(videoID: "aaaaaaaaaaa", title: "new")
        XCTAssertEqual(queue.items.map(\.title), ["C", "new"])
        queue.remove(third.id)
        queue.remove(first.id)
        XCTAssertNil(queue.currentItemID)
    }
}

final class LibraryStoreTests: XCTestCase {
    func testPlayerSizePersistenceAndLegacyLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        var queue = PlaybackQueue()
        let item = queue.append(videoID: "aaaaaaaaaaa")
        _ = queue.select(item.id)
        for size in PlayerSize.allCases {
            let snapshot = LibrarySnapshot(queue: queue, volume: 0.3, playerSize: size)
            try store.save(snapshot)
            XCTAssertEqual(try store.load(), snapshot)
        }

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        legacy.removeValue(forKey: "playerSize")
        try JSONSerialization.data(withJSONObject: legacy).write(to: store.fileURL)
        let restored = try store.load()
        XCTAssertEqual(restored.playerSize, .standard)
        XCTAssertEqual(restored.queue, queue)
        XCTAssertEqual(restored.volume, 0.3)
    }

    func testUnknownRepeatModeAndMissingTitleStayReadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(fileURL: directory.appendingPathComponent("library.json"))
        var queue = PlaybackQueue(repeatMode: .all)
        let item = queue.append(videoID: "aaaaaaaaaaa", title: "A")
        _ = queue.select(item.id)
        try store.save(LibrarySnapshot(queue: queue, playerSize: .mini, queueExpanded: true))

        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        var stored = try XCTUnwrap(raw["queue"] as? [String: Any])
        var items = try XCTUnwrap(stored["items"] as? [[String: Any]])
        stored["repeatMode"] = "shuffle"
        items[0].removeValue(forKey: "title")
        stored["items"] = items
        raw["queue"] = stored
        try JSONSerialization.data(withJSONObject: raw).write(to: store.fileURL)

        let restored = try store.load()
        XCTAssertEqual(restored.queue.repeatMode, .off)
        XCTAssertEqual(restored.queue.items.map(\.title), ["aaaaaaaaaaa"])
        XCTAssertEqual(restored.queue.currentItemID, item.id)
        XCTAssertEqual(restored.playerSize, .mini)
        XCTAssertTrue(restored.queueExpanded)
    }

    func testAnOlderPlaceholderTitleStillCountsAsUnresolved() throws {
        let json = #"{"id":"\#(UUID().uuidString)","videoID":"aaaaaaaaaaa","title":"aaaaaaaaaaa"}"#
        let item = try JSONDecoder().decode(QueueItem.self, from: Data(json.utf8))
        XCTAssertNil(item.fetchedTitle, "Older versions stored the video id in place of a missing title.")
        XCTAssertEqual(item.title, "aaaaaaaaaaa")
    }

    func testAnOlderLibraryWithDuplicatesCollapsesOnLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        let store = LibraryStore(fileURL: url)

        // Written the way earlier versions could, with the selection on the copy.
        let keptID = UUID(), droppedID = UUID(), otherID = UUID()
        let raw: [String: Any] = [
            "volume": 0.5,
            "playerSize": "standard",
            "queue": [
                "repeatMode": "all",
                "currentItemID": droppedID.uuidString,
                "items": [
                    ["id": keptID.uuidString, "videoID": "aaaaaaaaaaa", "title": "A"],
                    ["id": otherID.uuidString, "videoID": "bbbbbbbbbbb", "title": "B"],
                    ["id": droppedID.uuidString, "videoID": "aaaaaaaaaaa", "title": "A again"]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: raw).write(to: url)

        let restored = try store.load()
        XCTAssertEqual(restored.queue.items.map(\.videoID), ["aaaaaaaaaaa", "bbbbbbbbbbb"])
        XCTAssertEqual(restored.queue.items.map(\.title), ["A", "B"], "The first occurrence wins.")
        XCTAssertEqual(restored.queue.currentItemID, keptID,
                       "The selection pointed at the dropped copy and must move to the surviving one.")
        XCTAssertEqual(restored.queue.repeatMode, .all)
    }

    func testRoundTripMissingAndCorrupt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("nested/library.json")
        let store = LibraryStore(fileURL: url)
        XCTAssertEqual(try store.load(), LibrarySnapshot())
        var queue = PlaybackQueue()
        _ = queue.append(videoID: "aaaaaaaaaaa")
        let snapshot = LibrarySnapshot(queue: queue, volume: 2)
        try store.save(snapshot)
        XCTAssertEqual(try store.load(), LibrarySnapshot(queue: queue, volume: 1))
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: url), Data("not json".utf8))
        try? FileManager.default.removeItem(at: directory)
    }
}
