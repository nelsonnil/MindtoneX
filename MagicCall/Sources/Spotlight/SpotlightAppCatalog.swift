import SwiftUI
import UIKit

/// Apps the performer can place in Siri Suggestions. iOS does not let an app list installed apps,
/// so icons and names come from the App Store lookup API and are cached on disk.
struct SpotlightCatalogApp: Identifiable, Hashable {
    let bundleId: String
    /// Home screen label for third-party brands; nil for Apple apps, whose localized name comes from the store.
    let fixedName: String?
    var id: String { bundleId }
}

enum SpotlightAppCatalog {
    static let apps: [SpotlightCatalogApp] = [
        .init(bundleId: "com.google.GoogleMobile", fixedName: "Google"),
        .init(bundleId: "com.apple.mobilesafari", fixedName: nil),
        .init(bundleId: "com.google.chrome.ios", fixedName: "Chrome"),
        .init(bundleId: "net.whatsapp.WhatsApp", fixedName: "WhatsApp"),
        .init(bundleId: "com.burbn.instagram", fixedName: "Instagram"),
        .init(bundleId: "com.facebook.Facebook", fixedName: "Facebook"),
        .init(bundleId: "com.spotify.client", fixedName: "Spotify"),
        .init(bundleId: "com.google.ios.youtube", fixedName: "YouTube"),
        .init(bundleId: "com.openai.chat", fixedName: "ChatGPT"),
        .init(bundleId: "com.zhiliaoapp.musically", fixedName: "TikTok"),
        .init(bundleId: "com.google.Gmail", fixedName: "Gmail"),
        .init(bundleId: "ph.telegra.Telegraph", fixedName: "Telegram"),
        .init(bundleId: "com.netflix.Netflix", fixedName: "Netflix"),
        .init(bundleId: "com.atebits.Tweetie2", fixedName: "X"),
        .init(bundleId: "com.apple.MobileAddressBook", fixedName: nil),
        .init(bundleId: "com.apple.mobilephone", fixedName: nil),
        .init(bundleId: "com.apple.MobileSMS", fixedName: nil),
        .init(bundleId: "com.apple.mobilemail", fixedName: nil),
        .init(bundleId: "com.apple.mobilenotes", fixedName: nil),
        .init(bundleId: "com.apple.reminders", fixedName: nil),
        .init(bundleId: "com.apple.mobilecal", fixedName: nil),
        .init(bundleId: "com.apple.camera", fixedName: nil),
        .init(bundleId: "com.apple.mobileslideshow", fixedName: nil),
        .init(bundleId: "com.apple.Maps", fixedName: nil),
        .init(bundleId: "com.apple.weather", fixedName: nil),
        .init(bundleId: "com.apple.calculator", fixedName: nil),
    ]

    static func app(_ bundleId: String) -> SpotlightCatalogApp? { apps.first { $0.bundleId == bundleId } }
}

@MainActor
final class SpotlightAppIconStore: ObservableObject {
    static let shared = SpotlightAppIconStore()

    @Published private(set) var icons: [String: UIImage] = [:]
    @Published private(set) var storeNames: [String: String] = [:]

    private var diskCache: [String: UIImage] = [:]
    private var inFlight: Set<String> = []
    private static let namesKey = "spotlight.storeNames"

    private init() {
        storeNames = UserDefaults.standard.dictionary(forKey: Self.namesKey + "." + Self.countryCode) as? [String: String] ?? [:]
    }

    func name(for bundleId: String) -> String {
        if let fixed = SpotlightAppCatalog.app(bundleId)?.fixedName { return fixed }
        return storeNames[bundleId] ?? ""
    }

    /// Reads the disk cache without publishing, so views can call it while rendering.
    func icon(for bundleId: String) -> UIImage? {
        if let icon = icons[bundleId] ?? diskCache[bundleId] { return icon }
        guard let data = try? Data(contentsOf: Self.iconURL(bundleId)), let image = UIImage(data: data) else { return nil }
        diskCache[bundleId] = image
        return image
    }

    func prefetch(_ bundleIds: [String]) {
        for id in bundleIds where icon(for: id) == nil || (SpotlightAppCatalog.app(id)?.fixedName == nil && storeNames[id] == nil) {
            guard !inFlight.contains(id) else { continue }
            inFlight.insert(id)
            Task { await fetch(id) }
        }
    }

    private func fetch(_ bundleId: String) async {
        defer { inFlight.remove(bundleId) }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            // No `lang`: the store answers 400 for most language/country pairs; each storefront uses its own language.
            URLQueryItem(name: "country", value: Self.countryCode),
        ]
        guard let url = components.url else { return }
        do {
            let (raw, _) = try await URLSession.shared.data(from: url)
            // Store descriptions contain raw control characters that JSONSerialization rejects.
            let data = Data(raw.map { $0 < 0x20 ? 0x20 : $0 })
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = (json["results"] as? [[String: Any]])?.first else {
                dlog("[SPOTLIGHT] icon lookup · \(bundleId) · not in store (\(Self.countryCode))")
                return
            }
            if let trackName = result["trackName"] as? String {
                storeNames[bundleId] = Self.homeScreenName(fromStoreName: trackName)
                UserDefaults.standard.set(storeNames, forKey: Self.namesKey + "." + Self.countryCode)
            }
            if icon(for: bundleId) == nil,
               let artwork = (result["artworkUrl512"] as? String).flatMap(URL.init(string:)) {
                let (imageData, _) = try await URLSession.shared.data(from: artwork)
                if let image = UIImage(data: imageData) {
                    try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)
                    try? imageData.write(to: Self.iconURL(bundleId))
                    icons[bundleId] = image
                }
            }
        } catch {
            dlog("✗ [SPOTLIGHT] icon lookup · \(bundleId) · \(error.localizedDescription)")
        }
    }

    /// “Mapas de Apple” → “Mapas”, “Gmail - El correo de Google” → “Gmail”.
    static func homeScreenName(fromStoreName name: String) -> String {
        var short = name
        for separator in [":", " - ", " – ", " — "] {
            if let range = short.range(of: separator) { short = String(short[..<range.lowerBound]) }
        }
        for suffix in [" de Apple", " d’Apple", " von Apple", " di Apple", " da Apple"] where short.hasSuffix(suffix) {
            short = String(short.dropLast(suffix.count))
        }
        return short.trimmingCharacters(in: .whitespaces)
    }

    private static var countryCode: String { (Locale.current.region?.identifier ?? "US").lowercased() }

    private static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SpotlightIcons")
    }

    private static func iconURL(_ bundleId: String) -> URL {
        cacheDir.appendingPathComponent("\(bundleId).jpg")
    }
}

/// Home screen icon shape: store artwork is square, iOS masks it to a continuous rounded square.
struct SpotlightAppIcon: View {
    @ObservedObject private var store = SpotlightAppIconStore.shared
    let bundleId: String
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let image = store.icon(for: bundleId) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.white.opacity(0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5) }
    }
}
