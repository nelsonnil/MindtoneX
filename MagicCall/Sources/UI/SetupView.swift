import PhotosUI
import SwiftUI

/// Main TestFlight home — English, non-technical testers.
struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var queryFocused: Bool

    @AppStorage(Prefs.Key.performanceMode) private var performanceModeRaw = Prefs.PerformanceMode.fakeRingtone.rawValue
    @AppStorage(Prefs.Key.background) private var background = StageBackground.black.rawValue
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = true
    @AppStorage(Prefs.Key.hideStatusBar) private var hideStatusBar = false
    @AppStorage(Prefs.Key.darkStatusBarText) private var darkStatusBarText = false

    @State private var photoItem: PhotosPickerItem?
    @State private var isSharePerforming = false

    private var mode: Prefs.PerformanceMode {
        Prefs.PerformanceMode(rawValue: performanceModeRaw) ?? .fakeRingtone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    songSection
                    modePicker
                    POCBanner()
                    comingSoonSection

                    switch mode {
                    case .fakeRingtone:
                        fakeRingtoneContent
                    case .shareRingtone:
                        shareRingtoneContent
                    }

                    advancedLink
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MagicCall")
            .navigationBarTitleDisplayMode(.large)
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
        }
    }

    // MARK: Song

    private var songSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Song", systemImage: "music.note.list")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Title and artist, e.g. Bohemian Rhapsody Queen", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($queryFocused)
                    .onSubmit { Task { await model.search() } }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    queryFocused = false
                    Task { await model.search() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || model.loadState == .searching)
            }

            songStatusCard

            if !model.results.isEmpty {
                otherMatchesCard
            }
        }
    }

    @ViewBuilder
    private var songStatusCard: some View {
        Group {
            switch model.loadState {
            case .idle:
                Text("Search for a song to begin.")
                    .foregroundStyle(.secondary)
            case .searching:
                Label("Searching…", systemImage: "hourglass")
            case .downloading:
                Label("Downloading preview…", systemImage: "arrow.down.circle")
            case .ready:
                if let track = model.selected {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(track.title) — \(track.artist)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                        Text("\(track.source.rawValue) · \(model.timings)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(model.isAudible ? "Playing…" : "Preview 3 seconds") { model.audition() }
                            .buttonStyle(.bordered)
                            .disabled(model.isAudible)
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var otherMatchesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other matches")
                .font(.subheadline.weight(.semibold))
            ForEach(model.results.prefix(6)) { track in
                Button {
                    Task { await model.select(track) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .foregroundStyle(.primary)
                            Text("\(track.artist) · \(track.source.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if track == model.selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                if track.id != model.results.prefix(6).last?.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var modePicker: some View {
        Picker("Mode", selection: $performanceModeRaw) {
            ForEach(Prefs.PerformanceMode.allCases) { m in
                Text(m.title).tag(m.rawValue)
            }
        }
        .pickerStyle(.segmented)
    }

    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Future song input")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ComingSoonInputRow(title: "Voice recognition", icon: "mic.fill")
            ComingSoonInputRow(title: "Music API / library", icon: "link")
            ComingSoonInputRow(title: "AI song guess", icon: "brain.head.profile")
        }
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Fake Ringtone

    private var fakeRingtoneContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Fake Ringtone", icon: "theatermasks.fill", tint: .purple)

            Text("""
            Put your iPhone on **Silent**. When a real call arrives, the system ringtone stays quiet, but this app plays your song full volume. When the caller hangs up, the song stops — so it feels like the ringtone was the song all along.
            """)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            SilentModeIllustration()

            setupChecklist

            backgroundSection

            statusBarSection

            performFakeButton

            Text("On the black screen: stay in this app, keep the phone unlocked. Exit with a **two-finger hold** (1.5 s). Optional: triple-tap the top-left corner for the debug log.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var setupChecklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Before you perform")
                .font(.subheadline.weight(.semibold))
            checklistRow("Silent mode ON (real ringtone muted)")
            checklistRow("Settings → Apps → Phone → Incoming Calls: **Banner**")
            checklistRow("Silence Unknown Callers: **Off**")
            checklistRow("Focus / Do Not Disturb: **Off**")
            checklistRow("Bluetooth & AirPods: **Disconnected**")
            checklistRow("Media volume: **Up**")
            checklistRow("Stay in MagicCall, screen on & unlocked")
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stage background")
                .font(.subheadline.weight(.semibold))
            Picker("Background", selection: $background) {
                ForEach(StageBackground.allCases) { kind in
                    Text(kind.label).tag(kind.rawValue)
                }
            }
            .pickerStyle(.menu)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Load home screen screenshot", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("Tip: use a screenshot of your real Home Screen so the incoming call banner looks natural on top.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status bar (with screenshot)")
                .font(.subheadline.weight(.semibold))
            Toggle(isOn: $maskStatusBar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cover status bar in screenshot")
                    Text("Blurs the fake time/battery in your image so only the real status bar shows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $hideStatusBar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide status bar")
                    Text("Hides the system status bar entirely during the act.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: $darkStatusBarText) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dark status bar text")
                    Text("Use on light wallpapers so clock and icons stay readable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .toggleStyle(.switch)
    }

    private var performFakeButton: some View {
        Button {
            model.performFakeRingtone()
        } label: {
            Label("Perform", systemImage: "play.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.loadState != .ready)
    }

    // MARK: Share Ringtone

    private var shareRingtoneContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Share Ringtone", icon: "bell.badge.fill", tint: .orange)

            Text("""
            This sets your song as a **real iOS ringtone** (official “Use as Ringtone”). Turn **Silent OFF** and turn **ringer volume up**. After setup, one tap in the Share sheet is enough each performance.
            """)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ShareRingtoneFavoritesIllustration()

            VStack(alignment: .leading, spacing: 8) {
                Text("Ringer volume")
                    .font(.subheadline.weight(.semibold))
                Text("Settings → Sounds & Haptics → Ringtone & Alerts → enable **Change with Buttons**, then raise volume with the side buttons while the ringtone preview plays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if model.ringtoneStaged {
                Label("Ringtone file ready on device", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
            }

            Text("""
            **Show tip:** When you “look up your number” for the spectator, tap **Use as Ringtone** from Favorites — it’s fast and looks natural.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                isSharePerforming = true
                Task {
                    await model.performShareRingtone()
                    isSharePerforming = false
                }
            } label: {
                if isSharePerforming {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Label("Perform", systemImage: "square.and.arrow.up.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(model.loadState != .ready || isSharePerforming)

            Text("Perform exports the clip if needed, then opens Share automatically so you can tap Use as Ringtone.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var advancedLink: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack {
                Label("Advanced", systemImage: "gearshape.2.fill")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.title2.weight(.bold))
            .foregroundStyle(tint)
    }

    private func checklistRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.tint)
                .font(.caption)
                .padding(.top, 2)
            Text(.init(text))
                .font(.footnote)
        }
    }
}
