import Foundation

/// When Perform must have an OpenAI key before entering the stage (same Keychain entry as legacy Song → Voice).
enum OpenAIPerformRequirements {
    static var requiresKeyBeforePerform: Bool {
        switch VoiceSettings.inputMode {
        case .aiVoice, .card:
            return true
        case .notes:
            return NotesSettings.useAIPicker
        case .manual, .api:
            return false
        }
    }
}

enum OpenAIAPIKeyCopy {
    static let singleKeyHelper =
        "This single OpenAI API key powers Voice AI listening and Camera card reading during Perform."

    static let performanceSettingsHint =
        "Add or change your key under Home → **Performance settings** (OpenAI section). Voice and Camera share that one key."

    static let helpIntro =
        "MindtoneX uses your OpenAI account for Voice AI and for reading handwritten cards with Camera. You only need **one** API key — not separate keys for Voice and Camera."

    static let helpCostNote =
        "Typical cost: a few cents per card photo for vision; Voice realtime usage is billed separately on your OpenAI account."

    static let apiKeysURL = URL(string: "https://platform.openai.com/api-keys")!
    static let billingURL = URL(string: "https://platform.openai.com/settings/organization/billing")!
}

extension VoiceSettings {
    /// Last four characters for “Key on file” hints (Keychain unchanged since legacy Voice UI).
    static var apiKeyOnFileLabel: String? {
        guard let key = apiKey else { return nil }
        return "Key on file · …\(String(key.suffix(4)))"
    }
}
