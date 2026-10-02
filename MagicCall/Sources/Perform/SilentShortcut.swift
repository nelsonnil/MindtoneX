import UIKit

/// Runs the user's “Ringtone Oracle Silent On/Off” Shortcut before Perform, through
/// `shortcuts://x-callback-url/run-shortcut`, and continues when Shortcuts calls back
/// `magiccall://…`. iOS offers no public API to change Silent Mode directly.
@MainActor
final class SilentShortcut: ObservableObject {
    static let shared = SilentShortcut()

    static let scheme = "magiccall"
    static let silentOnName = "Ringtone Oracle Silent On"
    static let silentOffName = "Ringtone Oracle Silent Off"

    /// iCloud share links (https://www.icloud.com/shortcuts/…) — tap **Get** on the mode card.
    /// Paste Nelson’s links here when ready, e.g. `URL(string: "https://www.icloud.com/shortcuts/…")!`
    static let silentOnInstallURL: URL? = nil
    static let silentOffInstallURL: URL? = nil
    static let createShortcutURL = URL(string: "shortcuts://create-shortcut")!

    enum Key {
        static let silentOnEnabled = "shortcut.silentOnBeforeFake"
        static let silentOffEnabled = "shortcut.silentOffBeforeShare"
    }

    enum Purpose: String {
        case fake, share, test
    }

    /// Setup-screen hint after a failed or cancelled run (never shown during Perform).
    @Published var hint: String?
    @Published private(set) var lastTestResult: String?

    private var pending: (purpose: Purpose, startedAt: Date, continuation: () -> Void)?
    private var fallbackWork: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SilentShortcut.shared.appBecameActive() }
        }
    }

    static func isEnabled(for mode: Prefs.PerformanceMode) -> Bool {
        let key = mode == .fakeRingtone ? Key.silentOnEnabled : Key.silentOffEnabled
        return UserDefaults.standard.bool(forKey: key)
    }

    static func enableBoth() {
        UserDefaults.standard.set(true, forKey: Key.silentOnEnabled)
        UserDefaults.standard.set(true, forKey: Key.silentOffEnabled)
    }

    /// Runs the shortcut for `mode`, then `continuation` (Perform) once Shortcuts returns.
    func runBeforePerform(mode: Prefs.PerformanceMode, then continuation: @escaping () -> Void) {
        let name = mode == .fakeRingtone ? Self.silentOnName : Self.silentOffName
        run(name: name, purpose: mode == .fakeRingtone ? .fake : .share, continuation: continuation)
    }

    func test(mode: Prefs.PerformanceMode) {
        lastTestResult = "Running “\(mode == .fakeRingtone ? Self.silentOnName : Self.silentOffName)”…"
        let name = mode == .fakeRingtone ? Self.silentOnName : Self.silentOffName
        run(name: name, purpose: .test) {}
    }

    private func run(name: String, purpose: Purpose, continuation: @escaping () -> Void) {
        guard let url = Self.runURL(name: name, purpose: purpose) else { return }
        pending = (purpose, Date(), continuation)
        dlog("[SHORTCUT] ▶︎ run “\(name)” (\(purpose.rawValue)) · \(url.absoluteString)")
        UIApplication.shared.open(url) { opened in
            MainActor.assumeIsolated {
                guard !opened else { return }
                dlog("✗ [SHORTCUT] could not open the Shortcuts app")
                self.finish(result: "error", message: "Couldn’t open the Shortcuts app. Is it installed?")
            }
        }
    }

    /// Returns true when the URL belonged to us.
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == Self.scheme else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let message = items.first { $0.name == "errorMessage" }?.value
        let host = url.host ?? ""
        dlog("[SHORTCUT] ← callback \(host) \(message.map { "· \($0)" } ?? "")")
        switch host {
        case "perform", "success": finish(result: "success", message: nil)
        case "cancel": finish(result: "cancel", message: nil)
        case "error": finish(result: "error", message: message)
        default: dlog("[SHORTCUT] unknown callback \(url.absoluteString)")
        }
        return true
    }

    // MARK: Private

    private static func runURL(name: String, purpose: Purpose) -> URL? {
        func cb(_ host: String) -> String { "\(scheme)://\(host)?for=\(purpose.rawValue)" }
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")
        c?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: cb(purpose == .test ? "success" : "perform")),
            URLQueryItem(name: "x-error", value: cb("error")),
            URLQueryItem(name: "x-cancel", value: cb("cancel")),
        ]
        return c?.url
    }

    private func finish(result: String, message: String?) {
        fallbackWork?.cancel()
        fallbackWork = nil
        guard let p = pending else { return }
        pending = nil
        let ms = Int(Date().timeIntervalSince(p.startedAt) * 1000)
        dlog("[SHORTCUT] result=\(result) after \(ms) ms (\(p.purpose.rawValue))")

        if p.purpose == .test {
            switch result {
            case "success": lastTestResult = "✓ Shortcut ran. Check that Silent Mode changed."
            case "cancel": lastTestResult = "Shortcut was cancelled."
            default: lastTestResult = "✗ \(message ?? "Shortcut failed.") Check the name is exactly right."
            }
            return
        }
        switch result {
        case "success":
            hint = nil
        case "cancel":
            hint = "The Silent shortcut was cancelled. Perform continued anyway — check Silent Mode by hand."
        default:
            hint = "The Silent shortcut didn’t run (\(message ?? "not found")). Perform continued anyway. Install “\(p.purpose == .fake ? Self.silentOnName : Self.silentOffName)” — see Silent Mode shortcuts below."
        }
        p.continuation()
    }

    /// If Shortcuts never calls back (user switched back by hand), continue after a short wait.
    private func appBecameActive() {
        guard let p = pending, p.purpose != .test, Date().timeIntervalSince(p.startedAt) > 0.5 else { return }
        fallbackWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                guard SilentShortcut.shared.pending != nil else { return }
                dlog("[SHORTCUT] no callback 1.5 s after returning → continuing Perform")
                SilentShortcut.shared.finish(result: "no-callback", message: "no reply from Shortcuts")
            }
        }
        fallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
