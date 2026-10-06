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
        static let boostSystemVolumeOnTrigger = "audio.boostSystemVolumeOnTrigger"
        static let boostMediaVolumeOnFakePerform = "audio.boostMediaVolumeOnFakePerform"
        static let fakePlaybackVolume = "audio.fakePlaybackVolume"

        static let attemptRingerMaxOnStage = "ringtone.attemptRingerMaxOnStage"

        static let autoTrigger = "trigger.autoOnCall"
        static let tapTrigger = "trigger.tap"
        static let volumeButtonTrigger = "trigger.volumeButton"
        static let diskCache = "songs.diskCache"
        static let deezerFallback = "songs.deezerFallback"
        static let storeCountry = "songs.storeCountry"

        static let maskStatusBar = "stage.maskStatusBar"
        /// `StageStatusBarContent` raw value — automatic luminance or forced icon style on stage.
        static let stageStatusBarContent = "stage.statusBarContent"

        static let darwinSignals = "probe.darwinSignals"
        static let toneIdentifierToTry = "probe.toneIdentifierToTry"
        static let callKitCallerName = "callkit.callerName"
        static let callKitDelay = "callkit.delay"

        static let autoStageRingtone = "ringtone.autoStageOnSearch"
        static let discreetRingtoneUI = "ringtone.discreetUI"
        static let ringtoneUseQuickLook = "ringtone.useQuickLook"

        static let performanceMode = "ui.performanceMode"
        /// When ON, present ringtone Share sheet as soon as the song locks during Perform.
        static let autoShareOnSongLock = "performance.autoShareOnSongLock"

        /// One-time bump of legacy `clipSeconds` (e.g. 10) to `RingtoneLimits.exportMaxSeconds`.
        static let clipSecondsMigratedToExportMax = "audio.clipSecondsMigratedToExportMax"
        static let performanceModeMigratedToSingle = "ui.performanceModeMigratedToSingle"
    }

    /// Home sections start collapsed on first install.
    static func registerHomeSectionDefaults() {
        d.register(defaults: [
            HomeSectionExpandKey.performance: false,
            HomeSectionExpandKey.songInput: false,
            HomeSectionExpandKey.wordApi: false,
            HomeSectionExpandKey.notesContact: false,
            HomeSectionExpandKey.feedback: false,
            HomeSectionExpandKey.library: false,
            HomeSectionExpandKey.performLog: false,
        ])
    }

    enum PerformanceMode: String, CaseIterable, Identifiable {
        case fakeRingtone
        case shareRingtone

        var id: String { rawValue }

        /// User-facing mode name (App Store–safe: no “fake”).
        var title: String {
            switch self {
            case .fakeRingtone: return "Stage Ringtone"
            case .shareRingtone: return "Phone Ringtone"
            }
        }

        /// Compact badge on the Perform bar.
        var shortBadge: String {
            switch self {
            case .fakeRingtone: return "STAGE"
            case .shareRingtone: return "PHONE"
            }
        }

        var tileSubtitle: String {
            switch self {
            case .fakeRingtone: return "Silent stage · volume control"
            case .shareRingtone: return "Install on iPhone · share sheet"
            }
        }

        static let modePickerSubtitle = "Stage plays in the app · Phone sets the real ringtone"
    }

    static func registerDefaults() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Key.noInterruptions: true,
            Key.mixWithOthers: false,
            Key.hotStandby: true,
            Key.clipSeconds: RingtoneLimits.defaultClipSeconds,
            Key.startOffset: 0.0,
            Key.loopClip: true,
            Key.stopOnAnswer: true,
            Key.forceMediaVolume: false,
            Key.mediaVolumeTarget: 0.8,
            Key.boostSystemVolumeOnTrigger: true,
            Key.boostMediaVolumeOnFakePerform: true,
            Key.fakePlaybackVolume: 1.0,
            Key.attemptRingerMaxOnStage: false,
            Key.autoTrigger: true,
            Key.tapTrigger: true,
            Key.volumeButtonTrigger: false,
            Key.diskCache: false,
            Key.deezerFallback: true,
            Key.storeCountry: "",
            Key.maskStatusBar: false,
            Key.stageStatusBarContent: StageStatusBarContent.automatic.rawValue,
            Key.darwinSignals: true,
            Key.toneIdentifierToTry: "system:Radar",
            Key.callKitCallerName: "Ana",
            Key.callKitDelay: 5.0,
            Key.autoStageRingtone: true,
            Key.discreetRingtoneUI: true,
            Key.ringtoneUseQuickLook: false,
            Key.performanceMode: PerformanceMode.fakeRingtone.rawValue,
            Key.autoShareOnSongLock: false,
        ])
        registerHomeSectionDefaults()
        NotesContactSettings.registerDefaults()
        NotesContactWordSettings.registerDefaults()
        migrateClipSecondsIfNeeded()
        migratePerformanceModeToSingleIfNeeded()
    }

    /// Former Phone Ringtone mode → single Performance + auto-share toggle.
    private static func migratePerformanceModeToSingleIfNeeded() {
        guard !d.bool(forKey: Key.performanceModeMigratedToSingle) else { return }
        let mode = PerformanceMode(rawValue: d.string(forKey: Key.performanceMode) ?? "") ?? .fakeRingtone
        if mode == .shareRingtone {
            d.set(true, forKey: Key.autoShareOnSongLock)
            d.set(PerformanceMode.fakeRingtone.rawValue, forKey: Key.performanceMode)
            dlog("Migración: Phone Ringtone → Performance + autoShareOnSongLock")
        }
        d.set(true, forKey: Key.performanceModeMigratedToSingle)
    }

    /// Bumps stored clip length below the iOS ringtone cap once (registerDefaults does not overwrite existing values).
    private static func migrateClipSecondsIfNeeded() {
        guard !d.bool(forKey: Key.clipSecondsMigratedToExportMax) else { return }
        let stored = d.object(forKey: Key.clipSeconds) != nil ? d.double(forKey: Key.clipSeconds) : RingtoneLimits.defaultClipSeconds
        if stored < RingtoneLimits.exportMaxSeconds {
            d.set(RingtoneLimits.exportMaxSeconds, forKey: Key.clipSeconds)
            dlog("Migración clip: \(String(format: "%.0f", stored)) s → \(Int(RingtoneLimits.exportMaxSeconds)) s")
        }
        d.set(true, forKey: Key.clipSecondsMigratedToExportMax)
    }

    static var autoStageRingtone: Bool { d.bool(forKey: Key.autoStageRingtone) }
    static var discreetRingtoneUI: Bool { d.bool(forKey: Key.discreetRingtoneUI) }
    static var ringtoneUseQuickLook: Bool { d.bool(forKey: Key.ringtoneUseQuickLook) }

    private static var d: UserDefaults { .standard }

    static var performanceMode: PerformanceMode {
        PerformanceMode(rawValue: d.string(forKey: Key.performanceMode) ?? "") ?? .fakeRingtone
    }

    static var autoShareOnSongLock: Bool { d.bool(forKey: Key.autoShareOnSongLock) }

    static var noInterruptions: Bool { d.bool(forKey: Key.noInterruptions) }
    static var mixWithOthers: Bool { d.bool(forKey: Key.mixWithOthers) }
    static var hotStandby: Bool { d.bool(forKey: Key.hotStandby) }
    static var clipSeconds: Double {
        let v = d.object(forKey: Key.clipSeconds) != nil ? d.double(forKey: Key.clipSeconds) : RingtoneLimits.defaultClipSeconds
        return min(max(v, RingtoneLimits.clipStepperMin), RingtoneLimits.clipStepperMax)
    }
    static var startOffset: Double { d.double(forKey: Key.startOffset) }
    static var loopClip: Bool { d.bool(forKey: Key.loopClip) }
    static var stopOnAnswer: Bool { d.bool(forKey: Key.stopOnAnswer) }
    static var forceMediaVolume: Bool { d.bool(forKey: Key.forceMediaVolume) }
    static var mediaVolumeTarget: Double { d.double(forKey: Key.mediaVolumeTarget) }
    static var boostSystemVolumeOnTrigger: Bool { d.bool(forKey: Key.boostSystemVolumeOnTrigger) }
    static var boostMediaVolumeOnFakePerform: Bool { d.bool(forKey: Key.boostMediaVolumeOnFakePerform) }
    static var fakePlaybackVolume: Double {
        let v = d.double(forKey: Key.fakePlaybackVolume)
        return v > 0 ? v : 1.0
    }
    static var attemptRingerMaxOnStage: Bool { d.bool(forKey: Key.attemptRingerMaxOnStage) }
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
            "forceVol=\(forceMediaVolume)(\(mediaVolumeTarget)) boostFakePerform=\(boostMediaVolumeOnFakePerform) boostOnTrigger=\(boostSystemVolumeOnTrigger)",
            "ringerMaxOnStage=\(attemptRingerMaxOnStage)",
            "diskCache=\(diskCache) deezer=\(deezerFallback) store=\(storeCountry.isEmpty ? "auto" : storeCountry)",
        ].joined(separator: " · ")
    }
}

