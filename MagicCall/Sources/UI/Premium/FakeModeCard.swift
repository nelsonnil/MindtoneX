import PhotosUI
import SwiftUI

struct FakeModeContent: View {
    @Binding var photoItem: PhotosPickerItem?
    var stageScreenshotGeneration: Int

    @AppStorage(Prefs.Key.fakePlaybackVolume) private var fakePlaybackVolume = 1.0
    @AppStorage(Prefs.Key.stageStatusBarContent) private var stageStatusBarContentRaw = StageStatusBarContent.automatic.rawValue

    private var hasScreenshot: Bool { StageImageStore.hasScreenshot }

    private var statusBarContentSelection: Binding<StageStatusBarContent> {
        Binding(
            get: { StageStatusBarContent(rawValue: stageStatusBarContentRaw) ?? .automatic },
            set: { stageStatusBarContentRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShortcutsInstallPanel(mode: .fakeRingtone)

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

            stageRow
        }
    }

    private var stageRow: some View {
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

            VStack(alignment: .leading, spacing: 6) {
                Text("Status bar icons")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                Picker("Status bar icons", selection: statusBarContentSelection) {
                    ForEach(StageStatusBarContent.allCases) { mode in
                        Text(mode.segmentTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Dark = black icons (light wallpaper). Light = white icons (dark wallpaper). Auto matches the top of your screenshot.")
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
