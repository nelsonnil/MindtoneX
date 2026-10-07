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
            .environmentObject(model)
            .environmentObject(DebugLog.shared)
            .onOpenURL { url in
                if !SilentShortcut.shared.handle(url) { dlog("Open URL ignored: \(url.absoluteString)") }
            }
            .fullScreenCover(isPresented: $model.showingDiscreetRingtonePrep) {
                RingtoneDisguiseView()
            }
            .onAppear {
                AppModel.setScreenAwakeWhileInForeground(true)
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
