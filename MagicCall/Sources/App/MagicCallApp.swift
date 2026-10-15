import SwiftUI

@main
struct MagicCallApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.phase {
                case .setup: SetupView()
                case .stage: StageView()
                }
            }
            // MPVolumeView must live in a window for programmatic media volume (Perform, interference test sheet, etc.).
            .background {
                HiddenVolumeView()
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
            .environmentObject(model)
            .environmentObject(DebugLog.shared)
            .onOpenURL { url in
                if PerformURLScheme.handle(url) { return }
                if !SilentShortcut.shared.handle(url) { dlog("Open URL ignored: \(url.absoluteString)") }
            }
            .fullScreenCover(isPresented: $model.showingDiscreetRingtonePrep) {
                RingtoneDisguiseView()
            }
            .fullScreenCover(isPresented: $model.wordSpectatorDialSheet, onDismiss: {
                if !WordApiContactPerformGate.awaitingOutgoingEnd {
                    WordApiContactPerformGate.cancelPendingPerform()
                }
                model.revertAutoPerformCoverIfIdle(reason: "dial dismissed")
            }) {
                WordApiSpectatorDialSheet()
                    .environmentObject(model)
            }
            .sheet(isPresented: $model.wordKnownContactPicker) {
                WordApiKnownContactPicker(
                    onPick: { model.handleKnownContactPicked($0) },
                    onCancel: { model.handleKnownContactPickerCancelled() }
                )
            }
            .onAppear {
                AppModel.setScreenAwakeWhileInForeground(true)
            }
            // Fires on cold launch too (scenePhase onChange does not report the initial `.active`).
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                model.tryAutoStartPerformOnOpen(reason: "app active")
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    AppModel.setScreenAwakeWhileInForeground(true)
                    model.refreshArmedState(reason: "scenePhase.active")
                case .background:
                    AppModel.setScreenAwakeWhileInForeground(false)
                    dlog("scenePhase → background")
                    model.pauseVoiceAndAudioForSetupUI(reason: "scenePhase.background")
                    model.maintainArmedInBackgroundIfNeeded()
                    model.prepareAutoPerformCoverForNextOpen()
                case .inactive:
                    AppModel.setScreenAwakeWhileInForeground(true)
                    dlog("[APP] scenePhase → inactive")
                    model.pauseVoiceAndAudioForSetupUI(reason: "scene inactive")
                    model.onSceneBecameInactive()
                @unknown default:
                    break
                }
            }
        }
    }
}
