import SwiftUI

/// Notes-style preview + independent word input for the contact chip.
struct NotesContactHomeCard: View {
    @ObservedObject private var wordSession = NotesContactWordSession.shared
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

    private var hasLiveWord: Bool { spectatorWord != nil }

    private var chipTitle: String {
        if let word = spectatorWord { return word }
        let place = buttonPlaceholder.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? NotesContactSettings.defaultButtonPlaceholder : place
    }

    private var collapsedSummary: String {
        if let word = spectatorWord {
            return "Word: «\(WordApiInputPanel.truncated(word, max: 28))» · \(NotesContactWordSettings.provider.gridTitle)"
        }
        if !wordInputEnabled { return "Word input off" }
        if NotesContactWordSettings.hasWordEndpoint {
            return "\(NotesContactWordSettings.provider.gridTitle) · chip placeholder"
        }
        return "Set word source (Inject, API, Card…)"
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.notesContact,
            accent: OracleTheme.sectionTeal,
            icon: "note.text.badge.plus",
            title: "Notes contact",
            summary: collapsedSummary
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your note copy and a contact chip. The chip shows your placeholder until the **Notes word** source locks a spectator word during Perform.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                NotesContactWordInputPanel()

                notesPreview

                VStack(alignment: .leading, spacing: 6) {
                    Text("Chip placeholder (before word arrives)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    TextField("Contact", text: $buttonPlaceholder)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var notesPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.75))
                Spacer()
                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.85))
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .foregroundStyle(.black.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.97))

            ZStack(alignment: .topLeading) {
                if noteBody.isEmpty {
                    Text("Type your note…")
                        .font(.body)
                        .foregroundStyle(.black.opacity(0.28))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                TextEditor(text: $noteBody)
                    .font(.body)
                    .foregroundStyle(.black)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100, maxHeight: 140)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .background(Color.white)

            HStack {
                contactChip
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.98))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.25), value: chipTitle)
    }

    private var contactChip: some View {
        HStack(spacing: 6) {
            Image(systemName: hasLiveWord ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.caption.weight(.semibold))
            Text(chipTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(hasLiveWord ? Color.white : Color.black.opacity(0.72))
        .background {
            Capsule()
                .fill(hasLiveWord ? OracleTheme.sectionTeal : Color(white: 0.92))
        }
        .accessibilityLabel(hasLiveWord ? "Contact suggestion \(chipTitle)" : "Placeholder \(chipTitle)")
    }
}
