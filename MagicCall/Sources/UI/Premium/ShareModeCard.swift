import SwiftUI

struct ShareModeContent: View {
    var onInfo: () -> Void
    var onFavoritesInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button(action: onFavoritesInfo) {
                    Image(systemName: "star.circle")
                        .font(.body)
                        .foregroundStyle(OracleTheme.gold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share favorites guide")
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share Ringtone guide")
            }

            ShortcutsInstallPanel(mode: .shareRingtone)
        }
    }
}
