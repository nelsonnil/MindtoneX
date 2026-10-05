import Foundation

/// Cleans OCR text before `prepareSongQuery`.
enum CardTextMapper {
    private static let noisePrefixes = ["canción:", "cancion:", "song:", "tema:", "título:", "titulo:"]

    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "♪", with: "")
        s = s.replacingOccurrences(of: "\"", with: "")
        s = s.replacingOccurrences(of: "'", with: "")
        let lower = s.lowercased()
        for p in noisePrefixes where lower.hasPrefix(p) {
            s = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s = s.replacingOccurrences(of: "  ", with: " ")
        if s.count > 100 { s = String(s.prefix(100)) }
        return s
    }

    /// Canonical vote key: normalized title + artist from a loaded track id or query.
    static func canonicalKey(title: String, artist: String) -> String {
        PreviewService.normalize("\(title) \(artist)")
    }

    static func canonicalKey(from track: PreviewTrack) -> String {
        canonicalKey(title: track.title, artist: track.artist)
    }
}
