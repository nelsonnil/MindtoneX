import Foundation

struct SongPick: Equatable, Codable {
    var hasSong: Bool
    var title: String
    var artist: String
    var searchQuery: String
    var confidence: Double
    var reasoning: String

    enum CodingKeys: String, CodingKey {
        case hasSong = "has_song"
        case title, artist
        case searchQuery = "search_query"
        case confidence, reasoning
    }

    var label: String { artist.isEmpty ? title : "\(title) — \(artist)" }

    /// Same song regardless of casing, accents or punctuation.
    var key: String {
        (title + "|" + artist)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == "|" }
    }
}

enum SongPickerError: LocalizedError {
    case http(Int, String)
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, _): return "Speech service unavailable (HTTP \(code))."
        case .badOutput: return "Couldn't match a song from what was said."
        }
    }
}

enum SongPicker {
    static func pick(transcript: String, previous: SongPick?) async throws -> SongPick? {
        if let key = VoiceSettings.apiKey {
            return try await openAI(transcript: transcript, previous: previous, apiKey: key, model: VoiceSettings.pickerModel)
        }
        return heuristic(transcript: transcript)
    }

    // MARK: OpenAI Responses API + structured output

    static let instructions = """
    You listen, through one phone microphone, to a live conversation during a magic trick. The magician (performer) asks a spectator to name any song. You get an automatic speech-recognition transcript: no speaker labels, possible recognition errors, and English titles may be spelled the way a Spanish speaker pronounces them (e.g. "bojemian rapsodi" = "Bohemian Rhapsody", "dispasito" = "Despacito"). Spanish, English, or a mix.

    Decide which song the SPECTATOR has finally chosen.

    Rules:
    1. Ignore songs the magician mentions as examples, suggestions or hypotheticals ("por ejemplo", "como", "cualquiera, puede ser…", "no sé, tipo…", "for example", "like", "any song, even…"), songs in questions he asks, and songs mentioned while explaining the trick.
    2. The choice is normally the answer right after the request ("¿qué canción?", "dime una canción", "name a song"). A confirmation ("sí, esa", "esa misma", "yes, that one") or the magician repeating it back ("¿Thriller? perfecto") confirms the previous answer.
    3. Changes of mind: the LAST commitment wins ("Despacito… no, mejor Thriller" → Thriller; "o no, espera", "cambio", "actually", "better", "la otra"). If the spectator retracts without naming a new song, return has_song=false unless an earlier answer is clearly re-confirmed.
    4. Return the official title and main artist with canonical spelling, in the song's original language. If only an artist or a lyric is given, pick that artist's most famous matching song only when it is reasonably clear, with lower confidence.
    5. If no song has been chosen yet, return has_song=false with empty title, artist and search_query.
    6. confidence (0 to 1) = how sure you are that this is the spectator's final choice AND that it is identified correctly.
    7. search_query = text for a music store search: "title artist".
    8. reasoning: one short English sentence (max 25 words) saying who said what.

    Examples:
    - "Piensa en una canción, la que quieras, por ejemplo Despacito o Yesterday. ¿Cuál? — Mmm… Thriller." → Thriller, Michael Jackson, high confidence.
    - "Dime una canción. — La Macarena. No, no, mejor Bohemian Rhapsody." → Bohemian Rhapsody, Queen.
    - "Any song you like, could be anything, Shakira, whatever. — Hmm, let me think…" → has_song=false.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "has_song": ["type": "boolean"],
            "title": ["type": "string"],
            "artist": ["type": "string"],
            "search_query": ["type": "string"],
            "confidence": ["type": "number"],
            "reasoning": ["type": "string"],
        ],
        "required": ["has_song", "title", "artist", "search_query", "confidence", "reasoning"],
        "additionalProperties": false,
    ]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static func openAI(transcript: String, previous: SongPick?, apiKey: String, model: String) async throws -> SongPick {
        let previousText = previous.map { "\($0.label) (confidence \(String(format: "%.2f", $0.confidence)))" } ?? "none"
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": "Transcript so far, oldest first:\n\"\"\"\n\(transcript)\n\"\"\"\n\nYour previous answer: \(previousText). Re-read the whole transcript and answer again.",
            "text": ["format": ["type": "json_schema", "name": "spectator_song", "strict": true, "schema": schema]],
            "store": false,
            "max_output_tokens": 2000,
        ]
        if model.hasPrefix("gpt-5") || model.hasPrefix("gpt-6") || model.hasPrefix("o") {
            body["reasoning"] = ["effort": "low"]
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SongPickerError.http(status, String(decoding: data, as: UTF8.self)) }

        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = outputText(json) else {
            throw SongPickerError.badOutput(String(decoding: data, as: UTF8.self))
        }
        guard let pick = try? JSONDecoder().decode(SongPick.self, from: Data(text.utf8)) else {
            throw SongPickerError.badOutput(text)
        }
        return pick
    }

    private static func outputText(_ json: [String: Any]) -> String? {
        if let text = json["output_text"] as? String, !text.isEmpty { return text }
        for item in json["output"] as? [[String: Any]] ?? [] where item["type"] as? String == "message" {
            for part in item["content"] as? [[String: Any]] ?? [] {
                if part["type"] as? String == "output_text", let text = part["text"] as? String { return text }
                if part["type"] as? String == "refusal" { return nil }
            }
        }
        return nil
    }

    // MARK: Offline fallback (no API key)

    private static let commitCues = [
        "mejor", "elijo", "escojo", "me quedo con", "la cancion es", "mi cancion es", "quiero", "pon", "ponme",
        "i choose", "i pick", "my song is", "actually", "let's go with", "lets go with", "i'll go with", "ill go with",
    ]
    private static let exampleCues = ["por ejemplo", "como ", "cualquiera", "puede ser", "for example", "like ", "any song", "anything"]
    private static let fillers: Set<String> = [
        "no", "si", "sí", "pues", "eh", "em", "mmm", "hmm", "la", "el", "de", "una", "un", "yes", "yeah", "the", "um", "uh", "vale", "ok", "okay",
    ]

    /// Very rough guess: the words after the last commitment cue, or the last short answer that
    /// isn't a question or an example. The preview lookup then validates it.
    static func heuristic(transcript: String) -> SongPick? {
        let folded = transcript.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let sentences = folded
            .components(separatedBy: CharacterSet(charactersIn: ".!?¿¡\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }

        var bestCue: (range: Range<String.Index>, cue: String)?
        for cue in commitCues {
            if let r = folded.range(of: cue, options: .backwards), bestCue == nil || r.lowerBound > bestCue!.range.lowerBound {
                bestCue = (r, cue)
            }
        }
        var candidate: String?
        if let bestCue {
            let tail = folded[bestCue.range.upperBound...]
            candidate = tail.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first
        } else {
            candidate = sentences.reversed().first { s in
                let words = s.split(separator: " ")
                return (1...7).contains(words.count) && !exampleCues.contains(where: { s.contains($0) })
            }
        }
        guard var text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) else { return nil }
        var words = text.split(separator: " ").map(String.init)
        while let first = words.first, fillers.contains(first) { words.removeFirst() }
        text = words.joined(separator: " ")
        guard text.count >= 3 else { return nil }
        return SongPick(hasSong: true, title: text, artist: "", searchQuery: text, confidence: 0.6,
                        reasoning: "Offline guess (no API key): last short answer\(bestCue.map { " after “\($0.cue)”" } ?? "").")
    }
}
