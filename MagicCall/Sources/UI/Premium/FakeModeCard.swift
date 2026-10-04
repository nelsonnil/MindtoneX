import PhotosUI
import SwiftUI

struct FakeModeContent: View {
    @Binding var photoItem: PhotosPickerItem?

    @AppStorage(Prefs.Key.fakePlaybackVolume) private var fakePlaybackVolume = 1.0

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
            Text("Stage background")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            HStack(spacing: 12) {
                stageThumb
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose screenshot", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OracleTheme.textPrimary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var stageThumb: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black)
            .frame(width: 52, height: 68)
            .overlay {
                if let image = StageImageStore.load() {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorderHighlight, lineWidth: 1)
            }
    }
}
