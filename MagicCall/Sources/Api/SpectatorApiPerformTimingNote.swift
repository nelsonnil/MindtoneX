import SwiftUI

/// Copy for Inject / Elips / Custom API connection screens (song, caller word, Notes chip).
enum SpectatorApiPerformTiming {
    static let settingsNote =
        "**Perform timing:** Tap **Perform** on Home **before** the spectator searches. "
        + "The **first poll** after Perform only records a **baseline** — whatever was already on Inject, Elips, or Custom **from earlier**. "
        + "MindtoneX **locks** when the API shows a **new** song or word **after** Perform has started (usually within a few seconds, polls every ~2 s). "
        + "A search done **before** Perform will **not** count as the prediction."
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
