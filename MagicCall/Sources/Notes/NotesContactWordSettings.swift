import Foundation

/// Word source for the **Notes contact** chip — separate endpoints from Caller name and song API.
enum NotesContactWordSettings {
    typealias Provider = WordApiSettings.Provider

    enum Key {
        static let wordInputEnabled = "notesContact.word.enabled"
        static let provider = "notesContact.word.provider"
        static let injectID = "notesContact.word.inject.id"
        static let elipsURL = "notesContact.word.elips.url"
        static let customURL = "notesContact.word.custom.url"
        static let customField = "notesContact.word.custom.field"
        static let customHeaderName = "notesContact.word.custom.headerName"
    }

    static let defaultCustomField = "word"
    private static let customHeaderAccount = "notesContact.word.custom.headerValue"
    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            Key.wordInputEnabled: true,
            Key.provider: Provider.inject.rawValue,
            Key.customField: defaultCustomField,
        ])
    }

    static var wordInputEnabled: Bool {
        if d.object(forKey: Key.wordInputEnabled) != nil {
            return d.bool(forKey: Key.wordInputEnabled)
        }
        return true
    }

    static var provider: Provider {
        Provider(rawValue: d.string(forKey: Key.provider) ?? "") ?? .inject
    }

    static var injectID: String { trimmed(d.string(forKey: Key.injectID)) }
    static var elipsURL: String { trimmed(d.string(forKey: Key.elipsURL)) }
    static var customURL: String { trimmed(d.string(forKey: Key.customURL)) }
    static var customField: String {
        let f = trimmed(d.string(forKey: Key.customField) ?? defaultCustomField)
        return f.isEmpty ? defaultCustomField : f
    }

    static var customHeaderName: String { trimmed(d.string(forKey: Key.customHeaderName)) }

    static var customHeaderValue: String? {
        let value = trimmed(Keychain.get(account: customHeaderAccount))
        return value.isEmpty ? nil : value
    }

    static func saveCustomHeaderValue(_ value: String?) {
        let clean = trimmed(value)
        Keychain.set(clean.isEmpty ? nil : clean, account: customHeaderAccount)
    }

    static var hasWordEndpoint: Bool {
        switch provider {
        case .card:
            return VoiceSettings.inputMode == .card
        case .voice:
            return VoiceListenPlan.current.notesContact
        case .custom:
            guard endpoint(for: provider) != nil else { return false }
            return !customField.isEmpty
        default:
            return endpoint(for: provider) != nil
        }
    }

    static var isConfigured: Bool {
        wordInputEnabled && hasWordEndpoint
    }

    static var setupHint: String {
        switch provider {
        case .inject: return "Enter your Inject ID for the Notes word"
        case .elips: return "Add your Elips word URL in connection details"
        case .custom: return customURL.isEmpty ? "Add your API URL in connection details" : "Pick the JSON field in connection details"
        case .card: return "Set Song input to Camera — write the Notes chip word on **line 3**"
        case .voice: return "Set Song input to Voice — use the Notes contact script on this card"
        }
    }

    static func injectEndpoint(for id: String) -> URL? {
        let id = trimmed(id)
        guard !id.isEmpty else { return nil }
        if id.lowercased().hasPrefix("http") { return URL(string: id) }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: WordApiSettings.injectEndpointTemplate.replacingOccurrences(of: "{ID}", with: encoded))
    }

    static func endpoint(for provider: Provider) -> URL? {
        switch provider {
        case .inject: return injectEndpoint(for: injectID)
        case .elips: return httpURL(elipsURL)
        case .custom: return httpURL(customURL)
        case .card, .voice: return nil
        }
    }

    static func summary() -> String {
        "notes provider=\(provider.rawValue) url=\(endpoint(for: provider)?.absoluteString ?? "card")"
    }

    private static func trimmed(_ s: String?) -> String {
        s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func httpURL(_ raw: String) -> URL? {
        let t = trimmed(raw)
        guard !t.isEmpty else { return nil }
        var s = t
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        return URL(string: s)
    }
}

enum NotesContactWordClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = WordApiSettings.requestTimeout
        return URLSession(configuration: config)
    }()

    static func fetch(performDiagnostics: WordFetchDiagnostics? = nil) async throws -> WordReading {
        let provider = NotesContactWordSettings.provider
        guard var url = NotesContactWordSettings.endpoint(for: provider) else {
            throw WordApiClient.ClientError.notConfigured
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query = components?.queryItems ?? []
        query.append(URLQueryItem(name: "mx", value: String(Int(Date().timeIntervalSince1970 * 1000))))
        query.append(URLQueryItem(name: "_", value: UUID().uuidString))
        components?.queryItems = query
        if let busted = components?.url { url = busted }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: WordApiSettings.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if provider == .custom,
           !NotesContactWordSettings.customHeaderName.isEmpty,
           let value = NotesContactWordSettings.customHeaderValue {
            request.setValue(value, forHTTPHeaderField: NotesContactWordSettings.customHeaderName)
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WordApiClient.ClientError.http(http.statusCode)
        }
        guard let object = ApiJSON.object(from: data) else { throw WordApiClient.ClientError.notJSON }
        let raw = String(data: data.prefix(600), encoding: .utf8) ?? ""
        return try WordApiClient.parse(
            object,
            provider: provider,
            raw: raw,
            customField: NotesContactWordSettings.customField
        )
    }
}
