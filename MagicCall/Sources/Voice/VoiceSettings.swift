import AVFoundation
import Foundation
import Security

/// Preferences for the AI Voice song input. Views use @AppStorage with the same keys.
enum VoiceSettings {
    enum Key {
        static let inputMode = "song.inputMode"
        static let engine = "voice.engine"
        static let transcribeModel = "voice.transcribeModel"
        static let pickerModel = "voice.pickerModel"
        static let language = "voice.language"
        static let lockDelay = "voice.lockDelay"
        static let minConfidence = "voice.minConfidence"
        static let hapticOnLock = "voice.hapticOnLock"
    }

    enum InputMode: String, CaseIterable, Identifiable {
        case manual
        case aiVoice
        case notes

        var id: String { rawValue }
        var title: String {
            switch self {
            case .manual: return "Manual"
            case .aiVoice: return "AI Voice"
            case .notes: return "Notes"
            }
        }
    }

    enum Engine: String, CaseIterable, Identifiable {
        case openAIRealtime
        case appleOnDevice

        var id: String { rawValue }
        var title: String {
            switch self {
            case .openAIRealtime: return "OpenAI (best)"
            case .appleOnDevice: return "Apple on-device"
            }
        }
        var detail: String {
            switch self {
            case .openAIRealtime:
                return "Streams audio to OpenAI live transcription. Best with Spanish/English mixes and song titles. Needs an API key and internet."
            case .appleOnDevice:
                return "Apple speech recognition on the iPhone, no key needed. Weaker with English titles said in Spanish. With an API key, the AI still picks the song; without one, a simple offline guess is used."
            }
        }
    }

    enum Language: String, CaseIterable, Identifiable {
        case spanishEnglish
        case spanish
        case english
        case auto

        var id: String { rawValue }
        var title: String {
            switch self {
            case .spanishEnglish: return "Spanish + English"
            case .spanish: return "Spanish"
            case .english: return "English"
            case .auto: return "Automatic"
            }
        }
        var openAICodes: [String] {
            switch self {
            case .spanishEnglish: return ["es", "en"]
            case .spanish: return ["es"]
            case .english: return ["en"]
            case .auto: return []
            }
        }
        var appleLocale: Locale {
            switch self {
            case .spanishEnglish, .spanish: return Locale(identifier: "es-ES")
            case .english: return Locale(identifier: "en-US")
            case .auto: return Locale.current
            }
        }
    }

    struct ModelOption: Identifiable {
        let id: String
        let label: String
    }

    static let transcribeModels: [ModelOption] = [
        ModelOption(id: "gpt-live-transcribe", label: "gpt-live-transcribe (recommended)"),
        ModelOption(id: "gpt-4o-transcribe", label: "gpt-4o-transcribe"),
        ModelOption(id: "gpt-4o-mini-transcribe", label: "gpt-4o-mini-transcribe (cheapest)"),
    ]

    static let pickerModels: [ModelOption] = [
        ModelOption(id: "gpt-6-luna", label: "gpt-6-luna (fast, recommended)"),
        ModelOption(id: "gpt-6.1-sol", label: "gpt-6.1-sol (smarter, slower)"),
    ]

    static let defaultLockDelay = 5.0
    static let defaultMinConfidence = 0.55

    private static var d: UserDefaults { .standard }

    static var inputMode: InputMode { InputMode(rawValue: d.string(forKey: Key.inputMode) ?? "") ?? .manual }
    static var engine: Engine { Engine(rawValue: d.string(forKey: Key.engine) ?? "") ?? .openAIRealtime }
    static var transcribeModel: String { nonEmpty(d.string(forKey: Key.transcribeModel)) ?? transcribeModels[0].id }
    static var pickerModel: String { nonEmpty(d.string(forKey: Key.pickerModel)) ?? pickerModels[0].id }
    static var language: Language { Language(rawValue: d.string(forKey: Key.language) ?? "") ?? .spanishEnglish }
    static var lockDelay: Double { d.object(forKey: Key.lockDelay) == nil ? defaultLockDelay : d.double(forKey: Key.lockDelay) }
    static var minConfidence: Double { d.object(forKey: Key.minConfidence) == nil ? defaultMinConfidence : d.double(forKey: Key.minConfidence) }
    static var hapticOnLock: Bool { d.object(forKey: Key.hapticOnLock) == nil ? true : d.bool(forKey: Key.hapticOnLock) }

    static var apiKey: String? { nonEmpty(Keychain.get(account: keychainAccount)) }

    static func saveAPIKey(_ key: String?) {
        Keychain.set(nonEmpty(key?.trimmingCharacters(in: .whitespacesAndNewlines)), account: keychainAccount)
    }

    /// Ready to listen: Apple engine works without a key; OpenAI needs one.
    static var isConfigured: Bool { engine == .appleOnDevice || apiKey != nil }

    static func summary() -> String {
        "engine=\(engine.rawValue) stt=\(transcribeModel) picker=\(apiKey != nil ? pickerModel : "offline") lang=\(language.rawValue) lock=\(lockDelay)s minConf=\(minConfidence)"
    }

    private static let keychainAccount = "openai.apiKey"

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}

enum Keychain {
    private static let service = "MagicCall.Voice"

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { dlog("✗ Keychain save failed: \(status)") }
    }
}

/// Audio session rules while the microphone is in use.
///
/// The Fake Ringtone player normally runs in `.playback`. Recording needs `.playAndRecord`
/// (with `.defaultToSpeaker`, otherwise the song would come out of the earpiece). While a voice
/// session is active, `RingtoneAudioEngine.configureSession()` reads this flag so the category
/// never flips back and forth during the act; after the song locks it returns to `.playback`.
enum VoiceAudioSession {
    static var recordCategoryActive = false

    @MainActor
    static func activateForListening() throws {
        recordCategoryActive = true
        let model = AppModel.shared
        if model.isArmed {
            try model.audio.configureSession()
            if Prefs.hotStandby, model.audio.player != nil, model.audio.player?.isPlaying != true {
                model.audio.startStandby()
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try session.setActive(true)
        }
    }

    @MainActor
    static func deactivateIfIdle() {
        guard !AppModel.shared.isArmed else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
