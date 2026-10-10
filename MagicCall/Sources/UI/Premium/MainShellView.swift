import PhotosUI
import SwiftUI

/// Premium home shell — hero, performance setup, song input, feedback, and a fixed Perform dock.
struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.card.rawValue

    @State private var photoItem: PhotosPickerItem?
    @State private var stageScreenshotGeneration = 0
    @State private var activeSheet: OracleSheet?
    @State private var homeAppeared = false
    @AppStorage("ui.performanceGuideOpened") private var performanceGuideOpened = false
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HeroLogoView(onTripleTap: { activeSheet = .debugLog })

                PerformanceCard(
                    photoItem: $photoItem,
                    stageScreenshotGeneration: stageScreenshotGeneration
                )

                SongInputStrip(inputModeRaw: $inputModeRaw)

                WordApiHomeCard()

                AlbumArtContactHomeCard()

                NotesContactHomeCard()

                FeedbackCard()

                SongLibrarySection()

                PerformUserLogCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .opacity(homeAppeared ? 1 : 0)
            .offset(y: homeAppeared ? 0 : 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if inputModeRaw == VoiceSettings.InputMode.manual.rawValue {
                inputModeRaw = VoiceSettings.InputMode.card.rawValue
            }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.86)) {
                homeAppeared = true
            }
        }
        .background { OracleAnimatedBackdrop(animated: OracleIdleDecorations.animated) }
        .overlay(alignment: .topTrailing) {
            if model.showsHomePerformSetupChrome {
                instructionsButton
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.showsHomePerformSetupChrome {
                PerformBottomBar()
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    StageImageStore.save(data)
                    stageScreenshotGeneration += 1
                    dlog("Stage background image saved (\(data.count / 1024) KB)")
                }
            }
        }
        .onChange(of: activeSheet) { _, sheet in
            if let sheet {
                model.pauseVoiceAndAudioForSetupUI(reason: "sheet \(sheet.id)")
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .setup {
                SongLibraryStore.shared.reloadFromDisk()
                SongLibraryStore.shared.logRecentDisplayMerge(context: "MainShell.setup")
            }
        }
        .alert("Can't start Perform", isPresented: voicePreflightAlertPresented) {
            Button("OK", role: .cancel) { model.voiceOpenAIPreflightAlert = nil }
        } message: {
            Text(model.voiceOpenAIPreflightAlert ?? "")
        }
        .sheet(isPresented: openAIMissingKeySheetPresented) {
            OpenAIMissingKeySheet()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .performanceGuide:
                NavigationStack {
                    PerformanceGuideSheet(onOpenFavorites: { activeSheet = .favoritesSetup })
                }
            case .shortcutsSetup:
                NavigationStack { ShortcutsSetupSheet() }
            case .favoritesSetup:
                NavigationStack { FavoritesSetupSheet() }
            case .debugLog:
                NavigationStack { DebugLogView() }
            case .apiSettings:
                ApiSettingsSheet()
            }
        }
    }

    private var voicePreflightAlertPresented: Binding<Bool> {
        Binding(
            get: { model.showsHomePerformSetupChrome && model.voiceOpenAIPreflightAlert != nil },
            set: { if !$0 { model.voiceOpenAIPreflightAlert = nil } }
        )
    }

    private var openAIMissingKeySheetPresented: Binding<Bool> {
        Binding(
            get: { model.showsHomePerformSetupChrome && model.openAIMissingKeySheet },
            set: { if !$0 { model.openAIMissingKeySheet = false } }
        )
    }

    private var instructionsButton: some View {
        Button {
            performanceGuideOpened = true
            activeSheet = .performanceGuide
        } label: {
            Image(systemName: "lightbulb.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.04))
                .frame(width: 44, height: 44)
            .background {
                ZStack {
                    Circle()
                        .fill(OracleTheme.goldGradient)
                    if !performanceGuideOpened {
                        Circle()
                            .strokeBorder(OracleTheme.gold.opacity(0.55), lineWidth: 2)
                            .opacity(0.75)
                    }
                }
            }
            .shadow(color: OracleTheme.gold.opacity(0.28), radius: 8, y: 4)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                if !performanceGuideOpened {
                    Circle()
                        .fill(OracleTheme.coral)
                        .frame(width: 9, height: 9)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.trailing, 14)
        .accessibilityLabel("Instructions — start here")
        .accessibilityHint("Opens performance instructions")
    }
}
