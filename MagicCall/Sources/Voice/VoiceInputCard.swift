import SwiftUI

struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            let normalized = CGFloat(min(1, max(0, (20 * log10(max(level, 0.0001)) + 60) / 60)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(normalized > 0.8 ? OracleTheme.coral : OracleTheme.gold)
                    .frame(width: geo.size.width * normalized)
                    .animation(.linear(duration: 0.1), value: normalized)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Microphone level")
    }
}
