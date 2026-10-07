import SwiftUI

/// Animated incoming-call preview (compact banner layout): digits → spectator word — same caller ID on full-screen incoming UI.
struct WordApiIncomingCallBannerPreview: View {
    var phoneDigits: String
    var predictionWord: String

    private let cycle: TimeInterval = 5.2
    private let phoneHold: TimeInterval = 2.0
    private let morphDuration: TimeInterval = 0.55
    private let wordHold: TimeInterval = 2.05

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = cyclePhase(elapsed: t.truncatingRemainder(dividingBy: cycle))
                VStack(alignment: .leading, spacing: 8) {
                    banner(for: phase)
                        .frame(height: 78)
                    caption(for: phase)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview incoming call from phone number to prediction word, banner or full screen")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            PulsingLiveDot()
            Text("INCOMING CALL · LIVE PREVIEW")
                .font(OracleTheme.techLabel())
                .foregroundStyle(OracleTheme.gold.opacity(0.92))
            Spacer()
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OracleTheme.indigo.opacity(0.85))
                .symbolEffect(.pulse, options: .repeating)
        }
    }

    private func caption(for phase: CyclePhase) -> some View {
        Text(phase.caption)
            .font(.caption2)
            .foregroundStyle(OracleTheme.textSecondary)
            .animation(.easeInOut(duration: 0.25), value: phase.kind)
    }

    private func banner(for phase: CyclePhase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.11, blue: 0.16),
                            Color(red: 0.06, green: 0.06, blue: 0.09),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    OracleTheme.gold.opacity(0.35),
                                    Color.white.opacity(0.08),
                                    OracleTheme.indigo.opacity(0.25),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.45), radius: 16, y: 8)

            if phase.morphProgress > 0.02, phase.morphProgress < 0.98 {
                MorphScanLine(progress: phase.morphProgress)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            HStack(spacing: 12) {
                CallerAvatarRing(morph: phase.morphProgress, showingWord: phase.kind == .prediction)
                VStack(alignment: .leading, spacing: 3) {
                    ZStack(alignment: .leading) {
                        primaryLine(phoneDisplay, progress: phase.phoneOpacity, blur: phase.phoneBlur)
                        primaryLine(displayWord, progress: phase.wordOpacity, blur: phase.wordBlur)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, OracleTheme.goldLight.opacity(0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .frame(height: 26, alignment: .leading)

                    HStack(spacing: 6) {
                        Text(phase.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.55))
                        if phase.kind == .prediction {
                            TechChip(text: "PREDICTION")
                        } else {
                            TechChip(text: "NUMBER", tint: Color.white.opacity(0.35))
                        }
                    }
                }
                Spacer(minLength: 4)
                trailingIndicator(for: phase)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func primaryLine(_ text: String, progress: Double, blur: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .default))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .opacity(progress)
            .blur(radius: blur)
            .offset(y: (1 - progress) * 6)
    }

    @ViewBuilder
    private func trailingIndicator(for phase: CyclePhase) -> some View {
        if phase.kind == .prediction {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(OracleTheme.gold)
                .symbolEffect(.bounce, value: phase.wordOpacity > 0.9)
        } else {
            Image(systemName: "phone.arrow.down.left.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.green.opacity(0.9))
                .symbolEffect(.pulse, options: .repeating)
        }
    }

    private var phoneDisplay: String {
        Self.formatPhone(phoneDigits)
    }

    private var displayWord: String {
        let w = predictionWord.trimmingCharacters(in: .whitespacesAndNewlines)
        return w.isEmpty ? "ECLIPSE" : w.uppercased()
    }

    private func cyclePhase(elapsed: TimeInterval) -> CyclePhase {
        let morphStart = phoneHold
        let morphEnd = morphStart + morphDuration
        let wordEnd = morphEnd + wordHold

        if elapsed < morphStart {
            return CyclePhase(kind: .phoneNumber, morphProgress: 0, subtitle: "mobile · incoming")
        }
        if elapsed < morphEnd {
            let p = (elapsed - morphStart) / morphDuration
            return CyclePhase(kind: .morphing, morphProgress: p, subtitle: "MindtoneX · syncing caller ID")
        }
        if elapsed < wordEnd {
            return CyclePhase(kind: .prediction, morphProgress: 1, subtitle: "mobile · caller name")
        }
        let tail = (elapsed - wordEnd) / max(0.001, cycle - wordEnd)
        return CyclePhase(kind: .phoneNumber, morphProgress: 1 - tail, subtitle: "mobile · incoming")
    }

    static func formatPhone(_ raw: String) -> String {
        WordApiSettings.formatPhoneForDisplay(raw)
    }

    private struct CyclePhase: Equatable {
        enum Kind { case phoneNumber, morphing, prediction }
        let kind: Kind
        let morphProgress: Double
        let subtitle: String

        var phoneOpacity: Double {
            switch kind {
            case .phoneNumber: return 1
            case .morphing: return max(0, 1 - morphProgress * 1.15)
            case .prediction: return 0
            }
        }

        var wordOpacity: Double {
            switch kind {
            case .phoneNumber: return 0
            case .morphing: return min(1, morphProgress * 1.1)
            case .prediction: return 1
            }
        }

        var phoneBlur: CGFloat {
            kind == .morphing ? CGFloat(morphProgress * 4) : 0
        }

        var wordBlur: CGFloat {
            kind == .morphing ? CGFloat((1 - morphProgress) * 4) : 0
        }

        var caption: String {
            switch kind {
            case .phoneNumber:
                return "First phase — the dialed number as caller ID (banner or full-screen incoming UI)."
            case .morphing:
                return "When the word locks, Contacts + Call Directory swap the label in place."
            case .prediction:
                return "Locked spectator word as the incoming-call name — your reveal on caller ID."
            }
        }
    }
}

// MARK: - Subviews

private struct PulsingLiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 7, height: 7)
            .overlay {
                Circle()
                    .stroke(Color.red.opacity(0.45), lineWidth: 2)
                    .scaleEffect(pulse ? 1.8 : 1)
                    .opacity(pulse ? 0 : 0.8)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

private struct CallerAvatarRing: View {
    let morph: Double
    let showingWord: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: showingWord
                            ? [OracleTheme.gold, OracleTheme.goldLight]
                            : [Color.green.opacity(0.85), Color.green.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                }
            Image(systemName: showingWord ? "person.fill.checkmark" : "phone.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(showingWord ? OracleTheme.ink : .white)
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: showingWord)
        }
        .scaleEffect(1 + morph * 0.06)
    }
}

private struct TechChip: View {
    var text: String
    var tint: Color = OracleTheme.gold.opacity(0.85)

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
            }
    }
}

private struct MorphScanLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * progress
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, OracleTheme.gold.opacity(0.55), OracleTheme.indigo.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 56)
                .offset(x: x - 28)
                .blur(radius: 0.5)
        }
        .allowsHitTesting(false)
    }
}
