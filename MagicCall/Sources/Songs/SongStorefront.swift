import Foundation

/// iTunes Search API storefront for song preview lookup (`country` query param).
/// Not app UI language — pick which Apple Music / iTunes catalog to search.
enum SongStorefront {
    static let automaticTitle = "Automatic (iPhone region)"

    private static let catalogByCode: [String: String] = loadCatalog()
    private static let sortedCatalogEntries: [(code: String, name: String)] = {
        catalogByCode
            .map { (code: $0.key, name: englishDisplayName(code: $0.key, fallback: $0.value)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// All storefronts for the picker (ISO code → English name), alphabetical by name.
    static var catalogEntries: [(code: String, name: String)] { sortedCatalogEntries }

    static func isAutomatic(stored: String) -> Bool {
        stored.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func normalizedCode(stored: String) -> String {
        stored.trimmingCharacters(in: .whitespaces).uppercased()
    }

    static func isKnownStorefront(code: String) -> Bool {
        let c = code.uppercased()
        return !c.isEmpty && catalogByCode[c] != nil
    }

    /// Label for the Performance settings row.
    static func pickerRowTitle(stored: String) -> String {
        if isAutomatic(stored: stored) { return automaticTitle }
        let code = normalizedCode(stored: stored)
        if let official = catalogByCode[code] {
            return "\(englishDisplayName(code: code, fallback: official)) (\(code))"
        }
        return "Custom storefront (\(code))"
    }

    /// Resolved code sent to iTunes (same rules as `PreviewService`).
    static func effectiveCode(stored: String = Prefs.storeCountry) -> String {
        let manual = normalizedCode(stored: stored)
        if !manual.isEmpty { return manual }
        return Locale.current.region?.identifier.uppercased() ?? "US"
    }

    private static func loadCatalog() -> [String: String] {
        guard
            let url = Bundle.main.url(forResource: "ITunesStorefrontCountries", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            assertionFailure("Missing ITunesStorefrontCountries.json")
            return ["US": "United States"]
        }
        return decoded
    }

    private static func englishDisplayName(code: String, fallback: String) -> String {
        let locale = Locale(identifier: "en_US")
        if let localized = locale.localizedString(forRegionCode: code), !localized.isEmpty {
            return localized
        }
        return sanitizeCatalogName(fallback)
    }

    private static func sanitizeCatalogName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: " (the)", with: "")
            .replacingOccurrences(of: "Bahamas (the)", with: "Bahamas")
    }
}
