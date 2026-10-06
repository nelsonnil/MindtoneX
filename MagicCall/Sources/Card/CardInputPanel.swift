import SwiftUI

struct CardInputPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var session = CardSongSession.shared
    @State private var showPractice = false
    @State private var cameraDenied = false

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

            HStack(spacing: 10) {
                Button {
                    Task {
                        let ok = await CardSettings.requestCameraIfNeeded()
                        cameraDenied = !ok
                        if ok { showPractice = true }
                    }
                } label: {
                    Label("Practice scan", systemImage: "camera.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(OracleTheme.indigo.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    PerformanceCues.playSongLockVibration()
                } label: {
                    Image(systemName: "waveform")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OracleTheme.gold)
                .accessibilityLabel("Test lock vibration")
            }

            if session.context == .test, !session.lastOCRText.isEmpty {
                Text("Last read: \(session.lastOCRText)")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .lineLimit(2)
            }

            if model.loadState == .ready, let track = model.selected, session.state == .locked {
                LoadedSongReadyRow(track: track)
            }
        }
        .sheet(isPresented: $showPractice) {
            CardPracticeScanView()
        }
        .alert("Camera", isPresented: $cameraDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable camera for MindtoneX in Settings → Privacy.")
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
