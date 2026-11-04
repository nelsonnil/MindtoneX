import Contacts
import Foundation

/// Preferences for the Spotlight song input. Views use @AppStorage with the same keys.
/// Song search timing (idle delay, Return, Interpret) is shared with Notes (`NotesSettings`).
enum SpotlightSettings {
    enum Key {
        static let contactIdentifier = "spotlight.contactIdentifier"
        static let contactName = "spotlight.contactName"
        static let disguiseText = "spotlight.disguiseText"
        static let suggestedApps = "spotlight.suggestedApps"
        static let browser = "spotlight.browser"
        static let pickedCard = "spotlight.pickedCard"
    }

    enum Browser: String, CaseIterable, Identifiable {
        case safari
        case chrome
        case google

        var id: String { rawValue }
        var title: String {
            switch self {
            case .safari: return "Safari"
            case .chrome: return "Chrome"
            case .google: return "Google"
            }
        }
        var bundleId: String {
            switch self {
            case .safari: return "com.apple.mobilesafari"
            case .chrome: return "com.google.chrome.ios"
            case .google: return "com.google.GoogleMobile"
            }
        }
    }

    static let suggestedAppCount = 8
    static let defaultSuggestedApps = [
        "com.google.GoogleMobile", "com.apple.mobilesafari", "net.whatsapp.WhatsApp", "com.burbn.instagram",
        "com.spotify.client", "com.facebook.Facebook", "com.apple.MobileAddressBook", "com.apple.mobilephone",
    ]

    private static var d: UserDefaults { .standard }

    static var contactIdentifier: String? {
        let id = d.string(forKey: Key.contactIdentifier) ?? ""
        return id.isEmpty ? nil : id
    }

    static var contactName: String {
        (d.string(forKey: Key.contactName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func saveContact(identifier: String, name: String) {
        d.set(identifier, forKey: Key.contactIdentifier)
        d.set(name, forKey: Key.contactName)
    }

    /// Copy of the card returned by the contact picker, which works without Contacts access.
    /// Used when the store can’t give the card back (access denied, or iOS 18 limited access without that contact).
    static func savePickedCard(_ contact: CNContact) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: contact, requiringSecureCoding: true)
        d.set(data, forKey: Key.pickedCard)
    }

    static var pickedCard: CNContact? {
        guard let data = d.data(forKey: Key.pickedCard) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CNContact.self, from: data)
    }

    /// What the spectator sees in the search bar: one character per key press, whatever key was pressed.
    static var disguiseText: String {
        let custom = (d.string(forKey: Key.disguiseText) ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? defaultDisguise(for: contactName) : custom
    }

    /// Spotlight shows exactly what is typed: lowercase, usually without accents.
    static func defaultDisguise(for name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    static var suggestedApps: [String] { decodeApps(d.string(forKey: Key.suggestedApps)) }

    static func decodeApps(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return defaultSuggestedApps }
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    static func encodeApps(_ ids: [String]) -> String { ids.joined(separator: ",") }

    static var browser: Browser { Browser(rawValue: d.string(forKey: Key.browser) ?? "") ?? .safari }

    static func summary() -> String {
        "contact=\(contactName.isEmpty ? "none" : contactName) disguise=“\(disguiseText)” browser=\(browser.rawValue) · \(NotesSettings.summary())"
    }
}

/// Spotlight section titles in the device language (iOS 26 wording).
struct SpotlightStrings {
    let siriSuggestions: String
    let showLess: String
    let topHit: String
    let suggestions: String
    let contacts: String
    let searchPlaceholder: String
    let recentSearches: String
    let clear: String

    static var current: SpotlightStrings {
        let code = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        switch code {
        case "es":
            return SpotlightStrings(siriSuggestions: "Sugerencias de Siri", showLess: "Mostrar menos", topHit: "Mejor resultado",
                                    suggestions: "Sugerencias", contacts: "Contactos", searchPlaceholder: "Búsqueda",
                                    recentSearches: "Búsquedas recientes", clear: "Borrar")
        case "fr":
            return SpotlightStrings(siriSuggestions: "Suggestions de Siri", showLess: "Afficher moins", topHit: "Meilleur résultat",
                                    suggestions: "Suggestions", contacts: "Contacts", searchPlaceholder: "Rechercher",
                                    recentSearches: "Recherches récentes", clear: "Effacer")
        case "de":
            return SpotlightStrings(siriSuggestions: "Siri-Vorschläge", showLess: "Weniger anzeigen", topHit: "Toptreffer",
                                    suggestions: "Vorschläge", contacts: "Kontakte", searchPlaceholder: "Suchen",
                                    recentSearches: "Letzte Suchen", clear: "Löschen")
        case "it":
            return SpotlightStrings(siriSuggestions: "Suggerimenti di Siri", showLess: "Mostra meno", topHit: "Risultato migliore",
                                    suggestions: "Suggerimenti", contacts: "Contatti", searchPlaceholder: "Cerca",
                                    recentSearches: "Ricerche recenti", clear: "Cancella")
        case "pt":
            return SpotlightStrings(siriSuggestions: "Sugestões da Siri", showLess: "Mostrar Menos", topHit: "Melhor Resultado",
                                    suggestions: "Sugestões", contacts: "Contatos", searchPlaceholder: "Buscar",
                                    recentSearches: "Buscas Recentes", clear: "Apagar")
        default:
            return SpotlightStrings(siriSuggestions: "Siri Suggestions", showLess: "Show Less", topHit: "Top Hit",
                                    suggestions: "Suggestions", contacts: "Contacts", searchPlaceholder: "Search",
                                    recentSearches: "Recent Searches", clear: "Clear")
        }
    }
}
