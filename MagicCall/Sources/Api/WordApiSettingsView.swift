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
                        WordApiProviderPicker(selectionRaw: $providerRaw)
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
                case .card: cardSetupCard
                }

                oracleCard {
                    VStack(alignment: .leading, spacing: 12) {
                        OracleEyebrow(text: "Call Identification (caller number)")
                        oracleField("34612345678 (country code + number)", text: $fallbackPhoneDigits)
                            .keyboardType(.phonePad)
                        Text("Used when **Save locked word as contact name** is off, or as backup digits. With contact modes on the **Caller name** card, Known uses the picked contact; Unknown uses the number from the Perform dial sheet.")
                            .font(.caption2)
                            .foregroundStyle(OracleTheme.textSecondary)

                        Text("Call Directory still runs if Contacts access is denied.")
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
                        .disabled(testing || !WordApiSettings.hasWordEndpoint || provider == .card)

                        if let testResult {
                            Text(testResult.text)
                                .font(.caption)
                                .foregroundStyle(testResult.ok ? OracleTheme.gold : OracleTheme.coral)
                                .textSelection(.enabled)
                        } else if provider == .card {
                            Text("No network test — run a full **Perform** volume scan with Card song input.")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                        } else {
                            Text("Reads your word source once and shows the current text.")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                        }
                    }
                }

                oracleCard {
                    VStack(alignment: .leading, spacing: 10) {
                        OracleEyebrow(text: "On Perform")
                        Text(provider == .card
                            ? "Turn **Show word on incoming call** on. Set **Song input** to **Card** and write **line 1** = song, **line 2** = word. One **volume** scan during Perform locks both."
                            : "Turn **Show word on incoming call** on the **Caller name** card first. Then polls every \(Int(WordApiSettings.pollInterval)) seconds alongside song input. First reading = old word; **next change** = spectator word → locked → name on incoming call.")
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
        .navigationTitle("Caller name connection")
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
            Text("Where the spectator’s word comes from (Inject, Elips, your API, or Card). Separate from song input.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }

    private var cardSetupCard: some View {
        oracleCard {
            VStack(alignment: .leading, spacing: 10) {
                OracleEyebrow(text: "Card layout")
                Text("Same physical card as song input. **Line 1** (top) = song title in ALL CAPS. **Line 2** = one spectator word. Optional labels: `SONG:` / `WORD:` or `PALABRA:`.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if VoiceSettings.inputMode != .card {
                    Label("Song input is not Card — switch it on the home screen.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.coral)
                } else {
                    Label("Song input = Card — ready for combined scan.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.gold)
                }
            }
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
            let rc = reading.receiveCount.map { "rc \($0) · " } ?? ""
            if reading.hasWord {
                testResult = (true, "Connected · \(count)\(rc)label “\(WordApiInputPanel.truncated(reading.label, max: 40))”")
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
