import Foundation

public enum PlayerSize: String, Codable, CaseIterable, Sendable {
    case standard
    case medium
    case mini

    // Whole-point 16:9 dimensions avoid fractional edges in the embedded view.
    public var width: Double {
        switch self {
        case .standard: return 448
        case .medium: return 320
        case .mini: return 192
        }
    }
    public var videoHeight: Double { width * 9 / 16 }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public var queue: PlaybackQueue
    public var volume: Double
    public var playerSize: PlayerSize

    public init(queue: PlaybackQueue = PlaybackQueue(), volume: Double = 0.65, playerSize: PlayerSize = .standard) {
        self.queue = queue
        self.volume = Self.clampedVolume(volume)
        self.playerSize = playerSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queue = try container.decode(PlaybackQueue.self, forKey: .queue)
        volume = Self.clampedVolume(try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.65)
        playerSize = PlayerSize(rawValue: try container.decodeIfPresent(String.self, forKey: .playerSize) ?? "") ?? .standard
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
