import SwiftUI
import UIKit

// MARK: - Stage image (aspect fill, matches StageBackgroundView)

enum InterferenceStageSnapshot {
    @MainActor
    static func aspectFillCGImage(viewSize: CGSize) -> CGImage? {
        guard let image = StageImageStore.load(), viewSize.width > 1, viewSize.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: viewSize, format: format)
        let drawn = renderer.image { _ in
            let iw = image.size.width, ih = image.size.height
            let scale = max(viewSize.width / iw, viewSize.height / ih)
            let w = iw * scale, h = ih * scale
            image.draw(in: CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h))
        }
        return drawn.cgImage
    }

    @MainActor
    static func isDarkStageScreenshot() -> Bool {
        (StageImageStore.statusBarLuminance() ?? 0) <= 0.179
    }
}

// MARK: - Perform / test overlay (Metal ascent)

struct InterferenceStageRippleOverlay: View {
    var isMorphing: Bool
    var morphToken: Int
    @AppStorage(StageImageStore.revisionDefaultsKey) private var stageScreenshotRevision = ""

    var body: some View {
        GeometryReader { geo in
            InterferenceStageRippleRepresentable(
                isMorphing: isMorphing,
                morphToken: morphToken,
                viewSize: geo.size,
                screenshotRevision: stageScreenshotRevision
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct InterferenceStageRippleRepresentable: UIViewRepresentable {
    let isMorphing: Bool
    let morphToken: Int
    let viewSize: CGSize
    let screenshotRevision: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StageProximityRippleHost {
        let view = StageProximityRippleHost(frame: .zero)
        context.coordinator.host = view
        return view
    }

    func updateUIView(_ uiView: StageProximityRippleHost, context: Context) {
        _ = screenshotRevision
        let image = InterferenceStageSnapshot.aspectFillCGImage(viewSize: viewSize)
        let isDark = MainActor.assumeIsolated { InterferenceStageSnapshot.isDarkStageScreenshot() }
        uiView.updateContent(image, isDark: isDark)

        uiView.alpha = isMorphing ? 1 : 0
        if morphToken != context.coordinator.lastToken {
            context.coordinator.lastToken = morphToken
            if isMorphing {
                uiView.beginMorph()
            }
        } else if isMorphing, context.coordinator.lastMorphing == false {
            uiView.beginMorph()
        } else if !isMorphing, context.coordinator.lastMorphing {
            uiView.endMorph()
        }
        context.coordinator.lastMorphing = isMorphing
    }

    static func dismantleUIView(_ uiView: StageProximityRippleHost, coordinator: Coordinator) {
        uiView.stopAndClear()
    }

    final class Coordinator {
        weak var host: StageProximityRippleHost?
        var lastToken = 0
        var lastMorphing = false
    }
}

extension InterferenceShowController.Phase {
    var showsProximityRipple: Bool {
        switch self {
        case .morph1, .morph2: return true
        default: return false
        }
    }
}

extension InterferenceTestController.Phase {
    var showsProximityRipple: Bool {
        switch self {
        case .handDetected, .interference, .secondHandDetected, .secondInterference: return true
        default: return false
        }
    }
}

// MARK: - Full-screen rehearsal (no Perform, no phone call)

struct InterferenceStageRehearsalSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = false
    @AppStorage(InterferenceSettings.Key.ringtoneID) private var ringtoneID = InterferenceSettings.Ringtone.defaultValue.rawValue
    @StateObject private var test = InterferenceTestController()
    @State private var morphToken = 0
    private var ringtone: InterferenceSettings.Ringtone {
        InterferenceSettings.Ringtone(rawValue: ringtoneID) ?? .ringtone1
    }

    var body: some View {
        ZStack {
            StageBackgroundView(maskStatusBar: maskStatusBar)
                .ignoresSafeArea()

            InterferenceStageRippleOverlay(
                isMorphing: test.phase.showsProximityRipple,
                morphToken: morphToken
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button("Done") {
                        test.stop()
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(12)
                }
                Spacer()
                rehearsalChrome
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            test.prefillSongs(model: model)
        }
        .onDisappear { test.stop() }
        .onChange(of: test.phase) { _, phase in
            if phase.showsProximityRipple {
                morphToken += 1
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, test.phase.isBusy {
                test.stop(note: "Stopped because MindtoneX left the screen.")
            }
        }
    }

    @ViewBuilder
    private var rehearsalChrome: some View {
        VStack(spacing: 10) {
            Text("Stage preview")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))
            Text(rehearsalDetail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            if test.phase == .idle || test.phase.isError {
                Button {
                    Task { await startRehearsal() }
                } label: {
                    Label("Start ringtone rehearsal", systemImage: "phone.arrow.down.left.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(OracleTheme.ink)
                        .background(OracleTheme.goldGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if test.phase.isBusy {
                Button {
                    test.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(OracleTheme.textPrimary)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rehearsalDetail: String {
        if case .error(let message) = test.phase {
            return message
        }
        switch test.phase {
        case .idle:
            return "Full stage wallpaper · ringtone · open hand · Proximity Rise (same Metal path as Cardphone). Uses your Home song\(SpectatorSettings.isTwo ? "s" : "") — set songs in **Test lab** first if needed."
        case .playingRingtone:
            return "Ringtone · hold an open hand above the front camera (green dot is normal)."
        case .handDetected, .interference:
            return "Interference morph · light rises toward Dynamic Island."
        case .playingSong:
            return test.waitingForSecondHand
                ? "Song 1 · waiting for hand 2 · fingers \(test.fingersSeen)+"
                : "Clean song 1."
        case .secondHandDetected, .secondInterference:
            return "Second interference morph · hand 2."
        case .playingSecondSong:
            return "Clean song 2."
        default:
            return "Starting…"
        }
    }

    private func startRehearsal() async {
        guard test.phase == .idle || test.phase.isError else { return }
        model.pauseVoiceAndAudioForSetupUI(reason: "stage rehearsal")
        await test.play(model: model, ringtone: ringtone)
    }
}

private extension InterferenceTestController.Phase {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// Legacy name — opens full rehearsal (replaces static-only preview).
typealias InterferenceStagePreviewSheet = InterferenceStageRehearsalSheet
