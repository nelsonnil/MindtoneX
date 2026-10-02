import AVFoundation
import QuartzCore

/// Microphone capture with AVAudioEngine. Delivers the native buffer (for Apple Speech) and,
/// optionally, mono 16-bit PCM at 24 kHz (the format the OpenAI Realtime API expects).
final class MicCapture {
    enum MicError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone input available." }
    }

    static let pcmSampleRate: Double = 24_000

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: MicCapture.pcmSampleRate,
                                          channels: 1, interleaved: true)!
    private(set) var isRunning = false

    var producePCM16 = true
    /// Called on the audio thread: native buffer, optional 24 kHz PCM16, RMS level 0…1.
    var onAudio: ((AVAudioPCMBuffer, Data?, Float) -> Void)?

    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default:
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            }
        }
    }

    static func inputDescription() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs
            .map { "\($0.portType.rawValue)(\($0.portName))" }
            .joined(separator: ",")
    }

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicError.noInput }
        converter = AVAudioConverter(from: format, to: pcmFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        dlog("[VOICE] mic on: \(Int(format.sampleRate)) Hz × \(format.channelCount) · input=\(Self.inputDescription())")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        dlog("[VOICE] mic off")
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let level = Self.rms(buffer)
        let pcm = producePCM16 ? convert(buffer) : nil
        onAudio?(buffer, pcm, level)
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter else { return nil }
        let ratio = pcmFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0, let channel = out.int16ChannelData else { return nil }
        return Data(bytes: channel[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }

    /// Builds the audio-thread callback outside any actor, so it is never main-actor isolated.
    static func makeHandler(transcriber: LiveTranscriber?, meter: LevelThrottle) -> (AVAudioPCMBuffer, Data?, Float) -> Void {
        { [weak transcriber] buffer, pcm, level in
            transcriber?.feed(buffer, pcm16: pcm, level: level)
            meter.push(level)
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = data[0]
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        return (sum / Float(n)).squareRoot()
    }
}

/// Forwards the mic level to the main thread about 10 times per second, keeping the peak.
final class LevelThrottle {
    var onLevel: ((_ level: Float, _ peak: Float) -> Void)?
    private var last: CFTimeInterval = 0
    private var peak: Float = 0

    func push(_ level: Float) {
        peak = max(peak, level)
        let now = CACurrentMediaTime()
        guard now - last > 0.1 else { return }
        last = now
        let p = peak
        DispatchQueue.main.async { self.onLevel?(level, p) }
    }
}
