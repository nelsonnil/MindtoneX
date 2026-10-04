import PhotosUI
import SwiftUI

/// Premium home shell — hero, mode picker card, mode detail, song strip, Advanced card,
/// and a fixed bottom bar with the readiness strip and Perform.
struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var queryFocused: Bool

    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue
    @AppStorage(Prefs.Key.background) private var background = StageBackground.black.rawValue
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue

    @State private var photoItem: PhotosPickerItem?
    @State private var activeSheet: OracleSheet?

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: performanceModeRaw) ?? .fakeRingtone
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HeroLogoView()

                UnifiedPerformanceModeCard(
                    modeRaw: $performanceModeRaw,
                    background: $background,
                    photoItem: $photoItem,
                    onFakeInfo: { activeSheet = .fakeDetails },
                    onShareInfo: { activeSheet = .shareDetails },
                    onFavoritesInfo: { activeSheet = .favoritesSetup }
                )

                OracleCard(section: .songInput) {
                    SongInputStrip(
                        inputModeRaw: $inputModeRaw,
                        queryFocused: $queryFocused
                    )
                }

                // One Feedback block (vibration + status dot) — not separate cards.
                FeedbackCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { OracleBackdrop() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PerformBottomBar(mode: mode)
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    StageImageStore.save(data)
                    background = StageBackground.image.rawValue
                    dlog("Stage background image saved (\(data.count / 1024) KB)")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .fakeDetails:
                NavigationStack { FakeDetailSheet() }
            case .shareDetails:
                NavigationStack { ShareDetailSheet() }
            case .shortcutsSetup:
                NavigationStack { ShortcutsSetupSheet() }
            case .favoritesSetup:
                NavigationStack { FavoritesSetupSheet() }
            case .advanced:
                NavigationStack { SettingsView() }
            case .debugLog:
                NavigationStack { DebugLogView() }
            case .apiSettings:
                ApiSettingsSheet()
            }
        }
    }
}
