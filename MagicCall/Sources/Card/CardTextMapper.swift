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

    /// Extra store search tries when OCR garbles handwriting (e.g. LOSE tURSeS → Lose Yourself).
    static func songSearchVariants(from raw: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let q = clean(s)
            guard q.count >= 2 else { return }
            if !out.contains(where: { ApiJSON.sameText($0, q) }) { out.append(q) }
        }
        add(raw)
        let cleanRaw = clean(raw)
        if let range = cleanRaw.range(of: " - ") {
            let artist = String(cleanRaw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(cleanRaw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            add(title)
            add("\(title) \(artist)")
        }
        let folded = cleanRaw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        if folded.contains("lose"), folded.contains("your") {
            add("Lose Yourself Eminem")
            add("Lose Yourself")
        }
        if folded.contains("eminem"), folded.contains("lose") {
            add("Eminem Lose Yourself")
        }
        return out
    }
}
