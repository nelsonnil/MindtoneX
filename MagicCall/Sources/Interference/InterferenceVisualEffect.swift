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

// MARK: - Perform / preview overlay (Metal ascent)

struct InterferenceStageRippleOverlay: View {
    var isMorphing: Bool
    var morphToken: Int
    var morphDuration: TimeInterval = InterferenceSettings.flashInterferenceDuration
    @AppStorage(StageImageStore.revisionDefaultsKey) private var stageScreenshotRevision = ""

    var body: some View {
        GeometryReader { geo in
            InterferenceStageRippleRepresentable(
                isMorphing: isMorphing,
                morphToken: morphToken,
                morphDuration: morphDuration,
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
    let morphDuration: TimeInterval
    let viewSize: CGSize
    let screenshotRevision: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StageProximityRippleHost {
        StageProximityRippleHost(frame: .zero)
    }

    func updateUIView(_ uiView: StageProximityRippleHost, context: Context) {
        let coordinator = context.coordinator
        if viewSize != coordinator.contentSize || screenshotRevision != coordinator.contentRevision {
            coordinator.contentSize = viewSize
            coordinator.contentRevision = screenshotRevision
            let image = InterferenceStageSnapshot.aspectFillCGImage(viewSize: viewSize)
            uiView.updateContent(image, isDark: InterferenceStageSnapshot.isDarkStageScreenshot())
        }

        uiView.morphDuration = morphDuration
        uiView.alpha = isMorphing ? 1 : 0
        if isMorphing, morphToken != coordinator.lastToken {
            uiView.beginMorph()
        } else if !isMorphing, coordinator.lastMorphing {
            uiView.endMorph()
        }
        coordinator.lastToken = morphToken
        coordinator.lastMorphing = isMorphing
    }

    static func dismantleUIView(_ uiView: StageProximityRippleHost, coordinator: Coordinator) {
        uiView.stopAndClear()
    }

    final class Coordinator {
        var contentSize: CGSize = .zero
        var contentRevision = ""
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

// MARK: - Flash interference stage preview

/// Opens straight into the ringtone on the stage screenshot; an open hand plays the flash clip with the
/// rising lens, then the picked song. No controls on screen besides a discreet Done.
struct FlashInterferenceStagePreviewSheet: View {
    let song: PreviewTrack
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
        ZStack(alignment: .topTrailing) {
            StageBackgroundView(maskStatusBar: maskStatusBar)
                .ignoresSafeArea()

            InterferenceStageRippleOverlay(
                isMorphing: test.phase.showsProximityRipple,
                morphToken: morphToken,
                morphDuration: InterferenceSettings.flashInterferenceDuration
            )
            .ignoresSafeArea()

            Button("Done") {
                test.stop()
                dismiss()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.55))
            .padding(14)

            if case .error(let message) = test.phase {
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .task {
            model.pauseVoiceAndAudioForSetupUI(reason: "flash stage preview")
            await test.play(model: model, ringtone: ringtone, overrideSong1: song, forcedMode: .flashInterference)
        }
        .onDisappear { test.stop() }
        .onChange(of: test.phase) { old, new in
            if new.showsProximityRipple, !old.showsProximityRipple { morphToken += 1 }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, test.phase.isBusy {
                test.stop(note: "Stopped because MindtoneX left the screen.")
            }
        }
    }
}
