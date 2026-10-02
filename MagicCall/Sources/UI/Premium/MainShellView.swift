import PhotosUI
import SwiftUI

/// Premium home shell — hero, song strip, mode card, floating dock.
struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var queryFocused: Bool

    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue
    @AppStorage(Prefs.Key.background) private var background = StageBackground.black.rawValue
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = true
    @AppStorage(Prefs.Key.hideStatusBar) private var hideStatusBar = false
    @AppStorage(Prefs.Key.darkStatusBarText) private var darkStatusBarText = false
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue

    @State private var photoItem: PhotosPickerItem?
    @State private var activeSheet: OracleSheet?

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: performanceModeRaw) ?? .fakeRingtone
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OracleTheme.screenGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    HeroLogoView {
                        activeSheet = .advanced
                    }

                    OracleCard {
                        SongInputStrip(
                            inputModeRaw: $inputModeRaw,
                            queryFocused: $queryFocused
                        )
                    }

                    Group {
                        switch mode {
                        case .fakeRingtone:
                            FakeModeCard(
                                background: $background,
                                maskStatusBar: $maskStatusBar,
                                hideStatusBar: $hideStatusBar,
                                darkStatusBarText: $darkStatusBarText,
                                photoItem: $photoItem,
                                onInfo: { activeSheet = .fakeDetails },
                                onShortcutsSetup: { activeSheet = .shortcutsSetup }
                            )
                        case .shareRingtone:
                            ShareModeCard(
                                onInfo: { activeSheet = .shareDetails },
                                onShortcutsSetup: { activeSheet = .shortcutsSetup },
                                onFavoritesInfo: { activeSheet = .favoritesSetup }
                            )
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: performanceModeRaw)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }

            FloatingModeDock(modeRaw: $performanceModeRaw) {
                activeSheet = .guide
            }
            .padding(.bottom, 8)
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
            case .guide:
                GuideSheet()
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
            }
        }
    }
}
