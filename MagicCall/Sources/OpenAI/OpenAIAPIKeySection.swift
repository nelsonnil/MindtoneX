import SwiftUI

/// OpenAI API key field — single edit location (Performance settings). Uses `VoiceSettings` Keychain.
struct OpenAIAPIKeySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyDraft = ""
    @State private var savedKeyHint: String?
    @State private var connectionTesting = false
    @State private var connectionTestResult: (ok: Bool, text: String)?
    @State private var showHelpSheet = false

    private var effectiveAPIKeyForTest: String? {
        let draft = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty { return draft }
        return VoiceSettings.apiKey
    }

    private var showsOpenAISetupHints: Bool {
        !model.isPerformTrickUIActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("OpenAI API key")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.textPrimary)
                if showsOpenAISetupHints {
                    Button {
                        showHelpSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.body.weight(.medium))
                            .foregroundStyle(OracleTheme.gold.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How to set up OpenAI")
                }
                Spacer(minLength: 0)
            }

            if showsOpenAISetupHints {
                Text(OpenAIAPIKeyCopy.singleKeyHelper)
                    .font(.caption)
                    .foregroundStyle(OracleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                SecureField("sk-… paste key from platform.openai.com", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .submitLabel(.done)
                    .onSubmit { commitKeyDraft() }
                    .onChange(of: keyDraft) { _, _ in
                        connectionTestResult = nil
                    }

                if !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: commitKeyDraft) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(OracleTheme.gold)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save API key")
                }

                Button {
                    Task { await runConnectionTest() }
                } label: {
                    Group {
                        if connectionTesting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(OracleTheme.gold)
                        } else {
                            Text("Test")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(minWidth: 44)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(OracleTheme.gold)
                .disabled(connectionTesting || effectiveAPIKeyForTest == nil)
                .accessibilityLabel("Test OpenAI connection")
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if showsOpenAISetupHints, let connectionTestResult {
                Label(connectionTestResult.text, systemImage: connectionTestResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(connectionTestResult.ok ? OracleTheme.gold : OracleTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsOpenAISetupHints, let onFile = savedKeyHint ?? VoiceSettings.apiKeyOnFileLabel {
                HStack(spacing: 8) {
                    Label(onFile, systemImage: "key.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OracleTheme.textSecondary)
                    Spacer(minLength: 8)
                    Button("Remove key") {
                        VoiceSettings.saveAPIKey(nil)
                        keyDraft = ""
                        refreshKey()
                        connectionTestResult = nil
                        dlog("[OPENAI] token removed")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OracleTheme.coral.opacity(0.95))
                }
            }
        }
        .onAppear { refreshKey() }
        .sheet(isPresented: $showHelpSheet) {
            OpenAIHelpSheet()
        }
    }

    private func refreshKey() {
        savedKeyHint = VoiceSettings.apiKeyOnFileLabel
    }

    private func commitKeyDraft() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        VoiceSettings.saveAPIKey(trimmed)
        keyDraft = ""
        refreshKey()
        dlog("[OPENAI] token saved to Keychain (shared Voice + Camera)")
    }

    private func runConnectionTest() async {
        guard let key = effectiveAPIKeyForTest else {
            connectionTestResult = (false, "Paste your OpenAI API key, then tap Test.")
            return
        }
        connectionTesting = true
        connectionTestResult = nil
        defer { connectionTesting = false }

        if let error = await VoiceOpenAIPreflight.validate(apiKey: key) {
            connectionTestResult = (false, error)
        } else {
            connectionTestResult = (true, "Connected")
            if !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commitKeyDraft()
            }
        }
    }
}
