import AVFoundation
import Foundation

/// Replicate token + MusicGen Melody generation for the lab.
///
/// The token belongs to the person testing the app and is kept in the same Keychain service as the
/// OpenAI key. It must never be bundled with a distributed build: a production version needs a backend.
enum ReplicateMusicBoxSettings {
    private static let keychainAccount = "replicate.apiToken"

    static var token: String? {
        guard let token = Keychain.get(account: keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return nil }
        return token
    }

    static var isConfigured: Bool { token != nil }

    static var tokenHint: String? {
        guard let token else { return nil }
        return "••••" + String(token.suffix(4))
    }

    static func saveToken(_ token: String?) {
        Keychain.set(token?.trimmingCharacters(in: .whitespacesAndNewlines), account: keychainAccount)
    }

    static let tokensURL = URL(string: "https://replicate.com/account/api-tokens")!
}

enum ReplicateMusicBoxError: LocalizedError {
    case missingToken
    case http(String, Int, String)
    case failed(String)
    case timedOut
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Add your Replicate API token first."
        case .http(let stage, let code, let message):
            return "Replicate HTTP \(code) [\(stage)]: \(message)"
        case .failed(let message):
            return "MusicGen failed: \(message)"
        case .timedOut:
            return "MusicGen took too long. Try generating again."
        case .invalidResponse(let stage):
            return "Replicate returned an unexpected response [\(stage)]."
        }
    }
}

struct ReplicateMusicBoxClient: Sendable {
    private static let modelURL = URL(string: "https://api.replicate.com/v1/models/meta/musicgen")!
    private static let predictionsURL = URL(string: "https://api.replicate.com/v1/predictions")!

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    /// Generates a 30-second version of the selected preview and downloads the resulting WAV.
    func generate(
        track: PreviewTrack,
        songData: Data,
        style: MusicBoxStyle,
        onPredictionCreated: @escaping @Sendable (String) -> Void,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        guard let token = ReplicateMusicBoxSettings.token else {
            Self.log("✗ token missing · Keychain has no Replicate token", sync: true)
            throw ReplicateMusicBoxError.missingToken
        }

        let started = Date()
        Self.log("start · track=\(track.title) — \(track.artist) · source=\(track.source.rawValue) · style=\(style.rawValue)")
        Self.log("token · present=true · chars=\(token.count) · suffix=\(String(token.suffix(4))) · songData=\(songData.count / 1024) KB")
        Self.log("preview · scheme=\(track.previewURL.scheme ?? "?") · host=\(track.previewURL.host ?? "?") · pathExt=\(track.previewURL.pathExtension.isEmpty ? "none" : track.previewURL.pathExtension)")

        onStatus("Checking the MusicGen model…")
        let version = try await fetchLatestVersion(token: token)
        Self.log("model ready · version=\(Self.shortID(version)) · elapsed=\(Self.elapsed(since: started))")

        onStatus("Sending the song to MusicGen…")
        var prediction = try await createPrediction(token: token, version: version, track: track, songData: songData, style: style)
        onPredictionCreated(prediction.id)
        Self.logPrediction("created", prediction)

        let deadline = Date().addingTimeInterval(240)
        var poll = 0
        var lastStatus = prediction.status
        while !prediction.isTerminal {
            try Task.checkCancellation()
            guard Date() < deadline else {
                Self.log("✗ timeout · prediction=\(prediction.id) · lastStatus=\(prediction.status) · elapsed=\(Self.elapsed(since: started))", sync: true)
                throw ReplicateMusicBoxError.timedOut
            }
            onStatus(Self.statusText(prediction.status))
            try await Task.sleep(nanoseconds: 3_000_000_000)
            poll += 1
            prediction = try await fetchPrediction(token: token, prediction: prediction)
            if prediction.status != lastStatus || prediction.isTerminal {
                Self.logPrediction("poll \(poll)", prediction)
                lastStatus = prediction.status
            } else {
                Self.log("poll \(poll) · prediction=\(prediction.id) · status=\(prediction.status) · elapsed=\(Self.elapsed(since: started))")
            }
        }

        if prediction.status == "failed" || prediction.status == "canceled" {
            Self.log("✗ prediction ended · id=\(prediction.id) · status=\(prediction.status) · error=\(prediction.errorText ?? "none")", sync: true)
            throw ReplicateMusicBoxError.failed(prediction.errorText ?? prediction.status)
        }
        guard prediction.status == "succeeded", let outputURL = prediction.outputURL else {
            Self.log("✗ succeeded without output URL · id=\(prediction.id) · status=\(prediction.status)", sync: true)
            throw ReplicateMusicBoxError.invalidResponse("output")
        }

        onStatus("Downloading the AI version…")
        Self.log("download start · host=\(outputURL.host ?? "?") · pathExt=\(outputURL.pathExtension.isEmpty ? "none" : outputURL.pathExtension)")
        do {
            let (data, response) = try await session.data(from: outputURL)
            Self.logHTTP("download", response: response, data: data)
            try Self.check("download", response: response, data: data)
            guard !data.isEmpty else { throw ReplicateMusicBoxError.invalidResponse("download-empty") }
            Self.log("download ready · bytes=\(data.count) · elapsed=\(Self.elapsed(since: started))")
            return data
        } catch let error as ReplicateMusicBoxError {
            throw error
        } catch {
            Self.log("✗ download transport · \(Self.describe(error))", sync: true)
            throw error
        }
    }

