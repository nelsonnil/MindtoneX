import SwiftUI

struct HeroLogoView: View {
    var onTripleTap: (() -> Void)?

    @State private var tapCount = 0
    @State private var tapResetTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width * 0.42, geo.size.height)
            ZStack {
                RadialGradient(
                    colors: [OracleTheme.indigo.opacity(0.35), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: size * 0.9
                )
                .frame(width: size * 1.4, height: size * 1.1)
                .offset(y: -size * 0.08)

                Image("HeroLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .shadow(color: OracleTheme.gold.opacity(0.35), radius: 24, y: 8)
                    .accessibilityLabel("Ringtone Oracle")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 168)
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
