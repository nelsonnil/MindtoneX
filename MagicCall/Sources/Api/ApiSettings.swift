import Foundation

/// Preferences for the API song input. Only one integration is active at a time: the provider is
/// a single stored value, so Inject, Elips and Custom API can never poll together.
enum ApiSettings {
    enum Key {
        static let provider = "api.provider"
        static let injectID = "api.inject.id"
        static let elipsURL = "api.elips.url"
        static let customURL = "api.custom.url"
        static let customField = "api.custom.field"
        static let customHeaderName = "api.custom.headerName"
    }

    enum Provider: String, CaseIterable, Identifiable {
        case inject
        case elips
        case custom

        var id: String { rawValue }
        var title: String {
            switch self {
            case .inject: return "Inject"
            case .elips: return "Elips"
            case .custom: return "Custom API"
            }
        }
        var detail: String {
            switch self {
            case .inject:
                return "Enter your Inject ID. The app reads https://11z.co/_w/{ID}/selection; a new search changes its count/value and that value is used as the song title."
            case .elips:
                return "Paste the full API URL from the Elips app (https://pag.gg/…/api/…). A new song (or artist) in the response is used as the song."
            case .custom:
                return "Any URL that returns a JSON object. Pick the field that holds the song title (e.g. song, value, data.title). A new value is used as the song."
            }
        }
    }

    /// Same cadence as G-Sensor's WatchPeekValueStore.
    static let pollInterval: TimeInterval = 2.0
    static let requestTimeout: TimeInterval = 8.0
    static let injectEndpointTemplate = "https://11z.co/_w/{ID}/selection"

    private static var d: UserDefaults { .standard }

    static var provider: Provider { Provider(rawValue: d.string(forKey: Key.provider) ?? "") ?? .inject }
    static var injectID: String { trimmed(d.string(forKey: Key.injectID)) }
    static var elipsURL: String { trimmed(d.string(forKey: Key.elipsURL)) }
    static var customURL: String { trimmed(d.string(forKey: Key.customURL)) }
    static let defaultCustomField = "song"
    static var customField: String { trimmed(d.string(forKey: Key.customField) ?? defaultCustomField) }
    static var customHeaderName: String { trimmed(d.string(forKey: Key.customHeaderName)) }

    static var customHeaderValue: String? {
        let value = trimmed(Keychain.get(account: customHeaderAccount))
        return value.isEmpty ? nil : value
    }

    static func saveCustomHeaderValue(_ value: String?) {
        let clean = trimmed(value)
        Keychain.set(clean.isEmpty ? nil : clean, account: customHeaderAccount)
    }

    /// Accepts a bare Inject ID or, for convenience, a full URL pasted from Inject.
    static func injectEndpoint(for id: String) -> URL? {
        let id = trimmed(id)
        guard !id.isEmpty else { return nil }
        if id.lowercased().hasPrefix("http") { return URL(string: id) }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: injectEndpointTemplate.replacingOccurrences(of: "{ID}", with: encoded))
    }

    static func endpoint(for provider: Provider) -> URL? {
        switch provider {
        case .inject: return injectEndpoint(for: injectID)
        case .elips: return httpURL(elipsURL)
        case .custom: return httpURL(customURL)
        }
    }

    static var isConfigured: Bool {
        guard endpoint(for: provider) != nil else { return false }
        return provider != .custom || !customField.isEmpty
    }

    /// What the strip and status bar show when the active integration is missing a field.
    static var setupHint: String {
        switch provider {
        case .inject: return "Enter your Inject ID above"
        case .elips: return "Tap connection details and paste your Elips URL"
        case .custom: return customURL.isEmpty ? "Tap connection details and add your API URL" : "Choose the JSON field in connection details"
        }
    }

    static func summary() -> String {
        let url = endpoint(for: provider)?.absoluteString ?? "none"
        let field = provider == .custom ? " field=\(customField)" : ""
        return "provider=\(provider.rawValue) url=\(url)\(field) every=\(pollInterval)s"
    }

    private static let customHeaderAccount = "customApi.headerValue"

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    private static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One poll result, normalized across integrations.
struct ApiReading: Equatable {
    /// Inject / Elips `count` — bumps on every new submission, even when the text repeats.
    var count: Int?
    var title: String
    var artist: String
    var raw: String

