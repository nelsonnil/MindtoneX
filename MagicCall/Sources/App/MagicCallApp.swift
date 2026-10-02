import SwiftUI

@main
struct MagicCallApp: App {
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
        }
    }
}
