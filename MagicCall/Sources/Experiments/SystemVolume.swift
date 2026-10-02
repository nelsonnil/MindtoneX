import MediaPlayer
import SwiftUI
import UIKit

/// MPVolumeView es pública, pero mover su UISlider interno por código no está documentado.
/// Tenerla en la jerarquía (casi invisible) también oculta el HUD de volumen del sistema.
final class SystemVolume {
    static let shared = SystemVolume()
    fileprivate weak var volumeView: MPVolumeView?

    private var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    var isAttached: Bool { volumeView != nil }

    func set(_ value: Float) {
        guard let slider else {
            dlog("SystemVolume: MPVolumeView no está en pantalla, no se puede fijar el volumen")
            return
        }
        // El slider necesita un ciclo de runloop tras aparecer para aceptar valores.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            slider.value = value
            slider.sendActions(for: .valueChanged)
            dlog("SystemVolume: volumen multimedia → \(String(format: "%.2f", value))")
        }
    }
}

struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -200, y: -200, width: 10, height: 10))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        SystemVolume.shared.volumeView = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
