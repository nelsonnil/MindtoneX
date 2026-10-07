import CoreTelephony
import Foundation

/// Preferences for the Word API (incoming-call caller name). Separate keys and endpoints from song API.
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
        /// When ON, locked word is saved as a Contact name for the identification phone (primary caller ID on iOS).
        static let saveWordAsContact = "wordApi.saveWordAsContact"
        static let contactMode = "wordApi.contactMode"
        static let knownContactIdentifier = "wordApi.knownContact.identifier"
        static let knownContactPhoneDigits = "wordApi.knownContact.phoneDigits"
        static let knownContactDisplayName = "wordApi.knownContact.displayName"
        static let knownContactOriginalGivenName = "wordApi.knownContact.originalGivenName"
        static let knownContactGivenNameBeforeLock = "wordApi.knownContact.givenNameBeforeLock"
        static let restoreKnownNameOnSettingsExit = "wordApi.knownContact.restoreOnSettingsExit"
        static let lastDialedPhoneDigits = "wordApi.lastDialedPhoneDigits"
    }

    enum ContactMode: String, CaseIterable, Identifiable {
        case unknown
        case known

        var id: String { rawValue }

        var title: String {
            switch self {
            case .unknown: return "Unknown"
            case .known: return "Known"
            }
        }

        var pickerSymbol: String {
            switch self {
            case .unknown: return "phone.badge.plus"
            case .known: return "person.crop.circle.fill"
            }
        }

        var pickerHint: String {
            switch self {
            case .unknown: return "New number"
            case .known: return "Pick contact"
            }
        }

        var detailLine: String {
            switch self {
            case .unknown:
                return "Dial from the app on Perform (real call) so we learn the number. On lock: new contact if the number is new, or update that number’s existing card — first name becomes the word."
            case .known:
                return "Pick their contact before Perform. On lock: update that same card only — replace first name with the word (not a new contact)."
            }
        }
    }

    enum Provider: String, CaseIterable, Identifiable {
        case inject
        case elips
        case custom
        case card
        case voice

        var id: String { rawValue }
        var title: String {
            switch self {
            case .inject: return "Inject"
            case .elips: return "Elips"
            case .custom: return "Custom API"
            case .card: return "Camera (OCR)"
            case .voice: return "Voice (AI)"
            }
        }

        /// Compact label for the home integration grid.
        var gridTitle: String {
            switch self {
            case .inject: return "Inject"
            case .elips: return "Elips"
            case .custom: return "Custom"
            case .card: return "Camera OCR"
            case .voice: return "Voice"
            }
        }

        var pickerSymbol: String {
            switch self {
            case .inject: return "antenna.radiowaves.left.and.right"
            case .elips: return "link.circle.fill"
            case .custom: return "curlybraces"
            case .card: return "doc.viewfinder"
            case .voice: return "mic.fill"
            }
        }

        var pickerHint: String {
            switch self {
            case .inject: return "Word JSON · poll"
            case .elips: return "pag.gg URL · poll"
            case .custom: return "REST + field"
            case .card: return "Volume scan"
            case .voice: return "Own AI prompt"
            }
        }

        var detail: String {
            switch self {
            case .inject:
                return "Enter your Inject ID for the **word** endpoint. The app reads the JSON; a new submission changes count/value and that text becomes the incoming caller name."
            case .elips:
                return "Paste the full **word** API URL from Elips (https://pag.gg/…). During Perform the app polls every 2 s; if the word changes it updates the **incoming caller name**, otherwise it stays as is."
            case .custom:
                return "Any URL returning a JSON object. Pick the field for the label (e.g. word, label, value). Polled every 2 s during Perform; optional `count` / `receiveCount` in JSON help detect changes."
            case .card:
                return "Same **volume scan** as Card song input. **Line 1** = song · **line 2** = caller name word (this card). Notes chip uses **line 3** on the Notes contact card when that source is Card OCR. No network poll."
            case .voice:
                return "Uses the **Song input = Voice** microphone with a **separate AI prompt** for the contact word (see script hint). Requires OpenAI key in Voice settings."
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
        switch provider {
        case .card:
            return VoiceSettings.inputMode == .card
        case .voice:
            return VoiceListenPlan.current.callerName
        case .custom:
            guard endpoint(for: provider) != nil else { return false }
            return !customField.isEmpty
        default:
            guard endpoint(for: provider) != nil else { return false }
            return true
        }
    }

    static var provider: Provider { Provider(rawValue: d.string(forKey: Key.provider) ?? "") ?? .inject }
    static var injectID: String { trimmed(d.string(forKey: Key.injectID)) }
    static var elipsURL: String { trimmed(d.string(forKey: Key.elipsURL)) }
    static var customURL: String { trimmed(d.string(forKey: Key.customURL)) }
    static let defaultCustomField = "word"
    static var customField: String { trimmed(d.string(forKey: Key.customField) ?? defaultCustomField) }
    static var customHeaderName: String { trimmed(d.string(forKey: Key.customHeaderName)) }
    static var fallbackPhoneDigits: String { trimmed(d.string(forKey: Key.fallbackPhoneDigits)) }

    /// Saves the locked word as the contact display name for the spectator number (default ON).
    static var saveWordAsContactEnabled: Bool {
        if d.object(forKey: Key.saveWordAsContact) != nil {
            return d.bool(forKey: Key.saveWordAsContact)
        }
        return true
    }

    static func setSaveWordAsContactEnabled(_ enabled: Bool) {
        d.set(enabled, forKey: Key.saveWordAsContact)
    }

    static var contactMode: ContactMode {
        ContactMode(rawValue: d.string(forKey: Key.contactMode) ?? "") ?? .unknown
    }

    static func setContactMode(_ mode: ContactMode) {
        d.set(mode.rawValue, forKey: Key.contactMode)
    }

    static var knownContactIdentifier: String? {
        let id = trimmed(d.string(forKey: Key.knownContactIdentifier))
        return id.isEmpty ? nil : id
    }

    static var knownContactDisplayName: String { trimmed(d.string(forKey: Key.knownContactDisplayName)) }
    static var knownContactPhoneDigits: String { trimmed(d.string(forKey: Key.knownContactPhoneDigits)) }
    static var knownContactOriginalGivenName: String { trimmed(d.string(forKey: Key.knownContactOriginalGivenName)) }
    static var lastDialedPhoneDigits: String { trimmed(d.string(forKey: Key.lastDialedPhoneDigits)) }

    static var hasKnownContactSelected: Bool {
        knownContactIdentifier != nil && knownContactPhoneDigits.count >= 7
    }

    static var restoreKnownNameOnSettingsExit: Bool {
        if d.object(forKey: Key.restoreKnownNameOnSettingsExit) != nil {
            return d.bool(forKey: Key.restoreKnownNameOnSettingsExit)
        }
        return true
    }

    static func setRestoreKnownNameOnSettingsExit(_ enabled: Bool) {
        d.set(enabled, forKey: Key.restoreKnownNameOnSettingsExit)
    }

    static func saveKnownContactSelection(
        identifier: String,
        displayName: String,
        phoneDigits: String,
        originalGivenName: String
    ) {
        d.set(identifier, forKey: Key.knownContactIdentifier)
        d.set(displayName, forKey: Key.knownContactDisplayName)
        d.set(canonicalPhoneDigits(phoneDigits), forKey: Key.knownContactPhoneDigits)
        d.set(originalGivenName, forKey: Key.knownContactOriginalGivenName)
        d.removeObject(forKey: Key.knownContactGivenNameBeforeLock)
    }

    static func saveKnownContactGivenNameBeforeLock(_ givenName: String) {
        d.set(givenName, forKey: Key.knownContactGivenNameBeforeLock)
    }

    static func clearKnownContactSelection() {
        d.removeObject(forKey: Key.knownContactIdentifier)
        d.removeObject(forKey: Key.knownContactDisplayName)
        d.removeObject(forKey: Key.knownContactPhoneDigits)
        d.removeObject(forKey: Key.knownContactOriginalGivenName)
        d.removeObject(forKey: Key.knownContactGivenNameBeforeLock)
    }

    static func setLastDialedPhoneDigits(_ digits: String) {
        d.set(canonicalPhoneDigits(digits), forKey: Key.lastDialedPhoneDigits)
    }

    /// Strip to digits only (no country inference).
    static func normalizePhoneDigits(_ raw: String) -> String {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("00") { digits.removeFirst(2) }
        return digits
    }

    /// Device region for national dial heuristics (Settings → Region, then SIM country).
    static var deviceRegionISO: String {
        if let region = Locale.current.region?.identifier, !region.isEmpty {
            return region.uppercased()
        }
        if let sim = cellularCountryISO() {
            return sim
        }
        return "US"
    }

    private static func cellularCountryISO() -> String? {
        let info = CTTelephonyNetworkInfo()
        let codes = info.serviceSubscriberCellularProviders?
            .values
            .compactMap { $0.isoCountryCode?.uppercased() }
            .filter { !$0.isEmpty && $0 != "--" }
        return codes?.first
    }

    static func defaultCountryCallingCode(for region: String = deviceRegionISO) -> String? {
        switch region.uppercased() {
        case "ES": return "34"
        case "US", "CA", "DO", "PR": return "1"
        case "GB", "UK": return "44"
        case "FR": return "33"
        case "DE": return "49"
        case "IT": return "39"
        case "PT": return "351"
        case "MX": return "52"
        case "AR": return "54"
        case "CO": return "57"
        case "CL": return "56"
        default: return nil
        }
    }

    /// Full digits for Call Directory / Contacts (adds country code when user typed a national number).
    static func canonicalPhoneDigits(_ raw: String) -> String {
        var d = normalizePhoneDigits(raw)
        guard !d.isEmpty else { return d }
        if d.hasPrefix("00") { d.removeFirst(2) }
        while d.first == "0", d.count > 10 { d.removeFirst() }
        guard let cc = defaultCountryCallingCode() else { return d }
        if d.hasPrefix(cc) { return d }
        if shouldPrependCountryCode(d, countryCode: cc) {
            return cc + d
        }
        return d
    }

    private static func shouldPrependCountryCode(_ digits: String, countryCode: String) -> Bool {
        switch countryCode {
        case "34":
            return digits.count == 9 && ["6", "7", "9"].contains(String(digits.prefix(1)))
        case "1":
            return digits.count == 10
        case "44":
            return digits.count >= 10 && digits.count <= 11 && digits.hasPrefix("7")
        default:
            return digits.count >= 8 && digits.count <= 11
        }
    }

    /// National number without country code — how you usually dial on this phone.
    static func nationalNumber(fromCanonical digits: String) -> String {
        let d = canonicalPhoneDigits(digits)
        guard let cc = defaultCountryCallingCode(), d.hasPrefix(cc), d.count > cc.count else {
            return d
        }
        return String(d.dropFirst(cc.count))
    }

    /// `tel:` URL using national format when possible (same as Phone app dial pad).
    static func phoneDialURL(storedDigits: String) -> URL? {
        let canonical = canonicalPhoneDigits(storedDigits)
        guard canonical.count >= 7 else { return nil }
        let national = nationalNumber(fromCanonical: canonical)
        if national.count >= 7, let url = URL(string: "tel://\(national)") {
            return url
        }
        return URL(string: "tel://+\(canonical)")
    }

    static func formatPhoneForDisplay(_ raw: String) -> String {
        let canonical = canonicalPhoneDigits(raw)
        guard canonical.count >= 9 else { return phoneDisplayPlaceholder() }
        let national = nationalNumber(fromCanonical: canonical)
        if national.count == 9 {
            let a = national.prefix(3)
            let b = national.dropFirst(3).prefix(3)
            let c = national.suffix(3)
            return "\(a) \(b) \(c)"
        }
        if national.count == 10 {
            let a = national.prefix(3)
            let b = national.dropFirst(3).prefix(3)
            let c = national.suffix(4)
            return "(\(a)) \(b)-\(c)"
        }
        return national
    }

    static func phoneDisplayPlaceholder() -> String {
        switch deviceRegionISO.uppercased() {
        case "ES": return "690 808 919"
        case "US", "CA": return "(415) 555-0123"
        default: return "phone number"
        }
    }

    static func phoneEntryHint() -> String {
        switch deviceRegionISO.uppercased() {
        case "ES":
            return "Escribe el móvil como en Teléfono (690 808 919). No hace falta +34 ni 034."
        default:
            return "Enter the number like your Phone app — country code optional; we use your iPhone region."
        }
    }

    /// Digits used for Call Directory + contact sync (contact modes override manual field when ON).
    static func identificationPhoneDigitsRaw() -> String {
        if saveWordAsContactEnabled {
            switch contactMode {
            case .known:
                if knownContactPhoneDigits.count >= 7 {
                    return canonicalPhoneDigits(knownContactPhoneDigits)
                }
            case .unknown:
                if lastDialedPhoneDigits.count >= 7 {
                    return canonicalPhoneDigits(lastDialedPhoneDigits)
                }
            }
        }
        return canonicalPhoneDigits(fallbackPhoneDigits)
    }

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
        case .card, .voice: return nil
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
        case .card: return "Select **Card** as song input — line 1 song · line 2 caller word (see Instructions)"
        case .voice: return "Set **Song input** to **Voice** and add OpenAI key — use the contact-word script on this card"
        }
    }

    static func summary() -> String {
        let url = endpoint(for: provider)?.absoluteString ?? "none"
        let field = provider == .custom ? " field=\(customField)" : ""
        let cadence = provider == .card ? "volume-scan" : "every=\(pollInterval)s"
        return "word provider=\(provider.rawValue) url=\(url)\(field) \(cadence)"
    }

    /// Parses identification phone into Call Directory numeric form (digits only, no +).
    static func fallbackPhoneNumber() -> Int64? {
        let digits = identificationPhoneDigitsRaw()
        guard digits.count >= 7, let value = Int64(digits) else { return nil }
        return value
    }

    /// E.164 with leading + for Contacts / display.
    static func identificationPhoneE164String() -> String? {
        guard let value = fallbackPhoneNumber() else { return nil }
        return "+\(value)"
    }

    /// Legacy name used by older contact sync call sites.
    static func fallbackPhoneE164String() -> String? {
        identificationPhoneE164String()
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

    static func parse(
        _ object: [String: Any],
        provider: WordApiSettings.Provider,
        raw: String,
        customField: String? = nil
    ) throws -> WordReading {
        switch provider {
        case .card, .voice:
            throw ClientError.notConfigured
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
            let field = customField ?? WordApiSettings.customField
            guard let value = ApiJSON.value(in: object, path: field) else { throw ClientError.missingField(field) }
            return WordReading(count: ApiJSON.int(in: object, keys: ["count"]),
                               receiveCount: ApiJSON.int(in: object, keys: ["receiveCount", "receive_count"]),
                               word: ApiJSON.text(value),
                               raw: raw)
        }
    }
}
