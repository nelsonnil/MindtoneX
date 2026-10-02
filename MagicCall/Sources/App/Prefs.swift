import Foundation

/// Todos los interruptores de experimento. Las vistas usan @AppStorage con las mismas claves.
enum Prefs {
    enum Key {
        static let noInterruptions = "audio.noInterruptionsFromSystemAlerts"
        static let mixWithOthers = "audio.mixWithOthers"
        static let hotStandby = "audio.hotStandby"
        static let clipSeconds = "audio.clipSeconds"
        static let startOffset = "audio.startOffset"
        static let loopClip = "audio.loopClip"
        static let stopOnAnswer = "audio.stopOnAnswer"
        static let forceMediaVolume = "audio.forceMediaVolume"
        static let mediaVolumeTarget = "audio.mediaVolumeTarget"

        static let autoTrigger = "trigger.autoOnCall"
        static let tapTrigger = "trigger.tap"
        static let volumeButtonTrigger = "trigger.volumeButton"

        static let diskCache = "songs.diskCache"
        static let deezerFallback = "songs.deezerFallback"
        static let storeCountry = "songs.storeCountry"

        static let background = "stage.background"
        static let maskStatusBar = "stage.maskStatusBar"
        static let hideStatusBar = "stage.hideStatusBar"
        static let darkStatusBarText = "stage.darkStatusBarText"

        static let darwinSignals = "probe.darwinSignals"
        static let toneIdentifierToTry = "probe.toneIdentifierToTry"
        static let callKitCallerName = "callkit.callerName"
        static let callKitDelay = "callkit.delay"

        static let autoStageRingtone = "ringtone.autoStageOnSearch"
        static let discreetRingtoneUI = "ringtone.discreetUI"
        static let ringtoneUseQuickLook = "ringtone.useQuickLook"
    }

    /// Archivo único reutilizado en cada actuación (≤30 s).
    static let stagedRingtoneFilename = "Actuacion.m4a"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.noInterruptions: true,
            Key.mixWithOthers: false,
            Key.hotStandby: true,
            Key.clipSeconds: 10.0,
            Key.startOffset: 0.0,
            Key.loopClip: true,
            Key.stopOnAnswer: true,
            Key.forceMediaVolume: false,
            Key.mediaVolumeTarget: 0.8,
            Key.autoTrigger: true,
            Key.tapTrigger: true,
            Key.volumeButtonTrigger: false,
            Key.diskCache: false,
            Key.deezerFallback: true,
            Key.storeCountry: "",
            Key.background: StageBackground.black.rawValue,
            Key.maskStatusBar: true,
            Key.hideStatusBar: false,
            Key.darkStatusBarText: false,
            Key.darwinSignals: true,
            Key.toneIdentifierToTry: "system:Radar",
            Key.callKitCallerName: "Ana",
            Key.callKitDelay: 5.0,
            Key.autoStageRingtone: true,
            Key.discreetRingtoneUI: true,
            Key.ringtoneUseQuickLook: false,
        ])
    }

    static var autoStageRingtone: Bool { d.bool(forKey: Key.autoStageRingtone) }
    static var discreetRingtoneUI: Bool { d.bool(forKey: Key.discreetRingtoneUI) }
    static var ringtoneUseQuickLook: Bool { d.bool(forKey: Key.ringtoneUseQuickLook) }

    private static var d: UserDefaults { .standard }

    static var noInterruptions: Bool { d.bool(forKey: Key.noInterruptions) }
    static var mixWithOthers: Bool { d.bool(forKey: Key.mixWithOthers) }
    static var hotStandby: Bool { d.bool(forKey: Key.hotStandby) }
    static var clipSeconds: Double { d.double(forKey: Key.clipSeconds) }
    static var startOffset: Double { d.double(forKey: Key.startOffset) }
    static var loopClip: Bool { d.bool(forKey: Key.loopClip) }
    static var stopOnAnswer: Bool { d.bool(forKey: Key.stopOnAnswer) }
    static var forceMediaVolume: Bool { d.bool(forKey: Key.forceMediaVolume) }
    static var mediaVolumeTarget: Double { d.double(forKey: Key.mediaVolumeTarget) }
    static var autoTrigger: Bool { d.bool(forKey: Key.autoTrigger) }
    static var tapTrigger: Bool { d.bool(forKey: Key.tapTrigger) }
    static var volumeButtonTrigger: Bool { d.bool(forKey: Key.volumeButtonTrigger) }
    static var diskCache: Bool { d.bool(forKey: Key.diskCache) }
    static var deezerFallback: Bool { d.bool(forKey: Key.deezerFallback) }
    static var storeCountry: String { d.string(forKey: Key.storeCountry) ?? "" }
    static var darwinSignals: Bool { d.bool(forKey: Key.darwinSignals) }
    static var toneIdentifierToTry: String { d.string(forKey: Key.toneIdentifierToTry) ?? "system:Radar" }
    static var callKitCallerName: String { d.string(forKey: Key.callKitCallerName) ?? "Ana" }
    static var callKitDelay: Double { d.double(forKey: Key.callKitDelay) }

    static func summary() -> String {
        [
            "noInterruptions=\(noInterruptions)",
            "mixWithOthers=\(mixWithOthers)",
            "hotStandby=\(hotStandby)",
            "clip=\(clipSeconds)s offset=\(startOffset)s loop=\(loopClip)",
            "stopOnAnswer=\(stopOnAnswer)",
            "auto=\(autoTrigger) tap=\(tapTrigger) volBtn=\(volumeButtonTrigger)",
            "forceVol=\(forceMediaVolume)(\(mediaVolumeTarget))",
            "diskCache=\(diskCache) deezer=\(deezerFallback) store=\(storeCountry.isEmpty ? "auto" : storeCountry)",
        ].joined(separator: " · ")
    }
}

enum StageBackground: String, CaseIterable, Identifiable {
    case black, gradient, image
    var id: String { rawValue }
    var label: String {
        switch self {
        case .black: return "Negro"
        case .gradient: return "Degradado oscuro"
        case .image: return "Imagen propia (p. ej. captura de tu pantalla de inicio)"
        }
    }
}