    var hasSong: Bool { !title.isEmpty }
    var searchQuery: String { [title, artist].filter { !$0.isEmpty }.joined(separator: " ") }
    var label: String { artist.isEmpty ? title : "\(title) — \(artist)" }

    /// True when this reading is a new spectator search compared with `old`.
    func isNewSearch(comparedTo old: ApiReading) -> Bool {
        guard hasSong else { return false }
        if let count, let oldCount = old.count, count != oldCount { return true }
        return !ApiJSON.sameText(title, old.title) || !ApiJSON.sameText(artist, old.artist)
    }
}

enum ApiSongClient {
    enum ClientError: LocalizedError {
        case notConfigured
        case http(Int)
        case notJSON
        case missingField(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "API not set up"
            case .http(let code): return "Server answered HTTP \(code)"
            case .notJSON: return "Response is not a JSON object"
            case .missingField(let field): return "Field “\(field)” not found in the response"
            }
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = ApiSettings.requestTimeout
        return URLSession(configuration: config)
    }()

    static func fetch(_ provider: Provider = ApiSettings.provider) async throws -> ApiReading {
        guard let url = ApiSettings.endpoint(for: provider) else { throw ClientError.notConfigured }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: ApiSettings.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .custom, !ApiSettings.customHeaderName.isEmpty, let value = ApiSettings.customHeaderValue {
            request.setValue(value, forHTTPHeaderField: ApiSettings.customHeaderName)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        guard let object = ApiJSON.object(from: data) else { throw ClientError.notJSON }
        let raw = String(data: data.prefix(600), encoding: .utf8) ?? ""
        return try parse(object, provider: provider, raw: raw)
    }

    typealias Provider = ApiSettings.Provider

    static func parse(_ object: [String: Any], provider: Provider, raw: String) throws -> ApiReading {
        switch provider {
        case .inject:
            return ApiReading(count: ApiJSON.int(in: object, keys: ["count"]),
                              title: ApiJSON.string(in: object, keys: ["value"]),
                              artist: "", raw: raw)
        case .elips:
            let song = ApiJSON.string(in: object, keys: ["song"])
            let words = ApiJSON.string(in: object, keys: ["outputWords", "word"])
            let fallback = words.isEmpty ? ApiJSON.string(in: object, keys: ["wordToNumber"]) : words
            return ApiReading(count: ApiJSON.int(in: object, keys: ["count"]),
                              title: song.isEmpty ? fallback : song,
                              artist: ApiJSON.string(in: object, keys: ["artist"]), raw: raw)
        case .custom:
            let field = ApiSettings.customField
            guard let value = ApiJSON.value(in: object, path: field) else { throw ClientError.missingField(field) }
            return ApiReading(count: nil, title: ApiJSON.text(value), artist: "", raw: raw)
        }
    }
}

/// Lenient JSON helpers, ported from G-Sensor's `JSONObjectCaseInsensitive`.
enum ApiJSON {
    static func object(from data: Data) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        if let dict = json as? [String: Any] { return dict }
        if let array = json as? [[String: Any]] { return array.first }
        return nil
    }

    static func lookup(_ object: [String: Any], key: String) -> Any? {
        if let exact = object[key] { return exact }
        return object.first { $0.key.compare(key, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.value
    }

    /// Case-insensitive key lookup; dots walk into nested objects (`data.song`).
    static func value(in object: [String: Any], path: String) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }
        var current: Any = object
        for part in parts {
            guard let dict = current as? [String: Any], let next = lookup(dict, key: part) else { return nil }
            current = next
        }
        return current is NSNull ? nil : current
    }

    static func string(in object: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let v = lookup(object, key: key) {
                if let nested = v as? [String: Any] {
                    let inner = string(in: nested, keys: ["value", "word", "label", "text", "selection"])
                    if !inner.isEmpty { return inner }
                }
                let s = text(v)
                if !s.isEmpty { return s }
            }
        }
        return ""
    }

    static func int(in object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            switch lookup(object, key: key) {
            case let n as NSNumber: return n.intValue
            case let s as String: if let i = Int(s.trimmingCharacters(in: .whitespaces)) { return i }
            default: continue
            }
        }
        return nil
    }

    static func text(_ value: Any) -> String {
        switch value {
        case let s as String: return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }

    static func sameText(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(b.trimmingCharacters(in: .whitespacesAndNewlines),
                     options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
