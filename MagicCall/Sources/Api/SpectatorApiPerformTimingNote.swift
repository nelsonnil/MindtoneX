import SwiftUI

/// Copy for Inject / Elips / Custom API connection screens (song, caller word, Notes chip).
enum SpectatorApiPerformTiming {
    static let settingsNote =
        "**Perform timing:** On **Perform**, MindtoneX polls every ~2 s and **uses whatever song the API shows** (including a search done **before** Perform). "
        + "If the spectator **changes** the search **during** Perform, the app **switches** to that new song for the ringtone and stage."
}

struct SpectatorApiPerformTimingNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(OracleTheme.gold)
            Text(.init(SpectatorApiPerformTiming.settingsNote))
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OracleTheme.gold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OracleTheme.gold.opacity(0.35), lineWidth: 1)
        }
    }
}

extension WordApiSettings.Provider {
    var showsNetworkPerformTimingNote: Bool {
        switch self {
        case .inject, .elips, .custom: return true
        case .card, .voice: return false
        }
    }
}
