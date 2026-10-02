import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// MPVolumeView es pública, pero mover su UISlider interno por código no está documentado.
/// Tenerla en la jerarquía (casi invisible) también oculta el HUD de volumen del sistema.
final class SystemVolume {
    static let shared = SystemVolume()
    fileprivate weak var volumeView: MPVolumeView?

    /// Volumen multimedia que había antes del primer “subir al máximo” de la llamada.
    private var savedOutputVolume: Float?

    private var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    var isAttached: Bool { volumeView != nil }

    var outputVolume: Float { AVAudioSession.sharedInstance().outputVolume }

    /// Guarda el volumen actual (solo la primera vez) y lo sube al 100 %.
    func captureAndBoostToMaximum() {
        if savedOutputVolume == nil {
            savedOutputVolume = outputVolume
            dlog("SystemVolume: guardado volumen previo \(String(format: "%.2f", savedOutputVolume ?? 0))")
        }
        set(1.0, label: "máximo")
    }

    /// Vuelve al volumen guardado al terminar la llamada o al desarmar.
    func restoreSavedIfNeeded() {
        guard let saved = savedOutputVolume else { return }
        savedOutputVolume = nil
        set(saved, label: "restaurar")
    }

    func set(_ value: Float, label: String? = nil) {
        guard let slider else {
            dlog("SystemVolume: MPVolumeView no está en pantalla, no se puede fijar el volumen")
            return
        }
        let clamped = min(max(value, 0), 1)
        // El slider necesita un ciclo de runloop tras aparecer para aceptar valores.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            slider.value = clamped
            slider.sendActions(for: .valueChanged)
            let tag = label.map { " (\($0))" } ?? ""
            dlog("SystemVolume: volumen multimedia → \(String(format: "%.2f", clamped))\(tag)")
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
