import Foundation
import UIKit

/// Deep link to start Perform (same as tapping **Perform** on Home).
/// Registered scheme: `magiccall` (see Info.plist). Do not use host `perform` — reserved for Silent Shortcut callbacks.
enum PerformURLScheme {
    static let scheme = SilentShortcut.scheme
    static let host = "start-perform"

    static var urlString: String { "\(scheme)://\(host)" }

    private static var performWhenActiveObserver: NSObjectProtocol?

    @MainActor
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme.lowercased() else { return false }
        guard matchesPerformDeepLink(url) else { return false }
        dlog("[URL] → Perform (\(url.absoluteString))")
        AppModel.shared.autoPerformAllowedOnNextForeground = false
        AppModel.shared.showPerformCover()
        schedulePerformWhenActive()
        return true
    }

    /// Mic / scene setup need an active app; Shortcuts and NFC often deliver the URL before `scenePhase == .active`.
    @MainActor
    private static func schedulePerformWhenActive() {
        if UIApplication.shared.applicationState == .active {
            AppModel.shared.performFromURLBehindCover()
            return
        }
        guard performWhenActiveObserver == nil else {
            dlog("[URL] Perform already queued for active")
            return
        }
        dlog("[URL] defer Perform until active (state=\(UIApplication.shared.applicationState.rawValue))")
        performWhenActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            if let obs = performWhenActiveObserver {
                NotificationCenter.default.removeObserver(obs)
                performWhenActiveObserver = nil
            }
            dlog("[URL] active → Perform")
            MainActor.assumeIsolated {
                AppModel.shared.performFromURLBehindCover()
            }
        }
    }

    private static func matchesPerformDeepLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        if host == Self.host { return true }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if path == Self.host { return true }
        if host == "start", path == "perform" { return true }
        return false
    }
}
