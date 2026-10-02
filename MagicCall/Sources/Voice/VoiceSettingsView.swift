import AVFoundation
import SwiftUI

/// Microphone level test helper (used from `AiVoiceInputPanel` on the home screen).
@MainActor
final class MicTester: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var level: Float = 0
    @Published private(set) var result: String?
    @Published private(set) var ok = false

    private let mic = MicCapture()
    private var peak: Float = 0

    func run() async {
        result = nil
        guard await MicCapture.requestPermission() else {
            ok = false
            result = "Microphone access is off. Turn it on in iPhone Settings → Privacy & Security → Microphone → \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "RingtoneX")."
            return
        }
        peak = 0
        do {
            try VoiceAudioSession.activateForListening()
            mic.producePCM16 = false
            let meter = LevelThrottle()
            meter.onLevel = { [weak self] level, peak in
                MainActor.assumeIsolated {
                    self?.level = level
                    self?.peak = peak
                }
            }
            mic.onAudio = MicCapture.makeHandler(transcriber: nil, meter: meter)
            try mic.start()
            running = true
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        } catch {
            ok = false
            result = "Could not start the microphone: \(RingtoneAudioEngine.describe(error))"
        }
        mic.stop()
        mic.onAudio = nil
        running = false
        level = 0
        VoiceAudioSession.recordCategoryActive = false
        if AppModel.shared.isArmed { try? AppModel.shared.audio.configureSession() } else { VoiceAudioSession.deactivateIfIdle() }
        if result == nil {
            ok = peak > 0.01
            result = ok
                ? "Microphone works (peak level \(String(format: "%.2f", peak))) · \(MicCapture.inputDescription())"
                : "No sound detected. Check nothing covers the microphone and try again."
        }
        dlog("[VOICE] mic test: \(result ?? "")")
    }
}
