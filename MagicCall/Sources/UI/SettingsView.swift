import PhotosUI
import SwiftUI

/// Advanced options for testers who want full control and diagnostics.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

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

    @AppStorage(Prefs.Key.autoTrigger) private var autoTrigger = true
    @AppStorage(Prefs.Key.tapTrigger) private var tapTrigger = true
    @AppStorage(Prefs.Key.volumeButtonTrigger) private var volumeButtonTrigger = false

    @AppStorage(Prefs.Key.diskCache) private var diskCache = false
    @AppStorage(Prefs.Key.deezerFallback) private var deezerFallback = true
    @AppStorage(Prefs.Key.storeCountry) private var storeCountry = ""

    @AppStorage(Prefs.Key.darwinSignals) private var darwinSignals = true
    @AppStorage(Prefs.Key.toneIdentifierToTry) private var toneIdentifier = "system:Radar"
    @AppStorage(Prefs.Key.callKitCallerName) private var callKitCallerName = "Ana"
    @AppStorage(Prefs.Key.callKitDelay) private var callKitDelay = 5.0

    @AppStorage(Prefs.Key.autoStageRingtone) private var autoStageRingtone = true
    @AppStorage(Prefs.Key.discreetRingtoneUI) private var discreetRingtoneUI = true
    @AppStorage(Prefs.Key.ringtoneUseQuickLook) private var ringtoneUseQuickLook = false
    @AppStorage(Prefs.Key.attemptRingerMaxOnStage) private var attemptRingerMaxOnStage = false
    @AppStorage(SharePerformFlow.tapToHomeKey) private var tapToHome = true
    @AppStorage(SharePerformFlow.autoHomeKey) private var autoHome = true
    @AppStorage(SharePerformFlow.hapticOnShareKey) private var hapticOnShare = true

    @AppStorage(SilentShortcut.Key.silentOnEnabled) private var silentOnEnabled = false
    @AppStorage(SilentShortcut.Key.silentOffEnabled) private var silentOffEnabled = false
    @ObservedObject private var silentShortcut = SilentShortcut.shared

    @AppStorage(NotesSettings.Key.idleSearchEnabled) private var notesIdleSearch = true
    @AppStorage(NotesSettings.Key.idleDelay) private var notesIdleDelay = NotesSettings.defaultIdleDelay
    @AppStorage(NotesSettings.Key.searchOnReturn) private var notesSearchOnReturn = true
    @AppStorage(NotesSettings.Key.useAIPicker) private var notesUseAI = true
    @AppStorage(NotesSettings.Key.hapticOnReady) private var notesHaptic = false

    @State private var confirmToneChange = false

    var body: some View {
        Form {
            NavigationLink {
                DebugLogView()
            } label: {
                Label("Debug log", systemImage: "doc.text.magnifyingglass")
            }
            NavigationLink {
                VoiceSettingsView()
            } label: {
                Label("AI Voice settings", systemImage: "mic.badge.plus")
            }

            audioSection
            shortcutSection
            triggerSection
            notesSection
            previewsSection
            shareRingtoneSection
            privateSection
            callKitSection
        }
        .navigationTitle("Advanced")
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
            Toggle("Boost media volume to max when song starts", isOn: $boostSystemVolumeOnTrigger)
        } header: {
            Text("Audio engine")
        } footer: {
            Text("“Reduce system alert interruptions” maps to Apple’s prefersNoInterruptionsFromSystemAlerts — it asks iOS to let your audio continue when a call banner appears. Hot standby keeps the player running silently so playback starts instantly. Boost volume restores your previous level when the call ends.")
        }
    }

    private var shortcutSection: some View {
        Section {
            Toggle("Fake Ringtone: run “\(SilentShortcut.silentOnName)”", isOn: $silentOnEnabled)
            Button("Test silent shortcut (On)") { silentShortcut.test(mode: .fakeRingtone) }
            Toggle("Share Ringtone: run “\(SilentShortcut.silentOffName)”", isOn: $silentOffEnabled)
            Button("Test silent shortcut (Off)") { silentShortcut.test(mode: .shareRingtone) }
            if let result = silentShortcut.lastTestResult {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Silent Mode shortcuts")
        } footer: {
            Text("Perform opens Shortcuts (it flashes briefly) and comes back to Ringtone Oracle by itself. Turn these on after installing the shortcuts — see the setup card on the main screen.")
        }
    }

    private var triggerSection: some View {
        Section {
            Toggle("Auto-start on incoming call", isOn: $autoTrigger)
            Toggle("Tap screen to start/stop song", isOn: $tapTrigger)
            Toggle("Volume buttons to start/stop", isOn: $volumeButtonTrigger)
        } header: {
            Text("Fake Ringtone triggers")
        } footer: {
            Text("Auto-start uses CallKit call detection plus audio session signals. Leave on for performances. Tap is a backup if auto-start fails.")
        }
    }

    private var notesSection: some View {
        Section {
            Toggle("Search when typing stops", isOn: $notesIdleSearch)
            if notesIdleSearch {
                Stepper("Idle delay: \(NotesInputControls.format(notesIdleDelay))", value: $notesIdleDelay,
                        in: NotesSettings.idleDelayRange, step: 0.5)
            }
            Toggle("Search on Return", isOn: $notesSearchOnReturn)
            Toggle("Use AI to read the note", isOn: $notesUseAI)
                .disabled(VoiceSettings.apiKey == nil)
            Toggle("Soft vibration when the song is ready", isOn: $notesHaptic)
        } header: {
            Text("Notes input")
        } footer: {
            Text("Notes Perform shows a white note. After the idle delay (or Return, or the checkmark) the note is searched and the song is loaded in the background; the incoming call then plays it like AI Voice. With an OpenAI key the AI turns the note into “title artist”; otherwise the note is searched as written.")
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
            Text("Song previews")
        } footer: {
            Text("Previews are short clips for instant playback — not full tracks. Country code examples: US, ES, MX.")
        }
    }

    private var shareRingtoneSection: some View {
        Section {
            Toggle("Prepare ringtone file when song is ready", isOn: $autoStageRingtone)
            Toggle("Black flash before Share sheet", isOn: $discreetRingtoneUI)
            Toggle("Use Quick Look instead of Share", isOn: $ringtoneUseQuickLook)
            Toggle("Go Home via private API (tap black screen)", isOn: $tapToHome)
            Toggle("Go Home automatically after Use as Ringtone", isOn: $autoHome)
                .disabled(!tapToHome)
            Toggle("Soft vibration when ringtone is added", isOn: $hapticOnShare)
            if PrivateProbes.isCompiled {
                Toggle("Try private API: max ringer volume on export", isOn: $attemptRingerMaxOnStage)
            }
        } header: {
            Text("Share Ringtone export")
        } footer: {
            Text("Auto-prepare builds the .m4a in the background. Quick Look is an alternate path if “Use as Ringtone” doesn’t appear in Share. Going Home uses an undocumented iOS call (the same as pressing Home). With auto-Home on, the app tries to go Home 6 times in the 2 s after “Use as Ringtone”, but iOS 26 then opens Settings → Ringtone and no app can close it — press Home once. The black-screen tap stays as a backup.")
        }
    }

    private var privateSection: some View {
        Section {
            if PrivateProbes.isCompiled {
                Toggle("Log Darwin notifications at launch", isOn: $darwinSignals)
                Button("Run read-only private API probes") { model.runReadOnlyProbes() }
                TextField("Tone ID to try", text: $toneIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                privateWriteButtons
            } else {
                Text("Private experiments are disabled in TestFlight builds.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.probeResults) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(r.outcome.rawValue) · \(r.name)").font(.footnote.bold())
                    Text(r.detail).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        } header: {
            Text("Private API experiments")
        } footer: {
            Text("For engineering only. These call undocumented iOS APIs and usually fail without jailbreak. Results are copied to the debug log.")
        }
    }

    @ViewBuilder
    private var privateWriteButtons: some View {
        #if MAGIC_PRIVATE_PROBES
        Button("Try change default ringtone (ToneLibrary)") { confirmToneChange = true }
            .confirmationDialog("May change the system default ringtone. Restore afterward.",
                                isPresented: $confirmToneChange, titleVisibility: .visible) {
                Button("Try") { model.runToneSet() }
            }
        Button("Restore original ringtone") { model.runToneRestore() }
        Button("Try ringer volume 0") { model.runRingerVolume(0) }
        Button("Try ringer volume 50%") { model.runRingerVolume(0.5) }
        Button("Try ringer volume max (lab)") { model.runRingerVolumeMax() }
        #endif
    }

    private var callKitSection: some View {
        Section {
            TextField("Simulated caller name", text: $callKitCallerName)
            Stepper("Delay: \(Int(callKitDelay)) s", value: $callKitDelay, in: 2...30, step: 1)
            Button("Schedule fake CallKit call + enter stage") {
                model.scheduleCallKitFallback()
                model.performFakeRingtone()
            }
            .disabled(model.loadState != .ready)
        } header: {
            Text("CallKit fallback (not a real phone call)")
        } footer: {
            Text("Shows Apple’s fake incoming UI for comparison. Spectators will see the app name — not for real performances.")
        }
    }
}
