import CallKit
import Foundation

enum CallDirectorySync {
    private static let directoryManager = CXCallDirectoryManager()
    private static let maxReloadAttempts = 3
    private static let reloadRetryDelay: TimeInterval = 0.6
    private static var active: Bool { WordApiSettings.callerLabelEnabled }

    static func reloadExtensions(reason: String) {
        guard active else { return }
        let ids = [CallerLabelStore.extensionBundleID, CallerLabelStore.liveLookupExtensionBundleID]
        for id in ids {
            reloadExtension(withIdentifier: id, reason: reason, attempt: 1)
        }
    }

    private static func reloadExtension(withIdentifier id: String, reason: String, attempt: Int) {
        directoryManager.reloadExtension(withIdentifier: id) { error in
            if let error {
                let code = (error as NSError).code
                dlog("✗ [CALL-ID] reload \(id) (\(reason)) attempt \(attempt)/\(maxReloadAttempts): \(error.localizedDescription) (code \(code))")
                guard attempt < maxReloadAttempts else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + reloadRetryDelay) {
                    reloadExtension(withIdentifier: id, reason: reason, attempt: attempt + 1)
                }
            } else if attempt > 1 {
                dlog("[CALL-ID] reload \(id) ok (\(reason)) · succeeded on retry \(attempt)")
            } else {
                dlog("[CALL-ID] reload \(id) ok (\(reason))")
            }
        }
    }

    static func syncPerformArmed(_ armed: Bool, reason: String) {
        guard active else { return }
        CallerLabelStore.setPerformArmed(armed)
        if armed {
            refreshIdentificationNumbers()
        } else {
            CallerLabelStore.setIdentificationPhoneNumbers([])
        }
        reloadExtensions(reason: reason)
    }

    static func refreshIdentificationNumbers() {
        guard active else { return }
        var numbers: [Int64] = []
        if let fallback = WordApiSettings.fallbackPhoneNumber() {
            numbers.append(fallback)
        }
        CallerLabelStore.setIdentificationPhoneNumbers(numbers)
    }
}
