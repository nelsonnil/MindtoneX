import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// MPVolumeView es pública, pero mover su UISlider interno por código no está documentado.
/// Tenerla en la jerarquía (casi invisible) también oculta el HUD de volumen del sistema.
final class SystemVolume {
    static let shared = SystemVolume()

    /// Side buttons need room below 100 % / above 0 % so `outputVolume` KVO fires on the first press.
    static let cardScanHeadroomLevel: Float = 0.92
    /// After Unknown spectator outgoing call, nudge media to mid so **volume up** can scan (not stuck at max).
    static let postSpectatorCallScanLevel: Float = 0.50
    static let volumeCeilingThreshold: Float = 0.985
    static let volumeFloorThreshold: Float = 0.015

    fileprivate weak var volumeView: MPVolumeView?

    /// Volumen multimedia que había antes del primer “subir al máximo” de la llamada.
    private var savedOutputVolume: Float?
    /// Ignore side-button KVO briefly after we move the slider in code (headroom / boost).
    private var programmaticChangeUntil: CFTimeInterval = 0
    /// Last level written via `MPVolumeView` — used to ignore KVO echo after headroom / restore.
    private(set) var lastProgrammaticLevel: Float?

    var isProgrammaticVolumeChange: Bool {
        CACurrentMediaTime() < programmaticChangeUntil
    }

    /// True when the side buttons likely moved volume (not our slider or call/headroom echo).
    func isUserInitiatedHardwareChange(from old: Float, to new: Float) -> Bool {
        guard abs(new - old) > 0.001 else { return false }
        guard !isProgrammaticVolumeChange else { return false }
        if let baseline = lastProgrammaticLevel, abs(new - baseline) < 0.02, abs(old - baseline) < 0.02 {
            return false
        }
        return true
    }

    private var slider: UISlider? {
        volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    var isAttached: Bool { volumeView != nil }

    var outputVolume: Float { AVAudioSession.sharedInstance().outputVolume }

    var isAtMediaVolumeCeiling: Bool { outputVolume >= Self.volumeCeilingThreshold }
    var isAtMediaVolumeFloor: Bool { outputVolume <= Self.volumeFloorThreshold }

    /// After a card scan trigger, restore a level that still leaves headroom if the user was at 100 %.
    func levelForCardScanVolumeRevert(prePress: Float) -> Float {
        if prePress >= Self.volumeCeilingThreshold { return Self.cardScanHeadroomLevel }
        if prePress <= Self.volumeFloorThreshold { return Self.cardScanHeadroomLevel }
        return prePress
    }

    /// Guarda el volumen actual (solo la primera vez) y lo sube al 100 %.
    func captureAndBoostToMaximum(sliderRetries: Int = 5) {
        if savedOutputVolume == nil {
            savedOutputVolume = outputVolume
            dlog("SystemVolume: guardado volumen previo \(String(format: "%.2f", savedOutputVolume ?? 0))")
        }
        set(1.0, label: "máximo", sliderRetries: sliderRetries)
    }

    /// Vuelve al volumen guardado al terminar la llamada o al desarmar.
    func restoreSavedIfNeeded() {
        guard let saved = savedOutputVolume else { return }
        savedOutputVolume = nil
        set(saved, label: "restaurar")
    }

    /// iOS only emits `outputVolume` KVO when the level can change — nudge off 0 % / 100 % so side buttons work during Card scan.
    @discardableResult
    func ensureHeadroomForHardwareVolumeButtons(reason: String, sliderRetries: Int = 8) -> Bool {
        let v = outputVolume
        if v >= Self.volumeCeilingThreshold {
            dlog("[CARD] headroom · media at ceiling (\(String(format: "%.2f", v))) · nudging to \(String(format: "%.2f", Self.cardScanHeadroomLevel)) (\(reason))")
            set(Self.cardScanHeadroomLevel, label: "\(reason) headroom", sliderRetries: sliderRetries)
            return true
        }
        if v <= Self.volumeFloorThreshold {
            dlog("[CARD] headroom · media at floor (\(String(format: "%.2f", v))) · nudging to 0.08 (\(reason))")
            set(0.08, label: "\(reason) headroom", sliderRetries: sliderRetries)
            return true
        }
        dlog("[CARD] headroom · ok at \(String(format: "%.2f", v)) (\(reason))")
        return false
    }

    func set(_ value: Float, label: String? = nil, sliderRetries: Int = 0) {
        guard let slider else {
            if sliderRetries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.set(value, label: label, sliderRetries: sliderRetries - 1)
                }
            } else {
                dlog("SystemVolume: MPVolumeView slider unavailable (\(label ?? "set"))")
            }
            return
        }
        let clamped = min(max(value, 0), 1)
        // El slider necesita un ciclo de runloop tras aparecer para aceptar valores.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.lastProgrammaticLevel = clamped
            self.programmaticChangeUntil = CACurrentMediaTime() + 1.0
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

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        SystemVolume.shared.volumeView = uiView
    }
}
