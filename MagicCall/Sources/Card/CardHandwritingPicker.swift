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

    /// Store hit plausibly matches what vision read (rejects unrelated top results such as another song by the artist).
    func accepts(_ track: PreviewTrack) -> Bool {
        let wantTitle = PreviewService.normalize(title)
        guard wantTitle.count >= 3 else { return true }
        let gotTitle = PreviewService.normalize(track.title)
        if gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) { return true }
        let wantArtist = PreviewService.normalize(artist)
        if !wantArtist.isEmpty, gotTitle.contains(wantArtist), wantTitle.count < 4 { return false }
        return wantTitle.split(separator: " ").count <= 1
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

/// Spectators = 2: one card with two song titles — upper = spectator 1 (`_1`), lower = spectator 2 (`_2`).
struct CardTwoSongPick: Equatable, Codable {
    var hasSong1: Bool
    var title1: String
    var artist1: String
    var searchQuery1: String
    var hasSong2: Bool
    var title2: String
    var artist2: String
    var searchQuery2: String
    var confidence: Double
    var reasoning: String
    var hasCallerWord: Bool
    var callerWord: String
    var hasNotesWord: Bool
    var notesWord: String

    enum CodingKeys: String, CodingKey {
        case hasSong1 = "has_song_1"
        case title1 = "title_1"
        case artist1 = "artist_1"
        case searchQuery1 = "search_query_1"
        case hasSong2 = "has_song_2"
        case title2 = "title_2"
        case artist2 = "artist_2"
        case searchQuery2 = "search_query_2"
        case confidence, reasoning
        case hasCallerWord = "has_caller_word"
        case callerWord = "caller_word"
        case hasNotesWord = "has_notes_word"
        case notesWord = "notes_word"
    }

    /// Each song as a regular card pick, so store queries and the title check match one spectator.
    var firstSong: CardHandwritingPick {
        songPick(hasSong: hasSong1, title: title1, artist: artist1, query: searchQuery1)
    }

    var secondSong: CardHandwritingPick {
        songPick(hasSong: hasSong2, title: title2, artist: artist2, query: searchQuery2)
    }

    func wordsParse(expectCaller: Bool, expectNotes: Bool) -> CardOCRParse {
        CardOCRParse(
            songQuery: searchQuery1,
            callerLine: expectCaller && hasCallerWord ? callerWord : nil,
            notesLine: expectNotes && hasNotesWord ? notesWord : nil
        )
    }

    private func songPick(hasSong: Bool, title: String, artist: String, query: String) -> CardHandwritingPick {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return CardHandwritingPick(
            hasSong: hasSong && !(cleanTitle.isEmpty && cleanQuery.isEmpty),
            title: cleanTitle,
            artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
            searchQuery: cleanQuery,
            confidence: confidence,
            reasoning: reasoning,
            hasCallerWord: false,
            callerWord: "",
            hasNotesWord: false,
            notesWord: ""
        )
    }
}

