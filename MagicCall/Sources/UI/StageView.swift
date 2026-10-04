import SwiftUI
import UIKit

/// Lo que ve el espectador: un fondo neutro a pantalla completa. Sin texto ni controles.
/// El banner real de llamada de iOS aparece encima de esto.
struct StageView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var notes = NotesSongSession.shared
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = false
    /// Observed so status bar style refreshes when a new screenshot is saved (luminance is recomputed in `StageImageStore.save`).
    @AppStorage(StageImageStore.luminanceDefaultsKey) private var stageStatusBarLuminance = 0.0
    @AppStorage(StageImageStore.revisionDefaultsKey) private var stageScreenshotRevision = ""
    @AppStorage(Prefs.Key.stageStatusBarContent) private var stageStatusBarContentRaw = StageStatusBarContent.automatic.rawValue

    private var hasStageScreenshot: Bool { StageImageStore.hasScreenshot }

    private var statusBarContentMode: StageStatusBarContent {
        StageStatusBarContent(rawValue: stageStatusBarContentRaw) ?? .automatic
    }

    /// Screenshot-only stage: status bar content from automatic luminance or user override.
    private var hidesStatusBarForStage: Bool { false }

    /// Dark status bar content = black icons/text; light content = white icons/text.
    private var prefersDarkStatusBarContent: Bool {
        _ = stageStatusBarLuminance
        _ = stageScreenshotRevision
        return statusBarContentMode.prefersDarkContent(hasScreenshot: hasStageScreenshot)
    }

    var body: some View {
        Group {
            if notes.isActive {
                NotesPerformView()
            } else {
                callStage
            }
        }
        .overlay(alignment: .topTrailing) { PerformStatusDot() }
    }

    private var callStage: some View {
        ZStack(alignment: .topLeading) {
            StageBackgroundView(maskStatusBar: maskStatusBar)
                .ignoresSafeArea()

            StageGestureLayer(
                onTap: {
                    if SharePerformFlow.shared.isActive {
                        SharePerformFlow.shared.handleTap()
                    } else if Prefs.tapTrigger {
                        model.toggleManual()
                    }
                },
                onLongPress: {
                    model.openFakeShareAfterCallIfNeeded()
                },
                onTwoFingerSwipeDown: { model.disarm() }
            )
            .ignoresSafeArea()

            HiddenVolumeView().frame(width: 1, height: 1)

            Color.clear
                .frame(width: 90, height: 90)
                .contentShape(Rectangle())
                .onTapGesture(count: 3) { model.showDebugOverlay.toggle() }
                .ignoresSafeArea()

            if model.showDebugOverlay {
                DebugOverlay().transition(.opacity)
            }
        }
        .background {
            StageStatusBarStyleController(useDarkContent: prefersDarkStatusBarContent)
        }
        .statusBarHidden(hidesStatusBarForStage)
        .preferredColorScheme(prefersDarkStatusBarContent ? .light : .dark)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.2), value: model.showDebugOverlay)
        .animation(.easeInOut(duration: 0.2), value: prefersDarkStatusBarContent)
    }
}

/// UIKit status bar style (more reliable than SwiftUI alone when global plist styles differ).
private struct StageStatusBarStyleController: UIViewControllerRepresentable {
    let useDarkContent: Bool

    func makeUIViewController(context: Context) -> Controller { Controller(useDarkContent: useDarkContent) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.useDarkContent = useDarkContent
        controller.setNeedsStatusBarAppearanceUpdate()
    }

    final class Controller: UIViewController {
        var useDarkContent: Bool
        init(useDarkContent: Bool) { self.useDarkContent = useDarkContent; super.init(nibName: nil, bundle: nil) }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override var preferredStatusBarStyle: UIStatusBarStyle {
            useDarkContent ? .darkContent : .lightContent
        }
    }
}

/// UIKit para tener un deslizamiento real con dos dedos; SwiftUI no distingue número de dedos.
struct StageGestureLayer: UIViewRepresentable {
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onTwoFingerSwipeDown: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLongPress: onLongPress) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.numberOfTouchesRequired = 1

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        longPress.minimumPressDuration = 0.55
        tap.require(toFail: longPress)

        let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeDown(_:)))
        swipe.numberOfTouchesRequired = 2
        swipe.direction = .down

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(swipe)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onTwoFingerSwipeDown = onTwoFingerSwipeDown
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void = {}
        var onLongPress: () -> Void = {}
        var onTwoFingerSwipeDown: () -> Void = {}
        private var didLongPress = false

        init(onLongPress: @escaping () -> Void) {
            self.onLongPress = onLongPress
        }

        @objc func tap() {
            guard !didLongPress else {
                didLongPress = false
                return
            }
            onTap()
        }

        @objc func longPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            didLongPress = true
            dlog("[STAGE] long-press on stage")
            onLongPress()
        }

        @objc func swipeDown(_ recognizer: UISwipeGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            dlog("[STAGE] two-finger swipe down → leave Perform")
            onTwoFingerSwipeDown()
        }
    }
}

