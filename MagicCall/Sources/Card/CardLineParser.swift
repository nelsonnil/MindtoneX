import Foundation

/// Handwritten card layout (top → bottom): line 1 = song · line 2 = caller word · line 3 = Notes chip word.
struct CardOCRParse: Equatable {
    var songQuery: String
    /// Raw text on **line 2** (caller name when Card OCR is enabled for Caller name).
    var callerLine: String?
    /// Raw text on **line 3** (Notes contact chip when Card OCR is enabled for Notes word).
    var notesLine: String?
}

enum CardLineParser {
    private static let songPrefixes = ["song:", "canción:", "cancion:", "tema:", "título:", "titulo:"]
    private static let callerPrefixes = ["word:", "palabra:", "w:", "caller:", "contact:", "contacto:"]
    private static let notesPrefixes = ["notes:", "note:", "nota:", "chip:", "notesword:"]

    static func parse(orderedLines: [String]) -> CardOCRParse {
        var labeledSong: String?
        var labeledCaller: String?
        var labeledNotes: String?
        var plain: [String] = []

        for raw in orderedLines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 1 else { continue }
            let lower = trimmed.lowercased()
            if let stripped = stripPrefix(lower, trimmed, prefixes: notesPrefixes) {
                labeledNotes = stripped
                continue
            }
            if let stripped = stripPrefix(lower, trimmed, prefixes: callerPrefixes) {
                labeledCaller = stripped
                continue
            }
            if let stripped = stripPrefix(lower, trimmed, prefixes: songPrefixes) {
                labeledSong = stripped
                continue
            }
            plain.append(CardTextMapper.clean(trimmed))
        }

        var song = labeledSong.map { CardTextMapper.clean($0) } ?? ""
        var callerLine = labeledCaller.map { CardTextMapper.clean($0) }
        var notesLine = labeledNotes.map { CardTextMapper.clean($0) }

        if song.isEmpty, plain.count >= 1 {
            song = plain[0]
        }
        if callerLine == nil, plain.count >= 2 {
            callerLine = plain[1]
        }
        if notesLine == nil, plain.count >= 3 {
            notesLine = plain[2]
        }

        callerLine = callerLine.flatMap { line in
            let w = normalizeWord(line)
            return w == nil || ApiJSON.sameText(w!, song) ? nil : line
        }
        notesLine = notesLine.flatMap { line in
            let w = normalizeWord(line)
            guard let w else { return nil }
            if ApiJSON.sameText(w, song) { return nil }
            if let c = callerLine.flatMap(normalizeWord), ApiJSON.sameText(w, c) { return nil }
            return line
        }

        return CardOCRParse(songQuery: song, callerLine: callerLine, notesLine: notesLine)
    }

    static func normalizedCallerWord(from parse: CardOCRParse) -> String? {
        parse.callerLine.flatMap { normalizeWord($0) }
    }

    static func normalizedNotesWord(from parse: CardOCRParse) -> String? {
        parse.notesLine.flatMap { normalizeWord($0) }
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
