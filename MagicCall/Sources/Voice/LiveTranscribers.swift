import AVFoundation
import Foundation
import Speech

/// A streaming speech-to-text backend. Callbacks always arrive on the main thread.
protocol LiveTranscriber: AnyObject {
    /// `itemID` groups one utterance; `text` is the whole utterance so far; `isFinal` closes it.
    var onUpdate: ((_ itemID: String, _ text: String, _ isFinal: Bool) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start() throws
    /// Called on the audio thread.
    func feed(_ buffer: AVAudioPCMBuffer, pcm16: Data?, level: Float)
    func stop()
    var wantsPCM16: Bool { get }
}

// MARK: - OpenAI Realtime transcription (WebSocket)

/// `wss://api.openai.com/v1/realtime?intent=transcription` with a `type: "transcription"` session.
///
/// `gpt-live-transcribe` has no server VAD, so the client commits each turn after a short pause
/// (or every few seconds of continuous talk). The older `gpt-4o(-mini)-transcribe` models use
/// server VAD and commit on their own.
final class OpenAIRealtimeTranscriber: NSObject, LiveTranscriber, URLSessionWebSocketDelegate {
    var onUpdate: ((String, String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    let wantsPCM16 = true

    private let apiKey: String
    private let model: String
    private let languages: [String]
    private let usesClientCommit: Bool

    private var urlSession: URLSession?
    private var socket: URLSessionWebSocketTask?
    private let queue = DispatchQueue(label: "magiccall.voice.realtime")
    private var isOpen = false
    private var stopped = false
    private var pendingBeforeOpen: [Data] = []
    private var chunk = Data()
    private var texts: [String: String] = [:]

    private let bytesPerSecond = Int(MicCapture.pcmSampleRate) * 2
    private var bytesSinceCommit = 0
    private var speechMs: Double = 0
    private var silenceMs: Double = 0
    private var heardSpeech = false
    private let speechLevel: Float = 0.012

    init(apiKey: String, model: String, languages: [String]) {
        self.apiKey = apiKey
        self.model = model
        self.languages = languages
        usesClientCommit = model.hasPrefix("gpt-live") || model == "gpt-transcribe"
    }

    func start() throws {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        urlSession = session
        socket = task
        task.resume()
        receive()
        dlog("[VOICE] OpenAI realtime connecting · model=\(model) languages=\(languages)")
    }

    func stop() {
        queue.async {
            guard !self.stopped else { return }
            self.stopped = true
            if self.isOpen, self.heardSpeech, self.bytesSinceCommit > self.bytesPerSecond / 5, self.usesClientCommit {
                self.flushChunk()
                self.send(["type": "input_audio_buffer.commit"])
            }
            self.socket?.cancel(with: .normalClosure, reason: nil)
            self.urlSession?.finishTasksAndInvalidate()
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer, pcm16: Data?, level: Float) {
        guard let pcm16, !pcm16.isEmpty else { return }
        queue.async { self.ingest(pcm16, level: level) }
    }

    // MARK: Sending

    private func ingest(_ data: Data, level: Float) {
        guard !stopped else { return }
        guard isOpen else {
            pendingBeforeOpen.append(data)
            let total = pendingBeforeOpen.reduce(0) { $0 + $1.count }
            if total > bytesPerSecond * 8 { pendingBeforeOpen.removeFirst() }
            return
        }
        chunk.append(data)
        if chunk.count >= bytesPerSecond / 10 { flushChunk() }
        guard usesClientCommit else { return }

        let ms = Double(data.count) / Double(bytesPerSecond) * 1000
        bytesSinceCommit += data.count
        if level >= speechLevel {
            speechMs += ms
            silenceMs = 0
            if speechMs >= 150 { heardSpeech = true }
        } else {
            silenceMs += ms
        }
        let longEnough = bytesSinceCommit >= bytesPerSecond * 3 / 10
        if heardSpeech, longEnough, silenceMs >= 650 || bytesSinceCommit >= bytesPerSecond * 8 {
            flushChunk()
            send(["type": "input_audio_buffer.commit"])
            resetTurn()
        } else if !heardSpeech, bytesSinceCommit >= bytesPerSecond * 15 {
            send(["type": "input_audio_buffer.clear"])
            resetTurn()
        }
    }

    private func resetTurn() {
        bytesSinceCommit = 0
        speechMs = 0
        silenceMs = 0
        heardSpeech = false
    }

    private func flushChunk() {
        guard !chunk.isEmpty else { return }
        send(["type": "input_audio_buffer.append", "audio": chunk.base64EncodedString()])
        chunk.removeAll(keepingCapacity: true)
    }

    private func sessionUpdate() -> [String: Any] {
        var transcription: [String: Any] = [
            "model": model,
            "prompt": "Live conversation during a magic trick: a magician asks a spectator to name a song. Spanish and English mixed. Song titles and artist names.",
        ]
        if usesClientCommit {
            if !languages.isEmpty { transcription["languages"] = languages }
            transcription["delay"] = "low"
        } else if languages.count == 1 {
            transcription["language"] = languages[0]
        }
        var input: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": Int(MicCapture.pcmSampleRate)],
            "transcription": transcription,
        ]
        if usesClientCommit {
            input["turn_detection"] = NSNull()
        } else {
            input["turn_detection"] = ["type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 300, "silence_duration_ms": 600] as [String: Any]
        }
        return ["type": "session.update", "session": ["type": "transcription", "audio": ["input": input]]]
    }

    private func send(_ event: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            guard let error, let self else { return }
            self.queue.async {
                guard !self.stopped else { return }
                self.report("send failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Receiving

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handle(text)
                case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
                self.receive()
            case .failure(let error):
                self.queue.async {
                    guard !self.stopped else { return }
                    self.report("connection closed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "conversation.item.input_audio_transcription.delta":
            let id = event["item_id"] as? String ?? "item"
            let delta = event["delta"] as? String ?? ""
            queue.async {
                let full = (self.texts[id] ?? "") + delta
                self.texts[id] = full
                DispatchQueue.main.async { self.onUpdate?(id, full, false) }
            }
        case "conversation.item.input_audio_transcription.completed":
            let id = event["item_id"] as? String ?? "item"
            let transcript = event["transcript"] as? String ?? ""
            queue.async {
                self.texts[id] = transcript
                DispatchQueue.main.async { self.onUpdate?(id, transcript, true) }
            }
        case "conversation.item.input_audio_transcription.failed":
            dlog("[VOICE] OpenAI transcription failed for an item: \(text.prefix(300))")
        case "session.created", "session.updated":
            dlog("[VOICE] OpenAI \(type)")
        case "error":
            let err = event["error"] as? [String: Any]
            let message = err?["message"] as? String ?? text
            let code = err?["code"] as? String ?? ""
            if code == "input_audio_buffer_commit_empty" || message.lowercased().contains("buffer too small") {
                dlog("[VOICE] OpenAI (ignored) \(message)")
            } else {
                queue.async { self.report(message) }
            }
        default:
            break
        }
    }

    private func report(_ message: String) {
        dlog("✗ [VOICE] OpenAI realtime: \(message)")
        let userMessage = Self.userFacingRealtimeError(message)
        DispatchQueue.main.async { self.onError?(userMessage) }
    }

    /// Maps vendor-branded API/WebSocket errors to neutral on-screen copy.
    private static func userFacingRealtimeError(_ message: String) -> String {
        let lower = message.lowercased()
        guard lower.contains("openai") || lower.contains("gpt") else {
            return VoiceOpenAIPreflight.scrubVendorBranding(message)
        }
        if lower.contains("api key") || lower.contains("invalid") || lower.contains("incorrect") || lower.contains("authentication") {
            return "Speech connection failed. Check your API key under Speech."
        }
        if lower.contains("quota") || lower.contains("billing") || lower.contains("insufficient") {
            return "Speech service quota reached. Check billing and try again."
        }
        if lower.contains("rate limit") {
            return "Rate limit reached. Wait a moment and try again."
        }
        return "Speech connection lost. Check your network and try again."
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async {
            guard !self.stopped else { return }
            self.isOpen = true
            self.send(self.sessionUpdate())
            let buffered = self.pendingBeforeOpen
            self.pendingBeforeOpen.removeAll()
            dlog("[VOICE] OpenAI realtime open · sending \(buffered.reduce(0) { $0 + $1.count } / 1000) KB buffered audio")
            for data in buffered { self.ingest(data, level: 0.05) }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async {
            guard !self.stopped else { return }
            let why = reason.map { String(decoding: $0, as: UTF8.self) } ?? ""
            self.report("closed by server (\(closeCode.rawValue)) \(why)")
        }
    }
}

// MARK: - Apple on-device speech

/// SFSpeechRecognizer fed from the same microphone tap. Recognition tasks are restarted every
/// ~50 s or after each final result, because Apple limits a single request to about a minute.
final class AppleSpeechTranscriber: LiveTranscriber {
    var onUpdate: ((String, String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    let wantsPCM16 = false

    private let recognizer: SFSpeechRecognizer?
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var segment = 0
    private var segmentStarted = Date()
    private var lastText = ""
    private var stopped = false
    private var consecutiveErrors = 0

    init(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    static func requestPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
            }
        }
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "MagicCall.Voice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Apple speech recognition is not available right now."])
        }
        dlog("[VOICE] Apple speech · locale=\(recognizer.locale.identifier) onDevice=\(recognizer.supportsOnDeviceRecognition)")
        begin()
    }

    func stop() {
        lock.lock()
        stopped = true
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        lock.unlock()
    }

    func feed(_ buffer: AVAudioPCMBuffer, pcm16: Data?, level: Float) {
        lock.lock()
        let req = request
        let expired = Date().timeIntervalSince(segmentStarted) > 50
        lock.unlock()
        req?.append(buffer)
        if expired { DispatchQueue.main.async { self.rollOver() } }
    }

    private func begin() {
        guard let recognizer else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        segment += 1
        let id = "apple-\(segment)"
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        req.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        segmentStarted = Date()
        lastText = ""
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                DispatchQueue.main.async {
                    guard !self.stopped else { return }
                    self.consecutiveErrors = 0
                    self.lastText = text
                    self.onUpdate?(id, text, isFinal)
                    if isFinal { self.begin() }
                }
            } else if let error {
                DispatchQueue.main.async { self.recover(from: error, id: id) }
            }
        }
    }

    private func rollOver() {
        lock.lock()
        let req = request
        segmentStarted = Date()
        lock.unlock()
        req?.endAudio()
    }

    private func recover(from error: Error, id: String) {
        guard !stopped else { return }
        if !lastText.isEmpty { onUpdate?(id, lastText, true) }
        consecutiveErrors += 1
        let ns = error as NSError
        dlog("[VOICE] Apple speech restart after \(ns.domain) \(ns.code): \(ns.localizedDescription)")
        if consecutiveErrors > 6 {
            onError?("Apple speech keeps failing: \(ns.localizedDescription)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.begin() }
    }
}
