import Foundation
import UIKit

/// Deep link to start Perform (same as tapping **Perform** on Home).
/// Registered scheme: `magiccall` (see Info.plist). Do not use host `perform` — reserved for Silent Shortcut callbacks.
///
/// Optional query (search catalog + preload audio before the call):
/// - `song` or `song1` — first song (e.g. `Thriller Michael Jackson`)
/// - `song2` — second song (enables 2-song on call when Interference ringtone is on)
/// - `songs` — both separated by `|` (e.g. `Gasolina Daddy Yankee|Despacito Luis Fonsi`)
enum PerformURLScheme {
    static let scheme = SilentShortcut.scheme
    static let host = "start-perform"

    static var urlString: String { "\(scheme)://\(host)" }

    static let exampleSong1 = "Thriller Michael Jackson"
    static let exampleSong2 = "Billie Jean Michael Jackson"

    static var examplePerformOnlyURL: String { urlString }
    static var exampleOneSongURL: String { urlString(song1: exampleSong1) }
    static var exampleTwoSongsURL: String { urlString(song1: exampleSong1, song2: exampleSong2) }

    static func urlString(song1: String, song2: String? = nil) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var items: [URLQueryItem] = [URLQueryItem(name: "song1", value: song1)]
        if let song2, !song2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "song2", value: song2))
        }
        components.queryItems = items
        return components.url?.absoluteString ?? urlString
    }

    /// 1–2 search strings from `song`, `song1`, `song2`, or `songs=a|b`.
    static func songQueries(from url: URL) -> [String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        let items = components.queryItems ?? []
        func firstValue(named name: String) -> String? {
            let raw = items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.count >= 2 ? raw : nil
        }
        if let combined = firstValue(named: "songs"), combined.contains("|") {
            let parts = combined.split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 }
            if !parts.isEmpty { return Array(parts.prefix(2)) }
        }
        var out: [String] = []
        if let s = firstValue(named: "song") ?? firstValue(named: "song1") { out.append(s) }
        if let s2 = firstValue(named: "song2") { out.append(s2) }
        return Array(out.prefix(2))
    }

    private static var performWhenActiveObserver: NSObjectProtocol?

    @MainActor
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme.lowercased() else { return false }
        guard matchesPerformDeepLink(url) else { return false }
        let songs = songQueries(from: url)
        if songs.isEmpty {
            dlog("[URL] → Perform (\(url.absoluteString))")
        } else {
            dlog("[URL] → Perform + \(songs.count) song(s) (\(url.absoluteString))")
        }
        AppModel.shared.setPendingPerformURLSongQueries(songs.isEmpty ? nil : songs)
        AppModel.shared.autoPerformAllowedOnNextForeground = false
        if isCarphoneVisualHandoff(url), let payload = CarphoneMagicCallHandoffStore.consume() {
            AppModel.shared.applyCarphoneVisualHandoff(payload)
        } else {
            AppModel.shared.showPerformCover()
        }
        schedulePerformWhenActive()
        return true
    }

    static func isCarphoneVisualHandoff(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains(where: {
            $0.name.caseInsensitiveCompare("from") == .orderedSame
                && $0.value?.lowercased() == "cardphone"
        }) ?? false
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

// MARK: - Carphone CALL visual handoff (App Group `group.com.nelson.tono`)

enum CarphoneMagicCallHandoffStore {
    static let appGroupID = "group.com.nelson.tono"
    static let fileName = "carphone_magiccall_handoff.json"
    static let ttl: TimeInterval = 90

    struct Payload: Codable, Equatable {
        var dialDigits: String
        var issuedAt: Date
    }

    static func consume() -> Payload? {
        guard let url = containerFileURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.dialDigits.isEmpty,
              Date().timeIntervalSince(payload.issuedAt) <= ttl else {
            return nil
        }
        return payload
    }

    private static var containerFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }
}
