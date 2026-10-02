import SwiftUI

/// Single home-screen surface for AI Voice: API key, engine/models, locking, and live listen debug.
struct AiVoiceInputPanel: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared

    @AppStorage(VoiceSettings.Key.engine) private var engineRaw = VoiceSettings.Engine.openAIRealtime.rawValue
    @AppStorage(VoiceSettings.Key.transcribeModel) private var transcribeModel = VoiceSettings.transcribeModels[0].id
    @AppStorage(VoiceSettings.Key.pickerModel) private var pickerModel = VoiceSettings.pickerModels[0].id
    @AppStorage(VoiceSettings.Key.language) private var languageRaw = VoiceSettings.Language.spanishEnglish.rawValue

    @State private var keyDraft = ""
    @State private var savedKeyHint: String?
    @State private var showModels = false

    private var engine: VoiceSettings.Engine { VoiceSettings.Engine(rawValue: engineRaw) ?? .openAIRealtime }
    private var configured: Bool { VoiceSettings.isConfigured }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionBlock
            VoiceLockingControls()
            liveListenBlock
        }
        .onAppear(perform: refreshKey)
        .onChange(of: engineRaw) { _, _ in refreshKey() }
    }

    // MARK: Connection & key

    private var connectionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            OracleEyebrow(text: "Connection")

            VStack(spacing: 0) {
                pickerRow("Engine") {
                    Picker("Engine", selection: $engineRaw) {
                        ForEach(VoiceSettings.Engine.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .tint(OracleTheme.gold)
                }
                rowDivider
                pickerRow("Language") {
                    Picker("Language", selection: $languageRaw) {
                        ForEach(VoiceSettings.Language.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .tint(OracleTheme.gold)
                }
                rowDivider
                apiKeyRow
                if engine == .openAIRealtime {
                    rowDivider
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showModels.toggle() }
                    } label: {
                        HStack {
                            Text("AI models")
                                .font(.subheadline)
                                .foregroundStyle(OracleTheme.textPrimary)
                            Spacer()
                            Image(systemName: showModels ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OracleTheme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    if showModels {
                        rowDivider
                        pickerRow("Transcription") {
                            Picker("Transcription", selection: $transcribeModel) {
                                ForEach(VoiceSettings.transcribeModels) { Text($0.label).tag($0.id) }
                            }
                            .labelsHidden()
                            .tint(OracleTheme.gold)
                        }
                        rowDivider
                        pickerRow("Song picker") {
                            Picker("Song picker", selection: $pickerModel) {
                                ForEach(VoiceSettings.pickerModels) { Text($0.label).tag($0.id) }
                            }
                            .labelsHidden()
                            .tint(OracleTheme.gold)
                        }
                    }
                }
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }

            Text(engine.detail)
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
        }
    }

    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = savedKeyHint {
                HStack {
                    Label("Key saved (\(hint))", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.gold)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        VoiceSettings.saveAPIKey(nil)
                        refreshKey()
                        dlog("[VOICE] API key removed")
                    }
                    .font(.caption)
                }
            }
            SecureField(savedKeyHint == nil ? "OpenAI API key (sk-…)" : "Replace key", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button("Save key") {
                VoiceSettings.saveAPIKey(keyDraft)
                keyDraft = ""
                refreshKey()
                dlog("[VOICE] API key saved to Keychain")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(OracleTheme.gold)
            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Live listen (debug)

    private var liveListenBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                OracleEyebrow(text: "Live preview")
                Spacer()
                voiceStatusChip
            }
            Text("Talk like on stage. You’ll see what the app hears and which song the AI picks. Nothing is shown during Perform.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)

            livePreviewTestControls

            if !configured {
                Label("Add an API key above, or choose Apple on-device (no key).", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            if voice.isActive {
                LevelMeter(level: voice.level)
            }

            if case .failed(let message) = voice.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            }

            transcriptBox
            pickBox
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }

    private var livePreviewTestControls: some View {
        HStack(spacing: 10) {
            if voice.isActive {
                Button(role: .destructive) { voice.stopTest() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    model.clearSongForNextPerformance()
                    Task { await voice.start(context: .test) }
                } label: {
                    Label("Test", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(OracleTheme.indigo)
                .disabled(!configured)
            }
            if voice.hasContent && !voice.isActive {
                Button { model.resetVoicePerformance() } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var voiceStatusChip: some View {
        let (text, color): (String, Color) = {
            switch voice.state {
            case .idle: return ("Off", OracleTheme.textSecondary)
            case .starting: return ("Starting…", OracleTheme.indigo)
            case .listening: return ("Listening", OracleTheme.coral)
            case .locked: return ("Locked", OracleTheme.gold)
            case .failed: return ("Error", OracleTheme.coral)
            }
        }()
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var transcriptBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What it heard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.textSecondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if voice.lines.isEmpty {
                            Text(voice.isActive ? "Listening… say something." : "Nothing yet. Tap Test and talk.")
                                .foregroundStyle(OracleTheme.textSecondary.opacity(0.7))
                        }
                        ForEach(voice.lines) { line in
                            Text(line.text.isEmpty ? "…" : line.text)
                                .foregroundStyle(line.isFinal ? OracleTheme.textPrimary : OracleTheme.textSecondary)
                                .italic(!line.isFinal)
                                .id(line.id)
                        }
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(minHeight: 60, maxHeight: 140)
                .onChange(of: voice.lines) { _, lines in
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var pickBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI pick")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.textSecondary)
                if voice.isThinking {
                    ProgressView().controlSize(.mini)
                    Text("Thinking…").font(.caption2).foregroundStyle(OracleTheme.textSecondary)
                }
            }
            if let pick = voice.lockedPick ?? voice.candidate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pick.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Confidence \(VoiceSongSession.percent(pick.confidence))")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                    Text(pick.reasoning)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    pickStatus
                }
            } else {
                Text("No song yet.")
                    .font(.footnote)
                    .foregroundStyle(OracleTheme.textSecondary.opacity(0.7))
            }
            if let error = voice.lastAIError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(OracleTheme.coral)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var pickStatus: some View {
        if voice.state == .locked {
            Label("Locked — listening stopped", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.gold)
        } else {
            switch voice.prep {
            case .preparing:
                Label("Finding and preparing the song…", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
            case .notFound:
                Label("Not found in previews — keep talking or try again", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(OracleTheme.coral)
            case .ready:
                if let deadline = voice.lockDeadline {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let left = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                        Label("Ready · locks in \(left) s unless they change their mind", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.indigo)
                    }
                } else {
                    Label("Ready", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                }
            case nil:
                EmptyView()
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 14)
    }

    private func pickerRow<C: View>(_ title: String, @ViewBuilder picker: () -> C) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(OracleTheme.textPrimary)
            Spacer(minLength: 8)
            picker()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func refreshKey() {
        savedKeyHint = VoiceSettings.apiKey.map { "…" + String($0.suffix(4)) }
    }
}
