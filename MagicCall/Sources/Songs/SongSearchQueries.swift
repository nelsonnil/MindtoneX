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
        if !t.isEmpty {
            add(t)
            let stripped = stripLeadingArticles(t)
            if !stripped.isEmpty { add(stripped) }
        }
        if t.isEmpty, !a.isEmpty { add(a) }
        return Array(out.prefix(6))
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
        let framed = stripSongFraming(cleaned)
        guard framed.count >= 2 || cleaned.count >= 2 else { return [] }
        var out = variants(title: "", artist: "", rawQuery: framed.isEmpty ? cleaned : framed)
        if framed.count >= 2, !out.contains(where: { ApiJSON.sameText($0, framed) }) {
            out.insert(framed, at: 0)
        }
        let stripped = stripLeadingArticles(framed.isEmpty ? cleaned : framed)
        if stripped.count >= 2, !out.contains(where: { ApiJSON.sameText($0, stripped) }) {
            out.append(stripped)
        }
        if cleaned.count >= 2, !out.contains(where: { ApiJSON.sameText($0, cleaned) }) {
            out.append(cleaned)
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
        if !a.isEmpty { return a }
        return r
    }

    static func stripLeadingArticles(_ raw: String) -> String {
        var words = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        while let first = words.first.map(fold), leadingArticles.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// Drops spoken/written framing ("la canción", "the song") so a title-only query remains.
    static func stripSongFraming(_ raw: String) -> String {
        var words = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        let frames: [[String]] = [
            ["la", "cancion", "se", "llama"],
            ["the", "song", "is", "called"],
            ["la", "cancion", "es"],
            ["el", "tema", "es"],
            ["mi", "cancion", "es"],
            ["my", "song", "is"],
            ["la", "cancion"],
            ["una", "cancion"],
            ["el", "tema"],
            ["the", "song"],
            ["cancion"],
            ["song"],
        ]
        for frame in frames.sorted(by: { $0.count > $1.count }) {
            guard words.count > frame.count else { continue }
            let head = words.prefix(frame.count).map(fold)
            if head == frame {
                words.removeFirst(frame.count)
                break
            }
        }
        return stripLeadingArticles(words.joined(separator: " "))
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
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
        SongSearchQueries.variants(title: title, artist: artist, rawQuery: filledSearchQuery)
    }

    func storeSearchRetryQueries() -> [String] {
        SongSearchQueries.retryVariants(title: title, artist: artist)
    }

    var allStoreSearchQueries: [String] {
        SongSearchQueries.allVariants(title: title, artist: artist, rawQuery: filledSearchQuery)
    }

    /// Title (and artist when known) even if the model left `search_query` blank.
    var filledSearchQuery: String {
        SongSearchQueries.buildSearchQuery(title: title, artist: artist, raw: searchQuery)
    }

    var hasUsableTitle: Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= 2 || filledSearchQuery.count >= 2
    }

    /// Title named without artist: store ranking picks the most popular recording.
    var isTitleOnly: Bool {
        artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    /// Singer/group named without a title: the store lookup picks their most popular song.
    var isArtistOnly: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && artist.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    /// A specific title by the artist of an artist-only pick ("Shakira… Waka Waka") — same choice, not a new song.
    func refines(_ artistOnly: SongPick) -> Bool {
        guard artistOnly.isArtistOnly, !isArtistOnly else { return false }
        let mine = PreviewService.normalize(artist)
        let theirs = PreviewService.normalize(artistOnly.artist)
        guard !mine.isEmpty, !theirs.isEmpty else { return false }
        return mine.contains(theirs) || theirs.contains(mine)
    }

    /// Artist-only picks take the title/artist of the store hit actually loaded.
    func filled(from track: PreviewTrack?) -> SongPick {
        guard isArtistOnly, let track else { return self }
        var copy = self
        copy.title = track.title
        copy.artist = track.artist
        return copy
    }

    func withFilledSearchQuery() -> SongPick {
        var copy = self
        copy.searchQuery = filledSearchQuery
        if copy.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isArtistOnly {
            copy.title = SongSearchQueries.stripSongFraming(copy.searchQuery)
        }
        return copy
    }
}
