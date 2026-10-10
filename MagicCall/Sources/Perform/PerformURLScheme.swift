import Foundation

/// Deep link to start Perform (same as tapping **Perform** on Home).
/// Registered scheme: `magiccall` (see Info.plist). Do not use host `perform` — reserved for Silent Shortcut callbacks.
enum PerformURLScheme {
    static let scheme = SilentShortcut.scheme
    static let host = "start-perform"

    static var urlString: String { "\(scheme)://\(host)" }

    @MainActor
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme.lowercased() else { return false }
        guard matchesPerformDeepLink(url) else { return false }
        dlog("[URL] → Perform (\(url.absoluteString))")
        AppModel.shared.perform()
        return true
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
