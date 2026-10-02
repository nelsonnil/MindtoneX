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
            .fullScreenCover(isPresented: $model.showingDiscreetRingtonePrep) {
                RingtoneDisguiseView()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.refreshArmedState(reason: "scenePhase.active")
                case .background:
                    dlog("scenePhase → background")
                    model.maintainArmedInBackgroundIfNeeded()
                case .inactive:
                    dlog("scenePhase → inactive")
                @unknown default:
                    break
                }
            }
        }
    }
}
