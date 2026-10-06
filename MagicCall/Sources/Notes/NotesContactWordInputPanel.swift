import SwiftUI

/// Word source controls for Notes contact (Inject / Elips / Custom / Card OCR).
struct NotesContactWordInputPanel: View {
    @ObservedObject private var session = NotesContactWordSession.shared
    @AppStorage(NotesContactWordSettings.Key.wordInputEnabled) private var wordInputEnabled = true
    @AppStorage(NotesContactWordSettings.Key.provider) private var providerRaw = NotesContactWordSettings.Provider.inject.rawValue
    @AppStorage(NotesContactWordSettings.Key.injectID) private var injectID = ""
    @AppStorage(VoiceSettings.Key.inputMode) private var songInputModeRaw = VoiceSettings.InputMode.card.rawValue

    @State private var showConnectionSheet = false

    private var provider: NotesContactWordSettings.Provider {
        NotesContactWordSettings.Provider(rawValue: providerRaw) ?? .inject
    }

    private var configured: Bool { NotesContactWordSettings.hasWordEndpoint }
    private var songInputIsCard: Bool {
        (VoiceSettings.InputMode(rawValue: songInputModeRaw) ?? .card) == .card
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $wordInputEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Word for Notes chip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Independent from Caller name — own Inject / API / Card line 3")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            .tint(OracleTheme.sectionTeal)
            .onChange(of: wordInputEnabled) { _, on in
                if !on { session.reset(reason: "word input off") }
            }

            if wordInputEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    WordApiProviderPicker(selectionRaw: $providerRaw)

                    HStack(spacing: 8) {
                        Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(configured ? OracleTheme.sectionTeal : OracleTheme.coral)
                        Text(configured ? "\(provider.title) ready" : NotesContactWordSettings.setupHint)
                            .font(.caption)
                            .foregroundStyle(configured ? OracleTheme.textSecondary : OracleTheme.coral)
                    }

                    if provider == .card {
                        if !songInputIsCard {
                            Label("Song input must be **Card** — Notes word is **line 3** on the card.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.coral)
                        }
                    } else if provider == .voice {
                        Text(provider.detail)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        VoiceMagicianScriptBlock(channel: .notesContact, accent: OracleTheme.sectionTeal)
                        Text("On Perform, the Notes chip word uses its **own AI prompt** on the same Voice mic as the song.")
                            .font(.caption2)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if provider == .inject {
                        TextField("Inject word ID", text: $injectID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if provider != .card && provider != .voice {
                        Button { showConnectionSheet = true } label: {
                            HStack {
                                Label("Connection details", systemImage: "link.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(OracleTheme.sectionTeal)
                        }
                        .buttonStyle(.plain)
                    }

                    if session.state == .locked, let word = session.lockedReading?.label {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(OracleTheme.sectionTeal)
                            Text(word)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(OracleTheme.textPrimary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .sheet(isPresented: $showConnectionSheet) {
            NotesContactConnectionSheet()
        }
    }
}
