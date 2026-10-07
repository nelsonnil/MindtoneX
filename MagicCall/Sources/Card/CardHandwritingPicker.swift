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
        if lines.count >= 2, !lines[0].contains("-") {
            let l0 = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let l1 = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if l0.count >= 2, l1.count >= 3 {
                if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    artist = l0
                }
                if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 {
                    title = l1
                }
            }
        }
        let songPhysicalLines = (lines.count >= 2 && !lines[0].contains("-") && lines[1].split(whereSeparator: { $0.isWhitespace }).count >= 2) ? 2 : 1
        if expectCallerLine {
            if lines.count > songPhysicalLines {
                let callerCandidate = lines[songPhysicalLines].trimmingCharacters(in: .whitespacesAndNewlines)
                let tokens = callerCandidate.split(whereSeparator: { $0.isWhitespace })
                if tokens.count == 1, let w = CardLineParser.normalizeWord(callerCandidate) {
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
        if expectNotesLine, lines.count > songPhysicalLines + 1 {
            let notesCandidate = lines[songPhysicalLines + 1]
            if let w = CardLineParser.normalizeWord(notesCandidate) {
                notesWord = w
                hasNotesWord = true
            }
        }

        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = Self.buildSearchQuery(title: title, artist: artist, raw: searchQuery)

        if expectCallerLine, hasCallerWord {
            let cw = callerWord.trimmingCharacters(in: .whitespacesAndNewlines)
            if cw.split(whereSeparator: { $0.isWhitespace }).count > 1 || Self.callerLooksLikeSongFragment(cw, title: title, artist: artist) {
                hasCallerWord = false
                callerWord = ""
            }
        }
    }

    func storeSearchQueries() -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let q = CardTextMapper.clean(s)
            guard q.count >= 2 else { return }
            if !out.contains(where: { ApiJSON.sameText($0, q) }) { out.append(q) }
        }
        add(searchQuery)
        add("\(title) \(artist)")
        add(title)
        if !artist.isEmpty { add("\(title) \(artist)".trimmingCharacters(in: .whitespaces)) }
        return out
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
        let layout = CardOCRLayout.lineAssignmentSummary
        let lang = CardSettings.handwritingLanguage.openAIHint

        let instructions = """
        You read a photo of a handwritten performance card (black ink, often ALL CAPS). \
        \(lang)
        Layout top → bottom: \(layout).

        The local OCR hint (may be wrong) is only a hint — trust the image first:
        \"\"\"\(visionOCRHint)\"\"\"

        Rules:
        1. **Song lines:** Often line 1 = artist only (e.g. EMINEM) and line 2 = song title (LOSE YOURSELF). \
        Merge into title + artist. Fix OCR (YOULSELF → Yourself). Never put artist twice in search_query.
        2. search_query MUST be "Title Artist" (example: "Lose Yourself Eminem"). Never "Artist Artist".
        3. \(expectCallerLine ? "**Line 2** is ONLY the song title when line 1 is artist. **Caller word** is a separate physical line below the song — one word (e.g. NERVOUS). Never use a word from the song title as caller_word." : "Ignore caller line.")
        4. \(expectNotesLine ? "**Line 3** = single Notes chip word (separate line)." : "Ignore Notes line.")
        5. If unreadable, has_song=false and empty fields.
        6. confidence 0–1. reasoning: one short English sentence (max 25 words).
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
