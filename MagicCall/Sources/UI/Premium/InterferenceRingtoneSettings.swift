import AVFoundation
import SwiftUI
import UIKit

/// Performance settings block: master toggle, Ringtone 1 / 2, and the test lab (sheet inside Settings).
struct InterferenceRingtoneSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(InterferenceSettings.Key.enabled) private var enabled = false
    @AppStorage(InterferenceSettings.Key.ringtoneID) private var ringtoneID = InterferenceSettings.Ringtone.defaultValue.rawValue
    @State private var showTestMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interference ringtone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Your ringtone plays first. When the front camera sees an open hand, radio interference takes over and morphs into the song.")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(OracleTheme.gold)

            InterferenceRingtonePicker(selectionRaw: $ringtoneID)

            Button {
                showTestMode = true
            } label: {
                Label("Open test mode", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(OracleTheme.ink)
                    .background(OracleTheme.goldGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Test mode runs here in Settings only. Real calls in Perform still use the current ringtone engine — this switch is saved for the next build.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showTestMode) {
            NavigationStack {
                InterferenceTestView()
            }
            .environmentObject(model)
        }
    }
}

struct InterferenceRingtonePicker: View {
    @Binding var selectionRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Ringtone", selection: $selectionRaw) {
                ForEach(InterferenceSettings.Ringtone.allCases) { ringtone in
                    Text(ringtone.title).tag(ringtone.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("Ringtone 1 is the default.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }
}

// MARK: - Test mode

struct InterferenceTestView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(InterferenceSettings.Key.ringtoneID) private var ringtoneID = InterferenceSettings.Ringtone.defaultValue.rawValue
    @StateObject private var test = InterferenceTestController()

    private var ringtone: InterferenceSettings.Ringtone {
        InterferenceSettings.Ringtone(rawValue: ringtoneID) ?? InterferenceSettings.Ringtone.defaultValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                statusCard

                if test.phase == .playingRingtone {
                    cameraCard
                }

                block(number: 1, title: "Song") {
                    LibrarySongSearchBlock()
                        .disabled(test.phase.isBusy)
                        .opacity(test.phase.isBusy ? 0.5 : 1)
                }

                block(number: 2, title: "Ringtone") {
                    InterferenceRingtonePicker(selectionRaw: $ringtoneID)
                        .disabled(test.phase.isBusy)
                }

                controls

                Text("Place the iPhone face up, tap Play, then hold an open hand (5 fingers, palm to the screen) about a hand-span above it. The green camera dot is normal while the ringtone plays.")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(OracleTheme.screenGradient.ignoresSafeArea())
        .navigationTitle("Interference test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    test.stop()
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { test.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, test.phase.isBusy {
                test.stop(note: "Stopped because MindtoneX left the screen.")
            }
        }
    }

    // MARK: Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 44, height: 44)
                    .background(statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                stepRow(1, "Playing ringtone", detail: ringtone.title)
                stepRow(2, "Hand detected", detail: test.handDetectedAfter.map { String(format: "after %.1f s", $0) })
                stepRow(3, "Interference", detail: nil)
                stepRow(4, "Playing song", detail: model.selected.map { $0.title })
            }
        }
        .padding(16)
        .background(OracleTheme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(statusColor.opacity(0.45), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: test.phase)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch test.phase {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .playingRingtone: return "Playing ringtone"
        case .handDetected: return "Hand detected"
        case .interference: return "Interference"
        case .playingSong: return "Playing song"
        case .error: return "Error"
        }
    }

    private var statusDetail: String {
        switch test.phase {
        case .idle:
            return test.note ?? "Pick a song, choose a ringtone, then tap Play."
        case .starting:
            return "Loading sounds and opening the front camera."
        case .playingRingtone:
            return "Waiting for an open hand · fingers seen: \(test.fingersSeen)"
        case .handDetected:
            return "Camera off. Interference is coming in."
        case .interference:
            return "Static takes over the ringtone; the song comes through like a radio."
        case .playingSong:
            return "Clean song preview. Tap Stop to reset."
        case .error(let message):
            return message
        }
    }

    private var statusIcon: String {
        switch test.phase {
        case .idle: return "pause.circle"
        case .starting: return "hourglass"
        case .playingRingtone: return "bell.and.waves.left.and.right.fill"
        case .handDetected: return "hand.raised.fill"
        case .interference: return "antenna.radiowaves.left.and.right"
        case .playingSong: return "music.note"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch test.phase {
        case .idle, .starting: return OracleTheme.textSecondary
        case .error: return OracleTheme.danger
        case .playingSong: return OracleTheme.sectionTeal
        default: return OracleTheme.gold
        }
    }

    private func stepRow(_ step: Int, _ title: String, detail: String?) -> some View {
        let current = test.phase.step
        let done = current > step
        let active = current == step
        return HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "dot.circle.fill" : "circle"))
                .foregroundStyle(done || active ? OracleTheme.gold : OracleTheme.textSecondary.opacity(0.6))
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(done || active ? OracleTheme.textPrimary : OracleTheme.textSecondary)
            Spacer(minLength: 8)
            if let detail, done || active {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Camera

    private var cameraCard: some View {
        HStack(alignment: .top, spacing: 14) {
            InterferenceCameraPreview(session: test.detector.session)
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(OracleTheme.cardBorderHighlight, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 6) {
                Text("Front camera")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                Text("Fingers seen: \(test.fingersSeen) / \(HandGestureDetector.requiredFingers)+")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(test.fingersSeen >= HandGestureDetector.requiredFingers ? OracleTheme.gold : OracleTheme.textSecondary)
                Text("Preview is for practice only — it never shows on stage.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(OracleTheme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await test.play(model: model, ringtone: ringtone) }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(OracleTheme.ink)
                    .background(OracleTheme.goldGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(test.phase.isBusy)
            .opacity(test.phase.isBusy ? 0.45 : 1)
            .accessibilityHint("Starts the ringtone and the front camera")

            Button {
                test.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(OracleTheme.textPrimary)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OracleTheme.cardBorderHighlight, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(test.phase == .idle)
            .opacity(test.phase == .idle ? 0.45 : 1)
            .accessibilityHint("Stops sound and camera and resets the test")
        }
    }

    private func block<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(number) · \(title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)
            content()
        }
    }
}

/// Live front-camera preview for the test lab only.
private struct InterferenceCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
