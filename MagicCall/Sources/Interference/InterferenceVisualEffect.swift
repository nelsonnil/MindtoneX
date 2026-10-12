import SwiftUI

/// Full-screen TV-static overlay on the stage screenshot during interference morph (Perform + previews).
struct InterferenceVisualEffect: View {
    /// 0 = hidden, 1 = full static (matches audio morph peak).
    var intensity: Double

    var body: some View {
        if intensity > 0.02 {
            TimelineView(.animation(minimumInterval: 1 / 12, paused: false)) { timeline in
                Canvas { context, size in
                    let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 12)
                    let block: CGFloat = 5
                    var y: CGFloat = 0
                    while y < size.height {
                        var x: CGFloat = 0
                        while x < size.width {
                            let ix = Int(x / block)
                            let iy = Int(y / block)
                            let hash = (ix &* 73856093) ^ (iy &* 19349663) ^ (tick &* 83492791)
                            let n = Double(abs(hash % 1000)) / 1000
                            let rect = CGRect(x: x, y: y, width: block, height: block)
                            context.fill(
                                Path(rect),
                                with: .color(Color(white: n, opacity: 0.08 + n * 0.28))
                            )
                            x += block
                        }
                        y += block
                    }
                }
            }
            .opacity(min(1, max(0, intensity)) * 0.92)
            .blendMode(.screen)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension InterferenceShowController.Phase {
    /// Stage overlay strength while the radio static is audible in Perform.
    var stageVisualIntensity: Double {
        switch self {
        case .morph1, .morph2: return 1
        default: return 0
        }
    }
}

extension InterferenceTestController.Phase {
    var stageVisualIntensity: Double {
        switch self {
        case .interference, .secondInterference: return 1
        default: return 0
        }
    }
}

/// What the spectator sees on the saved screenshot — static only, no peek or controls.
struct InterferenceStagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.Key.maskStatusBar) private var maskStatusBar = false
    @State private var demoIntensity: Double = 0
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            StageBackgroundView(maskStatusBar: maskStatusBar)
                .ignoresSafeArea()
            InterferenceVisualEffect(intensity: demoIntensity)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.25), value: demoIntensity)

            VStack(spacing: 16) {
                Spacer()
                Text("Stage preview")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Same wallpaper as Perform. Static appears during the interference morph — nothing else on screen for the audience.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 28)
                Button {
                    playMorphDemo()
                } label: {
                    Label("Play morph preview", systemImage: "waveform.path")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(OracleTheme.ink)
                        .background(OracleTheme.goldGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OracleTheme.gold)
                    .padding(.bottom, 24)
            }
        }
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onDisappear {
            demoTask?.cancel()
            demoIntensity = 0
        }
    }

    private func playMorphDemo() {
        demoTask?.cancel()
        demoTask = Task {
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.25)) { demoIntensity = 1 }
            }
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.7)) { demoIntensity = 0 }
            }
        }
    }
}
