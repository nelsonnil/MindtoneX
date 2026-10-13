import SwiftUI
import UIKit

// MARK: - Stage image (aspect fill, matches StageBackgroundView)

enum InterferenceStageSnapshot {
    @MainActor
    static func aspectFillCGImage(viewSize: CGSize) -> CGImage? {
        guard viewSize.width > 1, viewSize.height > 1 else { return nil }
        // 8-bit sRGB: wide-color (16-bit float) bitmaps make MTKTextureLoader fail and the lens never draws.
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.preferredRange = .standard
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: viewSize, format: format)
        let image = StageImageStore.load()
        let drawn = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: viewSize))
            guard let image else { return }
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

/// Each new `morphToken` starts one Proximity Rise; it plays to the end on its own unless `isActive` goes false.
struct InterferenceStageRippleOverlay: View {
    var isActive: Bool
    var morphToken: Int
    var riseDuration: TimeInterval = InterferenceSettings.flashInterferenceDuration
    @AppStorage(StageImageStore.revisionDefaultsKey) private var stageScreenshotRevision = ""

    var body: some View {
        GeometryReader { geo in
            InterferenceStageRippleRepresentable(
                isActive: isActive,
                morphToken: morphToken,
                riseDuration: riseDuration,
                viewSize: geo.size,
                screenshotRevision: stageScreenshotRevision
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct InterferenceStageRippleRepresentable: UIViewRepresentable {
    let isActive: Bool
    let morphToken: Int
    let riseDuration: TimeInterval
    let viewSize: CGSize
    let screenshotRevision: String

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.lastToken = morphToken
        return coordinator
    }

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

        uiView.riseDuration = riseDuration
        if !isActive {
            if uiView.isAnimating { uiView.stopAndClear() }
        } else if morphToken != coordinator.lastToken {
            uiView.beginMorph()
        }
        coordinator.lastToken = morphToken
    }

    static func dismantleUIView(_ uiView: StageProximityRippleHost, coordinator: Coordinator) {
        uiView.stopAndClear()
    }

    final class Coordinator {
        var contentSize: CGSize = .zero
        var contentRevision = ""
        var lastToken = 0
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
/// rising lens, then the song of this call. A tap hangs up and rings the next call (song 2 with two songs).
/// No controls on screen; two-finger swipe down returns to Settings.
struct FlashInterferenceStagePreviewSheet: View {
    let songs: [PreviewTrack]
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = false
    @AppStorage(InterferenceSettings.Key.ringtoneID) private var ringtoneID = InterferenceSettings.Ringtone.defaultValue.rawValue
    @StateObject private var test = InterferenceTestController()
    @State private var morphToken = 0
    @State private var callIndex = 0
    @State private var ringTask: Task<Void, Never>?

    private var ringtone: InterferenceSettings.Ringtone {
        InterferenceSettings.Ringtone(rawValue: ringtoneID) ?? .ringtone1
    }

    private func ring() {
        guard !songs.isEmpty else { return }
        // Call 1 carries song 2 too (second hand during song 1); later calls go straight to song 2.
        let song = songs[min(callIndex, songs.count - 1)]
        let inCallSecond = callIndex == 0 && songs.count > 1 ? songs[1] : nil
        ringTask?.cancel()
        ringTask = Task {
            await test.play(model: model, ringtone: ringtone, overrideSong1: song, overrideSong2: inCallSecond,
                            forcedMode: .flashInterference)
        }
    }

    /// Only once the song is playing (or the run ended): ringing and the flash itself are never cut by a tap.
    private func hangUpAndRingNext() {
        switch test.phase {
        case .playingSong, .playingSecondSong, .idle, .error: break
        default: return
        }
        test.stop()
        callIndex += 1
        ring()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            StageBackgroundView(maskStatusBar: maskStatusBar)
                .ignoresSafeArea()

            InterferenceStageRippleOverlay(
                isActive: test.phase.isBusy,
                morphToken: morphToken
            )
            .ignoresSafeArea()

            StageGestureLayer(
                peekHoldEnabled: false,
                onPeekVisibility: { _ in },
                onTwoFingerSwipeDown: {
                    ringTask?.cancel()
                    test.stop()
                    dismiss()
                },
                onSingleTap: hangUpAndRingNext
            )
            .ignoresSafeArea()

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
        .onAppear {
            model.pauseVoiceAndAudioForSetupUI(reason: "flash stage preview")
            ring()
        }
        .onDisappear {
            ringTask?.cancel()
            test.stop()
        }
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