enum CardHandwritingPickerError: LocalizedError {
    case noAPIKey
    case encodeImage
    case http(Int, String)
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "OpenAI API key missing (Performance settings)."
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
        let instructions = """
        You read a photo of a handwritten performance card (black ink, often ALL CAPS). \
        Use the **whole image** as the source of truth — infer song title and artist from handwriting anywhere on the card. \
        \(CardSettings.openAIVisionLanguageRule)
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

        let text = try await requestCardJSON(
            apiKey: apiKey,
            model: model,
            instructions: instructions,
            imageBase64: b64,
            schemaName: "card_handwriting",
            schema: schema
        )
        guard var pick = try? JSONDecoder().decode(CardHandwritingPick.self, from: Data(text.utf8)) else {
            throw CardHandwritingPickerError.badOutput(text)
        }
        let hintLines = visionOCRHint.components(separatedBy: .newlines)
        pick.reconcile(withHintLines: hintLines, expectCallerLine: expectCallerLine, expectNotesLine: expectNotesLine)
        return pick
    }

    /// Spectators = 2: two song titles on one card (upper = spectator 1, lower = spectator 2).
    static func pickTwoSongs(
        jpeg: Data,
        visionOCRHint: String,
        expectCallerLine: Bool,
        expectNotesLine: Bool
    ) async throws -> CardTwoSongPick {
        guard let apiKey = VoiceSettings.apiKey else { throw CardHandwritingPickerError.noAPIKey }
        let model = VoiceSettings.pickerModel
        let b64 = jpeg.base64EncodedString()
        let callerRule = expectCallerLine
            ? "Caller word: the first single-word line BELOW both songs (has_caller_word=true). Never take it from a song title."
            : "Caller word: not used (has_caller_word=false, caller_word empty)."
        let notesRule = expectNotesLine
            ? "Notes chip word: the bottom single-word line on the card (has_notes_word=true)."
            : "Notes word: not used (has_notes_word=false, notes_word empty)."
        let instructions = """
        You read a photo of a handwritten performance card (black ink, often ALL CAPS). \
        TWO spectators each wrote ONE song. \(CardSettings.openAIVisionLanguageRule)
        The UPPER song belongs to spectator 1 (fields ending in _1); the LOWER song belongs to spectator 2 (fields ending in _2). \
        Usually one line each: a title, sometimes with the artist ("THRILLER - MICHAEL JACKSON"). If one song wraps onto a second line, merge it.

        Optional OCR hint, top to bottom (often wrong — do not follow line numbers blindly):
        \"\"\"\(visionOCRHint)\"\"\"

        \(callerRule)
        \(notesRule)

        Fix handwriting/OCR (YOULSELF → Yourself). Add the main artist when the title is famous and unambiguous; otherwise leave artist empty. \
        search_query_1 / search_query_2 = "Title Artist" (or the title alone). An unreadable song: has_song_N=false with empty strings. \
        confidence 0–1 for the whole card. reasoning: one short English sentence (max 25 words).
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "has_song_1": ["type": "boolean"],
                "title_1": ["type": "string"],
                "artist_1": ["type": "string"],
                "search_query_1": ["type": "string"],
                "has_song_2": ["type": "boolean"],
                "title_2": ["type": "string"],
                "artist_2": ["type": "string"],
                "search_query_2": ["type": "string"],
                "confidence": ["type": "number"],
                "reasoning": ["type": "string"],
                "has_caller_word": ["type": "boolean"],
                "caller_word": ["type": "string"],
                "has_notes_word": ["type": "boolean"],
                "notes_word": ["type": "string"],
            ],
            "required": [
                "has_song_1", "title_1", "artist_1", "search_query_1",
                "has_song_2", "title_2", "artist_2", "search_query_2",
                "confidence", "reasoning",
                "has_caller_word", "caller_word", "has_notes_word", "notes_word",
            ],
            "additionalProperties": false,
        ]

        let text = try await requestCardJSON(
            apiKey: apiKey,
            model: model,
            instructions: instructions,
            imageBase64: b64,
            schemaName: "card_two_songs",
            schema: schema
        )
        guard let pick = try? JSONDecoder().decode(CardTwoSongPick.self, from: Data(text.utf8)) else {
            throw CardHandwritingPickerError.badOutput(text)
        }
        return pick
    }

    /// Responses API call with the card photo and a strict JSON schema; returns the JSON text.
    private static func requestCardJSON(
        apiKey: String,
        model: String,
        instructions: String,
        imageBase64: String,
        schemaName: String,
        schema: [String: Any]
    ) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": "Read this card and return JSON."],
                        ["type": "input_image", "image_url": "data:image/jpeg;base64,\(imageBase64)"],
                    ],
                ],
            ],
            "text": ["format": ["type": "json_schema", "name": schemaName, "strict": true, "schema": schema]],
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
        return text
    }
}
