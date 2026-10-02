import PhotosUI
import SwiftUI

struct FakeModeCard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var background: String
    @Binding var maskStatusBar: Bool
    @Binding var hideStatusBar: Bool
    @Binding var darkStatusBarText: Bool
    @Binding var photoItem: PhotosPickerItem?
    var onInfo: () -> Void
    var onShortcutsSetup: () -> Void

    var body: some View {
        OracleCard {
            VStack(alignment: .leading, spacing: 16) {
                header

                SilentShortcutStatusRow(mode: .fakeRingtone, onSetup: onShortcutsSetup)

                stageRow

                statusBarSegmented

                OraclePerformButton(
                    title: "Perform",
                    gradient: OracleTheme.goldGradient,
                    disabled: !model.canPerform
                ) {
                    model.perform()
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    private var header: some View {
        HStack {
            Label("Fake Ringtone", systemImage: "theatermasks.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(OracleTheme.indigo)
            Spacer()
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .foregroundStyle(OracleTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var stageRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textSecondary)
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
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stageThumb: some View {
        let kind = StageBackground(rawValue: background) ?? .black
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black)
            .frame(width: 56, height: 72)
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
                    .stroke(OracleTheme.cardBorder, lineWidth: 1)
            }
    }

    private var statusBarSegmented: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status bar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textSecondary)
            HStack(spacing: 8) {
                statusToggle(title: "Cover", icon: "rectangle.topthird.inset.filled", isOn: $maskStatusBar)
                statusToggle(title: "Hide", icon: "eye.slash", isOn: $hideStatusBar)
                statusToggle(title: "Dark text", icon: "textformat", isOn: $darkStatusBarText)
            }
        }
    }

    private func statusToggle(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isOn.wrappedValue ? OracleTheme.gold : OracleTheme.textSecondary)
            .background(isOn.wrappedValue ? OracleTheme.gold.opacity(0.12) : Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isOn.wrappedValue ? OracleTheme.gold.opacity(0.5) : OracleTheme.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
