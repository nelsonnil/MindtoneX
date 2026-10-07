import Foundation

struct CardHandwritingPick: Equatable, Codable {
    var hasSong: Bool
    var title: String
    var artist: String
    var searchQuery: String
    var confidence: Double
    var reasoning: String
    var hasCallerWord: Bool
    var callerWord: String
    var hasNotesWord: Bool
    var notesWord: String

    enum CodingKeys: String, CodingKey {
        case hasSong = "has_song"
        case title, artist
        case searchQuery = "search_query"
        case confidence, reasoning
        case hasCallerWord = "has_caller_word"
        case callerWord = "caller_word"
        case hasNotesWord = "has_notes_word"
        case notesWord = "notes_word"
    }

    mutating func reconcile(withHintLines hintLines: [String], expectCallerLine: Bool, expectNotesLine: Bool) {
        let lines = CardLineParser.expandMergedOCRLines(hintLines)
        let visionSongComplete = hasSong && title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2

        if !expectCallerLine && !expectNotesLine {
            hasCallerWord = false
            callerWord = ""
            hasNotesWord = false
            notesWord = ""
            if !visionSongComplete {
                Self.mergeSongFields(from: lines, into: &self)
            }
        } else {
            let reserved = (expectCallerLine ? 1 : 0) + (expectNotesLine ? 1 : 0)
            let songLineCount = max(0, lines.count - reserved)
            let songLines = songLineCount > 0 ? Array(lines.prefix(songLineCount)) : lines
            if !visionSongComplete {
                Self.mergeSongFields(from: songLines, into: &self)
            }

            if expectCallerLine {
                if !hasCallerWord || callerWord.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    let callerIndex = lines.count - reserved
                    if reserved > 0, callerIndex >= 0, callerIndex < lines.count {
                        let callerCandidate = lines[callerIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                        if let w = CardLineParser.normalizeWord(callerCandidate) {
                            callerWord = w
                            hasCallerWord = true
                        } else {
                            hasCallerWord = false
                            callerWord = ""
                        }
                    } else {
                        hasCallerWord = false
                        callerWord = ""
                    }
                }
            } else {
                hasCallerWord = false
                callerWord = ""
            }

            if expectNotesLine {
                if !hasNotesWord || notesWord.trimmingCharacters(in: .whitespacesAndNewlines).count < 2,
                   let last = lines.last, lines.count >= reserved, reserved > 0 {
                    if let w = CardLineParser.normalizeWord(last) {
                        notesWord = w
                        hasNotesWord = true
                    }
                }
            } else {
                hasNotesWord = false
                notesWord = ""
            }
        }

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = Self.buildSearchQuery(title: title, artist: artist, raw: searchQuery)

        if expectCallerLine, hasCallerWord {
            let cw = callerWord.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.callerLooksLikeSongFragment(cw, title: title, artist: artist) {
                hasCallerWord = false
                callerWord = ""
            }
        }
    }

    private static func mergeSongFields(from lines: [String], into pick: inout CardHandwritingPick) {
        guard !lines.isEmpty else { return }
        if lines.count == 1 {
            let one = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if let dash = one.range(of: " - ") {
                let a = String(one[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
                let t = String(one[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
                if pick.artist.isEmpty { pick.artist = a }
                if pick.title.count < 3 { pick.title = t }
            } else if pick.title.isEmpty, pick.artist.isEmpty {
                pick.title = one
            }
            return
        }
        let l0 = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let l1 = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if pick.artist.isEmpty { pick.artist = l0 }
        if pick.title.count < 3 { pick.title = l1 }
        if lines.count > 2, pick.title.count < 4 {
            pick.title = lines.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
        }
    }

    func storeSearchQueries() -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let q = CardTextMapper.clean(s)
            guard q.count >= 2 else { return }
            if !out.contains(where: { ApiJSON.sameText($0, q) }) { out.append(q) }
        }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let built = Self.buildSearchQuery(title: t, artist: a, raw: searchQuery)
        if !built.isEmpty { add(built) }
        if !t.isEmpty, !a.isEmpty {
            add("\(t) \(a)")
            add("\(a) \(t)")
        }
        if !t.isEmpty { add(t) }
        if t.isEmpty, !a.isEmpty { add(a) }
        return Array(out.prefix(4))
    }

    /// Second pass when the primary queries miss (simpler title, no feat./punctuation).
    func storeSearchRetryQueries() -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let q = CardTextMapper.clean(s)
            guard q.count >= 2 else { return }
            if !out.contains(where: { ApiJSON.sameText($0, q) }) { out.append(q) }
        }
        let t = Self.simplifiedSongTitle(title)
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !a.isEmpty {
            add("\(t) \(a)")
            add("\(a) \(t)")
        }
        if !t.isEmpty { add(t) }
        return Array(out.prefix(3))
    }

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

