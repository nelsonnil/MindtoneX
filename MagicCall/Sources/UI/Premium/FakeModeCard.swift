import PhotosUI
import SwiftUI

struct FakeModeCard: View {
    @Binding var background: String
    @Binding var photoItem: PhotosPickerItem?
    var onInfo: () -> Void
    var onShortcutsSetup: () -> Void

    var body: some View {
        OracleCard {
            VStack(alignment: .leading, spacing: 16) {
                ModeDetailHeader(
                    title: "Fake Ringtone",
                    icon: "theatermasks.fill",
                    tint: OracleTheme.indigo,
                    summary: "Silent ON. A real call arrives and your song plays as if it were the ringtone.",
                    onInfo: onInfo
                )

                Divider().overlay(OracleTheme.cardBorder)

                SilentShortcutStatusRow(mode: .fakeRingtone, onSetup: onShortcutsSetup)

                stageRow
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
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

/// Compact title row for a mode detail card: icon, title, one-line summary, info button.
struct ModeDetailHeader: View {
    let title: String
    let icon: String
    let tint: Color
    let summary: String
    var onInfo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) details")
        }
    }
}
