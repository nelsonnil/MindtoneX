import SwiftUI

/// Connection setup for API song input — matches home Oracle styling (not system Form gray).
struct ApiSettingsView: View {
    @AppStorage(ApiSettings.Key.provider) private var providerRaw = ApiSettings.Provider.inject.rawValue
    @AppStorage(ApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(ApiSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(ApiSettings.Key.elipsPeekEnabled) private var elipsPeekEnabled = false
    @AppStorage(ApiSettings.Key.elipsPeekURL) private var elipsPeekURL = ""
    @AppStorage(ApiSettings.Key.elipsPeekField) private var elipsPeekField = ApiSettings.defaultElipsPeekField
    @AppStorage(ApiSettings.Key.elipsPeekHeaderName) private var elipsPeekHeaderName = ""
    @AppStorage(ApiSettings.Key.customURL) private var customURL = ""
    @AppStorage(ApiSettings.Key.customField) private var customField = ApiSettings.defaultCustomField
    @AppStorage(ApiSettings.Key.customHeaderName) private var customHeaderName = ""
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @ObservedObject private var session = ApiSongSession.shared
    @AppStorage(SpectatorSettings.Key.count) private var interferenceSongCount = 1
    @AppStorage(InterferenceSettings.Key.enabled) private var interferenceEnabled = false

    @State private var headerDraft = ""
    @State private var savedHeaderHint: String?
    @State private var elipsPeekExpanded = false
    @State private var elipsPeekHeaderDraft = ""
    @State private var elipsPeekHeaderHint: String?
    @State private var elipsPeekTesting = false
    @State private var elipsPeekTestResult: (ok: Bool, text: String)?
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var provider: ApiSettings.Provider { ApiSettings.Provider(rawValue: providerRaw) ?? .inject }
    private var twoSongsOnCall: Bool { interferenceEnabled && interferenceSongCount == 2 }
    private var songPerformTimingNote: String {
        guard provider == .elips, twoSongsOnCall else { return SpectatorApiPerformTiming.settingsNote }
        return SpectatorApiPerformTiming.elipsTwoSongsNote
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introBlock

                oracleCard {
                    VStack(alignment: .leading, spacing: 12) {
                        OracleEyebrow(text: "Integration")
                        Picker("Integration", selection: $providerRaw) {
                            ForEach(ApiSettings.Provider.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        Text(provider.detail)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        SpectatorApiPerformTimingNote(note: songPerformTimingNote)
                    }
                }

                switch provider {
                case .inject: injectCard
                case .elips: elipsCard
                case .custom: customCards
                }

                oracleCard {
                    VStack(alignment: .leading, spacing: 12) {
                        OracleEyebrow(text: "Check")
                        Button {
                            Task { await runTest() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.body.weight(.semibold))
                                Text(testing ? "Testing…" : "Test connection")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if testing { ProgressView().tint(OracleTheme.gold) }
                            }
                            .foregroundStyle(ApiSettings.isConfigured ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(testing || !ApiSettings.isConfigured)

                        if let testResult {
                            Text(testResult.text)
                                .font(.caption)
                                .foregroundStyle(testResult.ok ? OracleTheme.gold : OracleTheme.coral)
                                .textSelection(.enabled)
                        } else {
                            Text("Reads the API once and shows what it returns right now.")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                        }
                    }
                }

                oracleCard {
                    VStack(alignment: .leading, spacing: 10) {
                        OracleEyebrow(text: "On Perform")
                        Text("The app checks every \(Int(ApiSettings.pollInterval)) seconds. On Perform it uses **whatever song the API shows** (even if they searched before Perform). A **new search during Perform** replaces it — same idea as the caller word API.")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if inputModeRaw != VoiceSettings.InputMode.api.rawValue {
                            Button("Use API as song input") {
                                inputModeRaw = VoiceSettings.InputMode.api.rawValue
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OracleTheme.gold)
                        } else {
                            Label("API is your active song input", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OracleTheme.gold)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("API connection")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            refreshHeader()
            refreshElipsPeekHeader()
        }
        .onChange(of: providerRaw) { _, newValue in
            testResult = nil
            elipsPeekTestResult = nil
            if session.isActive { session.stopTest() }
            dlog("[API] integration → \(ApiSettings.Provider(rawValue: newValue)?.title ?? newValue)")
        }
        .onChange(of: elipsPeekEnabled) { _, _ in syncElipsPeekPolling() }
        .onChange(of: elipsPeekURL) { _, _ in syncElipsPeekPolling() }
        .onChange(of: elipsPeekField) { _, _ in syncElipsPeekPolling() }
    }

    private func syncElipsPeekPolling() {
        elipsPeekTestResult = nil
        guard session.isActive else { return }
        ApiElipsPeekSession.shared.startIfNeeded(context: session.context)
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect the spectator’s search")
                .font(.headline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            Text("Choose Inject, Elips, or your own API. Enter the details below — no separate “settings app”; this is the same screen as home, with more room.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }

    private var injectCard: some View {
        oracleCard {
            VStack(alignment: .leading, spacing: 10) {
                OracleEyebrow(text: "Inject ID")
                oracleField("00000", text: $injectID)
                    .keyboardType(.asciiCapable)
                if let url = ApiSettings.injectEndpoint(for: injectID) {
                    Text(url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(OracleTheme.textSecondary)
                        .textSelection(.enabled)
                }
                Text("Paste the API token from Inject. When the count changes, that value becomes the song title.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
    }

    private var elipsCard: some View {
        oracleCard {
            VStack(alignment: .leading, spacing: 10) {
                OracleEyebrow(text: "Elips API URL (song)")
                oracleField("https://pag.gg/…/api/…", text: $elipsURL)
                    .keyboardType(.URL)
                Text("Copy the full **song** API URL from the Elips app. This endpoint drives the locked song during Perform.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if twoSongsOnCall {
                    Text("**2 songs:** the song already on this URL when you enter Perform is only the starting point — it is not song 1. The next change is song 1; the change after that is song 2.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.35)

                DisclosureGroup(isExpanded: $elipsPeekExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Use peek text API", isOn: $elipsPeekEnabled)
                            .font(.subheadline)
                            .tint(OracleTheme.gold)

                        Text("Optional second endpoint. While you **hold** the stage in Perform, MindtoneX shows this JSON field in peek (only if enabled and configured).")
                            .font(.caption2)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        OracleEyebrow(text: "Peek Custom API URL")
                        oracleField("https://example.com/api/word", text: $elipsPeekURL)
                            .keyboardType(.URL)

                        HStack {
                            Text("JSON field")
                                .font(.subheadline)
                                .foregroundStyle(OracleTheme.textPrimary)
                            Spacer()
                            TextField(ApiSettings.defaultElipsPeekField, text: $elipsPeekField)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(OracleTheme.textPrimary)
                        }

                        OracleEyebrow(text: "Peek auth (optional)")
                        oracleField("Header name, e.g. Authorization", text: $elipsPeekHeaderName)
                        if let hint = elipsPeekHeaderHint {
                            HStack {
                                Label("Value saved (\(hint))", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(OracleTheme.gold)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    ApiSettings.saveElipsPeekHeaderValue(nil)
                                    refreshElipsPeekHeader()
                                }
                                .font(.caption)
                            }
                        }
                        SecureField(elipsPeekHeaderHint == nil ? "Header value" : "Replace value", text: $elipsPeekHeaderDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button("Save peek header value") {
                            ApiSettings.saveElipsPeekHeaderValue(elipsPeekHeaderDraft)
                            elipsPeekHeaderDraft = ""
                            refreshElipsPeekHeader()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.gold)
                        .disabled(elipsPeekHeaderDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button {
                            Task { await runElipsPeekTest() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "eye")
                                Text(elipsPeekTesting ? "Testing peek…" : "Test peek API")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                if elipsPeekTesting { ProgressView().tint(OracleTheme.gold) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(elipsPeekTesting || !ApiSettings.elipsPeekIsActive)

                        if let elipsPeekTestResult {
                            Text(elipsPeekTestResult.text)
                                .font(.caption2)
                                .foregroundStyle(elipsPeekTestResult.ok ? OracleTheme.gold : OracleTheme.coral)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Peek text · Custom API", systemImage: "eye")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                }
            }
        }
    }

    private var customCards: some View {
        Group {
            oracleCard {
                VStack(alignment: .leading, spacing: 10) {
                    OracleEyebrow(text: "Custom API")
                    oracleField("https://example.com/api/song", text: $customURL)
                        .keyboardType(.URL)
                    HStack {
                        Text("JSON field")
                            .font(.subheadline)
                            .foregroundStyle(OracleTheme.textPrimary)
                        Spacer()
                        TextField("song", text: $customField)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(OracleTheme.textPrimary)
                    }
                    Text("GET request; JSON object. Field names ignore case; use dots for nested keys (data.song).")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            oracleCard {
                VStack(alignment: .leading, spacing: 10) {
                    OracleEyebrow(text: "Authentication (optional)")
                    oracleField("Header name, e.g. Authorization", text: $customHeaderName)
                    if let hint = savedHeaderHint {
                        HStack {
                            Label("Value saved (\(hint))", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.gold)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                ApiSettings.saveCustomHeaderValue(nil)
                                refreshHeader()
                            }
                            .font(.caption)
                        }
                    }
                    SecureField(savedHeaderHint == nil ? "Header value, e.g. Bearer …" : "Replace value", text: $headerDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button("Save header value") {
                        ApiSettings.saveCustomHeaderValue(headerDraft)
                        headerDraft = ""
                        refreshHeader()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
                    .disabled(headerDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func oracleCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
    }

    private func oracleField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.subheadline)
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(OracleTheme.textPrimary)
    }

    private func refreshHeader() {
        savedHeaderHint = ApiSettings.customHeaderValue.map { "…" + String($0.suffix(4)) }
    }

    private func refreshElipsPeekHeader() {
        elipsPeekHeaderHint = ApiSettings.elipsPeekHeaderValue.map { "…" + String($0.suffix(4)) }
    }

    private func runElipsPeekTest() async {
        elipsPeekTesting = true
        defer { elipsPeekTesting = false }
        do {
            let text = try await ApiSongClient.fetchElipsPeekText()
            if text.isEmpty {
                elipsPeekTestResult = (true, "Connected · field is empty right now")
            } else {
                elipsPeekTestResult = (true, "Connected · peek text “\(text)”")
            }
        } catch {
            elipsPeekTestResult = (false, "Failed: \(error.localizedDescription)")
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        let provider = ApiSettings.provider
        do {
            let reading = try await ApiSongClient.fetch(provider)
            let count = reading.count.map { "count \($0) · " } ?? ""
            if reading.hasSong {
                testResult = (true, "Connected · \(count)current value “\(reading.label)”")
            } else {
                testResult = (true, "Connected · \(count)no song yet. Response: \(reading.raw.prefix(200))")
            }
            dlog("[API] test \(provider.rawValue): \(testResult?.text ?? "")")
        } catch {
            testResult = (false, "Failed: \(error.localizedDescription)")
            dlog("✗ [API] test \(provider.rawValue): \(error.localizedDescription)")
        }
    }
}
