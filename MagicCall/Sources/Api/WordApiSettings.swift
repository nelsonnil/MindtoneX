import Foundation

/// Preferences for the Word API (incoming-call banner label). Separate keys and endpoints from song API.
enum WordApiSettings {
    enum Key {
        /// Master toggle: caller label during Perform (UserDefaults `wordApi.callerLabelEnabled`).
        static let callerLabelEnabled = "wordApi.callerLabelEnabled"
        /// Legacy key from build 102 — migrated once on read.
        static let legacyEnabled = "wordApi.enabled"
        static let provider = "wordApi.provider"
        static let injectID = "wordApi.inject.id"
        static let elipsURL = "wordApi.elips.url"
        static let customURL = "wordApi.custom.url"
        static let customField = "wordApi.custom.field"
        static let customHeaderName = "wordApi.custom.headerName"
        /// Optional E.164 digits-only fallback for Call Directory (e.g. 15551234567).
        static let fallbackPhoneDigits = "wordApi.fallbackPhoneDigits"
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
                return "Enter your Inject ID for the **word** endpoint. The app reads the JSON; a new submission changes count/value and that text becomes the caller label."
            case .elips:
                return "Paste the full **word** API URL from Elips (https://pag.gg/…). During Perform the app polls every 2 s; if the word changes it updates the banner, otherwise it stays as is."
            case .custom:
                return "Any URL returning a JSON object. Pick the field for the label (e.g. word, label, value). Polled every 2 s during Perform; optional `count` / `receiveCount` in JSON help detect changes."
            }
        }
    }

    static let pollInterval: TimeInterval = 2.0
    static let requestTimeout: TimeInterval = 8.0
    static let injectEndpointTemplate = "https://11z.co/_w/{ID}/selection"

    private static var d: UserDefaults { .standard }

    /// When OFF, Perform behaves as before Word API: no polling, Call Directory, or extension reload.
    static var callerLabelEnabled: Bool {
        if d.object(forKey: Key.callerLabelEnabled) != nil {
            return d.bool(forKey: Key.callerLabelEnabled)
        }
        if d.object(forKey: Key.legacyEnabled) != nil {
            let legacy = d.bool(forKey: Key.legacyEnabled)
            d.set(legacy, forKey: Key.callerLabelEnabled)
            d.removeObject(forKey: Key.legacyEnabled)
            return legacy
        }
        return false
    }

    static func setCallerLabelEnabled(_ enabled: Bool) {
        d.set(enabled, forKey: Key.callerLabelEnabled)
    }

    /// Endpoint + provider ready (ignores caller-label toggle — for connection test UI).
    static var hasWordEndpoint: Bool {
        guard endpoint(for: provider) != nil else { return false }
        return provider != .custom || !customField.isEmpty
    }

    static var provider: Provider { Provider(rawValue: d.string(forKey: Key.provider) ?? "") ?? .inject }
    static var injectID: String { trimmed(d.string(forKey: Key.injectID)) }
    static var elipsURL: String { trimmed(d.string(forKey: Key.elipsURL)) }
    static var customURL: String { trimmed(d.string(forKey: Key.customURL)) }
    static let defaultCustomField = "word"
    static var customField: String { trimmed(d.string(forKey: Key.customField) ?? defaultCustomField) }
    static var customHeaderName: String { trimmed(d.string(forKey: Key.customHeaderName)) }
    static var fallbackPhoneDigits: String { trimmed(d.string(forKey: Key.fallbackPhoneDigits)) }

    static var customHeaderValue: String? {
        let value = trimmed(Keychain.get(account: customHeaderAccount))
        return value.isEmpty ? nil : value
    }

    static func saveCustomHeaderValue(_ value: String?) {
        let clean = trimmed(value)
        Keychain.set(clean.isEmpty ? nil : clean, account: customHeaderAccount)
    }

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
        callerLabelEnabled && hasWordEndpoint
    }

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
        return "word provider=\(provider.rawValue) url=\(url)\(field) every=\(pollInterval)s"
    }

    /// Parses optional fallback phone into Call Directory numeric form (digits only, no +).
    static func fallbackPhoneNumber() -> Int64? {
        var digits = fallbackPhoneDigits.filter(\.isNumber)
        if digits.hasPrefix("00") { digits.removeFirst(2) }
        guard digits.count >= 7, let value = Int64(digits) else { return nil }
        return value
    }

    private static let customHeaderAccount = "wordApi.custom.headerValue"

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    private static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WordReading: Equatable {
    /// Inject / Elips submission counter (may stay flat on `/selection` while the word changes).
    var count: Int?
    /// Inject bumps this on each new spectator submission even when `count` is unchanged.
    var receiveCount: Int?
    var word: String
    var raw: String

    var hasWord: Bool { !word.isEmpty }
    var label: String { word }

    /// Any movement since the previous poll (counters, label, or raw JSON).
    func pollDelta(comparedTo previous: WordReading) -> Bool {
        if raw != previous.raw { return true }
        if count != previous.count { return true }
        if receiveCount != previous.receiveCount { return true }
        return !ApiJSON.sameText(word, previous.word)
    }

    /// Same snapshot as baseline (Inject frozen polls look like this).
    func matchesSnapshot(of baseline: WordReading) -> Bool {
        count == baseline.count
            && receiveCount == baseline.receiveCount
            && ApiJSON.sameText(word, baseline.word)
            && raw == baseline.raw
    }

    /// True when this poll is a new spectator word compared with baseline `old`.
    func isNewWord(comparedTo old: WordReading) -> Bool {
        if let count, let oldCount = old.count, count > oldCount { return true }
        if let receiveCount, let oldReceive = old.receiveCount, receiveCount > oldReceive { return true }
        if raw != old.raw, hasWord { return true }
        guard hasWord else { return false }
        return !ApiJSON.sameText(word, old.word)
    }

    /// Perform lock: baseline change, or any poll-to-poll delta once baseline exists.
    func shouldLockPerformWord(comparedTo baseline: WordReading, previousPoll: WordReading?) -> Bool {
        if isNewWord(comparedTo: baseline) { return true }
        guard let previousPoll else { return false }
        guard pollDelta(comparedTo: previousPoll) else { return false }
        return !matchesSnapshot(of: baseline)
    }

    func unchangedVsBaselineReason(comparedTo old: WordReading) -> String {
        if !hasWord {
            if let count, let oldCount = old.count, count > oldCount {
                return "count bumped but word empty — should lock via count"
            }
            return "empty word in response (ignored)"
        }
        let sameCount = count == old.count
        let sameReceive = receiveCount == old.receiveCount
        let sameWord = ApiJSON.sameText(word, old.word)
        if sameCount && sameReceive && sameWord { return "API returned same as baseline" }
        if sameCount && sameReceive, word != old.word {
            return "word differs only by case/accents (treated as unchanged)"
        }
        if count != old.count || receiveCount != old.receiveCount {
            return "count/receive flat but text unchanged — Inject may not have bumped JSON yet"
        }
        return "unchanged by isNewWord rules"
    }
}

