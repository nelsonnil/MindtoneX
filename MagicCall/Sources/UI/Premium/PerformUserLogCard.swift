import SwiftUI

/// Home card: recent Perform sessions with plain Spanish event lines.
struct PerformUserLogCard: View {
    @ObservedObject private var log = PerformUserLog.shared
    @AppStorage("ui.performLogExpanded") private var expanded = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var summary: String {
        if let active = log.activeSession {
            return "En curso · \(active.entries.count) eventos"
        }
        guard let latest = log.sessions.first else { return "Sin actuaciones recientes" }
        return "\(latest.entries.count) eventos · \(Self.dayFormatter.string(from: latest.startedAt))"
    }

    var body: some View {
        HomePanel(accent: OracleHomeSection.advanced.accent) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(OracleHomeSection.advanced.accent)
                            .frame(width: 40, height: 40)
                            .background(OracleHomeSection.advanced.accent.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Registro de actuación")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(OracleTheme.textPrimary)
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(OracleTheme.textSecondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Contraer registro" : "Expandir registro")

                if expanded {
                    VStack(alignment: .leading, spacing: 12) {
                        if log.sessions.isEmpty {
                            Text("Aquí verás qué pasó en cada actuación: canción, palabra, llamada y avisos de conexión.")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                                .padding(.top, 16)
                        } else {
                            ForEach(log.sessions.prefix(5)) { session in
                                sessionBlock(session)
                            }
                        }

                        if !log.sessions.isEmpty {
                            Button(role: .destructive) {
                                log.clearAll()
                            } label: {
                                Text("Borrar historial")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(OracleTheme.coral.opacity(0.9))
                        }
                    }
                    .padding(.top, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionBlock(_ session: PerformUserLog.Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                Spacer(minLength: 4)
                if session.endedAt == nil {
                    Text("En curso")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(OracleTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(OracleTheme.gold.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(Self.dayFormatter.string(from: session.startedAt))
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(session.entries.suffix(12)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.timeFormatter.string(from: entry.at))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(OracleTheme.textSecondary.opacity(0.85))
                            .frame(width: 52, alignment: .leading)
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textPrimary.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
        }
    }
}
