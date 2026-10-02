import SwiftUI

/// Prominent mode picker card directly under the hero: Fake Ringtone | Share Ringtone.
struct ModePickerCard: View {
    @Binding var modeRaw: String
    @Namespace private var selection

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: modeRaw) ?? .fakeRingtone
    }

    var body: some View {
        OracleCard(padding: 6) {
            HStack(spacing: 6) {
                segment(.fakeRingtone,
                        title: "Fake Ringtone",
                        subtitle: "Silent · app plays the song",
                        icon: "bell.slash.fill")
                segment(.shareRingtone,
                        title: "Share Ringtone",
                        subtitle: "Real iOS ringtone",
                        icon: "bell.badge.fill")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Performance mode")
    }

    private func segment(_ value: Prefs.PerformanceMode, title: String, subtitle: String, icon: String) -> some View {
        let selected = mode == value
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { modeRaw = value.rawValue }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? OracleTheme.gold : OracleTheme.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary.opacity(selected ? 1 : 0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(OracleTheme.gold.opacity(0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .strokeBorder(OracleTheme.gold.opacity(0.55), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "modeSelection", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
