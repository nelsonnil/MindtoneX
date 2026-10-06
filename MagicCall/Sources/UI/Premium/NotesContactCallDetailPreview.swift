import SwiftUI

/// iOS **Contacts** detail sheet (mobile + Notes) — not the Apple Notes app.
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PreviewLiveDot()
                Text("CONTACTS · CALL PREVIEW")
                    .font(OracleTheme.techLabel())
                    .foregroundStyle(OracleTheme.sectionTeal.opacity(0.92))
                Spacer()
            }

            VStack(spacing: 12) {
                contactPhotoRow
                phoneAndNotesCard
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Contacts call preview")
    }

    private var contactPhotoRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(white: 0.22))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(initial)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            Text("Contact Photo & Poster")
                .font(.body)
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(14)
        .background(iOSGroupedRow)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var phoneAndNotesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("mobile")
                            .font(.subheadline)
                            .foregroundStyle(iOSNotesLabel)
                        if showsRecentCallBadge {
                            Text("RECENT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(iOSNotesLabel)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(iOSNotesLabel.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                    Text(phoneDisplay)
                        .font(.title2.weight(.regular))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "phone.fill")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !trimmedNotes.isEmpty {
                Divider().overlay(Color.white.opacity(0.12))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(iOSNotesLabel)
                    Text(trimmedNotes)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(iOSGroupedRow)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var iOSGroupedRow: some View {
        Color(red: 0.14, green: 0.13, blue: 0.17).opacity(0.95)
    }

    private var iOSNotesLabel: Color {
        Color(red: 0.72, green: 0.55, blue: 0.95)
    }
}

private struct PreviewLiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 7, height: 7)
            .overlay {
                Circle()
                    .stroke(Color.red.opacity(0.45), lineWidth: 2)
                    .scaleEffect(pulse ? 1.8 : 1)
                    .opacity(pulse ? 0 : 0.8)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}
