import CallKit
import Foundation

enum CallDirectorySync {
    private static var active: Bool { WordApiSettings.callerLabelEnabled }

    static func reloadExtensions(reason: String) {
        guard active else { return }
        let ids = [CallerLabelStore.extensionBundleID, CallerLabelStore.liveLookupExtensionBundleID]
        for id in ids {
            CXCallDirectoryManager.shared.reloadExtension(withIdentifier: id) { error in
                if let error {
                    dlog("✗ [CALL-ID] reload \(id) (\(reason)): \(error.localizedDescription)")
                } else {
                    dlog("[CALL-ID] reload \(id) ok (\(reason))")
                }
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
