import AVFoundation
import SwiftUI
import UIKit

/// Song card › Ringtone — Normal vs Interference, Ringtone 1 / 2, interference sound, test lab.
struct SongRingtoneModeBlock: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(InterferenceSettings.Key.enabled) private var enabled = false
    @AppStorage(InterferenceSettings.Key.ringtoneID) private var ringtoneID = InterferenceSettings.Ringtone.defaultValue.rawValue
    @AppStorage(InterferenceSettings.Key.presetID) private var presetID = InterferenceSettings.InterferencePreset.defaultValue.rawValue
    @State private var showTestMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ringtone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OracleTheme.textPrimary)

            HStack(spacing: 10) {
                modeChip("Normal ringtone", icon: "bell.fill", value: false)
                modeChip("Interference ringtone", icon: "antenna.radiowaves.left.and.right", value: true)
            }

            Text(enabled
                ? "Your ringtone plays first. When the front camera sees an open hand, radio interference takes over and morphs into the song."
                : "Standard MindtoneX ringtone — the song plays when the call rings.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if enabled {
                VStack(alignment: .leading, spacing: 10) {
                    InterferenceRingtonePicker(selectionRaw: $ringtoneID)
                    InterferencePresetPicker(selectionRaw: $presetID)
                }

                Button {
                    model.pauseVoiceAndAudioForSetupUI(reason: "interference test")
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
                .accessibilityHint("Practice ringtone, open hand, interference, and song")

                Text("Perform: incoming calls use this ringtone until the front camera sees an open hand. Banner call style keeps the camera on; Back Tap or the volume trigger can stand in for the hand.")
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !CardSettings.cameraAuthorized {
                    Label("Camera access is off — Perform will use the normal ringtone. Allow it in iPhone Settings → MindtoneX → Camera.", systemImage: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .sheet(isPresented: $showTestMode) {
            NavigationStack {
                InterferenceTestView()
            }
            .environmentObject(model)
        }
    }

    private func modeChip(_ title: String, icon: String, value: Bool) -> some View {
        let selected = enabled == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { enabled = value }
            dlog("[INTERF] ringtone mode → \(value ? "interference" : "normal")")
            if value {
                Task { _ = await CardSettings.requestCameraIfNeeded() }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .foregroundStyle(selected ? OracleTheme.textPrimary : OracleTheme.textSecondary)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? OracleTheme.gold.opacity(0.22) : Color.white.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? OracleTheme.gold.opacity(0.85) : OracleTheme.cardBorder, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Legacy name — ringtone UI moved to Song card.
typealias InterferenceRingtoneSettingsSection = SongRingtoneModeBlock

struct InterferenceRingtonePicker: View {
    @Binding var selectionRaw: String

    var body: some View {
        Picker("Ringtone", selection: $selectionRaw) {
            ForEach(InterferenceSettings.Ringtone.allCases) { ringtone in
                Text(ringtone.title).tag(ringtone.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct InterferencePresetPicker: View {
    @Binding var selectionRaw: String

    private var available: [InterferenceSettings.InterferencePreset] {
        InterferenceSettings.bundledPresets
    }

    var body: some View {
        if !available.isEmpty {
            HStack(spacing: 8) {
                Text("Interference sound")
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
                Spacer(minLength: 8)
                Picker("Interference sound", selection: $selectionRaw) {
                    ForEach(available) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(OracleTheme.gold)
            }
            .onAppear { syncSelection() }
            .onChange(of: selectionRaw) { _, _ in syncSelection() }
        }
    }

    private func syncSelection() {
        let resolved = InterferenceSettings.resolvedPreset(storedRaw: selectionRaw)
        if selectionRaw != resolved.rawValue {
            selectionRaw = resolved.rawValue
        }
    }
}

// MARK: - Test mode

struct InterferenceTestView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(InterferenceSettings.Key.ringtoneID) private var ringtoneID = InterferenceSettings.Ringtone.defaultValue.rawValue
    @AppStorage(InterferenceSettings.Key.presetID) private var presetID = InterferenceSettings.InterferencePreset.defaultValue.rawValue
    @AppStorage(Prefs.Key.storeCountry) private var storeCountry = ""
    @AppStorage(SpectatorSettings.Key.count) private var spectatorCount = 1
    @StateObject private var test = InterferenceTestController()

    private var twoSpectators: Bool { spectatorCount == 2 }

    private var songsMissing: Bool {
        twoSpectators && (test.song1 == nil || test.song2 == nil)
    }

    private var ringtone: InterferenceSettings.Ringtone {
        InterferenceSettings.Ringtone(rawValue: ringtoneID) ?? InterferenceSettings.Ringtone.defaultValue
    }

    private var preset: InterferenceSettings.InterferencePreset {
        InterferenceSettings.resolvedPreset(storedRaw: presetID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                statusCard

                if test.phase == .playingRingtone {
                    cameraCard
                }

                block(number: 1, title: twoSpectators ? "Songs" : "Song") {
                    VStack(alignment: .leading, spacing: 6) {
                        if twoSpectators { songSlots }
                        LibrarySongSearchBlock(
                            pickedTrackID: twoSpectators ? slotTrack(test.pickSlot)?.id : nil,
                            onPick: songPickHandler,
                            resultsPresentation: .sheet
                        )
                    }
                    .disabled(test.phase.isBusy)
                    .opacity(test.phase.isBusy ? 0.5 : 1)
                }

                block(number: 2, title: "Sound") {
                    VStack(alignment: .leading, spacing: 10) {
                        InterferenceRingtonePicker(selectionRaw: $ringtoneID)
                        InterferencePresetPicker(selectionRaw: $presetID)
                    }
                    .disabled(test.phase.isBusy)
                    .opacity(test.phase.isBusy ? 0.5 : 1)
                }

                block(number: 3, title: "Catalog") {
                    Text("Storefront: **\(SongStorefront.effectiveCode(stored: storeCountry))** · change under Home › Song › Catalog & ringtone")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .onAppear { test.prefillSongs(model: model) }
        .onDisappear { test.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, test.phase.isBusy {
                test.stop(note: "Stopped because MindtoneX left the screen.")
            }
        }
    }

    // MARK: Songs (Spectators = 2)

    private func slotTrack(_ slot: Int) -> PreviewTrack? {
        slot == 2 ? test.song2 : test.song1
    }

    /// Spectators = 2: matches fill the highlighted slot instead of loading into the Home song.
    private var songPickHandler: ((PreviewTrack) -> Void)? {
        guard twoSpectators else { return nil }
        let test = self.test
        let model = self.model
        return { track in
            test.assign(track, toSlot: test.pickSlot, model: model)
        }
    }

    private var songSlots: some View {
        VStack(alignment: .leading, spacing: 6) {
            songSlotRow(1)
            songSlotRow(2)
            Text("Tap a row, then a match below.")
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }

    private func songSlotRow(_ slot: Int) -> some View {
        let active = test.pickSlot == slot
        let track = slotTrack(slot)
        return Button {
            test.pickSlot = slot
        } label: {
            HStack(spacing: 8) {
                Text("\(slot)")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(active ? OracleTheme.ink : OracleTheme.textSecondary)
                    .background(active ? OracleTheme.gold : Color.white.opacity(0.08), in: Circle())
                Text(track.map { "\($0.title) — \($0.artist)" } ?? "Song \(slot) · spectator \(slot)")
                    .font(.subheadline.weight(track == nil ? .regular : .medium))
                    .foregroundStyle(track == nil ? OracleTheme.textSecondary : OracleTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if track != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.gold)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(active ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(active ? OracleTheme.gold.opacity(0.6) : OracleTheme.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Song \(slot): \(track.map { $0.title } ?? "not picked")")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(OracleTheme.textPrimary)
                Text(statusPhaseLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())
                Spacer(minLength: 0)
            }

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            flowLayoutSteps
        }
        .padding(16)
        .background(OracleTheme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(statusColor.opacity(0.35), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: test.phase)
        .accessibilityElement(children: .combine)
    }

    private var statusPhaseLabel: String {
        switch test.phase {
        case .idle: return "Ready"
        case .error: return "Issue"
        case .playingSong, .playingSecondSong: return "Song"
        default: return "Live"
        }
    }

    private var flowLayoutSteps: some View {
        let steps = twoSpectators ? twoSpectatorFlowSteps : oneSpectatorFlowSteps
        let active = twoSpectators ? test.phase.twoSpectatorStep : test.phase.step
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(steps, id: \.index) { step in
                    stepChip(step, activeStep: active)
                }
            }
        }
    }

    private var oneSpectatorFlowSteps: [(index: Int, title: String, detail: String?)] {
        [
            (1, "Ringtone", ringtone.title),
            (2, "Hand", test.handDetectedAfter.map { String(format: "%.1fs", $0) }),
            (3, "Static", preset.title),
            (4, "Song", resolvedSongTitle(for: 1)),
        ]
    }

    private var twoSpectatorFlowSteps: [(index: Int, title: String, detail: String?)] {
        [
            (1, "Ringtone", ringtone.title),
            (2, "Hand 1", test.handDetectedAfter.map { String(format: "%.1fs", $0) }),
            (3, "Song 1", resolvedSongTitle(for: 1)),
            (4, "Hand 2", test.secondHandDetectedAfter.map { String(format: "%.1fs", $0) }),
            (5, "Song 2", resolvedSongTitle(for: 2)),
        ]
    }

    private func resolvedSongTitle(for slot: Int) -> String? {
        if twoSpectators {
            return slotTrack(slot)?.title
        }
        return model.selected?.title
    }

    private func stepChip(_ step: (index: Int, title: String, detail: String?), activeStep: Int) -> some View {
        let done = activeStep > step.index
        let active = activeStep == step.index
        let tone: Color = done || active ? OracleTheme.gold : OracleTheme.textSecondary.opacity(0.75)
        return HStack(spacing: 4) {
            Text(step.title)
                .font(.caption2.weight(active ? .bold : .semibold))
            if let detail = step.detail, done || active {
                Text("· \(detail)")
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(active ? 0.1 : 0.04), in: Capsule())
        .overlay {
            Capsule().strokeBorder(active ? OracleTheme.gold.opacity(0.55) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title)\(step.detail.map { ", \($0)" } ?? "")")
    }

    private var statusTitle: String {
        switch test.phase {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .playingRingtone: return "Playing ringtone"
        case .handDetected: return twoSpectators ? "Hand 1 detected" : "Hand detected"
        case .interference: return "Interference"
        case .playingSong: return twoSpectators ? "Playing song 1" : "Playing song"
        case .secondHandDetected: return "Hand 2 detected"
        case .secondInterference: return "Interference 2"
        case .playingSecondSong: return "Playing song 2"
        case .error: return "Error"
        }
    }

    private var statusDetail: String {
        switch test.phase {
        case .idle:
            if let note = test.note { return note }
            return twoSpectators
                ? "Pick Song 1 and Song 2, choose a ringtone, then tap Play."
                : "Pick a song, choose a ringtone, then tap Play."
        case .starting:
            return "Loading sounds and opening the front camera."
        case .playingRingtone:
            return "Waiting for an open hand · fingers seen: \(test.fingersSeen)"
        case .handDetected:
            return "Camera off. Interference is coming in."
        case .interference:
            return twoSpectators
                ? "Static takes over the ringtone; song 1 comes through like a radio."
                : "Static takes over the ringtone; the song comes through like a radio."
        case .playingSong:
            guard twoSpectators else { return "Clean song preview. Tap Stop to reset." }
            if test.waitingForSecondHand {
                let wait = "Waiting for hand 2 · fingers seen: \(test.fingersSeen) / \(HandGestureDetector.requiredFingers)+"
                return test.note.map { "\($0) \(wait)" } ?? wait
            }
            return "Song 1 is clean. The camera comes back for hand 2 in a moment."
        case .secondHandDetected:
            return "Camera off. Interference 2 is coming in."
        case .secondInterference:
            return "Interference 2 takes over song 1; song 2 comes through like a radio."
        case .playingSecondSong:
            return "Clean song 2. Tap Stop to reset."
        case .error(let message):
            return message
        }
    }

    private var statusColor: Color {
        switch test.phase {
        case .idle, .starting: return OracleTheme.textSecondary
        case .error: return OracleTheme.danger
        case .playingSong, .playingSecondSong: return OracleTheme.sectionTeal
        default: return OracleTheme.gold
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
            .disabled(test.phase.isBusy || songsMissing)
            .opacity(test.phase.isBusy || songsMissing ? 0.45 : 1)
            .accessibilityHint(songsMissing ? "Pick Song 1 and Song 2 first" : "Starts the ringtone and the front camera")

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
