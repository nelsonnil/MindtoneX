import SwiftUI

struct HeroLogoView: View {
    var onTripleTap: (() -> Void)?

    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    private let size: CGFloat = 80

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathe = 1 + 0.04 * sin(t * 1.4)
            let orbit = t * 0.55

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(OracleTheme.deepIndigo.opacity(0.85))
                        .frame(width: size * 2.1 * breathe, height: size * 2.1 * breathe)
                        .blur(radius: 44)

                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    OracleTheme.gold.opacity(0.7),
                                    OracleTheme.indigo.opacity(0.4),
                                    OracleTheme.gold.opacity(0.15),
                                    OracleTheme.gold.opacity(0.7),
                                ],
                                center: .center
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: size * 1.35, height: size * 1.35)
                        .rotationEffect(.degrees(orbit * 28))
                        .opacity(0.85)

                    Circle()
                        .trim(from: 0, to: 0.42)
                        .stroke(OracleTheme.gold.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: size * 1.22, height: size * 1.22)
                        .rotationEffect(.degrees(-orbit * 42))

                    Image("HeroLogo")
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(1.09)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
                        .shadow(color: OracleTheme.gold.opacity(0.25), radius: 16, y: 8)
                        .shadow(color: .black.opacity(0.55), radius: 20, y: 12)
                        .accessibilityHidden(true)
                }
                .frame(height: size * 1.5)

                VStack(spacing: 6) {
                    Text("RingtoneX")
                        .font(OracleTheme.brandTitle())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [OracleTheme.textPrimary, OracleTheme.goldLight.opacity(0.95)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("LIVE PERFORMANCE CONTROL")
                        .font(OracleTheme.techLabel())
                        .tracking(2.2)
                        .foregroundStyle(OracleTheme.textSecondary.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RingtoneX")
        .onTapGesture {
            tapCount += 1
            tapResetTask?.cancel()
            tapResetTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { tapCount = 0 }
            }
            if tapCount >= 3 {
                tapCount = 0
                onTripleTap?()
            }
        }
    }
}
