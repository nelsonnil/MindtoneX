import SwiftUI

/// Collapsible "Advanced" card at the bottom of the home screen: stage status-bar options,
/// song details and entry points to settings, debug log and voice/API.
struct AdvancedDisclosureCard: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage("ui.advancedExpanded") private var expanded = false
    @AppStorage(Prefs.Key.hideStatusBar) private var hideStatusBar = false
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = false
    @AppStorage(Prefs.Key.background) private var stageBackground = StageBackground.black.rawValue
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue

    var onOpen: (OracleSheet) -> Void

    private var isManual: Bool {
        (VoiceSettings.InputMode(rawValue: inputModeRaw) ?? .manual) == .manual
    }

    var body: some View {
        OracleCard(section: .advanced, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if expanded {
                    VStack(alignment: .leading, spacing: 18) {
                        stageStatusBarSection
                        if isManual, model.loadState == .ready || !model.results.isEmpty {
                            songSection
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
                    Text("Settings, debug log, voice & API")
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

    // MARK: Sections

    private var stageStatusBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OracleEyebrow(text: "Stage status bar")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(OracleTheme.gold)
                    .font(.subheadline)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic")
                        .font(.subheadline)
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text(autoStatusBarDetail)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            toggleRow("Blur cover on screenshot",
                      detail: "Only if your wallpaper still shows an old status bar under the real one. Off by default.",
                      isOn: $maskStatusBar)
            toggleRow("Hide status bar",
                      detail: "Hides the system status bar entirely during the act.",
                      isOn: $hideStatusBar)
        }
    }

    private var autoStatusBarDetail: String {
        guard StageBackground(rawValue: stageBackground) == .image, StageImageStore.statusBarLuminance() != nil else {
            return "White text on dark stages. With a screenshot, status bar text color follows the top of your wallpaper — no blur unless you turn on Blur cover."
        }
        let dark = StageImageStore.wantsDarkStatusBarText()
        return "Screenshot wallpaper: \(dark ? "light" : "dark") top area → \(dark ? "dark" : "white") status bar text. No blur strip unless Blur cover is on."
    }

    private var songSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Song")
            if let track = model.selected, model.loadState == .ready {
                Text("\(track.source.rawValue) · \(model.timings)")
                    .font(.caption.monospaced())
                    .foregroundStyle(OracleTheme.textSecondary)
            }
            if !model.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(model.results.prefix(6))) { track in
                        Button {
                            Task { await model.select(track) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(OracleTheme.textPrimary)
                                    Text("\(track.artist) · \(track.source.rawValue)")
                                        .font(.caption2)
                                        .foregroundStyle(OracleTheme.textSecondary)
                                }
                                .lineLimit(1)
                                Spacer()
                                if track == model.selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(OracleTheme.gold)
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if track.id != model.results.prefix(6).last?.id {
                            Divider().overlay(OracleTheme.cardBorder)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Tools")
            VStack(spacing: 0) {
                toolRow("All advanced settings", icon: "gearshape.2.fill", sheet: .advanced)
                divider
                toolRow("Debug log", icon: "doc.text.magnifyingglass", sheet: .debugLog)
                divider
                toolRow("AI Voice & API key", icon: "mic.badge.plus", sheet: .voiceSettings)
                divider
                toolRow("API / song input", icon: "link", sheet: .apiSettings)
                divider
                toolRow("Voice debug", icon: "waveform.badge.magnifyingglass", sheet: .voiceDebug)
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    // MARK: Rows

    private var divider: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 46)
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
        .toggleStyle(.switch)
        .tint(OracleTheme.gold)
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
