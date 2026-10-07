import PhotosUI
import SwiftUI

/// Single Performance setup — volume, stage screenshot, auto-share toggle.
struct PerformanceCard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var photoItem: PhotosPickerItem?
    var stageScreenshotGeneration: Int

    @AppStorage(Prefs.Key.fakePlaybackVolume) private var fakePlaybackVolume = 1.0
    @AppStorage(Prefs.Key.storeCountry) private var storeCountry = ""
    @AppStorage(Prefs.Key.deezerFallback) private var deezerFallback = true
    @AppStorage(Prefs.Key.autoShareOnSongLock) private var autoShareOnSongLock = false
    @AppStorage(Prefs.Key.stageStatusBarContent) private var stageStatusBarContentRaw = StageStatusBarContent.automatic.rawValue
    @AppStorage(VoiceSettings.Key.inputMode) private var songInputModeRaw = VoiceSettings.InputMode.card.rawValue
    @AppStorage(CardSettings.Key.handwritingLanguage) private var cardLanguageRaw = CardSettings.HandwritingLanguage.englishAndSpanish.rawValue

    private var hasScreenshot: Bool { StageImageStore.hasScreenshot }
    private var songInputIsCamera: Bool {
        (VoiceSettings.InputMode(rawValue: songInputModeRaw) ?? .card) == .card
    }

    private var performanceSummary: String {
        let shot = hasScreenshot ? "Screenshot set" : "Screenshot required"
        let share = autoShareOnSongLock ? "Auto-share on" : "Auto-share off"
        return "\(shot) · Vol \(Int(fakePlaybackVolume * 100))% · \(share)"
    }

    private var statusBarContentSelection: Binding<StageStatusBarContent> {
        Binding(
            get: { StageStatusBarContent(rawValue: stageStatusBarContentRaw) ?? .automatic },
            set: { stageStatusBarContentRaw = $0.rawValue }
        )
    }

    var body: some View {
        CollapsibleHomeSection(
            expandedKey: HomeSectionExpandKey.performance,
            accent: OracleTheme.gold,
            icon: "photo.on.rectangle.angled",
            title: "Performance settings",
            summary: performanceSummary
        ) {
            VStack(alignment: .leading, spacing: 18) {
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
                    Text("Use **100%** for incoming-call playback. See **Instructions** for screenshot + status bar. Optional Share after lock.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                }

                stageScreenshotSection

                songSearchRegionSection

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

                if songInputIsCamera {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Camera card language")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OracleTheme.textPrimary)
                        Picker("Card language", selection: $cardLanguageRaw) {
                            ForEach(CardSettings.HandwritingLanguage.allCases) { lang in
                                Text(lang.title).tag(lang.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Used for on-device OCR and OpenAI vision when reading the handwritten card (song + word lines).")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var songStorefrontSelection: Binding<SongStorefront> {
        Binding(
            get: { SongStorefront.from(stored: storeCountry) },
            set: { newValue in
                storeCountry = newValue.rawValue
            }
        )
    }

    private var songSearchRegionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Song search region")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            Picker("Song search region", selection: songStorefrontSelection) {
                ForEach(SongStorefront.allCases) { region in
                    Text(region.menuTitle).tag(region)
                }
            }
            .pickerStyle(.menu)
            .tint(OracleTheme.gold)

            Text(
                "iTunes preview catalog for Voice, Camera, Notes, API, and Library. "
                + "Trying **\(SongStorefront.effectiveCode(stored: storeCountry))** first"
                + (SongStorefront.from(stored: storeCountry) == .auto
                    ? " (from your iPhone region)."
                    : ".")
                + " If empty, falls back to **US**."
            )
            .font(.caption)
            .foregroundStyle(OracleTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $deezerFallback) {
                Text("Deezer fallback when iTunes has no preview")
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
            }
            .tint(OracleTheme.gold)

            Text("For Chinese catalogs, try **CN**, **TW**, or **HK**. Deezer helps when Apple has no 30 s preview.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: storeCountry) { _, _ in
            Task { await model.previews.clearCaches() }
        }
        .onChange(of: deezerFallback) { _, _ in
            Task { await model.previews.clearCaches() }
        }
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
                Text("The strip with the time, signal, and battery above your wallpaper. Tap Auto, Dark, or Light in the preview to see icon color on stage.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                StageStatusBarIntegratedPreviewCard(
                    selection: statusBarContentSelection,
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

// MARK: - Status bar preview + style (single card)

private enum StageStatusBarPreviewSky {
    /// Sky backdrop so black and white status icons both read clearly.
    static let celeste = Color(red: 0.45, green: 0.78, blue: 0.96)
}

private struct StageStatusBarIntegratedPreviewCard: View {
    @Binding var selection: StageStatusBarContent
    let screenshotGeneration: Int

    @AppStorage(StageImageStore.luminanceDefaultsKey) private var stageStatusBarLuminance = 0.0
    @AppStorage(StageImageStore.revisionDefaultsKey) private var stageScreenshotRevision = ""
    @Namespace private var modeHighlight

    private var hasScreenshot: Bool { StageImageStore.hasScreenshot }

    private var autoPrefersDarkIcons: Bool {
        _ = stageStatusBarLuminance
        _ = stageScreenshotRevision
        return StageStatusBarContent.automatic.prefersDarkContent(hasScreenshot: hasScreenshot)
    }

    private var previewPrefersDarkIcons: Bool {
        switch selection {
        case .dark: return true
        case .light: return false
        case .automatic: return autoPrefersDarkIcons
        }
    }

    private var modeCaption: String {
        switch selection {
        case .automatic:
            if hasScreenshot {
                return autoPrefersDarkIcons ? "Auto · dark icons from your screenshot" : "Auto · light icons from your screenshot"
            }
            return "Auto · from screenshot top (when set)"
        case .dark: return "Dark · black time & signal"
        case .light: return "Light · white time & signal"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StageStatusBarPhoneTopPreview(prefersDarkContent: previewPrefersDarkIcons)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 6) {
                ForEach(StageStatusBarContent.allCases) { mode in
                    modeChip(mode)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Text(modeCaption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(OracleTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .id(screenshotGeneration)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selection)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: previewPrefersDarkIcons)
    }

    private func modeChip(_ mode: StageStatusBarContent) -> some View {
        let selected = selection == mode
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selection = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.pickerSymbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(mode.segmentTitle)
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? OracleTheme.ink : OracleTheme.textSecondary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(OracleTheme.goldGradient)
                        .matchedGeometryEffect(id: "statusBarMode", in: modeHighlight)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Large top-of-iPhone mock — status bar only on sky backdrop (no stage screenshot).
private struct StageStatusBarPhoneTopPreview: View {
    let prefersDarkContent: Bool

    private var iconColor: Color { prefersDarkContent ? .black : .white }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .padding(2)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    StageStatusBarPreviewSky.celeste

                    Capsule()
                        .fill(Color.black)
                        .frame(width: 88, height: 22)
                        .padding(.top, 10)

                    statusBarRow
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                }
                .frame(height: 56)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 20,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 20,
                        style: .continuous
                    )
                )
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            prefersDarkContent ? "Status bar preview, dark icons" : "Status bar preview, light icons"
        )
    }

    private var statusBarRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("9:41")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(iconColor)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(iconColor)
        }
        .animation(.easeInOut(duration: 0.28), value: prefersDarkContent)
    }
}
