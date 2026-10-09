import SwiftUI

struct CardInputPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var session = CardSongSession.shared
    @AppStorage(CardSettings.Key.cameraFacing) private var cameraFacingRaw = CardSettings.defaultCameraFacing.rawValue
    @AppStorage(SpectatorSettings.Key.count) private var spectatorCount = 1

    private var cameraFacing: Binding<CardSettings.CameraFacing> {
        Binding(
            get: { CardSettings.CameraFacing(rawValue: cameraFacingRaw) ?? .back },
            set: { cameraFacingRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OracleEyebrow(text: "Camera · handwriting OCR")

            VStack(alignment: .leading, spacing: 8) {
                Text("Camera for card")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary)
                Picker("Camera for card", selection: cameraFacing) {
                    ForEach(CardSettings.CameraFacing.allCases) { facing in
                        Text(facing.segmentTitle).tag(facing)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 10) {
                tipRow("doc.plaintext", "White matte card + thick black marker")
                if spectatorCount == 2 {
                    tipRow("person.2.fill", "2 spectators · two clear song titles in ALL CAPS, one per line — top = spectator 1, below = spectator 2")
                } else {
                    tipRow("textformat.size.larger", "ALL CAPS · \(CardOCRLayout.lineAssignmentSummary) (optional SONG:/WORD:/NOTES: labels)")
                }
                tipRow("hand.raised.fill", "Hold the card steady for the full ~\(String(format: "%.1f", CardSettings.burstSeconds)) s scan burst — motion blur hurts OCR")
                tipRow("camera.fill", "During Perform: press **volume up** to scan — green dot ~\(Int(CardSettings.defaultBurstSeconds)) s while reading (Camera Control also works on iPhone 16+)")
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

            if model.loadState == .ready, let track = model.selected, session.state == .locked {
                LoadedSongReadyRow(track: track)
            }
        }
        .onAppear {
            Task { _ = await CardSettings.requestCameraIfNeeded() }
        }
        .onChange(of: cameraFacingRaw) { _, _ in
            CardSongSession.shared.restartCameraIfRunning()
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
