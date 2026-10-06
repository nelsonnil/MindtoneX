import SwiftUI

struct NotesContactConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NotesContactWordSettings.Key.provider) private var providerRaw = NotesContactWordSettings.Provider.inject.rawValue
    @AppStorage(NotesContactWordSettings.Key.injectID) private var injectID = ""
    @AppStorage(NotesContactWordSettings.Key.elipsURL) private var elipsURL = ""
    @AppStorage(NotesContactWordSettings.Key.customURL) private var customURL = ""
    @AppStorage(NotesContactWordSettings.Key.customField) private var customField = NotesContactWordSettings.defaultCustomField
    @AppStorage(NotesContactWordSettings.Key.customHeaderName) private var customHeaderName = ""
    @ObservedObject private var session = NotesContactWordSession.shared

    @State private var headerDraft = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var provider: NotesContactWordSettings.Provider {
        NotesContactWordSettings.Provider(rawValue: providerRaw) ?? .inject
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Separate word URL from **Caller name** and from song API. Used only for the Notes contact chip.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    oracleCard {
                        VStack(alignment: .leading, spacing: 12) {
                            OracleEyebrow(text: "Integration")
                            WordApiProviderPicker(selectionRaw: $providerRaw)
                            Text(provider.detail)
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                        }
                    }

                    switch provider {
                    case .inject: injectFields
                    case .elips: elipsFields
                    case .custom: customFields
                    case .card: cardHint
                    case .voice: voiceHint
                    }

                    oracleCard {
                        Button {
                            Task { await runTest() }
                        } label: {
                            HStack {
                                Text(testing ? "Testing…" : "Test connection")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if testing { ProgressView().tint(OracleTheme.gold) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(testing || !NotesContactWordSettings.hasWordEndpoint || provider == .card || provider == .voice)

                        if let testResult {
                            Text(testResult.text)
                                .font(.caption)
                                .foregroundStyle(testResult.ok ? OracleTheme.gold : OracleTheme.coral)
                        }
                    }
                }
                .padding(20)
            }
            .background(OracleTheme.bgTop)
            .navigationTitle("Notes word connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                headerDraft = NotesContactWordSettings.customHeaderValue ?? ""
            }
        }
    }

    private var injectFields: some View {
        oracleCard {
            VStack(alignment: .leading, spacing: 8) {
                OracleEyebrow(text: "Inject ID")
                TextField("Word endpoint token", text: $injectID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var elipsFields: some View {
        oracleCard {
            VStack(alignment: .leading, spacing: 8) {
                OracleEyebrow(text: "Elips URL")
                TextField("https://pag.gg/…", text: $elipsURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var customFields: some View {
        VStack(spacing: 18) {
            oracleCard {
                VStack(alignment: .leading, spacing: 8) {
                    OracleEyebrow(text: "API URL")
                    TextField("https://…", text: $customURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    TextField("JSON field (e.g. word)", text: $customField)
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            oracleCard {
                VStack(alignment: .leading, spacing: 8) {
                    OracleEyebrow(text: "Optional header")
                    TextField("Header name", text: $customHeaderName)
                        .textInputAutocapitalization(.never)
                    TextField("Header value", text: $headerDraft)
                        .textInputAutocapitalization(.never)
                        .onChange(of: headerDraft) { _, v in
                            NotesContactWordSettings.saveCustomHeaderValue(v)
                        }
                }
            }
        }
    }

    private var cardHint: some View {
        oracleCard {
            Text("Uses **line 3** from the Card volume scan (line 1 = song, line 2 = caller name if enabled). No network URL.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }

    private var voiceHint: some View {
        oracleCard {
            VStack(alignment: .leading, spacing: 12) {
                VoiceMagicianScriptBlock(channel: .notesContact, accent: OracleTheme.sectionTeal)
                Text("No URL — Song input must be **Voice** with OpenAI key. Prompt is separate from Caller name and from the song picker.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
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

    private func runTest() async {
        testing = true
        defer { testing = false }
        session.stopTest()
        session.start(context: .test)
        defer { session.stopTest() }
        do {
            let reading = try await NotesContactWordClient.fetch()
            testResult = (true, "Current word: «\(reading.label)»")
        } catch {
            testResult = (false, error.localizedDescription)
        }
    }
}
