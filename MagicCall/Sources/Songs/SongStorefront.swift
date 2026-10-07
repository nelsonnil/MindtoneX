import Foundation

/// iTunes Search API storefront for song preview lookup (`country` query param).
enum SongStorefront: String, CaseIterable, Identifiable {
    case auto = ""
    case cn = "CN"
    case hk = "HK"
    case tw = "TW"
    case us = "US"
    case gb = "GB"
    case es = "ES"
    case fr = "FR"
    case de = "DE"
    case jp = "JP"
    case kr = "KR"
    case mx = "MX"
    case br = "BR"
    case au = "AU"
    case inRegion = "IN"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .auto: return "Automatic (iPhone region)"
        case .cn: return "China mainland (CN)"
        case .hk: return "Hong Kong (HK)"
        case .tw: return "Taiwan (TW)"
        case .us: return "United States (US)"
        case .gb: return "United Kingdom (GB)"
        case .es: return "Spain (ES)"
        case .fr: return "France (FR)"
        case .de: return "Germany (DE)"
        case .jp: return "Japan (JP)"
        case .kr: return "Korea (KR)"
        case .mx: return "Mexico (MX)"
        case .br: return "Brazil (BR)"
        case .au: return "Australia (AU)"
        case .inRegion: return "India (IN)"
        }
    }

    static func from(stored: String) -> SongStorefront {
        let code = stored.trimmingCharacters(in: .whitespaces).uppercased()
        if code.isEmpty { return .auto }
        return SongStorefront(rawValue: code) ?? .auto
    }

    /// Resolved code sent to iTunes (same rules as `PreviewService`).
    static func effectiveCode(stored: String = Prefs.storeCountry) -> String {
        let manual = stored.trimmingCharacters(in: .whitespaces).uppercased()
        if !manual.isEmpty { return manual }
        return Locale.current.region?.identifier.uppercased() ?? "US"
    }
}
