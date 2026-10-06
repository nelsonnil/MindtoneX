import PhotosUI
import SwiftUI

/// Single Performance setup — volume, stage screenshot, auto-share toggle.
struct PerformanceCard: View {
    @Binding var photoItem: PhotosPickerItem?
    var stageScreenshotGeneration: Int

    @AppStorage(Prefs.Key.fakePlaybackVolume) private var fakePlaybackVolume = 1.0
    @AppStorage(Prefs.Key.autoShareOnSongLock) private var autoShareOnSongLock = false
    @AppStorage(Prefs.Key.stageStatusBarContent) private var stageStatusBarContentRaw = StageStatusBarContent.automatic.rawValue

    private var hasScreenshot: Bool { StageImageStore.hasScreenshot }

    private var statusBarContentSelection: Binding<StageStatusBarContent> {
        Binding(
            get: { StageStatusBarContent(rawValue: stageStatusBarContentRaw) ?? .automatic },
            set: { stageStatusBarContentRaw = $0.rawValue }
        )
    }

    var body: some View {
        HomePanel(accent: OracleTheme.gold) {
            VStack(alignment: .leading, spacing: 18) {
                HomeSectionTitle(
                    title: "Performance",
                    subtitle: "Stage disguise · in-app playback on incoming call",
                    eyebrow: nil
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Playback volume")
                            .font(.subheadline)
                            .foregroundStyle(OracleTheme.textPrimary)
                        Spacer()
                        Text("\(Int(fakePlaybackVolume * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                    Slider(value: $fakePlaybackVolume, in: 0.3...1)
                        .tint(OracleTheme.gold)
                    Text("Side buttons adjust volume during Perform. After the call ends, long-press the stage to open Share.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                }

                stageScreenshotSection

                Toggle(isOn: $autoShareOnSongLock) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-open Share when song locks")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OracleTheme.textPrimary)
                        Text("Only while performing: opens Use as Ringtone when Voice, Notes, API, or Card locks a song during Perform.")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                }
                .tint(OracleTheme.gold)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Performance")
    }

    private var stageScreenshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stage screenshot")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            Text("Required. Pick a full-screen screenshot of your Home or Lock screen — the stage shows only this image during Perform.")
                .font(.caption)
                .foregroundStyle(hasScreenshot ? OracleTheme.textSecondary : OracleTheme.coral.opacity(0.95))
            HStack(spacing: 12) {
                stageThumb
                    .id(stageScreenshotGeneration)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(hasScreenshot ? "Replace screenshot" : "Choose screenshot", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OracleTheme.textPrimary)
                }
                .buttonStyle(.borderedProminent)
                .tint(hasScreenshot ? OracleTheme.gold.opacity(0.85) : OracleTheme.gold)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Status bar icons")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                StageStatusBarStylePicker(selection: statusBarContentSelection)
                Text("Match the clock and signal icons to your wallpaper.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var stageThumb: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: 52, height: 68)
            .overlay {
                if let image = StageImageStore.load() {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                        Text("Required")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(OracleTheme.coral.opacity(0.9))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        hasScreenshot ? OracleTheme.cardBorderHighlight : OracleTheme.coral.opacity(0.65),
                        style: hasScreenshot ? StrokeStyle(lineWidth: 1) : StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            }
    }
}

// MARK: - Status bar style

private struct StageStatusBarStylePicker: View {
    @Binding var selection: StageStatusBarContent
    @Namespace private var selectionNS

    var body: some View {
        HStack(spacing: 5) {
            ForEach(StageStatusBarContent.allCases) { mode in
                let selected = selection == mode
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = mode
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: mode.pickerSymbol)
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(mode.segmentTitle)
                            .font(.caption2.weight(.bold))
                        Text(mode.pickerHint)
                            .font(.system(size: 9, weight: .medium))
                            .opacity(selected ? 0.85 : 0.55)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(selected ? OracleTheme.ink : OracleTheme.textSecondary)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(OracleTheme.goldGradient)
                                .matchedGeometryEffect(id: "statusBarStyleFill", in: selectionNS)
                                .shadow(color: OracleTheme.gold.opacity(0.35), radius: 8, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}
