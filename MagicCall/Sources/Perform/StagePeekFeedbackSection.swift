import SwiftUI

/// Feedback card — hold-to-peek on stage (song / caller / notes lines).
struct StagePeekFeedbackSection: View {
    @AppStorage(PerformanceCues.PeekKey.enabled) private var peekEnabled = true
    @AppStorage(PerformanceCues.PeekKey.fontSize) private var fontSize = PerformanceCues.defaultPeekFontSize
    @AppStorage(PerformanceCues.PeekKey.color) private var colorHex = PerformanceCues.defaultPeekColor
    @AppStorage(PerformanceCues.PeekKey.anchorX) private var anchorX = PerformanceCues.defaultPeekAnchorX
    @AppStorage(PerformanceCues.PeekKey.anchorY) private var anchorY = PerformanceCues.defaultPeekAnchorY

    private var textColor: Binding<Color> {
        Binding(
            get: { Color(hex: colorHex) ?? .white },
            set: { colorHex = $0.hexString }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "eye.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OracleHomeSection.feedback.accent)
                    .frame(width: 36, height: 36)
                    .background(OracleHomeSection.feedback.accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hold-to-peek")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(OracleTheme.textPrimary)
                    Text("Keep your finger on the screen to see song, caller name, and Notes. Release to hide.")
                        .font(.caption2)
                        .foregroundStyle(OracleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Toggle("", isOn: $peekEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(OracleTheme.gold)
                    .fixedSize()
                    .accessibilityLabel("Hold-to-peek")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if peekEnabled {
                Divider().overlay(OracleTheme.cardBorder).padding(.leading, 14)
                VStack(alignment: .leading, spacing: 12) {
                    StagePeekLayoutPreview(
                        anchorX: $anchorX,
                        anchorY: $anchorY,
                        fontSize: $fontSize,
                        colorHex: $colorHex
                    )
                    HStack {
                        Text("Size \(Int(fontSize)) pt")
                            .font(.caption)
                            .foregroundStyle(OracleTheme.textSecondary)
                        Spacer()
                        Stepper("", value: $fontSize, in: PerformanceCues.peekFontSizeRange, step: 1)
                            .labelsHidden()
                            .tint(OracleTheme.gold)
                    }
                    HStack(spacing: 8) {
                        ColorPicker("", selection: textColor, supportsOpacity: true)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                        ForEach(PerformanceCues.colorPresets) { preset in
                            Button {
                                colorHex = preset.hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: preset.hex) ?? .clear)
                                    .frame(width: 22, height: 22)
                                    .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
                                    .overlay {
                                        Circle()
                                            .strokeBorder(OracleTheme.gold, lineWidth: colorHex.uppercased() == preset.hex ? 2 : 0)
                                            .padding(-2)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OracleTheme.cardBorder, lineWidth: 1)
        }
    }
}
