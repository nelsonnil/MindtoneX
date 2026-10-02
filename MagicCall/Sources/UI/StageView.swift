import SwiftUI
import UIKit

/// Lo que ve el espectador: un fondo neutro a pantalla completa. Sin texto ni controles.
/// El banner real de llamada de iOS aparece encima de esto.
struct StageView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.Key.background) private var background = StageBackground.black.rawValue
    @AppStorage(Prefs.Key.hideStatusBar) private var hideStatusBar = false

    private var darkStatusBarText: Bool {
        StageBackground(rawValue: background) == .image && StageImageStore.wantsDarkStatusBarText()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            StageBackgroundView(kind: StageBackground(rawValue: background) ?? .black,
                                maskStatusBar: true)
                .ignoresSafeArea()

            StageGestureLayer(
                onTap: {
                    if SharePerformFlow.shared.isActive {
                        SharePerformFlow.shared.handleTap()
                    } else if Prefs.tapTrigger {
                        model.toggleManual()
                    }
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
        .statusBarHidden(hideStatusBar)
        .preferredColorScheme(darkStatusBarText ? .light : .dark)
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.2), value: model.showDebugOverlay)
    }
}

/// UIKit para tener un deslizamiento real con dos dedos; SwiftUI no distingue número de dedos.
struct StageGestureLayer: UIViewRepresentable {
    let onTap: () -> Void
    let onTwoFingerSwipeDown: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.numberOfTouchesRequired = 1

        let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeDown(_:)))
        swipe.numberOfTouchesRequired = 2
        swipe.direction = .down

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(swipe)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onTwoFingerSwipeDown = onTwoFingerSwipeDown
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void = {}
        var onTwoFingerSwipeDown: () -> Void = {}

        @objc func tap() { onTap() }

        @objc func swipeDown(_ recognizer: UISwipeGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            dlog("[STAGE] two-finger swipe down → leave Perform")
            onTwoFingerSwipeDown()
        }
    }
}

enum StageImageStore {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stage-background.jpg")
    }

    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }

    private static let luminanceKey = "stage.statusBarLuminance"

    static func save(_ data: Data) {
        try? data.write(to: url, options: .atomic)
        UserDefaults.standard.removeObject(forKey: luminanceKey)
        if let image = UIImage(data: data) {
            UserDefaults.standard.set(topLuminance(of: image), forKey: luminanceKey)
        }
    }

    /// Average luminance (0–1) of the screenshot strip behind the status bar; nil without an image.
    static func statusBarLuminance() -> Double? {
        if let cached = UserDefaults.standard.object(forKey: luminanceKey) as? Double { return cached }
        guard let image = load() else { return nil }
        let value = topLuminance(of: image)
        UserDefaults.standard.set(value, forKey: luminanceKey)
        return value
    }

    /// True when the status bar should use dark text. 0.179 is where black and white text have equal contrast.
    static func wantsDarkStatusBarText() -> Bool {
        (statusBarLuminance() ?? 0) > 0.179
    }

    private static func topLuminance(of image: UIImage, fraction: CGFloat = 0.07) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let stripHeight = max(1, CGFloat(cg.height) * fraction)
        guard let strip = cg.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: stripHeight)) else { return 0 }

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
        let value = total / Double(w * h)
        dlog("Stage status bar luminance \(String(format: "%.3f", value)) → \(value > 0.179 ? "dark" : "white") text")
        return value
    }
}

struct StageBackgroundView: View {
    let kind: StageBackground
    let maskStatusBar: Bool

    /// La vista ignora el área segura, así que se lee del window real.
    static var statusBarHeight: CGFloat {
        UIApplication.mcKeyWindow?.safeAreaInsets.top ?? 59
    }

    var body: some View {
        switch kind {
        case .black:
            Color.black
        case .gradient:
            LinearGradient(colors: [Color(white: 0.07), Color(white: 0.01)],
                           startPoint: .top, endPoint: .bottom)
        case .image:
            if let image = StageImageStore.load() {
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        // Una captura de pantalla incluye su propia barra de estado (hora vieja).
                        // La tapamos con una versión desenfocada para que solo se vea la real.
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
                Color.black
            }
        }
    }
}
