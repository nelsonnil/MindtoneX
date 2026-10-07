import AVFoundation
import Foundation

/// Preferences for Card / OCR song input.
enum CardSettings {
    enum Key {
        static let burstSeconds = "card.burstSeconds"
        static let maxScanRetries = "card.maxScanRetries"
        static let practiceTipsSeen = "card.practiceTipsSeen"
        static let handwritingLanguage = "card.handwritingLanguage"
    }

    /// Language(s) on the handwritten card — Vision OCR + OpenAI vision hints.
    enum HandwritingLanguage: String, CaseIterable, Identifiable {
        case englishAndSpanish
        case english
        case spanish

        var id: String { rawValue }

        var title: String {
            switch self {
            case .englishAndSpanish: return "English + Spanish"
            case .english: return "English"
            case .spanish: return "Español"
            }
        }

        var visionLanguageCodes: [String] {
            switch self {
            case .englishAndSpanish: return ["en-US", "es-ES"]
            case .english: return ["en-US"]
            case .spanish: return ["es-ES"]
            }
        }

        var openAIHint: String {
            switch self {
            case .englishAndSpanish: return "Card may mix English and Spanish (song titles often English)."
            case .english: return "Card text is English (song titles, artist names)."
            case .spanish: return "Card text is Spanish."
            }
        }
    }

    /// Short grab after volume press — best frame by text amount, not a long burst.
    static let defaultBurstSeconds = 0.45
    static let defaultMaxScanRetries = 3

    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            Key.burstSeconds: defaultBurstSeconds,
            Key.maxScanRetries: defaultMaxScanRetries,
            Key.handwritingLanguage: HandwritingLanguage.englishAndSpanish.rawValue,
        ])
    }

    static var handwritingLanguage: HandwritingLanguage {
        HandwritingLanguage(rawValue: d.string(forKey: Key.handwritingLanguage) ?? "") ?? .englishAndSpanish
    }

    static var burstSeconds: Double {
        let v = d.double(forKey: Key.burstSeconds)
        return v > 0 ? v : defaultBurstSeconds
    }

    static var maxScanRetries: Int {
        let v = d.integer(forKey: Key.maxScanRetries)
        return v > 0 ? v : defaultMaxScanRetries
    }

    static var cameraAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static func requestCameraIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .video) { ok in cont.resume(returning: ok) }
            }
        default: return false
        }
    }

    static func summary() -> String {
        "burst=\(burstSeconds)s retries=\(maxScanRetries) cam=\(cameraAuthorized ? "ok" : "denied")"
    }
}
