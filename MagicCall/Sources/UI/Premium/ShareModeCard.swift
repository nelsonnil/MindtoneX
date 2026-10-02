import SwiftUI

struct ShareModeCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var isSharePerforming = false

    var onInfo: () -> Void
    var onShortcutsSetup: () -> Void
    var onFavoritesInfo: () -> Void

    var body: some View {
        OracleCard {
            VStack(alignment: .leading, spacing: 16) {
                ModeDetailHeader(
                    title: "Share Ringtone",
                    icon: "bell.badge.fill",
                    tint: OracleTheme.coral,
                    summary: "Silent OFF. Sets your song as a real iOS ringtone with one tap in Share.",
                    onInfo: onInfo
                )

                Divider().overlay(OracleTheme.cardBorder)

                ShortcutsInstallPanel(onInstallGuide: onShortcutsSetup)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(OracleTheme.gold)
                        .font(.caption)
                    Text("Star **Use as Ringtone** in Share → Edit Actions → Favorites.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                    Spacer(minLength: 0)
                    Button(action: onFavoritesInfo) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OracleTheme.gold)
                    .accessibilityLabel("Share Favorites setup")
                }

                Button {
                    isSharePerforming = true
                    Task {
                        await model.performShareRingtone()
                        isSharePerforming = false
                    }
                } label: {
                    Group {
                        if isSharePerforming {
                            ProgressView()
                        } else {
                            Label("Test: open Share sheet now", systemImage: "square.and.arrow.up")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(OracleTheme.textPrimary)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.loadState != .ready || isSharePerforming)
                .opacity(model.loadState != .ready ? 0.5 : 1)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }
}
