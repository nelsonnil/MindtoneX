import CryptoKit
import Foundation

/// Persisted fallback when a Voice Perform lock did not produce a durable `PreviewTrack` in recents.
struct RecentPerformSnapshot: Codable, Equatable, Identifiable {
    let title: String
    let artist: String
    let searchQuery: String
    let previewURL: String?
    let lockedAt: Date

    var id: String { dedupeKey }

    var dedupeKey: String {
        (searchQuery + "|" + title + "|" + artist)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == "|" || $0.isWhitespace }
    }

    init(title: String, artist: String, searchQuery: String, previewURL: String?, lockedAt: Date) {
        self.title = title
        self.artist = artist
        self.searchQuery = searchQuery
        self.previewURL = previewURL
        self.lockedAt = lockedAt
    }

    init(pick: SongPick, previewURL: String?, lockedAt: Date = Date()) {
        self.title = pick.title
        self.artist = pick.artist
        self.searchQuery = pick.searchQuery
        self.previewURL = previewURL
        self.lockedAt = lockedAt
    }

    func matches(_ track: PreviewTrack) -> Bool {
        if let previewURL, let url = URL(string: previewURL), track.previewURL == url { return true }
        let trackKey = (track.title + "|" + track.artist)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == "|" || $0.isWhitespace }
        let snapKey = (title + "|" + artist)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == "|" || $0.isWhitespace }
        return trackKey == snapKey
    }

    func asPreviewTrackIfPossible() -> PreviewTrack? {
        guard let previewURL, let url = URL(string: previewURL), url.scheme != nil else { return nil }
        return PreviewTrack(
            title: title,
            artist: artist,
            album: nil,
            artworkURL: nil,
            previewURL: url,
            source: url.isFileURL ? .imported : .itunes
        )
    }

    func asSyntheticPreviewTrack() -> PreviewTrack {
        if let real = asPreviewTrackIfPossible() { return real }
        return PreviewTrack(
            title: title,
            artist: artist,
            album: searchQuery,
            artworkURL: nil,
            previewURL: Self.placeholderURL(for: dedupeKey),
            source: .itunes
        )
    }

    static func isSnapshotPlaceholder(_ track: PreviewTrack) -> Bool {
        track.previewURL.pathExtension == "placeholder"
            && track.previewURL.path.contains("perform-snapshots")
    }

    static func placeholderURL(for dedupeKey: String) -> URL {
        let digest = SHA256.hash(data: Data(dedupeKey.utf8))
        let name = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("perform-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(name).placeholder")
    }
}