struct WordFetchDiagnostics: Sendable {
    let pollNumber: Int
}

enum WordApiClient {
    enum ClientError: LocalizedError {
        case notConfigured
        case http(Int)
        case notJSON
        case missingField(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Word API not set up"
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
        config.timeoutIntervalForRequest = WordApiSettings.requestTimeout
        return URLSession(configuration: config)
    }()

    private static var lastPerformFetchSnapshot: (count: Int?, receive: Int?, word: String)?

    static func resetPerformFetchDiagnostics() {
        lastPerformFetchSnapshot = nil
    }

    static func fetch(
        _ provider: WordApiSettings.Provider = WordApiSettings.provider,
        performDiagnostics: WordFetchDiagnostics? = nil
    ) async throws -> WordReading {
        guard var url = WordApiSettings.endpoint(for: provider) else { throw ClientError.notConfigured }
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
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        if provider == .custom, !WordApiSettings.customHeaderName.isEmpty, let value = WordApiSettings.customHeaderValue {
            request.setValue(value, forHTTPHeaderField: WordApiSettings.customHeaderName)
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        guard let object = ApiJSON.object(from: data) else { throw ClientError.notJSON }
        let raw = String(data: data.prefix(600), encoding: .utf8) ?? ""
        let reading = try parse(object, provider: provider, raw: raw)
        if let diag = performDiagnostics {
            let countStr = reading.count.map(String.init) ?? "–"
            let receiveStr = reading.receiveCount.map(String.init) ?? "–"
            let snapshot = (reading.count, reading.receiveCount, reading.word)
            let changed = lastPerformFetchSnapshot.map {
                $0.count != snapshot.0 || $0.receive != snapshot.1 || $0.word != snapshot.2
            } ?? true
            dlog("[WORD] fetch poll #\(diag.pollNumber) · \(provider.title) count=\(countStr) receive=\(receiveStr) word=«\(reading.label)»\(changed ? "" : " (same as last fetch)")")
            if changed { lastPerformFetchSnapshot = snapshot }
        }
        return reading
    }

    static func parse(_ object: [String: Any], provider: WordApiSettings.Provider, raw: String) throws -> WordReading {
        switch provider {
        case .inject:
            return WordReading(count: ApiJSON.int(in: object, keys: ["count"]),
                               receiveCount: ApiJSON.int(in: object, keys: ["receiveCount", "receive_count"]),
                               word: ApiJSON.string(in: object, keys: [
                                   "value", "word", "label", "selection", "text", "message", "ai", "input", "output"
                               ]),
                               raw: raw)
        case .elips:
            return WordReading(count: ApiJSON.int(in: object, keys: ["count"]),
                               receiveCount: ApiJSON.int(in: object, keys: ["receiveCount", "receive_count"]),
                               word: ApiJSON.string(in: object, keys: [
                                   "word", "label", "outputWords", "value", "selection", "text", "message", "ai", "output"
                               ]),
                               raw: raw)
        case .custom:
            let field = WordApiSettings.customField
            guard let value = ApiJSON.value(in: object, path: field) else { throw ClientError.missingField(field) }
            return WordReading(count: ApiJSON.int(in: object, keys: ["count"]),
                               receiveCount: ApiJSON.int(in: object, keys: ["receiveCount", "receive_count"]),
                               word: ApiJSON.text(value),
                               raw: raw)
        }
    }
}
