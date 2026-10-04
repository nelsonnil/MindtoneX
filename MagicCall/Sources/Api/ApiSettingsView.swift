import SwiftUI

/// Connection setup for API song input — matches home Oracle styling (not system Form gray).
struct ApiSettingsView: View {
    @AppStorage(ApiSettings.Key.provider) private var providerRaw = ApiSettings.Provider.inject.rawValue
    @AppStorage(ApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(ApiSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(ApiSettings.Key.customURL) private var customURL = ""
    @AppStorage(ApiSettings.Key.customField) private var customField = ApiSettings.defaultCustomField
    @AppStorage(ApiSettings.Key.customHeaderName) private var customHeaderName = ""
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @ObservedObject private var session = ApiSongSession.shared

    @State private var headerDraft = ""
    @State private var savedHeaderHint: String?
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var provider: ApiSettings.Provider { ApiSettings.Provider(rawValue: providerRaw) ?? .inject }

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
                        Text("The app checks every \(Int(ApiSettings.pollInterval)) seconds. The first reading is whatever was searched before; the **next change** is the spectator’s search. That song is loaded and locked for the call — like AI Voice.")
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
        .onAppear(perform: refreshHeader)
        .onChange(of: providerRaw) { _, newValue in
            testResult = nil
            if session.isActive { session.stopTest() }
            dlog("[API] integration → \(ApiSettings.Provider(rawValue: newValue)?.title ?? newValue)")
        }
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
                OracleEyebrow(text: "Elips API URL")
                oracleField("https://pag.gg/…/api/…", text: $elipsURL)
                    .keyboardType(.URL)
                Text("Copy the full API URL from the Elips app.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
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
