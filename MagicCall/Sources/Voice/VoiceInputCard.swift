import SwiftUI

/// Setup-screen card for the AI Voice song input: explainer, live test and what the AI heard.
struct VoiceInputCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var voice = VoiceSongSession.shared
    @AppStorage(VoiceSettings.Key.lockDelay) private var lockDelay = VoiceSettings.defaultLockDelay
    @AppStorage(VoiceSettings.Key.engine) private var engineRaw = VoiceSettings.Engine.openAIRealtime.rawValue
    @State private var configured = VoiceSettings.isConfigured

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !configured {
                Label("Add your OpenAI API key in Voice settings — or choose Apple on-device (no key).",
                      systemImage: "key.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HowItWorksCard(title: "How AI Voice works", icon: "sparkles",
                           steps: PerformCopy.aiVoiceSteps(lockSeconds: Int(lockDelay)))

            testPanel

            NavigationLink {
                VoiceSettingsView()
            } label: {
                HStack {
                    Label("Voice settings", systemImage: "slider.horizontal.3")
                    Spacer()
                    Text((VoiceSettings.Engine(rawValue: engineRaw) ?? .openAIRealtime).title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .onAppear { configured = VoiceSettings.isConfigured }
        .onChange(of: engineRaw) { _, _ in configured = VoiceSettings.isConfigured }
    }

    // MARK: Test panel

    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Try it here")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusChip
            }
            Text("Talk like you would on stage. You’ll see what the app hears and which song the AI picks. Nothing is shown during Perform.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if voice.isActive {
                    Button(role: .destructive) {
                        voice.stopTest()
                    } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        model.clearSongForNextPerformance()
                        Task { await voice.start(context: .test) }
                    } label: {
                        Label("Start test", systemImage: "mic.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!configured)
                }
                if voice.hasContent && !voice.isActive {
                    Button {
                        model.resetVoicePerformance()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if voice.isActive {
                LevelMeter(level: voice.level)
            }

            if case .failed(let message) = voice.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            transcriptBox
            pickBox
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var statusChip: some View {
        let (text, color): (String, Color) = {
            switch voice.state {
            case .idle: return ("Off", .secondary)
            case .starting: return ("Starting…", .blue)
            case .listening: return ("Listening", .red)
            case .locked: return ("Locked", .green)
            case .failed: return ("Error", .orange)
            }
        }()
        Text(text)
            .font(.caption.weight(.semibold))
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
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if voice.lines.isEmpty {
                            Text(voice.isActive ? "Listening… say something." : "Nothing yet. Press Start test and talk.")
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(voice.lines) { line in
                            Text(line.text.isEmpty ? "…" : line.text)
                                .foregroundStyle(line.isFinal ? .primary : .secondary)
                                .italic(!line.isFinal)
                                .id(line.id)
                        }
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(minHeight: 60, maxHeight: 150)
                .onChange(of: voice.lines) { _, lines in
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var pickBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AI pick")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if voice.isThinking {
                    ProgressView().controlSize(.mini)
                    Text("Thinking…").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let pick = voice.lockedPick ?? voice.candidate {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pick.label)
                        .font(.subheadline.weight(.semibold))
                    Text("Confidence \(VoiceSongSession.percent(pick.confidence))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pick.reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    pickStatus
                }
            } else {
                Text("No song yet.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            if let error = voice.lastAIError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var pickStatus: some View {
        if voice.state == .locked {
            Label("Locked — listening stopped", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            switch voice.prep {
            case .preparing:
                Label("Finding and preparing the song…", systemImage: "arrow.down.circle")
                    .font(.caption)
            case .notFound:
                Label("Not found in previews — keep talking or try again", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .ready:
                if let deadline = voice.lockDeadline {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let left = max(0, Int(deadline.timeIntervalSince(context.date).rounded(.up)))
                        Label("Ready · locks in \(left) s unless they change their mind", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else {
                    Label("Ready", systemImage: "checkmark.circle")
                        .font(.caption)
                }
            case nil:
                EmptyView()
            }
        }
    }
}

struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let normalized = CGFloat(min(1, max(0, (20 * log10(max(level, 0.0001)) + 60) / 60)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(normalized > 0.8 ? Color.orange : Color.green)
                    .frame(width: geo.size.width * normalized)
                    .animation(.linear(duration: 0.1), value: normalized)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Microphone level")
    }
}
