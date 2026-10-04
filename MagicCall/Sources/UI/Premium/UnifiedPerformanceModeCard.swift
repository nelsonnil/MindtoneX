import PhotosUI
import SwiftUI

/// Mode picker + mode-specific setup in one card (Fake or Share).
struct UnifiedPerformanceModeCard: View {
    @Binding var modeRaw: String
    @Binding var background: String
    @Binding var photoItem: PhotosPickerItem?
    @Namespace private var selection

    var onFakeInfo: () -> Void
    var onShareInfo: () -> Void
    var onFavoritesInfo: () -> Void

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: modeRaw) ?? .fakeRingtone
    }

    var body: some View {
        OracleCard(section: .mode) {
            VStack(alignment: .leading, spacing: 16) {
                modePicker
                Divider().overlay(OracleTheme.cardBorder)
                Group {
                    switch mode {
                    case .fakeRingtone:
                        FakeModeContent(
                            background: $background,
                            photoItem: $photoItem,
                            onInfo: onFakeInfo
                        )
                    case .shareRingtone:
                        ShareModeContent(
                            onInfo: onShareInfo,
                            onFavoritesInfo: onFavoritesInfo
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: modeRaw)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Performance mode")
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Mode")
            HStack(spacing: 8) {
                segment(.fakeRingtone, title: "Fake Ringtone", icon: "bell.slash.fill")
                segment(.shareRingtone, title: "Share Ringtone", icon: "bell.badge.fill")
            }
        }
    }

    private func segment(_ value: Prefs.PerformanceMode, title: String, icon: String) -> some View {
        let selected = mode == value
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { modeRaw = value.rawValue }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(selected ? OracleTheme.gold : OracleTheme.textSecondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(OracleTheme.gold.opacity(0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
