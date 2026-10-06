import SwiftUI

/// Visual clone of iOS **Contacts → contact detail** (mobile + Notes on one card) for Settings preview.
struct NotesContactCallDetailPreview: View {
    var contactName: String
    var phoneDigits: String
    var notesText: String
    var showsRecentCallBadge: Bool = true

    private var initial: String {
        let c = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = c.first else { return "?" }
        return String(first).uppercased()
    }

    private var phoneDisplay: String {
        WordApiIncomingCallBannerPreview.formatPhone(phoneDigits)
    }

    private var trimmedNotes: String {
        notesText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Así se ve en Contactos del iPhone (ficha del número al llamar).")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)

            // iOS dark Contacts canvas (grouped inset list)
            VStack(spacing: 14) {
                contactPhotoRow
                phoneAndNotesCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(iOSCanvasBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contacts detail preview")
    }

    private var contactPhotoRow: some View {
        HStack(spacing: 14) {
            monogramAvatar
            Text("Contact Photo & Poster")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.95))
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(iOSGroupedPlatter)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var monogramAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.45, green: 0.38, blue: 0.62),
                        Color(red: 0.28, green: 0.24, blue: 0.42),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 42, height: 42)
            .overlay {
                Text(initial)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
    }

    private var phoneAndNotesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("mobile")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(iOSAccentLabel)
                        if showsRecentCallBadge {
                            Text("RECENT")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(iOSAccentLabel)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(iOSAccentLabel.opacity(0.22))
                                .clipShape(Capsule())
                        }
                    }
                    Text(phoneDisplay)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Image(systemName: "phone.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, trimmedNotes.isEmpty ? 14 : 10)

            if !trimmedNotes.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1 / UIScreen.main.scale)
                    .padding(.leading, 16)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(iOSAccentLabel)
                    Text(trimmedNotes)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .background(iOSGroupedPlatter)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    /// Contacts dark mode grouped background (purple-gray).
    private var iOSCanvasBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.07, blue: 0.14),
                Color(red: 0.06, green: 0.05, blue: 0.10),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var iOSGroupedPlatter: Color {
        Color(red: 0.17, green: 0.15, blue: 0.22).opacity(0.98)
    }

    private var iOSAccentLabel: Color {
        Color(red: 0.68, green: 0.52, blue: 0.92)
    }
}
