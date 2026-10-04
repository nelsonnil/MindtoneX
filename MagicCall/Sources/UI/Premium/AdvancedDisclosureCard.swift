import SwiftUI

/// Optional home-screen extras: screenshot status-bar blur, debug log, and technical tuning sheet.
/// Song input, Mode, and Feedback own everything else.
struct AdvancedDisclosureCard: View {
    @AppStorage("ui.advancedExpanded") private var expanded = false
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = false
    @AppStorage(Prefs.Key.background) private var stageBackground = StageBackground.black.rawValue

    var onOpen: (OracleSheet) -> Void

    private var stageKind: StageBackground { StageBackground(rawValue: stageBackground) ?? .black }
    private var showsScreenshotBlur: Bool { stageKind == .image }

    var body: some View {
        OracleCard(section: .advanced, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if expanded {
                    VStack(alignment: .leading, spacing: 14) {
                        if showsScreenshotBlur {
                            screenshotBlurRow
                        } else {
                            Text("Nothing extra for this stage background. Status bar behavior is automatic — see the Mode card.")
                                .font(.caption)
                                .foregroundStyle(OracleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        toolsSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { expanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OracleHomeSection.advanced.accent)
                    .frame(width: 36, height: 36)
                    .background(OracleHomeSection.advanced.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Optional blur and debug log")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(OracleTheme.textSecondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Advanced")
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }

    private var screenshotBlurRow: some View {
        Toggle(isOn: $maskStatusBar) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Blur cover on screenshot")
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
                Text("Only if a stale status bar still shows through your wallpaper. Off by default.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .tint(OracleTheme.gold)
    }

    private var toolsSection: some View {
        VStack(spacing: 0) {
            toolRow("Debug log", icon: "doc.text.magnifyingglass", sheet: .debugLog)
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    private var divider: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 46)
    }

    private func toolRow(_ title: String, icon: String, sheet: OracleSheet) -> some View {
        Button {
            onOpen(sheet)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
