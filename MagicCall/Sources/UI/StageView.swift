import SwiftUI
import UIKit

/// Lo que ve el espectador: un fondo neutro a pantalla completa. Sin texto ni controles.
/// El banner real de llamada de iOS aparece encima de esto.
struct StageView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.Key.background) private var background = StageBackground.black.rawValue
    @AppStorage(Prefs.Key.hideStatusBar) private var hideStatusBar = false
    @AppStorage(Prefs.Key.darkStatusBarText) private var darkStatusBarText = false
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            StageBackgroundView(kind: StageBackground(rawValue: background) ?? .black,
                                maskStatusBar: maskStatusBar)
                .ignoresSafeArea()

            StageGestureLayer(
                onTap: { if Prefs.tapTrigger { model.toggleManual() } },
                onTwoFingerHold: { model.disarm() }
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

/// UIKit para tener un "mantener con dos dedos" real; SwiftUI no distingue número de dedos.
struct StageGestureLayer: UIViewRepresentable {
    let onTap: () -> Void
    let onTwoFingerHold: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.numberOfTouchesRequired = 1

        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.numberOfTouchesRequired = 2
        hold.minimumPressDuration = 1.5

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(hold)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onTwoFingerHold = onTwoFingerHold
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void = {}
        var onTwoFingerHold: () -> Void = {}

        @objc func tap() { onTap() }

        @objc func hold(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { onTwoFingerHold() }
        }
    }
}

enum StageImageStore {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stage-background.jpg")
    }

    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }

    static func save(_ data: Data) {
        try? data.write(to: url, options: .atomic)
    }
}

struct StageBackgroundView: View {
    let kind: StageBackground
    let maskStatusBar: Bool

    /// La vista ignora el área segura, así que se lee del window real.
    static var statusBarHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 59
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
