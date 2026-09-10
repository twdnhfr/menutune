import Foundation

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var queue: PlaybackQueue
    public var volume: Double

    public init(queue: PlaybackQueue = PlaybackQueue(), volume: Double = 0.65) {
        self.queue = queue
        self.volume = Self.clampedVolume(volume)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queue = try container.decode(PlaybackQueue.self, forKey: .queue)
        volume = Self.clampedVolume(try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.65)
    }

    private static func clampedVolume(_ volume: Double) -> Double {
        volume.isFinite ? min(max(volume, 0), 1) : 0.65
    }
}

public struct LibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LibrarySnapshot() }
        return try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuTune", isDirectory: true)
            .appendingPathComponent("library.json")
    }
}
