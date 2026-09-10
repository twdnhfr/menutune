import Foundation

public enum YouTubeLinkError: Error, LocalizedError, Equatable, Sendable {
    case invalidLink
    case invalidVideoID

    public var errorDescription: String? {
        switch self {
        case .invalidLink: return "Der YouTube-Link ist ungültig."
        case .invalidVideoID: return "Die YouTube-Video-ID ist ungültig."
        }
    }
}

public enum YouTubeLink {
    private static let idCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    public static func videoID(from input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidID(value) { return value }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased()
        else { throw YouTubeLinkError.invalidLink }

        let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let id: String?
        switch host {
        case "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com":
            if pathParts == ["watch"] {
                id = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if pathParts.count == 2 && ["shorts", "live", "embed"].contains(pathParts[0]) {
                id = pathParts[1]
            } else {
                id = nil
            }
        case "youtube-nocookie.com":
            id = pathParts.count == 2 && pathParts[0] == "embed" ? pathParts[1] : nil
        case "www.youtube-nocookie.com":
            id = pathParts.count == 2 && pathParts[0] == "embed" ? pathParts[1] : nil
        case "youtu.be":
            id = pathParts.count == 1 ? pathParts[0] : nil
        default:
            id = nil
        }

        guard let id, isValidID(id) else { throw YouTubeLinkError.invalidVideoID }
        return id
    }

    public static func startSeconds(from input: String) -> Double {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isValidID(value), let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com", "youtu.be"].contains(host)
        else { return 0 }
        let raw = components.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value ?? ""
        return min(parseTime(raw), 604_800)
    }

    public static func clipboardURL(from text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 8_192,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host != nil,
              (try? videoID(from: value)) != nil
        else { return nil }
        return value
    }

    private static func parseTime(_ raw: String) -> Double {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return 0 }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        var cursor = value.startIndex
        var total = 0.0
        var foundUnit = false
        var lastUnit: Character = " "
        while cursor < value.endIndex {
            let numberStart = cursor
            while cursor < value.endIndex && value[cursor].isNumber { cursor = value.index(after: cursor) }
            guard numberStart != cursor, cursor < value.endIndex else { return 0 }
            let number = Double(value[numberStart..<cursor]) ?? 0
            let unit = value[cursor]
            guard unit == "h" || unit == "m" || unit == "s", unit > lastUnit else { return 0 }
            let multiplier: Double = unit == "h" ? 3600 : unit == "m" ? 60 : 1
            total += number * multiplier
            foundUnit = true
            lastUnit = unit
            cursor = value.index(after: cursor)
        }
        return foundUnit && total.isFinite ? total : 0
    }

    private static func isValidID(_ value: String) -> Bool {
        value.utf8.count == 11 && value.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }
}
