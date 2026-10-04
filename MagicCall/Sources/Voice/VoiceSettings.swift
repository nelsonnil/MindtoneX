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
    }

    enum InputMode: String, CaseIterable, Identifiable {
        case manual
        case aiVoice
        case notes
        case api

        var id: String { rawValue }
        var title: String {
            switch self {
            case .manual: return "Manual"
            case .aiVoice: return "Voice"
            case .notes: return "Notes"
            case .api: return "API"
            }
        }
    }

    /// Speech engine (OpenAI only in UI; Apple on-device kept for legacy stored values).
    enum Engine: String, Identifiable {
        case openAIRealtime
        case appleOnDevice

        var id: String { rawValue }
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
    static var engine: Engine {
        let raw = d.string(forKey: Key.engine) ?? ""
        if raw == Engine.appleOnDevice.rawValue { return .openAIRealtime }
        return .openAIRealtime
    }
    static var transcribeModel: String { transcribeModels[0].id }
    static var pickerModel: String { pickerModels[0].id }
    static var languageOption: VoiceOpenAILanguages.Option {
        VoiceOpenAILanguages.resolve(stored: d.string(forKey: Key.language))
    }
    static var openAILanguageCodes: [String] { languageOption.openAICodes }
    static var lockDelay: Double { d.object(forKey: Key.lockDelay) == nil ? defaultLockDelay : d.double(forKey: Key.lockDelay) }
    static var minConfidence: Double { d.object(forKey: Key.minConfidence) == nil ? defaultMinConfidence : d.double(forKey: Key.minConfidence) }

    static var apiKey: String? { nonEmpty(Keychain.get(account: keychainAccount)) }

    static func saveAPIKey(_ key: String?) {
        Keychain.set(nonEmpty(key?.trimmingCharacters(in: .whitespacesAndNewlines)), account: keychainAccount)
    }

    static var isConfigured: Bool { apiKey != nil }

    static func summary() -> String {
        "engine=openAI stt=\(transcribeModel) picker=\(pickerModel) lang=\(languageOption.id) lock=\(lockDelay)s minConf=\(minConfidence)"
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