@MainActor
enum StageImageStore {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stage-background.jpg")
    }

    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }

    static var hasScreenshot: Bool { load() != nil }

    static let luminanceDefaultsKey = "stage.statusBarLuminance"
    static let revisionDefaultsKey = "stage.screenshotRevision"
    private static let luminanceKey = luminanceDefaultsKey

    static func save(_ data: Data) {
        try? data.write(to: url, options: .atomic)
        UserDefaults.standard.removeObject(forKey: luminanceKey)
        if let image = UIImage(data: data) {
            let value = topLuminance(of: image)
            UserDefaults.standard.set(value, forKey: luminanceKey)
            dlog("Stage status bar luminance \(String(format: "%.3f", value)) → \(value > 0.179 ? "dark" : "light") content")
        }
        UserDefaults.standard.set(UUID().uuidString, forKey: revisionDefaultsKey)
    }

    /// Average luminance (0–1) of the screenshot strip behind the status bar; nil without an image.
    static func statusBarLuminance() -> Double? {
        if let cached = UserDefaults.standard.object(forKey: luminanceKey) as? Double { return cached }
        guard let image = load() else { return nil }
        let value = topLuminance(of: image)
        UserDefaults.standard.set(value, forKey: luminanceKey)
        return value
    }

    /// True when the status bar should use dark content (black icons/text on a light top region).
    static func wantsDarkStatusBarText() -> Bool {
        (statusBarLuminance() ?? 0) > 0.179
    }

    private static func cgImageNormalized(_ image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let drawn = renderer.image { _ in image.draw(at: .zero) }
        return drawn.cgImage
    }

    /// Top strip of the image as it appears behind the status bar after `scaledToFill` on the device screen.
    private static func topLuminance(of image: UIImage, fraction: CGFloat = 0.07) -> Double {
        guard let cg = cgImageNormalized(image) else { return 0 }
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let viewSize = UIScreen.main.bounds.size
        let fillScale = max(viewSize.width / iw, viewSize.height / ih)
        let offsetY = (ih * fillScale - viewSize.height) / 2
        // Nominal status bar height (pt); avoids MainActor-only `mcKeyWindow` in this nonisolated helper.
        let statusBarPoints = (59 + 4) / fillScale
        let yStart = max(0, min(ih - 1, offsetY / fillScale))
        let stripHeight = max(1, min(ih - yStart, max(statusBarPoints, ih * fraction)))
        guard let strip = cg.cropping(to: CGRect(x: 0, y: yStart, width: iw, height: stripHeight)) else { return 0 }

        let w = 24, h = 4
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(strip, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return 0 }

        func linear(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * linear(pixels[i]) + 0.7152 * linear(pixels[i + 1]) + 0.0722 * linear(pixels[i + 2])
        }
        return total / Double(w * h)
    }
}

struct StageBackgroundView: View {
    let maskStatusBar: Bool

    /// La vista ignora el área segura, así que se lee del window real.
    @MainActor
    static var statusBarHeight: CGFloat {
        UIApplication.mcKeyWindow?.safeAreaInsets.top ?? 59
    }

    var body: some View {
        if let image = StageImageStore.load() {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    // Optional: blur strip to hide a stale status bar baked into the screenshot (Advanced → off by default).
                    if maskStatusBar {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: 18)
                            .frame(height: Self.statusBarHeight + 6, alignment: .top)
                            .clipped()
                    }
                }
            }
        } else {
            StageScreenshotMissingView()
        }
    }
}

/// Shown only if Perform was entered without a saved screenshot (should be blocked in setup).
struct StageScreenshotMissingView: View {
    var body: some View {
        Color(white: 0.11)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle.weight(.medium))
                    Text("Stage screenshot missing")
                        .font(.subheadline.weight(.semibold))
                    Text("Leave Perform and choose a screenshot in Performance setup.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .foregroundStyle(Color.white.opacity(0.55))
            }
    }
}