    func asSongPick() -> SongPick? {
        guard hasSong else { return nil }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        return SongPick(
            hasSong: true,
            title: title,
            artist: artist,
            searchQuery: q,
            confidence: confidence,
            reasoning: reasoning
        )
    }

    func asOCRParse(expectCaller: Bool, expectNotes: Bool) -> CardOCRParse {
        var song = searchQuery
        if song.isEmpty, hasSong { song = Self.buildSearchQuery(title: title, artist: artist, raw: "") }
        return CardOCRParse(
            songQuery: song,
            callerLine: expectCaller && hasCallerWord ? callerWord : nil,
            notesLine: expectNotes && hasNotesWord ? notesWord : nil
        )
    }

    private static func buildSearchQuery(title: String, artist: String, raw: String) -> String {
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

    private static func callerLooksLikeSongFragment(_ caller: String, title: String, artist: String) -> Bool {
        let c = caller.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let blob = (title + " " + artist).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard c.count >= 2 else { return true }
        if blob.contains(c) { return true }
        for word in title.split(separator: " ") where String(word).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == c {
            return true
        }
        return false
    }
}

enum CardHandwritingPickerError: LocalizedError {
    case noAPIKey
    case encodeImage
    case http(Int, String)
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "OpenAI token missing (Voice → Connection)."
        case .encodeImage: return "Could not encode camera frame."
        case .http(let c, _): return "Vision service unavailable (HTTP \(c))."
        case .badOutput: return "Could not read the card."
        }
    }
}

/// OpenAI vision: handwritten card → song + optional caller / Notes words (fixes OCR typos).
enum CardHandwritingPicker {
    static func pick(
        jpeg: Data,
        visionOCRHint: String,
        expectCallerLine: Bool,
        expectNotesLine: Bool
    ) async throws -> CardHandwritingPick {
        guard let apiKey = VoiceSettings.apiKey else { throw CardHandwritingPickerError.noAPIKey }
        let model = VoiceSettings.pickerModel
        let b64 = jpeg.base64EncodedString()
        let lang = CardSettings.handwritingLanguage.openAIHint

        let instructions = """
        You read a photo of a handwritten performance card (black ink, often ALL CAPS). \
        Use the **whole image** as the source of truth — infer song title and artist from handwriting anywhere on the card. \
        \(lang)
        Typical layout (flexible): \(CardOCRLayout.lineAssignmentSummary)

        Optional OCR hint (often wrong — do not follow line numbers blindly):
        \"\"\"\(visionOCRHint)\"\"\"

        \(CardOCRLayout.openAIVisionRules)

        Fix handwriting/OCR (YOULSELF → Yourself). If unreadable, has_song=false.
        confidence 0–1. reasoning: one short English sentence (max 25 words).
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "has_song": ["type": "boolean"],
                "title": ["type": "string"],
                "artist": ["type": "string"],
                "search_query": ["type": "string"],
                "confidence": ["type": "number"],
                "reasoning": ["type": "string"],
                "has_caller_word": ["type": "boolean"],
                "caller_word": ["type": "string"],
                "has_notes_word": ["type": "boolean"],
                "notes_word": ["type": "string"],
            ],
            "required": [
                "has_song", "title", "artist", "search_query", "confidence", "reasoning",
                "has_caller_word", "caller_word", "has_notes_word", "notes_word",
            ],
            "additionalProperties": false,
        ]

        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": "Read this card and return JSON."],
                        ["type": "input_image", "image_url": "data:image/jpeg;base64,\(b64)"],
                    ],
                ],
            ],
            "text": ["format": ["type": "json_schema", "name": "card_handwriting", "strict": true, "schema": schema]],
            "store": false,
            "max_output_tokens": 1200,
        ]
        if model.hasPrefix("gpt-5") || model.hasPrefix("gpt-6") || model.hasPrefix("o") {
            body["reasoning"] = ["effort": "low"]
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await SongPicker.openAISession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw CardHandwritingPickerError.http(status, String(decoding: data, as: UTF8.self))
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = SongPicker.outputText(json) else {
            throw CardHandwritingPickerError.badOutput(String(decoding: data, as: UTF8.self))
        }
        guard var pick = try? JSONDecoder().decode(CardHandwritingPick.self, from: Data(text.utf8)) else {
            throw CardHandwritingPickerError.badOutput(text)
        }
        let hintLines = visionOCRHint.components(separatedBy: .newlines)
        pick.reconcile(withHintLines: hintLines, expectCallerLine: expectCallerLine, expectNotesLine: expectNotesLine)
        return pick
    }
}
