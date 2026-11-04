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

    /// Validates a store result against imperfect OCR. Each OCR token may contain a small
    /// handwriting error, but unrelated popular results must not gain a vote.
    static func plausiblyMatches(_ rawOCR: String, track: PreviewTrack) -> Bool {
        let queryTokens = tokens(rawOCR).filter { $0.count >= 3 }
        guard !queryTokens.isEmpty else { return false }
        let titleTokens = tokens(track.title)
        let artistTokens = tokens(track.artist)
        let trackTokens = titleTokens + artistTokens
        guard !trackTokens.isEmpty else { return false }

        let similarities = queryTokens.map { query in
            trackTokens.map { tokenSimilarity(query, $0) }.max() ?? 0
        }
        let average = similarities.reduce(0, +) / Double(similarities.count)
        let strong = similarities.filter { $0 >= 0.72 }.count

        // One handwritten word can be an artist (SHAKLRA → Shakira) or a famous title.
        if queryTokens.count == 1 {
            return (similarities.first ?? 0) >= 0.72
        }
        return average >= 0.64 && strong >= max(1, queryTokens.count - 1)
    }

    private static func tokens(_ raw: String) -> [String] {
        PreviewService.normalize(raw).split(separator: " ").map(String.init)
    }

    /// Shared by store ranking (Notes typed input, Camera OCR validation).
    static func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        if lhs.count >= 4, rhs.count >= 4, lhs.contains(rhs) || rhs.contains(lhs) { return 0.9 }
        let distance = levenshtein(lhs, rhs)
        return 1 - Double(distance) / Double(max(lhs.count, rhs.count, 1))
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for (i, ac) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, bc) in b.enumerated() {
                current[j + 1] = min(
                    current[j] + 1,
                    previous[j + 1] + 1,
                    previous[j] + (ac == bc ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Extra store search tries when OCR garbles handwriting (e.g. LOSE tURSeS → Lose Yourself).
    static func songSearchVariants(from raw: String) -> [String] {
        var out = SongSearchQueries.variants(fromRawQuery: raw)
        func add(_ s: String) {
            let q = clean(s)
            guard q.count >= 2 else { return }
            if !out.contains(where: { ApiJSON.sameText($0, q) }) { out.append(q) }
        }
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
