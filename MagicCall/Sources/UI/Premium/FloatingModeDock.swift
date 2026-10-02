import SwiftUI

struct FloatingModeDock: View {
    @Binding var modeRaw: String
    var onGuide: () -> Void

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: modeRaw) ?? .fakeRingtone
    }

    var body: some View {
        HStack(spacing: 10) {
            modeCard(
                title: "Fake Ringtone",
                icon: "bell.slash.fill",
                selected: mode == .fakeRingtone,
                accent: OracleTheme.indigo
            ) {
                withAnimation(.easeInOut(duration: 0.25)) { modeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue }
            }

            modeCard(
                title: "Share Ringtone",
                icon: "bell.badge.fill",
                selected: mode == .shareRingtone,
                accent: OracleTheme.coral
            ) {
                withAnimation(.easeInOut(duration: 0.25)) { modeRaw = Prefs.PerformanceMode.shareRingtone.rawValue }
            }

            Button(action: onGuide) {
                VStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.title3)
                    Text("Guide")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(OracleTheme.textSecondary)
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("User guide")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(OracleTheme.cardFill)
        .overlay {
            RoundedRectangle(cornerRadius: OracleTheme.dockRadius, style: .continuous)
                .stroke(OracleTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: OracleTheme.dockRadius, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
        .padding(.horizontal, 16)
    }

    private func modeCard(title: String, icon: String, selected: Bool, accent _: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(selected ? OracleTheme.gold : OracleTheme.textSecondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Rectangle()
                    .fill(selected ? OracleTheme.gold : .clear)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? OracleTheme.gold.opacity(0.12) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? OracleTheme.gold.opacity(0.55) : OracleTheme.cardBorder, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}
