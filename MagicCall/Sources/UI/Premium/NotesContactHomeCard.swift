import SwiftUI

/// Contacts **Notes** field preview + word source for the Notes chip (API / OCR / Voice).
struct NotesContactHomeCard: View {
    @ObservedObject private var wordSession = NotesContactWordSession.shared
    @ObservedObject private var callerSession = WordApiSession.shared
    @AppStorage(NotesContactSettings.Key.noteBody) private var noteBody = ""
    @AppStorage(NotesContactSettings.Key.buttonPlaceholder) private var buttonPlaceholder = NotesContactSettings.defaultButtonPlaceholder
    @AppStorage(NotesContactWordSettings.Key.wordInputEnabled) private var wordInputEnabled = true

    private var spectatorWord: String? {
        guard wordInputEnabled else { return nil }
        if let locked = wordSession.lockedReading?.label.trimmingCharacters(in: .whitespacesAndNewlines),
           !locked.isEmpty {
            return locked
        }
        switch wordSession.state {
        case .watching, .locked, .connecting:
            if let last = wordSession.lastReading?.label.trimmingCharacters(in: .whitespacesAndNewlines),
               !last.isEmpty {
                return last
            }
        default:
            break
        }
        return nil
    }

    private var previewContactName: String {
        if let caller = callerSession.lockedReading?.label.trimmingCharacters(in: .whitespacesAndNewlines),
           !caller.isEmpty {
            return caller
        }
        if let word = spectatorWord { return word }
        return "Contact"
    }

    private var previewPhoneDigits: String {
        let digits = WordApiSettings.lastDialedPhoneDigits.isEmpty
            ? WordApiSettings.fallbackPhoneDigits
            : WordApiSettings.lastDialedPhoneDigits
        return digits
    }

    private var previewNotesText: String {
        NotesContactSettings.resolvedContactNote(lockedWord: spectatorWord)
    }

    private var collapsedSummary: String {
        if let word = spectatorWord {
            return "Word: «\(WordApiInputPanel.truncated(word, max: 28))» · \(NotesContactWordSettings.provider.gridTitle)"
        }
        if !wordInputEnabled { return "Word input off" }
        if !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Contact note · \(NotesContactWordSettings.provider.gridTitle)"
        }
        if NotesContactWordSettings.hasWordEndpoint {
            return "\(NotesContactWordSettings.provider.gridTitle) · empty note"
        }
        return "Set word source (Inject, API, Camera…)"
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.notesContact,
            accent: OracleTheme.sectionTeal,
            icon: "person.crop.circle.badge.checkmark",
            title: "Notes contact",
            summary: collapsedSummary
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("What appears in **Contacts → Notes** on the spectator’s card during a call — not the Apple Notes app. Leave the note empty unless you want copy there.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                NotesContactWordInputPanel()

                NotesContactCallDetailPreview(
                    contactName: previewContactName,
                    phoneDigits: previewPhoneDigits,
                    notesText: previewNotesText
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Note text (Contacts field)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    TextEditor(text: $noteBody)
                        .font(.subheadline)
                        .foregroundStyle(OracleTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72, maxHeight: 120)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("Empty by default. Only this text is saved — no MindtoneX boilerplate.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Word placeholder (optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    TextField("e.g. WORD", text: $buttonPlaceholder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text("If this exact word appears in the note above, it is replaced by the locked **Notes chip** word (Inject / Camera line 3 / Voice). Without a placeholder, the note is copied as-is.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
