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
                Text("Status bar (top of iPhone)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                Text("The strip with the **time**, **signal**, and **battery** above your wallpaper. Pick icon color so it matches your screenshot during Perform.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                StageStatusBarStylePicker(selection: statusBarContentSelection)
                StageStatusBarPreviewPanel(
                    selection: statusBarContentSelection.wrappedValue,
                    screenshotGeneration: stageScreenshotGeneration
                )
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

// MARK: - Status bar preview (Dark / Light icon styles)

private struct StageStatusBarPreviewPanel: View {
    let selection: StageStatusBarContent
    let screenshotGeneration: Int

    @AppStorage(StageImageStore.luminanceDefaultsKey) private var stageStatusBarLuminance = 0.0
    @AppStorage(StageImageStore.revisionDefaultsKey) private var stageScreenshotRevision = ""

    private var screenshot: UIImage? { StageImageStore.load() }
    private var autoPrefersDarkIcons: Bool {
        _ = stageStatusBarLuminance
        _ = stageScreenshotRevision
        return StageStatusBarContent.automatic.prefersDarkContent(hasScreenshot: screenshot != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch selection {
            case .automatic:
                HStack(spacing: 12) {
                    previewCard(
                        prefersDarkContent: true,
                        caption: "Dark icons",
                        subtitle: "Light wallpaper",
                        emphasized: screenshot != nil && autoPrefersDarkIcons
                    )
                    previewCard(
                        prefersDarkContent: false,
                        caption: "Light icons",
                        subtitle: "Dark wallpaper",
                        emphasized: screenshot != nil && !autoPrefersDarkIcons
                    )
                }
                if screenshot != nil {
                    Label(
                        autoPrefersDarkIcons ? "Auto · your screenshot uses dark icons" : "Auto · your screenshot uses light icons",
                        systemImage: "sparkles"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(OracleTheme.gold)
                } else {
                    Text("Add a screenshot above — Auto picks dark or light icons from the top of the image.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            case .dark:
                previewCard(
                    prefersDarkContent: true,
                    caption: "Dark icons on your stage",
                    subtitle: "Black time & signal",
                    emphasized: true,
                    fullWidth: true
                )
            case .light:
                previewCard(
                    prefersDarkContent: false,
                    caption: "Light icons on your stage",
                    subtitle: "White time & signal",
                    emphasized: true,
                    fullWidth: true
                )
            }
        }
        .id(screenshotGeneration)
        .animation(.easeInOut(duration: 0.22), value: selection)
        .animation(.easeInOut(duration: 0.22), value: stageScreenshotRevision)
    }

    @ViewBuilder
    private func previewCard(
        prefersDarkContent: Bool,
        caption: String,
        subtitle: String,
        emphasized: Bool,
        fullWidth: Bool = false
    ) -> some View {
        VStack(spacing: 6) {
            StageStatusBarPhonePreview(
                prefersDarkContent: prefersDarkContent,
                backgroundImage: screenshot
            )
            .frame(maxWidth: fullWidth ? .infinity : nil)
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(OracleTheme.textSecondary)
        }
        .frame(maxWidth: fullWidth ? .infinity : .infinity)
        .padding(8)
        .background(Color.white.opacity(emphasized ? 0.07 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    emphasized ? OracleTheme.gold.opacity(0.55) : OracleTheme.cardBorder,
                    lineWidth: emphasized ? 1.5 : 1
                )
        }
    }
}

/// Mini phone mockup — status bar strip only (what performers need to match).
private struct StageStatusBarPhonePreview: View {
    let prefersDarkContent: Bool
    var backgroundImage: UIImage?

    private var iconColor: Color { prefersDarkContent ? .black : .white }
    private var fallbackBackdrop: Color {
        prefersDarkContent ? Color(white: 0.92) : Color(white: 0.12)
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.85))
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Group {
                        if let backgroundImage {
                            Image(uiImage: backgroundImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            fallbackBackdrop
                        }
                    }
                    .frame(height: 72)
                    .clipped()

                    statusBarRow
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                    Capsule()
                        .fill(Color.black)
                        .frame(width: 52, height: 14)
                        .padding(.top, 6)
                }
                .frame(height: 72)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 36)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(3)
        }
        .frame(width: 118, height: 114)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(prefersDarkContent ? "Preview dark status bar icons" : "Preview light status bar icons")
    }

    private var statusBarRow: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("9:41")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(iconColor)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(iconColor)
        }
    }
}
