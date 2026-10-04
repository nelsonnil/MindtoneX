import PhotosUI
import SwiftUI

struct FakeModeContent: View {
    @Binding var background: String
    @Binding var photoItem: PhotosPickerItem?
    var onInfo: () -> Void

    @AppStorage(Prefs.Key.volumeDownOpensShareAfterCall) private var volumeDownOpensShareAfterCall = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                OracleEyebrow(text: "Setup")
                Spacer()
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fake Ringtone guide")
            }

            ShortcutsInstallPanel(mode: .fakeRingtone)

            Toggle(isOn: $volumeDownOpensShareAfterCall) {
                Text("Volume down opens share after call")
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(OracleTheme.gold)

            stageRow
        }
    }

    private var stageRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Stage")
            HStack(spacing: 12) {
                stageThumb
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Background", selection: $background) {
                        ForEach(StageBackground.allCases) { kind in
                            Text(kind.label).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(OracleTheme.gold)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose screenshot", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(OracleTheme.textPrimary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var stageThumb: some View {
        let kind = StageBackground(rawValue: background) ?? .black
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black)
            .frame(width: 52, height: 68)
            .overlay {
                switch kind {
                case .black:
                    Color.black
                case .gradient:
                    LinearGradient(colors: [.black, .gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                case .image:
                    if let image = StageImageStore.load() {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(OracleTheme.textSecondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorderHighlight, lineWidth: 1)
            }
    }
}
