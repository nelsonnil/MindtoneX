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
            VStack(spacing: 16) {
                HeroLogoView {
                    activeSheet = .advanced
                }

                ModePickerCard(modeRaw: $performanceModeRaw)

                Group {
                    switch mode {
                    case .fakeRingtone:
                        FakeModeCard(
                            background: $background,
                            photoItem: $photoItem,
                            onInfo: { activeSheet = .fakeDetails }
                        )
                    case .shareRingtone:
                        ShareModeCard(
                            onInfo: { activeSheet = .shareDetails },
                            onFavoritesInfo: { activeSheet = .favoritesSetup }
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: performanceModeRaw)

                OracleCard {
                    SongInputStrip(
                        inputModeRaw: $inputModeRaw,
                        queryFocused: $queryFocused
                    )
                }

                AdvancedDisclosureCard { activeSheet = $0 }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { OracleBackdrop() }
        .overlay(alignment: .topTrailing) { guideButton }
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
            case .debugLog:
                NavigationStack { DebugLogView() }
            case .voiceSettings:
                NavigationStack { VoiceSettingsView() }
            case .voiceDebug:
                NavigationStack { VoiceDebugSheet() }
                    .presentationDetents([.large])
            case .apiSettings:
                ApiSettingsSheet()
            }
        }
    }

    private var guideButton: some View {
        Button {
            activeSheet = .guide
        } label: {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OracleTheme.gold)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(OracleTheme.cardBorderHighlight, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 4)
        .accessibilityLabel("User guide")
    }
}
