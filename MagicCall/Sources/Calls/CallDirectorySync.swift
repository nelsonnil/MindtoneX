import CallKit
import Contacts
import Foundation

@MainActor
enum CallDirectorySync {
    private static let directoryManager = CXCallDirectoryManager.sharedInstance
    private static let maxReloadAttempts = 6
    private static var active: Bool { WordApiSettings.callerLabelEnabled }

    /// CallKit rejects a reload while the previous one is still loading (error 7), so reloads are
    /// serialized: requests during a load collapse into one follow-up that reads the latest store.
    private static var reloadInFlight = false
    private static var pendingReason: String?

    static let disabledHint = "Enable MindtoneX under Settings → Phone → Call Blocking & Identification."

    static func reloadExtensions(reason: String) {
        guard active else { return }
        guard !reloadInFlight else {
            pendingReason = reason
            return
        }
        startReload(reason: reason, attempt: 1)
    }

    private static func startReload(reason: String, attempt: Int) {
        reloadInFlight = true
        let requestedAt = Date()
        directoryManager.reloadExtension(withIdentifier: CallerLabelStore.extensionBundleID) { error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    finishReload(error: error, reason: reason, attempt: attempt, requestedAt: requestedAt)
                }
            }
        }
    }

    private static func finishReload(error: Error?, reason: String, attempt: Int, requestedAt: Date) {
        let id = CallerLabelStore.extensionBundleID
        if let error {
            let code = (error as? CXErrorCodeCallDirectoryManagerError)?.code
            dlog("✗ [CALL-ID] reload \(id) (\(reason)) attempt \(attempt)/\(maxReloadAttempts): \(error.localizedDescription) (code \((error as NSError).code))")
            if let code, isTransient(code), attempt < maxReloadAttempts {
                let delay = min(0.75 * pow(2, Double(attempt - 1)), 5)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated {
                        let next = pendingReason ?? reason
                        pendingReason = nil
                        startReload(reason: next, attempt: attempt + 1)
                    }
                }
                return
            }
            if code == .extensionDisabled {
                PerformUserLog.shared.logConnectionIssue(disabledHint)
            }
        } else {
            let retry = attempt > 1 ? " · succeeded on retry \(attempt)" : ""
            dlog("[CALL-ID] reload \(id) ok (\(reason))\(retry) · \(extensionLoadSummary(since: requestedAt))")
        }
        reloadInFlight = false
        if let next = pendingReason {
            pendingReason = nil
            startReload(reason: next, attempt: 1)
        }
    }

    private static func isTransient(_ code: CXErrorCodeCallDirectoryManagerError.Code) -> Bool {
        switch code {
        case .currentlyLoading, .loadingInterrupted, .unknown: return true
        default: return false
        }
    }

    private static func extensionLoadSummary(since requestedAt: Date) -> String {
        guard let load = CallerLabelStore.lastExtensionLoad(), load.at >= requestedAt.addingTimeInterval(-1) else {
            return "extension did not report back (App Group \(CallerLabelStore.appGroupID) missing from signing?)"
        }
        return "extension saw armed=\(load.performArmed) label=«\(load.label)» entries=\(load.entries)"
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

    /// Call after the Perform user log session has begun so warnings are visible on the home card.
    static func reportPerformReadiness() {
        guard active else { return }
        let snapshot = CallerLabelStore.load()
        let appGroup = CallerLabelStore.isAppGroupAvailable
        dlog("[CALL-ID] readiness · appGroup=\(appGroup) numbers=\(snapshot.identificationPhoneNumbers) armed=\(snapshot.performArmed)")
        if !appGroup {
            PerformUserLog.shared.log("Caller name: App Group not signed — rebuild with \(CallerLabelStore.appGroupID).")
        }
        if snapshot.identificationPhoneNumbers.isEmpty {
            if WordApiSettings.saveWordAsContactEnabled, WordApiSettings.contactMode == .unknown {
                PerformUserLog.shared.log("Caller name: dial the spectator on Perform (Unknown mode) or add a fallback number in Caller name settings.")
            } else if WordApiSettings.saveWordAsContactEnabled, WordApiSettings.contactMode == .known {
                PerformUserLog.shared.log("Caller name: choose a Known contact on the Caller name card.")
            } else {
                PerformUserLog.shared.log("Caller name: add the incoming number in Caller name → connection details → Call Identification.")
            }
        }
        if WordApiSettings.saveWordAsContactEnabled {
            let contacts = CNContactStore.authorizationStatus(for: .contacts)
            if contacts == .denied || contacts == .restricted {
                PerformUserLog.shared.log("Contacts off · word on call screen needs Contacts access, or use Call Directory only.")
            }
        }
        directoryManager.getEnabledStatusForExtension(withIdentifier: CallerLabelStore.extensionBundleID) { status, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    dlog("[CALL-ID] extension status=\(status.rawValue)\(error.map { " error=\($0.localizedDescription)" } ?? "")")
                    if status != .enabled {
                        PerformUserLog.shared.log(disabledHint)
                    }
                }
            }
        }
    }
}
