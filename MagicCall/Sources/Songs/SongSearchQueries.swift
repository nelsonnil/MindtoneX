import Foundation

/// Store search tries for a song pick or raw query (Voice, Notes, API, Camera, song 2).
enum SongSearchQueries {
    static func variants(title: String, artist: String, rawQuery: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let q = CardTextMapper.clean(s)
            guard q.count >= 2 else { return }
            if !out.contains(where: { ApiJSON.sameText($0, q) }) { out.append(q) }
        }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let built = buildSearchQuery(title: t, artist: a, raw: rawQuery)
        if !built.isEmpty { add(built) }
        let r = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty, !ApiJSON.sameText(r, built) { add(r) }
        if !t.isEmpty, !a.isEmpty {
            add("\(t) \(a)")
            add("\(a) \(t)")
        }
        if !t.isEmpty { add(t) }
        if t.isEmpty, !a.isEmpty { add(a) }
        return Array(out.prefix(5))
    }

    static func retryVariants(title: String, artist: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let q = CardTextMapper.clean(s)
            guard q.count >= 2 else { return }
            if !out.contains(where: { ApiJSON.sameText($0, q) }) { out.append(q) }
        }
        let t = simplifiedSongTitle(title)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !a.isEmpty {
            add("\(t) \(a)")
            add("\(a) \(t)")
        }
        if !t.isEmpty { add(t) }
        let stripped = stripLeadingArticles(t)
        if !stripped.isEmpty, !ApiJSON.sameText(stripped, t) { add(stripped) }
        return Array(out.prefix(4))
    }

    /// Raw utterance or note line with no structured title/artist.
    static func variants(fromRawQuery raw: String) -> [String] {
        let cleaned = CardTextMapper.clean(raw)
        guard cleaned.count >= 2 else { return [] }
        var out = variants(title: "", artist: "", rawQuery: cleaned)
        let stripped = stripLeadingArticles(cleaned)
        if stripped.count >= 2, !out.contains(where: { ApiJSON.sameText($0, stripped) }) {
            out.append(stripped)
        }
        return Array(out.prefix(6))
    }

    static func allVariants(title: String, artist: String, rawQuery: String) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        func appendUnique(_ list: [String]) {
            for q in list {
                let key = PreviewService.normalize(q)
                guard key.count >= 2, seen.insert(key).inserted else { continue }
                merged.append(q)
            }
        }
        appendUnique(variants(title: title, artist: artist, rawQuery: rawQuery))
        appendUnique(retryVariants(title: title, artist: artist))
        return merged
    }

    static func buildSearchQuery(title: String, artist: String, raw: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !a.isEmpty {
            let built = "\(t) \(a)"
            if r.isEmpty || ApiJSON.sameText(r, a) || ApiJSON.sameText(r, "\(a) \(a)") {
                return built
            }
        }
        if !r.isEmpty, !ApiJSON.sameText(r, "\(a) \(a)") { return r }
        if !t.isEmpty { return a.isEmpty ? t : "\(t) \(a)" }
        return r
    }

    static func stripLeadingArticles(_ raw: String) -> String {
        var words = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        while let first = words.first?.lowercased(), leadingArticles.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    private static let leadingArticles: Set<String> = [
        "la", "el", "los", "las", "le", "les", "the", "a", "an", "un", "una", "uno",
    ]

    private static func simplifiedSongTitle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)\s*[\(\[]\s*(feat\.?|ft\.?|featuring)[^\)\]]*[\)\]]"#,
            #"(?i)\s*-\s*(remix|live|acoustic|radio edit|version).*$"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
        }
        s = s.replacingOccurrences(of: "  ", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SongPick {
    func storeSearchQueries() -> [String] {
        SongSearchQueries.variants(title: title, artist: artist, rawQuery: searchQuery)
    }

    func storeSearchRetryQueries() -> [String] {
        SongSearchQueries.retryVariants(title: title, artist: artist)
    }

    var allStoreSearchQueries: [String] {
        SongSearchQueries.allVariants(title: title, artist: artist, rawQuery: searchQuery)
    }
}
