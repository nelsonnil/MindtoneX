import SwiftUI

struct WordApiSettingsView: View {
    @AppStorage(WordApiSettings.Key.provider) private var providerRaw = WordApiSettings.Provider.inject.rawValue
    @AppStorage(WordApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(WordApiSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(WordApiSettings.Key.customURL) private var customURL = ""
    @AppStorage(WordApiSettings.Key.customField) private var customField = WordApiSettings.defaultCustomField
    @AppStorage(WordApiSettings.Key.customHeaderName) private var customHeaderName = ""
    @AppStorage(WordApiSettings.Key.fallbackPhoneDigits) private var fallbackPhoneDigits = ""
    @ObservedObject private var session = WordApiSession.shared

    @State private var headerDraft = ""
    @State private var savedHeaderHint: String?
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var provider: WordApiSettings.Provider { WordApiSettings.Provider(rawValue: providerRaw) ?? .inject }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                introBlock

                oracleCard {
                    VStack(alignment: .leading, spacing: 12) {
                        OracleEyebrow(text: "Integration")
                        Picker("Integration", selection: $providerRaw) {
                            ForEach(WordApiSettings.Provider.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        Text(provider.detail)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                switch provider {
                case .inject: injectCard
                case .elips: elipsCard
                case .custom: customCards
                }

                oracleCard {
                    VStack(alignment: .leading, spacing: 10) {
                        OracleEyebrow(text: "Call Identification (optional fallback)")
                        oracleField("15551234567 (digits only, E.164)", text: $fallbackPhoneDigits)
                            .keyboardType(.phonePad)
                        Text("For **any-number** labels, enable **Live Caller ID Lookup** (iOS 18+) in Settings → Phone. This field helps **Call Directory** label one known number if Live Lookup is not set up yet.")
                            .font(.caption2)
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
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
                            .foregroundStyle(WordApiSettings.hasWordEndpoint ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(testing || !WordApiSettings.hasWordEndpoint)

                        if let testResult {
                            Text(testResult.text)
                                .font(.caption)
                                .foregroundStyle(testResult.ok ? OracleTheme.gold : OracleTheme.coral)
                                .textSelection(.enabled)
                        } else {
                            Text("Reads the Word API once and shows the current label text.")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                        }
                    }
                }

                oracleCard {
                    VStack(alignment: .leading, spacing: 10) {
                        OracleEyebrow(text: "On Perform")
                        Text("Turn **Caller label** on the home card first. Then polls every \(Int(WordApiSettings.pollInterval)) seconds in parallel with your song input. First reading = old word; **next change** = spectator word → locked → incoming call banner.")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Enable the MindtoneX extension under **Settings → Phone → Call Blocking & Identification**.")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                }
            }
            .padding(20)
        }
        .background(OracleTheme.bgTop)
        .navigationTitle("Word API connection")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear(perform: refreshHeader)
        .onChange(of: providerRaw) { _, newValue in
            testResult = nil
            if session.isActive { session.stopTest() }
            dlog("[WORD] integration → \(WordApiSettings.Provider(rawValue: newValue)?.title ?? newValue)")
        }
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect the spectator’s word")
                .font(.headline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            Text("Separate from the song API — own URL, Inject ID, and JSON field. Used only for the incoming-call label.")
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
                if let url = WordApiSettings.injectEndpoint(for: injectID) {
                    Text(url.absoluteString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(OracleTheme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var elipsCard: some View {
        oracleCard {
            VStack(alignment: .leading, spacing: 10) {
                OracleEyebrow(text: "Elips API URL")
                oracleField("https://pag.gg/…/api/…", text: $elipsURL)
                    .keyboardType(.URL)
            }
        }
    }

    private var customCards: some View {
        Group {
            oracleCard {
                VStack(alignment: .leading, spacing: 10) {
                    OracleEyebrow(text: "Custom API")
                    oracleField("https://example.com/api/word", text: $customURL)
                        .keyboardType(.URL)
                    HStack {
                        Text("JSON field")
                            .font(.subheadline)
                            .foregroundStyle(OracleTheme.textPrimary)
                        Spacer()
                        TextField("word", text: $customField)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(OracleTheme.textPrimary)
                    }
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
                                WordApiSettings.saveCustomHeaderValue(nil)
                                refreshHeader()
                            }
                            .font(.caption)
                        }
                    }
                    SecureField(savedHeaderHint == nil ? "Header value" : "Replace value", text: $headerDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button("Save header value") {
                        WordApiSettings.saveCustomHeaderValue(headerDraft)
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
        savedHeaderHint = WordApiSettings.customHeaderValue.map { "…" + String($0.suffix(4)) }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        let provider = WordApiSettings.provider
        do {
            let reading = try await WordApiClient.fetch(provider)
            let count = reading.count.map { "count \($0) · " } ?? ""
            if reading.hasWord {
                testResult = (true, "Connected · \(count)current label “\(reading.label)”")
            } else {
                testResult = (true, "Connected · \(count)no word yet. Response: \(reading.raw.prefix(200))")
            }
            dlog("[WORD] test \(provider.rawValue): \(testResult?.text ?? "")")
        } catch {
            testResult = (false, "Failed: \(error.localizedDescription)")
            dlog("✗ [WORD] test \(provider.rawValue): \(error.localizedDescription)")
        }
    }
}
