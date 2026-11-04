import AVFoundation
import Foundation

/// Preferences for Card / OCR song input.
enum CardSettings {
    enum Key {
        static let burstSeconds = "card.burstSeconds"
        static let maxScanRetries = "card.maxScanRetries"
        static let practiceTipsSeen = "card.practiceTipsSeen"
        static let cameraFacing = "card.cameraFacing"
        static let readingEngine = "card.readingEngine"
    }

    enum ReadingEngine: String, CaseIterable, Identifiable {
        case automatic
        case openAI
        case onDevice

        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .openAI: return "OpenAI"
            case .onDevice: return "On iPhone"
            }
        }

        var detail: String {
            switch self {
            case .automatic:
                return "Uses on-device OCR first for one song; OpenAI handles uncertain or two-song cards."
            case .openAI:
                return "Best for difficult handwriting and flexible layouts. Requires your API key."
            case .onDevice:
                return "Private and free. Uses Apple Vision plus iTunes/Deezer matching."
            }
        }

        var allowsOpenAI: Bool { self != .onDevice }
        var requiresOpenAI: Bool { self == .openAI }
    }

    enum CameraFacing: String, CaseIterable, Identifiable {
        case back
        case front

        var id: String { rawValue }

        var segmentTitle: String {
            switch self {
            case .back: return "Back"
            case .front: return "Front"
            }
        }

        var capturePosition: AVCaptureDevice.Position {
            switch self {
            case .back: return .back
            case .front: return .front
            }
        }
    }

    static let defaultCameraFacing = CameraFacing.back
    static let defaultReadingEngine = ReadingEngine.automatic

    /// On-device Vision OCR: device locale first, then English + Spanish (song titles are often EN/ES).
    static var visionRecognitionLanguages: [String] {
        var codes: [String] = []
        func appendUnique(_ code: String) {
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, !codes.contains(trimmed) else { return }
            codes.append(trimmed)
        }
        appendUnique(Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        appendUnique("en-US")
        appendUnique("es-ES")
        return codes
    }

    /// OpenAI vision card reader — language-agnostic (no per-locale UI).
    static let openAIVisionLanguageRule =
        "Read **all visible text** on the card in whatever language or script was used (song titles and artist names may be in any language)."

    /// Short grab after volume press — best frame by text amount, not a long burst.
    static let defaultBurstSeconds = 0.55
    static let defaultMaxScanRetries = 3

    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            Key.burstSeconds: defaultBurstSeconds,
            Key.maxScanRetries: defaultMaxScanRetries,
            Key.cameraFacing: defaultCameraFacing.rawValue,
            Key.readingEngine: defaultReadingEngine.rawValue,
        ])
    }

    static var cameraFacing: CameraFacing {
        get { CameraFacing(rawValue: d.string(forKey: Key.cameraFacing) ?? "") ?? defaultCameraFacing }
        set { d.set(newValue.rawValue, forKey: Key.cameraFacing) }
    }

    static var readingEngine: ReadingEngine {
        get { ReadingEngine(rawValue: d.string(forKey: Key.readingEngine) ?? "") ?? defaultReadingEngine }
        set { d.set(newValue.rawValue, forKey: Key.readingEngine) }
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
        "engine=\(readingEngine.rawValue) burst=\(burstSeconds)s retries=\(maxScanRetries) facing=\(cameraFacing.rawValue) cam=\(cameraAuthorized ? "ok" : "denied")"
    }
}
