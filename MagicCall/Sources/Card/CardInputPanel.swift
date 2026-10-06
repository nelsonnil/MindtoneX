import SwiftUI

struct CardInputPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var session = CardSongSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OracleEyebrow(text: "Card (handwriting OCR)")

            VStack(alignment: .leading, spacing: 10) {
                tipRow("doc.plaintext", "White matte card + thick black marker")
                tipRow("textformat.size.larger", "ALL CAPS · **line 1** = song title · **line 2** = one spectator word (optional SONG:/WORD: labels)")
                tipRow("camera.fill", "During Perform: press **volume up or down** — green dot ~\(Int(CardSettings.defaultBurstSeconds)) s while reading (Camera Control also works on iPhone 16+)")
                tipRow("button.programmable", "1 buzz = song read · 2 strong buzzes = preview ready")
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !CardSettings.cameraAuthorized {
                Label("Camera access required — open Settings to allow.", systemImage: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            Button {
                PerformanceCues.playSongLockVibration()
            } label: {
                Label("Test lock vibration", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(OracleTheme.gold)

            if model.loadState == .ready, let track = model.selected, session.state == .locked {
                LoadedSongReadyRow(track: track)
            }
        }
        .onAppear {
            Task { _ = await CardSettings.requestCameraIfNeeded() }
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.gold)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }
}
