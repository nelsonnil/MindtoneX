import SwiftUI
import UIKit

/// Home card: recent Perform sessions with plain English event lines.
struct PerformUserLogCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var log = PerformUserLog.shared
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// The latest session keeps its first lines: caller-name checks are logged at arm, before any event.
    private static let latestSessionHead = 20
    private static let latestSessionTail = 40
    private static let olderSessionLineLimit = 12

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var summary: String {
        if log.activeSession != nil {
            let count = log.activeSession?.entries.count ?? 0
            return "In progress · \(count) events"
        }
        guard let latest = log.sessions.first else { return "No recent performs" }
        return "\(latest.entries.count) events · \(Self.dayFormatter.string(from: latest.startedAt))"
    }

    var body: some View {
        if model.isPerformTrickUIActive {
            EmptyView()
        } else {
            performLogCard
        }
    }

    private var performLogCard: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.performLog,
            accent: OracleHomeSection.advanced.accent,
            icon: "list.bullet.rectangle",
            title: "Perform log",
            summary: summary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if log.sessions.isEmpty {
                    Text("Shows **inputs armed**, **Voice · heard**, every **OpenAI** answer (even when empty), **Recognized** locks, camera OCR, and call events.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                } else {
                    ForEach(log.sessions.prefix(5)) { session in
                        sessionBlock(session)
                    }
                }

                if !log.sessions.isEmpty {
                    Button(role: .destructive) {
                        log.clearAll()
                    } label: {
                        Text("Clear history")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OracleTheme.coral.opacity(0.9))
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
                    Text("Live")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(OracleTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(OracleTheme.gold.opacity(0.15))
                        .clipShape(Capsule())
                }
                Button {
                    UIPasteboard.general.string = Self.plainText(session)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OracleTheme.gold)
                .accessibilityLabel("Copy this perform log")
            }
            Text(Self.dayFormatter.string(from: session.startedAt))
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleEntries(of: session)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.timeFormatter.string(from: entry.at))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(OracleTheme.textSecondary.opacity(0.85))
                            .frame(width: 58, alignment: .leading)
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

    private func visibleEntries(of session: PerformUserLog.Session) -> [PerformUserLog.Entry] {
        let entries = session.entries
        guard session.id == log.sessions.first?.id else {
            return Array(entries.suffix(Self.olderSessionLineLimit))
        }
        let head = Self.latestSessionHead
        let tail = Self.latestSessionTail
        guard entries.count > head + tail else { return entries }
        let gap = PerformUserLog.Entry(
            at: entries[head].at,
            message: "… \(entries.count - head - tail) more lines — copy the log to see them all"
        )
        return Array(entries.prefix(head)) + [gap] + Array(entries.suffix(tail))
    }

    private static func plainText(_ session: PerformUserLog.Session) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = "MindtoneX \(version) (\(build)) · iOS \(UIDevice.current.systemVersion) · Region \(Locale.current.region?.identifier ?? "?")"
        let header = "\(session.title) · \(dayFormatter.string(from: session.startedAt))"
        let lines = session.entries.map { "\(timeFormatter.string(from: $0.at)) \($0.message)" }
        return ([device, header] + lines).joined(separator: "\n")
    }
}
