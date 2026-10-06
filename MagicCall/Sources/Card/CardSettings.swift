import AVFoundation
import Foundation

/// Preferences for Card / OCR song input.
enum CardSettings {
    enum Key {
        static let burstSeconds = "card.burstSeconds"
        static let maxScanRetries = "card.maxScanRetries"
        static let practiceTipsSeen = "card.practiceTipsSeen"
    }

    /// Short grab after volume press — best frame by text amount, not a long burst.
    static let defaultBurstSeconds = 0.45
    static let defaultMaxScanRetries = 3

    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            Key.burstSeconds: defaultBurstSeconds,
            Key.maxScanRetries: defaultMaxScanRetries,
        ])
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
