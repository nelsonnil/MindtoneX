import PhotosUI
import SwiftUI

/// Mode picker + mode-specific setup in one panel (Fake or Share).
struct UnifiedPerformanceModeCard: View {
    @Binding var modeRaw: String
    @Binding var background: String
    @Binding var photoItem: PhotosPickerItem?
    @Namespace private var selection

    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false
    @AppStorage("ui.modeSetupExpanded") private var setupExpanded = true

    var onFakeInfo: () -> Void
    var onShareInfo: () -> Void
    var onFavoritesInfo: () -> Void

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: modeRaw) ?? .fakeRingtone
    }

    private var shortcutReady: Bool {
        mode == .fakeRingtone ? silentOnEnabled : silentOffEnabled
    }

    var body: some View {
        HomePanel {
            VStack(alignment: .leading, spacing: 20) {
                HomeSectionTitle(
                    title: "Performance mode",
                    subtitle: "Fake plays on stage · Share sends the ringtone file"
                )

                VStack(spacing: 10) {
                    modeTile(.fakeRingtone, title: "Fake Ringtone", subtitle: "Silent stage · volume control", icon: "bell.slash.fill")
                    modeTile(.shareRingtone, title: "Share Ringtone", subtitle: "Prepare file · share sheet", icon: "bell.badge.fill")
                }

                setupDisclosure
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Performance mode")
        .onAppear {
            if !shortcutReady { setupExpanded = true }
        }
        .onChange(of: modeRaw) { _, _ in
            if !shortcutReady { setupExpanded = true }
        }
    }

    private var setupDisclosure: some View {
        DisclosureGroup(isExpanded: $setupExpanded) {
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
            .padding(.top, 12)
            .animation(.easeInOut(duration: 0.25), value: modeRaw)
        } label: {
            HStack(spacing: 8) {
                Text("Performance setup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                if shortcutReady {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.gold)
                }
            }
        }
        .tint(OracleTheme.gold)
    }

    private func modeTile(_ value: Prefs.PerformanceMode, title: String, subtitle: String, icon: String) -> some View {
        let selected = mode == value
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { modeRaw = value.rawValue }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(selected ? OracleTheme.gold : OracleTheme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(selected ? OracleTheme.gold.opacity(0.18) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(OracleTheme.gold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(OracleTheme.gold.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(OracleTheme.gold.opacity(0.55), lineWidth: 1.5)
                        }
                        .matchedGeometryEffect(id: "modeSelection", in: selection)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
