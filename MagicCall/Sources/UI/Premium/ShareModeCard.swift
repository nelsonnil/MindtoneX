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
                HStack {
                    Label("Share Ringtone", systemImage: "bell.badge.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(OracleTheme.coral)
                    Spacer()
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                SilentShortcutStatusRow(mode: .shareRingtone, onSetup: onShortcutsSetup)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(OracleTheme.gold)
                        .font(.caption)
                    Text("Star **Use as Ringtone** in Share → Edit Actions → Favorites.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                    Button(action: onFavoritesInfo) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OracleTheme.gold)
                }

                if model.ringtoneStaged {
                    Label("Ringtone file ready on device", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                OraclePerformButton(
                    title: "Perform",
                    gradient: OracleTheme.warmGradient,
                    disabled: !model.canPerform
                ) {
                    model.perform()
                }

                Button {
                    isSharePerforming = true
                    Task {
                        await model.performShareRingtone()
                        isSharePerforming = false
                    }
                } label: {
                    if isSharePerforming {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Test: open Share sheet now")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .tint(OracleTheme.textSecondary)
                .disabled(model.loadState != .ready || isSharePerforming)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }
}
