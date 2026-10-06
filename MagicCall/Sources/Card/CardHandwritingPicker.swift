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
        if song.isEmpty, hasSong { song = "\(title) \(artist)".trimmingCharacters(in: .whitespaces) }
        return CardOCRParse(
            songQuery: song,
            callerLine: expectCaller && hasCallerWord ? callerWord : nil,
            notesLine: expectNotes && hasNotesWord ? notesWord : nil
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

        let instructions = """
        You read a photo of a handwritten performance card (black ink, often ALL CAPS). \
        Layout top → bottom: \(layout).

        The local OCR hint (may be wrong) is only a hint — trust the image first:
        \"\"\"\(visionOCRHint)\"\"\"

        Rules:
        1. **Line 1** = song for a music store search. Fix handwriting/OCR errors (e.g. LOSE tURSeS → Lose Yourself, EMiNEM → Eminem).
        2. \(expectCallerLine ? "**Line 2** = single caller-name word for incoming call ID." : "Ignore line 2 (not used).")
        3. \(expectNotesLine ? "**Line 3** = single word for Notes contact chip." : "Ignore line 3 (not used).")
        4. search_query = best iTunes/Deezer query: "Title Artist".
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
        guard let pick = try? JSONDecoder().decode(CardHandwritingPick.self, from: Data(text.utf8)) else {
            throw CardHandwritingPickerError.badOutput(text)
        }
        return pick
    }
}
