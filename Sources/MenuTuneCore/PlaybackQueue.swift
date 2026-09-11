import Foundation

public struct QueueItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let videoID: String
    public var title: String

    public init(id: UUID = UUID(), videoID: String, title: String? = nil) {
        self.id = id
        self.videoID = videoID
        self.title = title ?? videoID
    }

    /// A missing title must not make the whole library unreadable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        videoID = try container.decode(String.self, forKey: .videoID)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? videoID
    }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one
}

public struct PlaybackQueue: Codable, Equatable, Sendable {
    public var items: [QueueItem]
    public var currentItemID: UUID?
    public var repeatMode: RepeatMode

    public init(items: [QueueItem] = [], currentItemID: UUID? = nil, repeatMode: RepeatMode = .off) {
        self.items = items
        self.currentItemID = currentItemID
        self.repeatMode = repeatMode
    }

    /// An unknown repeat mode from a newer version falls back instead of
    /// failing the whole load, which would block saving for the session.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A library written before entries were unique, or edited by hand, can
        // still hold duplicates; the first occurrence wins.
        let stored = try container.decodeIfPresent([QueueItem].self, forKey: .items) ?? []
        var seen = Set<String>()
        // Locals throughout: a closure may not capture a property this
        // initialiser has not assigned yet.
        let unique = stored.filter { seen.insert($0.videoID).inserted }
        items = unique

        let storedCurrent = try container.decodeIfPresent(UUID.self, forKey: .currentItemID)
        if let storedCurrent, !unique.contains(where: { $0.id == storedCurrent }) {
            // The selection pointed at a copy that just collapsed into another.
            let droppedVideoID = stored.first(where: { $0.id == storedCurrent })?.videoID
            currentItemID = droppedVideoID.flatMap { videoID in
                unique.first(where: { $0.videoID == videoID })?.id
            }
        } else {
            currentItemID = storedCurrent
        }
        repeatMode = RepeatMode(rawValue: try container.decodeIfPresent(String.self, forKey: .repeatMode) ?? "") ?? .off
    }

    public var currentItem: QueueItem? {
        guard let currentItemID else { return nil }
        return items.first { $0.id == currentItemID }
    }

    public func contains(videoID: String) -> Bool {
        items.contains { $0.videoID == videoID }
    }

    /// Entries are unique per video. Adding one that is already queued returns
    /// the existing entry, keeping its title and position, instead of making a
    /// second copy of the same thing.
    @discardableResult
    public mutating func append(videoID: String, title: String? = nil) -> QueueItem {
        if let existing = items.first(where: { $0.videoID == videoID }) { return existing }
        let item = QueueItem(videoID: videoID, title: title)
        items.append(item)
        return item
    }

    @discardableResult
    public mutating func select(_ id: UUID) -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        currentItemID = id
        return true
    }

    @discardableResult
    public mutating func next(automatic: Bool) -> QueueItem? {
        guard !items.isEmpty else { return nil }
        guard let currentItemID, let index = items.firstIndex(where: { $0.id == currentItemID }) else {
            self.currentItemID = items[0].id
            return items[0]
        }
        if automatic && repeatMode == .one { return items[index] }
        if index + 1 < items.count {
            self.currentItemID = items[index + 1].id
            return items[index + 1]
        }
        if repeatMode == .all {
            self.currentItemID = items[0].id
            return items[0]
        }
        return nil
    }

    @discardableResult
    public mutating func previous() -> QueueItem? {
        guard !items.isEmpty, let currentItemID, let index = items.firstIndex(where: { $0.id == currentItemID }) else { return nil }
        if index > 0 {
            self.currentItemID = items[index - 1].id
            return items[index - 1]
        }
        guard repeatMode == .all else { return nil }
        self.currentItemID = items[items.count - 1].id
        return items[items.count - 1]
    }

    public mutating func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentItemID == id
        items.remove(at: index)
        guard wasCurrent else { return }
        if index < items.count { currentItemID = items[index].id }
        else if let previous = items.last { currentItemID = previous.id }
        else { currentItemID = nil }
    }

    public mutating func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items.isEmpty else { return }
        let safeOffset: Int
        if offset > 0 {
            safeOffset = min(offset, items.count)
        } else {
            safeOffset = max(offset, -items.count)
        }
        let destination = min(max(index + safeOffset, 0), items.count - 1)
        guard destination != index else { return }
        let item = items.remove(at: index)
        items.insert(item, at: destination)
    }

    public mutating func updateTitle(videoID: String, title: String) {
        for index in items.indices where items[index].videoID == videoID { items[index].title = title }
    }
}
