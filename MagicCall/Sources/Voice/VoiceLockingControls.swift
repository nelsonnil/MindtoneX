import SwiftUI

/// Lock delay, minimum confidence and haptic — shown in the AI Voice song-input area (not Advanced).
struct VoiceLockingControls: View {
    @AppStorage(VoiceSettings.Key.lockDelay) private var lockDelay = VoiceSettings.defaultLockDelay
    @AppStorage(VoiceSettings.Key.minConfidence) private var minConfidence = VoiceSettings.defaultMinConfidence
    @AppStorage(VoiceSettings.Key.hapticOnLock) private var hapticOnLock = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OracleEyebrow(text: "Locking the song")

            Text("Each new song the AI hears restarts the countdown. Guesses below the minimum confidence are ignored.")
                .font(.caption)
                .foregroundStyle(OracleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                lockDelayRow
                rowDivider
                confidenceRow
                rowDivider
                hapticRow
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    private var rowDivider: some View {
        Divider().overlay(OracleTheme.cardBorder).padding(.leading, 14)
    }

    private var lockDelayRow: some View {
        HStack {
            Text("Lock after \(Int(lockDelay)) s without changes")
                .font(.subheadline)
                .foregroundStyle(OracleTheme.textPrimary)
            Spacer(minLength: 8)
            Stepper("", value: $lockDelay, in: 2...15, step: 1)
                .labelsHidden()
                .tint(OracleTheme.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var confidenceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Minimum confidence")
                    .font(.subheadline)
                    .foregroundStyle(OracleTheme.textPrimary)
                Spacer()
                Text(VoiceSongSession.percent(minConfidence))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(OracleTheme.gold)
            }
            Slider(value: $minConfidence, in: 0.3...0.9, step: 0.05)
                .tint(OracleTheme.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var hapticRow: some View {
        Toggle(isOn: $hapticOnLock) {
            Text("Soft vibration when the song locks")
                .font(.subheadline)
                .foregroundStyle(OracleTheme.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(OracleTheme.gold)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
