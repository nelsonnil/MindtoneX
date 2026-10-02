import SwiftUI

/// Settings → API / song input. The segmented selector is the only switch between integrations.
struct ApiSettingsView: View {
    @AppStorage(ApiSettings.Key.provider) private var providerRaw = ApiSettings.Provider.inject.rawValue
    @AppStorage(ApiSettings.Key.injectID) private var injectID = ""
    @AppStorage(ApiSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(ApiSettings.Key.customURL) private var customURL = ""
    @AppStorage(ApiSettings.Key.customField) private var customField = ApiSettings.defaultCustomField
    @AppStorage(ApiSettings.Key.customHeaderName) private var customHeaderName = ""
    @AppStorage(ApiSettings.Key.hapticOnLock) private var hapticOnLock = true
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue
    @ObservedObject private var session = ApiSongSession.shared

    @State private var headerDraft = ""
    @State private var savedHeaderHint: String?
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var provider: ApiSettings.Provider { ApiSettings.Provider(rawValue: providerRaw) ?? .inject }

    var body: some View {
        Form {
            Section {
                Picker("Integration", selection: $providerRaw) {
                    ForEach(ApiSettings.Provider.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text(provider.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Integration")
            } footer: {
                Text("Only one integration is active at a time, so they never poll together. Your settings for the others are kept.")
            }

            switch provider {
            case .inject: injectSection
            case .elips: elipsSection
            case .custom: customSection
            }

            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    HStack {
                        Label(testing ? "Testing…" : "Test connection", systemImage: "antenna.radiowaves.left.and.right")
                        if testing { Spacer(); ProgressView() }
                    }
                }
                .disabled(testing || !ApiSettings.isConfigured)
                if let testResult {
                    Text(testResult.text)
                        .font(.footnote)
                        .foregroundStyle(testResult.ok ? .green : .orange)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Check")
            } footer: {
                Text("Reads the API once and shows what it returns right now.")
            }

            Section {
                Toggle("Soft vibration when the song locks", isOn: $hapticOnLock)
                if inputModeRaw != VoiceSettings.InputMode.api.rawValue {
                    Button("Use API as song input") { inputModeRaw = VoiceSettings.InputMode.api.rawValue }
                }
            } header: {
                Text("Perform")
            } footer: {
                Text("On Perform the app checks the API every \(Int(ApiSettings.pollInterval)) seconds. The first answer is whatever was searched before; the next change is the spectator’s search. That song is found, loaded and locked — the call plays it, like AI Voice. Leaving Perform resets it for the next performance.")
            }
        }
        .navigationTitle("API / song input")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshHeader)
        .onChange(of: providerRaw) { _, newValue in
            testResult = nil
            if session.isActive { session.stopTest() }
            dlog("[API] integration → \(ApiSettings.Provider(rawValue: newValue)?.title ?? newValue)")
        }
    }

    private var injectSection: some View {
        Section {
            TextField("Inject ID, e.g. 00000", text: $injectID)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let url = ApiSettings.injectEndpoint(for: injectID) {
                Text(url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Inject")
        } footer: {
            Text("The API token shown in Inject. A new search bumps Inject’s count; its value becomes the song title.")
        }
    }

    private var elipsSection: some View {
        Section {
            TextField("https://pag.gg/…/api/…", text: $elipsURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Elips")
        } footer: {
            Text("Copy the API URL from the Elips app. The song (and artist, if sent) is used for the lookup.")
        }
    }

    private var customSection: some View {
        Group {
            Section {
                TextField("https://example.com/api/song", text: $customURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("JSON field, e.g. song", text: $customField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Custom API")
            } footer: {
                Text("GET request; the response must be a JSON object. Field names ignore upper/lower case; use dots for nested fields (data.song).")
            }

            Section {
                TextField("Header name, e.g. Authorization", text: $customHeaderName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let hint = savedHeaderHint {
                    HStack {
                        Label("Value saved (\(hint))", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            ApiSettings.saveCustomHeaderValue(nil)
                            refreshHeader()
                        }
                    }
                }
                SecureField(savedHeaderHint == nil ? "Header value, e.g. Bearer …" : "Replace value", text: $headerDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save value") {
                    ApiSettings.saveCustomHeaderValue(headerDraft)
                    headerDraft = ""
                    refreshHeader()
                }
                .disabled(headerDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Authentication (optional)")
            } footer: {
                Text("Sent with every request when both name and value are set. The value stays in this iPhone’s Keychain.")
            }
        }
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