/// iOS accepts custom ringtones only under ~30 s; export and defaults target the longest safe length.
enum RingtoneLimits {
    static let exportMaxSeconds: Double = 28
    static let defaultClipSeconds: Double = 28
    static let clipStepperMin: Double = 4
    static let clipStepperMax: Double = 30
}

/// Status bar icon/text color on the stage screenshot (not the bar tint).
enum StageStatusBarContent: String, CaseIterable, Identifiable {
    case automatic
    case dark
    case light

    var id: String { rawValue }

    /// Segmented control label (short).
    var segmentTitle: String {
        switch self {
        case .automatic: return "Auto"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var pickerSymbol: String {
        switch self {
        case .automatic: return "sparkles"
        case .dark: return "sun.max.fill"
        case .light: return "moon.stars.fill"
        }
    }

    var pickerHint: String {
        switch self {
        case .automatic: return "From screenshot"
        case .dark: return "Black icons"
        case .light: return "White icons"
        }
    }

    /// Accessibility / menu label.
    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .dark: return "Dark status bar"
        case .light: return "Light status bar"
        }
    }

    /// `true` → dark icons/text (for a light top area); `false` → light icons/text.
    @MainActor
    func prefersDarkContent(hasScreenshot: Bool) -> Bool {
        switch self {
        case .dark: return true
        case .light: return false
        case .automatic:
            guard hasScreenshot else { return false }
            return StageImageStore.wantsDarkStatusBarText()
        }
    }
}