    func cancel(predictionID: String) async {
        guard let token = ReplicateMusicBoxSettings.token,
              let url = URL(string: "https://api.replicate.com/v1/predictions/\(predictionID)/cancel") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            Self.logHTTP("cancel", response: response, data: data)
        } catch {
            Self.log("cancel transport · prediction=\(predictionID) · \(Self.describe(error))")
        }
    }

    // MARK: Model

    private func fetchLatestVersion(token: String) async throws -> String {
        var request = URLRequest(url: Self.modelURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Self.logRequest("model", request: request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.log("✗ model transport · \(Self.describe(error))", sync: true)
            throw error
        }
        Self.logHTTP("model", response: response, data: data)
        try Self.check("model", response: response, data: data)

        do {
            let model = try JSONDecoder().decode(ModelInfo.self, from: data)
            guard let version = model.latestVersion?.id, !version.isEmpty else {
                Self.log("✗ model response has no latest_version · body=\(Self.bodyPreview(data))", sync: true)
                throw ReplicateMusicBoxError.invalidResponse("model-version")
            }
            return version
        } catch let error as ReplicateMusicBoxError {
            throw error
        } catch {
            Self.log("✗ model decode · \(Self.describe(error)) · body=\(Self.bodyPreview(data))", sync: true)
            throw error
        }
    }

    // MARK: Predictions

    private func createPrediction(
        token: String,
        version: String,
        track: PreviewTrack,
        songData: Data,
        style: MusicBoxStyle
    ) async throws -> Prediction {
        let inputAudio = Self.inputAudio(track: track, songData: songData)
        let input = Input(
            modelVersion: "melody-large",
            prompt: style.aiPrompt,
            inputAudio: inputAudio,
            duration: 30,
            continuation: false,
            normalizationStrategy: "loudness",
            topK: 250,
            topP: 0,
            temperature: 0.7,
            classifierFreeGuidance: 4,
            outputFormat: "wav",
            seed: Self.seed(track: track, style: style)
        )
        let body = CreateRequest(version: version, input: input)
        let encodedBody = try JSONEncoder().encode(body)

        var request = URLRequest(url: Self.predictionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = encodedBody
        Self.logRequest("create", request: request)
        Self.log("create payload · version=\(Self.shortID(version)) · modelVersion=\(input.modelVersion) · body=\(encodedBody.count / 1024) KB · inputAudio=\(Self.inputDescription(inputAudio)) · promptChars=\(style.aiPrompt.count) · duration=30 · seed=\(input.seed)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.log("✗ create transport · \(Self.describe(error))", sync: true)
            throw error
        }
        Self.logHTTP("create", response: response, data: data)
        try Self.check("create", response: response, data: data)
        do {
            return try JSONDecoder().decode(Prediction.self, from: data)
        } catch {
            Self.log("✗ create decode · \(Self.describe(error)) · body=\(Self.bodyPreview(data))", sync: true)
            throw error
        }
    }

    private func fetchPrediction(token: String, prediction: Prediction) async throws -> Prediction {
        let url = prediction.urls?.get ?? URL(string: "https://api.replicate.com/v1/predictions/\(prediction.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.log("✗ poll transport · prediction=\(prediction.id) · \(Self.describe(error))", sync: true)
            throw error
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Self.logHTTP("poll", response: response, data: data)
        }
        try Self.check("poll", response: response, data: data)
        do {
            return try JSONDecoder().decode(Prediction.self, from: data)
        } catch {
            Self.log("✗ poll decode · prediction=\(prediction.id) · \(Self.describe(error)) · body=\(Self.bodyPreview(data))", sync: true)
            throw error
        }
    }

    // MARK: Input

    private static func inputAudio(track: PreviewTrack, songData: Data) -> String {
        // iTunes and Deezer previews are already hosted, so Replicate can fetch them directly.
        if track.source != .imported {
            return track.previewURL.absoluteString
        }
        // Imported files only exist on the iPhone; send those as a data URI instead.
        let mime: String
        switch track.fileTypeHint {
        case AVFileType.mp3.rawValue: mime = "audio/mpeg"
        case AVFileType.wav.rawValue: mime = "audio/wav"
        case AVFileType.caf.rawValue: mime = "audio/x-caf"
        case AVFileType.aiff.rawValue: mime = "audio/aiff"
        default: mime = "audio/mp4"
        }
        return "data:\(mime);base64,\(songData.base64EncodedString())"
    }

    private static func inputDescription(_ inputAudio: String) -> String {
        guard let url = URL(string: inputAudio), url.scheme != nil, !inputAudio.hasPrefix("data:") else {
            return "dataURI(chars=\(inputAudio.count))"
        }
        return "hosted(host=\(url.host ?? "?"), pathExt=\(url.pathExtension.isEmpty ? "none" : url.pathExtension))"
    }

    private static func seed(track: PreviewTrack, style: MusicBoxStyle) -> Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in (track.id + "|" + style.rawValue).utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(hash % 2_147_483_647)
    }

    private static func statusText(_ status: String) -> String {
        switch status {
        case "starting": return "MusicGen is starting…"
        case "processing": return "MusicGen is creating the version…"
        case "succeeded": return "Downloading the AI version…"
        default: return "MusicGen status: \(status)…"
        }
    }

    // MARK: HTTP + logging

    private static func check(_ stage: String, response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        var message = "Request failed."
        if let data,
           let error = try? JSONDecoder().decode(ReplicateError.self, from: data) {
            message = error.detail ?? error.title ?? message
        }
        log("✗ HTTP \(http.statusCode) [\(stage)] · \(message) · body=\(data.map(bodyPreview) ?? "none")", sync: true)
        throw ReplicateMusicBoxError.http(stage, http.statusCode, message)
    }

    private static func logRequest(_ stage: String, request: URLRequest) {
        let url = request.url?.absoluteString ?? "?"
        log("\(stage) → \(request.httpMethod ?? "?") \(url) · body=\(request.httpBody?.count ?? 0) B")
    }

    private static func logHTTP(_ stage: String, response: URLResponse, data: Data) {
        guard let http = response as? HTTPURLResponse else {
            log("\(stage) ← non-HTTP response · bytes=\(data.count)")
            return
        }
        let headers = http.allHeaderFields
        let requestID = headers["x-request-id"] ?? headers["X-Request-Id"] ?? headers["cf-ray"] ?? "?"
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "?"
        let isError = !(200..<300).contains(http.statusCode)
        let body = isError ? " · body=\(bodyPreview(data))" : ""
        log("\(stage) ← HTTP \(http.statusCode) · bytes=\(data.count) · type=\(contentType) · requestID=\(String(describing: requestID))\(body)", sync: isError)
    }

    private static func logPrediction(_ stage: String, _ prediction: Prediction) {
        let getHost = prediction.urls?.get?.host ?? "none"
        let outputHost = prediction.outputURL?.host ?? "none"
        log("\(stage) · prediction=\(prediction.id) · status=\(prediction.status) · getHost=\(getHost) · outputHost=\(outputHost) · error=\(prediction.errorText ?? "none")")
    }

    private static func bodyPreview(_ data: Data) -> String {
        let text = String(decoding: data.prefix(1200), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "empty" : text
    }

    private static func shortID(_ id: String) -> String {
        "\(id.prefix(8))…\(id.suffix(6)) (\(id.count) chars)"
    }

    private static func elapsed(since date: Date) -> String {
        String(format: "%.1fs", Date().timeIntervalSince(date))
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(error.localizedDescription)"
    }

    private static func log(_ message: String, sync: Bool = false) {
        // Always stored in the app log so a failed lab run can be inspected on device.
        DebugLog.shared.log("[MUSICBOX-AI][NET] \(message)", sync: sync)
    }

    // MARK: API models

    private struct ModelInfo: Decodable {
        struct Version: Decodable {
            let id: String
        }

        let latestVersion: Version?

        enum CodingKeys: String, CodingKey {
            case latestVersion = "latest_version"
        }
    }

    private struct CreateRequest: Encodable {
        let version: String
        let input: Input
    }

    private struct Input: Encodable {
        let modelVersion: String
        let prompt: String
        let inputAudio: String
        let duration: Int
        let continuation: Bool
        let normalizationStrategy: String
        let topK: Int
        let topP: Double
        let temperature: Double
        let classifierFreeGuidance: Int
        let outputFormat: String
        let seed: Int

        enum CodingKeys: String, CodingKey {
            case modelVersion = "model_version"
            case prompt
            case inputAudio = "input_audio"
            case duration
            case continuation
            case normalizationStrategy = "normalization_strategy"
            case topK = "top_k"
            case topP = "top_p"
            case temperature
            case classifierFreeGuidance = "classifier_free_guidance"
            case outputFormat = "output_format"
            case seed
        }
    }

    private struct ReplicateError: Decodable {
        let detail: String?
        let title: String?
        let status: Int?
    }

    private struct Prediction: Decodable {
        struct URLs: Decodable {
            let get: URL?
            let cancel: URL?
        }

        enum FlexibleOutput: Decodable {
            case url(String)
            case urls([String])
            case none

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    self = .none
                } else if let value = try? container.decode(String.self) {
                    self = .url(value)
                } else if let values = try? container.decode([String].self) {
                    self = .urls(values)
                } else {
                    self = .none
                }
            }
        }

        enum FlexibleError: Decodable {
            case text(String)
            case none

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    self = .none
                } else if let value = try? container.decode(String.self) {
                    self = .text(value)
                } else {
                    self = .none
                }
            }
        }

        let id: String
        let status: String
        let output: FlexibleOutput?
        let error: FlexibleError?
        let urls: URLs?

        var isTerminal: Bool {
            ["succeeded", "failed", "canceled"].contains(status)
        }

        var outputURL: URL? {
            guard let output else { return nil }
            switch output {
            case .url(let value): return URL(string: value)
            case .urls(let values): return values.first.flatMap(URL.init(string:))
            case .none: return nil
            }
        }

        var errorText: String? {
            if case .text(let value) = error { return value }
            return nil
        }
    }
}

extension MusicBoxStyle {
    var aiPrompt: String {
        switch self {
        case .musicBox:
            return "Solo antique ballerina music box playing the exact recognizable melody, delicate metal comb, sparse and elegant, no vocals, no drums, no piano, no other instruments"
        case .nokia:
            return "Solo monophonic vintage Nokia mobile phone ringtone playing the exact recognizable melody, square-wave beeps, one note at a time, no vocals, no drums, no chords, no accompaniment"
        case .polyphonic:
            return "2000s polyphonic mobile phone MIDI ringtone playing the exact recognizable melody, bright synthetic lead and simple bass, no vocals, no singing, no acoustic instruments"
        case .marimba:
            return "Solo iPhone marimba ringtone playing the exact recognizable melody, soft wooden marimba with gentle bass, clean and simple, no vocals, no drums, no other instruments"
        }
    }
}
