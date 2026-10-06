import Foundation

/// Parses a handwritten card into song (line 1) and spectator word (line 2).
struct CardDualParse: Equatable {
    var songQuery: String
    var spectatorWord: String?
}

enum CardLineParser {
    private static let songPrefixes = ["song:", "canción:", "cancion:", "tema:", "título:", "titulo:"]
    private static let wordPrefixes = ["word:", "palabra:", "w:"]

    static func parse(orderedLines: [String]) -> CardDualParse {
        var labeledSong: String?
        var labeledWord: String?
        var plain: [String] = []

        for raw in orderedLines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 1 else { continue }
            let lower = trimmed.lowercased()
            if let stripped = stripPrefix(lower, trimmed, prefixes: wordPrefixes) {
                labeledWord = stripped
                continue
            }
            if let stripped = stripPrefix(lower, trimmed, prefixes: songPrefixes) {
                labeledSong = stripped
                continue
            }
            plain.append(CardTextMapper.clean(trimmed))
        }

        var song = labeledSong.map { CardTextMapper.clean($0) } ?? ""
        var word = labeledWord.map { normalizeWord($0) } ?? nil

        if song.isEmpty, plain.count >= 1 {
            song = plain[0]
        }
        if word == nil, plain.count >= 2 {
            word = normalizeWord(plain[1])
        }

        if let w = word, ApiJSON.sameText(w, song) {
            word = plain.count >= 2 ? normalizeWord(plain[1]) : nil
        }
        if let w = word, song.split(separator: " ").contains(where: { ApiJSON.sameText(String($0), w) }) {
            // Word is only a title token — prefer explicit line 2; drop if ambiguous single-line card.
            if plain.count < 2 { word = nil }
        }

        return CardDualParse(songQuery: song, spectatorWord: word)
    }

    private static func stripPrefix(_ lower: String, _ original: String, prefixes: [String]) -> String? {
        for p in prefixes where lower.hasPrefix(p) {
            return String(original.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func normalizeWord(_ raw: String) -> String? {
        let cleaned = CardTextMapper.clean(raw)
        guard !cleaned.isEmpty else { return nil }
        let tokens = cleaned.split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "/" })
        guard let last = tokens.last else { return nil }
        let word = String(last).trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.count >= 2 else { return nil }
        return word
    }
}
