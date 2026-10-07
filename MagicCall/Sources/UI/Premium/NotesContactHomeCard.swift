import SwiftUI
import UIKit

/// Contacts **Notes** field preview + word source for the Notes chip (API / OCR / Voice).
struct NotesContactHomeCard: View {
    @ObservedObject private var wordSession = NotesContactWordSession.shared
    @ObservedObject private var callerSession = WordApiSession.shared
    @AppStorage(NotesContactSettings.Key.noteBody) private var noteBody = ""
    @AppStorage(NotesContactSettings.Key.buttonPlaceholder) private var buttonPlaceholder = NotesContactSettings.defaultButtonPlaceholder
    @AppStorage(NotesContactWordSettings.Key.wordInputEnabled) private var wordInputEnabled = true

    private var wordTokenInNote: Bool {
        noteBody.contains(NotesContactSettings.standardWordToken)
            || (!buttonPlaceholder.isEmpty && noteBody.contains(buttonPlaceholder))
    }

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
                Text("Preview clonado de la ficha **Contactos** del iPhone (mobile + Notes). No es la app Notas. Deja la nota vacía si no quieres texto ahí.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                NotesContactWordInputPanel()

                NotesContactCallDetailPreview(
                    contactName: previewContactName,
                    phoneDigits: previewPhoneDigits,
                    notesText: previewNotesText
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Texto de la nota (Contactos)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OracleTheme.textPrimary)
                        Spacer(minLength: 8)
                        Button {
                            insertWordPlaceholderToken()
                        } label: {
                            Label(NotesContactSettings.standardWordToken, systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(OracleTheme.gold)
                        .disabled(wordTokenInNote)
                    }

                    TextEditor(text: $noteBody)
                        .font(.subheadline)
                        .foregroundStyle(OracleTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72, maxHeight: 120)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if wordTokenInNote {
                        Label {
                            Text("En el show, **\(NotesContactSettings.standardWordToken)** se sustituye por la palabra bloqueada del chip Notas (\(NotesContactWordSettings.provider.gridTitle)).")
                                .font(.caption2)
                                .foregroundStyle(OracleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OracleTheme.gold)
                        }
                    } else {
                        Text("Vacía por defecto. Pulsa **\(NotesContactSettings.standardWordToken)** para marcar dónde quieres la palabra de la API; si no usas marcador, el texto se copia tal cual.")
                            .font(.caption2)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func insertWordPlaceholderToken() {
        let token = NotesContactSettings.standardWordToken
        buttonPlaceholder = token
        guard !noteBody.contains(token) else { return }
        if noteBody.isEmpty {
            noteBody = token
            return
        }
        let needsSpace = noteBody.last.map { !$0.isWhitespace && !$0.isNewline } ?? false
        noteBody += (needsSpace ? " " : "") + token
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
