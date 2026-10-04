import SwiftUI

/// Notes song-input settings shown in the song strip: when the written note is searched.
struct NotesInputControls: View {
    @AppStorage(NotesSettings.Key.idleSearchEnabled) private var idleSearchEnabled = true
    @AppStorage(NotesSettings.Key.idleDelay) private var idleDelay = NotesSettings.defaultIdleDelay
    @AppStorage(NotesSettings.Key.searchOnReturn) private var searchOnReturn = true
    @AppStorage(NotesSettings.Key.useAIPicker) private var useAIPicker = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Perform opens a blank white note. The spectator writes a song; Ringtone Oracle finds and loads it in the background, then the incoming call plays it.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            OracleEyebrow(text: "When to search")

            VStack(spacing: 0) {
                toggleRow("Search when typing stops", isOn: $idleSearchEnabled)
                if idleSearchEnabled {
                    rowDivider
                    idleDelayRow
                }
                rowDivider
                toggleRow("Search on Return", isOn: $searchOnReturn)
                rowDivider
                toggleRow("Interpret note with AI", detail: NotesSettings.aiPickerExplanation(isOn: useAIPicker),
                          isOn: $useAIPicker)
                    .disabled(VoiceSettings.apiKey == nil)
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }

            Text(footer)
                .font(.caption2)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.2), value: idleSearchEnabled)
    }

    private var footer: String {
        var parts = ["The checkmark always searches. Each new search replaces the last one until the call arrives; a call with nothing searched yet searches the note right away."]
        if VoiceSettings.apiKey == nil {
            parts.append("“Interpret note” needs a token (Voice → Connection); until then the note is searched exactly as typed.")
        }
        parts.append("Leave Perform: long-press the back button or swipe down with two fingers.")
        return parts.joined(separator: " ")
    }

    private var rowDivider: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 14)
    }

    private var idleDelayRow: some View {
        HStack {
            Text("After \(Self.format(idleDelay)) without typing")
                .font(.subheadline)
                .foregroundStyle(OracleTheme.textPrimary)
            Spacer(minLength: 8)
            Stepper("", value: $idleDelay, in: NotesSettings.idleDelayRange, step: 0.5)
                .labelsHidden()
                .tint(OracleTheme.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func toggleRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(OracleTheme.gold)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    static func format(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? "\(Int(seconds)) s" : String(format: "%.1f s", seconds)
    }
}
