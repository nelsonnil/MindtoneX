import SwiftUI

/// Technical tuning opened from the home Advanced card — not a second copy of Song input, Mode, or Feedback.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue

    @AppStorage(Prefs.Key.noInterruptions) private var noInterruptions = true
    @AppStorage(Prefs.Key.mixWithOthers) private var mixWithOthers = false
    @AppStorage(Prefs.Key.hotStandby) private var hotStandby = true
    @AppStorage(Prefs.Key.clipSeconds) private var clipSeconds = 10.0
    @AppStorage(Prefs.Key.startOffset) private var startOffset = 0.0
    @AppStorage(Prefs.Key.loopClip) private var loopClip = true
    @AppStorage(Prefs.Key.stopOnAnswer) private var stopOnAnswer = true
    @AppStorage(Prefs.Key.forceMediaVolume) private var forceMediaVolume = false
    @AppStorage(Prefs.Key.mediaVolumeTarget) private var mediaVolumeTarget = 0.8
    @AppStorage(Prefs.Key.boostSystemVolumeOnTrigger) private var boostSystemVolumeOnTrigger = true
    @AppStorage(Prefs.Key.boostMediaVolumeOnFakePerform) private var boostMediaVolumeOnFakePerform = true

    @AppStorage(Prefs.Key.autoTrigger) private var autoTrigger = true
    @AppStorage(Prefs.Key.tapTrigger) private var tapTrigger = true
    @AppStorage(Prefs.Key.volumeButtonTrigger) private var volumeButtonTrigger = false

    @AppStorage(Prefs.Key.diskCache) private var diskCache = false
    @AppStorage(Prefs.Key.deezerFallback) private var deezerFallback = true
    @AppStorage(Prefs.Key.storeCountry) private var storeCountry = ""

    @AppStorage(Prefs.Key.autoStageRingtone) private var autoStageRingtone = true
    @AppStorage(Prefs.Key.discreetRingtoneUI) private var discreetRingtoneUI = true
    @AppStorage(Prefs.Key.ringtoneUseQuickLook) private var ringtoneUseQuickLook = false
    @AppStorage(SharePerformFlow.hapticOnShareKey) private var hapticOnShare = true

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: performanceModeRaw) ?? .fakeRingtone
    }

    var body: some View {
        Form {
            audioSection
            if mode == .fakeRingtone { triggerSection }
            if mode == .shareRingtone { shareRingtoneSection }
            previewsSection
        }
        .navigationTitle("Engine & lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var audioSection: some View {
        Section {
            Toggle("Reduce system alert interruptions", isOn: $noInterruptions)
            Toggle("Hot standby (play at volume 0 before call)", isOn: $hotStandby)
            Toggle("Mix with other audio", isOn: $mixWithOthers)
            Toggle("Loop song clip", isOn: $loopClip)
            Toggle("Stop when call is answered", isOn: $stopOnAnswer)
            Stepper("Clip length: \(Int(clipSeconds)) s", value: $clipSeconds, in: 4...30, step: 1)
            Stepper("Start at second \(Int(startOffset))", value: $startOffset, in: 0...25, step: 1)
            Toggle("Set media volume when entering stage", isOn: $forceMediaVolume)
            if forceMediaVolume {
                Slider(value: $mediaVolumeTarget, in: 0.3...1) { Text("Target volume") }
            }
            Toggle("Boost media volume when entering Stage Perform", isOn: $boostMediaVolumeOnFakePerform)
            Toggle("Boost media volume to max when song starts", isOn: $boostSystemVolumeOnTrigger)
        } header: {
            Text("Audio engine")
        } footer: {
            Text("Defaults work for most shows. Stage mode uses a hidden volume slider (best effort — not guaranteed with Bluetooth, Focus, or if the stage view isn’t mounted yet). Hot standby starts playback instantly when a call arrives.")
        }
    }

    private var triggerSection: some View {
        Section {
            Toggle("Auto-start on incoming call", isOn: $autoTrigger)
            Toggle("Tap screen to start/stop song", isOn: $tapTrigger)
            Toggle("Volume buttons to start/stop", isOn: $volumeButtonTrigger)
        } header: {
            Text("\(Prefs.PerformanceMode.fakeRingtone.title) triggers")
        } footer: {
            Text("Leave auto-start on for performances. Tap is a backup if detection fails.")
        }
    }

    private var previewsSection: some View {
        Section {
            Toggle("Deezer fallback previews", isOn: $deezerFallback)
            Toggle("Disk cache (testing only)", isOn: $diskCache)
            TextField("iTunes store country (empty = auto)", text: $storeCountry)
                .textInputAutocapitalization(.characters)
            Button("Clear preview caches") { Task { await model.previews.clearCaches() } }
        } header: {
            Text("Song previews (lab)")
        }
    }

    private var shareRingtoneSection: some View {
        Section {
            Toggle("Prepare ringtone file when song is ready", isOn: $autoStageRingtone)
            Toggle("Black flash before Share sheet", isOn: $discreetRingtoneUI)
            Toggle("Use Quick Look instead of Share", isOn: $ringtoneUseQuickLook)
            Toggle("Soft vibration when ringtone is added", isOn: $hapticOnShare)
        } header: {
            Text("\(Prefs.PerformanceMode.shareRingtone.title) export")
        } footer: {
            Text("iOS 26 opens Settings → Ringtone after “Use as Ringtone” — press Home once if needed.")
        }
    }

}
