import SwiftUI

struct HeroLogoView: View {
    var onTripleTap: (() -> Void)?

    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    private let size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(OracleTheme.deepIndigo.opacity(0.9))
                .frame(width: size * 2.2, height: size * 2.2)
                .blur(radius: 46)

            Circle()
                .fill(OracleTheme.deepPurple.opacity(0.7))
                .frame(width: size * 1.5, height: size * 1.5)
                .offset(x: size * 0.35, y: size * 0.1)
                .blur(radius: 40)

            Circle()
                .fill(OracleTheme.gold.opacity(0.22))
                .frame(width: size * 1.1, height: size * 1.1)
                .blur(radius: 30)

            // The PNG has a light margin outside its rounded square; scaling up and clipping crops it
            // so no halo or ring shows against the dark backdrop.
            Image("HeroLogo")
                .resizable()
                .scaledToFit()
                .scaleEffect(1.09)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 22, y: 12)
                .accessibilityLabel("Ringtone Oracle")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
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
