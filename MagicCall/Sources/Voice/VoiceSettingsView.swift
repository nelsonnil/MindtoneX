import AVFoundation
import SwiftUI

struct VoiceSettingsView: View {
    @AppStorage(VoiceSettings.Key.engine) private var engineRaw = VoiceSettings.Engine.openAIRealtime.rawValue
    @AppStorage(VoiceSettings.Key.transcribeModel) private var transcribeModel = VoiceSettings.transcribeModels[0].id
    @AppStorage(VoiceSettings.Key.pickerModel) private var pickerModel = VoiceSettings.pickerModels[0].id
    @AppStorage(VoiceSettings.Key.language) private var languageRaw = VoiceSettings.Language.spanishEnglish.rawValue
    @AppStorage(VoiceSettings.Key.lockDelay) private var lockDelay = VoiceSettings.defaultLockDelay
    @AppStorage(VoiceSettings.Key.minConfidence) private var minConfidence = VoiceSettings.defaultMinConfidence
    @AppStorage(VoiceSettings.Key.hapticOnLock) private var hapticOnLock = true

    @State private var keyDraft = ""
    @State private var savedKeyHint: String?
    @StateObject private var micTest = MicTester()

    private var engine: VoiceSettings.Engine { VoiceSettings.Engine(rawValue: engineRaw) ?? .openAIRealtime }

    var body: some View {
        Form {
            Section {
                Picker("Listening engine", selection: $engineRaw) {
                    ForEach(VoiceSettings.Engine.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text(engine.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Language", selection: $languageRaw) {
                    ForEach(VoiceSettings.Language.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Listening")
            }

            Section {
                if let hint = savedKeyHint {
                    HStack {
                        Label("Key saved (\(hint))", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            VoiceSettings.saveAPIKey(nil)
                            refreshKey()
                            dlog("[VOICE] API key removed")
                        }
                    }
                }
                SecureField(savedKeyHint == nil ? "Paste your OpenAI API key (sk-…)" : "Replace key", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save key") {
                    VoiceSettings.saveAPIKey(keyDraft)
                    keyDraft = ""
                    refreshKey()
                    dlog("[VOICE] API key saved to Keychain")
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("OpenAI API key")
            } footer: {
                Text("Stored only in this iPhone’s Keychain. Create one at platform.openai.com → API keys. Needed for the OpenAI engine; with Apple on-device it is optional (it lets the AI pick the song).")
            }

            Section {
                Picker("Transcription model", selection: $transcribeModel) {
                    ForEach(VoiceSettings.transcribeModels) { Text($0.label).tag($0.id) }
                }
                .disabled(engine != .openAIRealtime)
                Picker("Song-picking model", selection: $pickerModel) {
                    ForEach(VoiceSettings.pickerModels) { Text($0.label).tag($0.id) }
                }
            } header: {
                Text("AI models")
            }

            Section {
                Stepper("Lock after \(Int(lockDelay)) s without changes", value: $lockDelay, in: 2...15, step: 1)
                VStack(alignment: .leading) {
                    Text("Minimum confidence: \(VoiceSongSession.percent(minConfidence))")
                    Slider(value: $minConfidence, in: 0.3...0.9, step: 0.05)
                }
                Toggle("Soft vibration when the song locks", isOn: $hapticOnLock)
            } header: {
                Text("Locking the song")
            } footer: {
                Text("Each new song the AI hears restarts the countdown. Guesses below the minimum confidence are ignored.")
            }

            Section {
                Button {
                    Task { await micTest.run() }
                } label: {
                    Label(micTest.running ? "Listening…" : "Test microphone", systemImage: "mic.circle")
                }
                .disabled(micTest.running || VoiceSongSession.shared.isActive)
                if micTest.running {
                    LevelMeter(level: micTest.level)
                }
                if let result = micTest.result {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(micTest.ok ? .green : .orange)
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("Shows your microphone level for 4 seconds — talk normally. The first time, iOS asks for microphone permission. iOS shows an orange dot while the microphone is on.")
            }
        }
        .navigationTitle("Voice settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshKey)
    }

    private func refreshKey() {
        savedKeyHint = VoiceSettings.apiKey.map { "…" + String($0.suffix(4)) }
    }
}

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
            result = "Microphone access is off. Turn it on in iPhone Settings → Privacy & Security → Microphone → MagicCall."
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
