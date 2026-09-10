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
        let third = queue.append(videoID: "aaaaaaaaaaa", title: "A2")
        return (queue, first, second, third)
    }

    func testNextPreviousAndRepeat() {
        var (queue, first, second, third) = queue()
        XCTAssertEqual(queue.next(automatic: false), first)
        XCTAssertEqual(queue.next(automatic: false), second)
        XCTAssertEqual(queue.next(automatic: false), third)
        XCTAssertNil(queue.next(automatic: false))
        XCTAssertEqual(queue.currentItem, third)
        XCTAssertEqual(queue.previous(), second)
        XCTAssertEqual(queue.next(automatic: false), third)
        queue.repeatMode = .all
        XCTAssertEqual(queue.next(automatic: true), first)
        XCTAssertEqual(queue.previous(), third)
        queue.repeatMode = .one
        XCTAssertEqual(queue.next(automatic: true), third)
        XCTAssertNil(queue.next(automatic: false))
    }

    func testRemovalReorderAndTitleUpdates() {
        var (queue, first, second, third) = queue()
        XCTAssertTrue(queue.select(second.id))
        queue.remove(second.id)
        XCTAssertEqual(queue.currentItemID, third.id)
        queue.move(third.id, by: -10)
        XCTAssertEqual(queue.items.map(\.id), [third.id, first.id])
        queue.updateTitle(videoID: "aaaaaaaaaaa", title: "neu")
        XCTAssertEqual(queue.items.map(\.title), ["neu", "neu"])
        queue.remove(third.id)
        queue.remove(first.id)
        XCTAssertNil(queue.currentItemID)
    }
}

final class LibraryStoreTests: XCTestCase {
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
