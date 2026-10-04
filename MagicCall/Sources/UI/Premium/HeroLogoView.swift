import SwiftUI

struct HeroLogoView: View {
    var onTripleTap: (() -> Void)?

    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    private let size: CGFloat = 76

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { context in
            let breathe = 1 + 0.035 * sin(context.date.timeIntervalSinceReferenceDate * 1.4)
            ZStack {
                Circle()
                    .fill(OracleTheme.deepIndigo.opacity(0.9))
                    .frame(width: size * 2.0 * breathe, height: size * 2.0 * breathe)
                    .blur(radius: 42)

                Circle()
                    .fill(OracleTheme.gold.opacity(0.18))
                    .frame(width: size * 1.05 * breathe, height: size * 1.05 * breathe)
                    .blur(radius: 26)

                Image("HeroLogo")
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(1.09)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
                    .accessibilityLabel("Ringtone Oracle")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .contentShape(Rectangle())
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
