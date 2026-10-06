import Foundation

struct WordPick: Equatable, Codable {
    var hasWord: Bool
    var word: String
    var confidence: Double
    var reasoning: String

    enum CodingKeys: String, CodingKey {
        case hasWord = "has_word"
        case word, confidence, reasoning
    }

    var normalizedWord: String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SpectatorWordPicker {
    static func pick(
        channel: SpectatorListenChannel,
        transcript: String,
        previous: WordPick?
    ) async throws -> WordPick? {
        guard channel == .callerName || channel == .notesContact else { return nil }
        if let key = VoiceSettings.apiKey {
            return try await openAI(channel: channel, transcript: transcript, previous: previous, apiKey: key, model: VoiceSettings.pickerModel)
        }
        return heuristic(channel: channel, transcript: transcript)
    }

    private static func instructions(for channel: SpectatorListenChannel) -> String {
        switch channel {
        case .callerName:
            return """
            You listen to a live magic performance. The magician asks the SPECTATOR what **single word** they think was saved as the spectator's **phone contact name** (caller ID / contact label).

            Rules:
            1. Ignore the magician's examples and hypotheticals. Only the spectator's final answer counts.
            2. Return one word (or a short proper name treated as one token), lowercase unless it's a brand/name that must stay capitalized.
            3. If they haven't committed to a word yet, return has_word=false and empty word.
            4. confidence 0–1 = how sure this is their final single-word answer.
            5. reasoning: one short English sentence (max 20 words).
            """
        case .notesContact:
            return """
            You listen to a live magic performance. The magician asks the SPECTATOR what **single word** they think will appear on a **contact chip / suggestion button** inside an Apple Notes note (not the song title).

            Rules:
            1. Ignore song titles, artist names, and unrelated chat. This is ONLY the word for the Notes contact chip.
            2. Ignore magician examples. The spectator's last committed answer wins.
            3. Return one word (or short name). If unclear, has_word=false.
            4. confidence 0–1.
            5. reasoning: one short English sentence (max 20 words).
            """
        case .song:
            return ""
        }
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "has_word": ["type": "boolean"],
            "word": ["type": "string"],
            "confidence": ["type": "number"],
            "reasoning": ["type": "string"],
        ],
        "required": ["has_word", "word", "confidence", "reasoning"],
        "additionalProperties": false,
    ]

    private static func openAI(
        channel: SpectatorListenChannel,
        transcript: String,
        previous: WordPick?,
        apiKey: String,
        model: String
    ) async throws -> WordPick {
        let previousText = previous.map { "«\($0.normalizedWord)» (confidence \(String(format: "%.2f", $0.confidence)))" } ?? "none"
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions(for: channel),
            "input": "Channel: \(channel.title)\nTranscript (oldest first):\n\"\"\"\n\(transcript)\n\"\"\"\nPrevious pick: \(previousText). Re-read and answer.",
            "text": ["format": ["type": "json_schema", "name": "spectator_word", "strict": true, "schema": schema]],
            "store": false,
            "max_output_tokens": 800,
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
        guard status == 200 else { throw SongPickerError.http(status, String(decoding: data, as: UTF8.self)) }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = SongPicker.outputText(json) else {
            throw SongPickerError.badOutput(String(decoding: data, as: UTF8.self))
        }
        guard let pick = try? JSONDecoder().decode(WordPick.self, from: Data(text.utf8)) else {
            throw SongPickerError.badOutput(text)
        }
        return pick
    }

    private static func heuristic(channel: SpectatorListenChannel, transcript: String) -> WordPick? {
        let folded = transcript.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let tokens = folded.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard let last = tokens.last(where: { $0.count >= 3 && !$0.allSatisfy(\.isNumber) }) else { return nil }
        return WordPick(
            hasWord: true,
            word: last,
            confidence: 0.55,
            reasoning: "Offline guess for \(channel.title) (no API key)"
        )
    }
}
