import PhotosUI
import SwiftUI

/// Premium home shell — hero, mode picker, song input, feedback, and a fixed Perform dock.
struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var queryFocused: Bool

    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.manual.rawValue

    @State private var photoItem: PhotosPickerItem?
    @State private var stageScreenshotGeneration = 0
    @State private var activeSheet: OracleSheet?
    @State private var homeAppeared = false
    @AppStorage("ui.performanceGuideOpened") private var performanceGuideOpened = false
    @State private var instructionsPulse = false

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: performanceModeRaw) ?? .fakeRingtone
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HeroLogoView(onTripleTap: { activeSheet = .debugLog })

                UnifiedPerformanceModeCard(
                    modeRaw: $performanceModeRaw,
                    photoItem: $photoItem,
                    stageScreenshotGeneration: stageScreenshotGeneration
                )

                HomePanel(accent: OracleTheme.indigo) {
                    SongInputStrip(
                        inputModeRaw: $inputModeRaw,
                        queryFocused: $queryFocused
                    )
                }

                HomePanel(accent: OracleTheme.indigo) {
                    SongLibraryPanel()
                }

                FeedbackCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .opacity(homeAppeared ? 1 : 0)
            .offset(y: homeAppeared ? 0 : 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.86)) {
                homeAppeared = true
            }
            if !performanceGuideOpened {
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    instructionsPulse = true
                }
            }
        }
        .background { OracleAnimatedBackdrop() }
        .overlay(alignment: .topTrailing) {
            instructionsButton
        }
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
        .alert("Can't start performance", isPresented: voicePreflightAlertPresented) {
            Button("OK", role: .cancel) { model.voiceOpenAIPreflightAlert = nil }
        } message: {
            Text(model.voiceOpenAIPreflightAlert ?? "")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .performanceGuide:
                NavigationStack {
                    PerformanceGuideSheet(
                        initialMode: mode,
                        onOpenFavorites: { activeSheet = .favoritesSetup }
                    )
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
            get: { model.voiceOpenAIPreflightAlert != nil },
            set: { if !$0 { model.voiceOpenAIPreflightAlert = nil } }
        )
    }

    private var instructionsButton: some View {
        Button {
            performanceGuideOpened = true
            instructionsPulse = false
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
                            .strokeBorder(OracleTheme.gold.opacity(instructionsPulse ? 0.95 : 0.35), lineWidth: 2)
                            .scaleEffect(instructionsPulse ? 1.12 : 1.0)
                            .opacity(instructionsPulse ? 0.85 : 0.35)
                    }
                }
            }
            .shadow(color: OracleTheme.gold.opacity(instructionsPulse ? 0.55 : 0.28), radius: instructionsPulse ? 14 : 8, y: 4)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                if !performanceGuideOpened {
                    Circle()
                        .fill(OracleTheme.coral)
                        .frame(width: 9, height: 9)
                        .offset(x: 4, y: -4)
                        .opacity(instructionsPulse ? 1 : 0.45)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.trailing, 14)
        .accessibilityLabel("Instructions — start here")
        .accessibilityHint("Opens performance mode instructions")
    }
}
