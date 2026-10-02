import SwiftUI
import UIKit

enum OracleTheme {
    static let bgTop = Color(red: 0.05, green: 0.04, blue: 0.10)
    static let bgBottom = Color(red: 0.03, green: 0.03, blue: 0.05)

    static let ink = Color(red: 0.020, green: 0.020, blue: 0.035)
    static let midnight = Color(red: 0.055, green: 0.050, blue: 0.130)
    static let deepIndigo = Color(red: 0.110, green: 0.090, blue: 0.290)
    static let deepPurple = Color(red: 0.200, green: 0.080, blue: 0.300)

    static let cardFill = Color(red: 0.085, green: 0.080, blue: 0.120).opacity(0.78)
    static let cardBorder = Color.white.opacity(0.08)
    static let cardBorderHighlight = Color.white.opacity(0.16)

    /// #D4AF37
    static let gold = Color(red: 212 / 255, green: 175 / 255, blue: 55 / 255)
    static let goldLight = Color(red: 0.96, green: 0.84, blue: 0.43)
    static let indigo = Color(red: 0.42, green: 0.42, blue: 0.96)
    static let coral = Color(red: 0.98, green: 0.45, blue: 0.09)

    static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let textSecondary = Color(red: 0.62, green: 0.61, blue: 0.66)
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.23)

    static let cardRadius: CGFloat = 22
    static let dockRadius: CGFloat = 26

    static var goldGradient: LinearGradient {
        LinearGradient(colors: [gold, goldLight], startPoint: .leading, endPoint: .trailing)
    }

    static var warmGradient: LinearGradient {
        LinearGradient(colors: [coral, gold], startPoint: .leading, endPoint: .trailing)
    }

    static var screenGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static var cardStroke: LinearGradient {
        LinearGradient(colors: [cardBorderHighlight, cardBorder, Color.white.opacity(0.04)],
                       startPoint: .top, endPoint: .bottom)
    }

    static func performGradient(for mode: Prefs.PerformanceMode) -> LinearGradient {
        mode == .fakeRingtone ? goldGradient : warmGradient
    }

    // MARK: Home section identity (Mode · Song · Feedback · Advanced)

    static let sectionTeal = Color(red: 0.32, green: 0.78, blue: 0.72)
    static let sectionSlate = Color(red: 0.58, green: 0.54, blue: 0.72)

    // MARK: Adaptive label color

    /// WCAG relative luminance (0 = black, 1 = white).
    static func relativeLuminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Composites `fill` at `opacity` over `base`, then picks black or white text.
    /// 0.179 is where contrast against black equals contrast against white.
    static func adaptiveLabel(on fill: Color, opacity: Double = 1, over base: Color = bgBottom) -> Color {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        UIColor(fill).getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        UIColor(base).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let a = CGFloat(opacity) * fa
        let mixed = Color(red: Double(fr * a + br * (1 - a)),
                          green: Double(fg * a + bg * (1 - a)),
                          blue: Double(fb * a + bb * (1 - a)))
        return relativeLuminance(mixed) > 0.179 ? .black : .white
    }
}

/// Layered dark backdrop: multi-stop indigo → purple → black, soft glows behind the hero, and a vignette.
struct OracleBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: OracleTheme.midnight, location: 0),
                        .init(color: Color(red: 0.07, green: 0.045, blue: 0.14), location: 0.28),
                        .init(color: Color(red: 0.035, green: 0.030, blue: 0.065), location: 0.62),
                        .init(color: OracleTheme.ink, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Ellipse()
                    .fill(OracleTheme.deepIndigo.opacity(0.75))
                    .frame(width: w * 1.3, height: w * 0.9)
                    .blur(radius: 80)
                    .offset(x: -w * 0.18, y: -geo.size.height * 0.36)

                Ellipse()
                    .fill(OracleTheme.deepPurple.opacity(0.55))
                    .frame(width: w * 1.0, height: w * 0.8)
                    .blur(radius: 90)
                    .offset(x: w * 0.30, y: -geo.size.height * 0.30)

                Circle()
                    .fill(OracleTheme.gold.opacity(0.07))
                    .frame(width: w * 0.6)
                    .blur(radius: 70)
                    .offset(y: -geo.size.height * 0.34)

                RadialGradient(
                    colors: [.clear, .clear, Color.black.opacity(0.55)],
                    center: UnitPoint(x: 0.5, y: 0.32),
                    startRadius: 0,
                    endRadius: max(geo.size.height, w) * 0.85
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

/// Visual tier on the home screen — each block gets its own accent wash and rail.
enum OracleHomeSection {
    case mode
    case songInput
    case feedback
    case advanced

    var accent: Color {
        switch self {
        case .mode: OracleTheme.gold
        case .songInput: OracleTheme.indigo
        case .feedback: OracleTheme.sectionTeal
        case .advanced: OracleTheme.sectionSlate
        }
    }

    var fillWash: Color { accent.opacity(0.11) }

    var borderTint: Color { accent.opacity(0.28) }

    var shadowTint: Color { accent.opacity(0.12) }
}

private struct OracleSectionAccentKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var oracleSectionAccent: Color? {
        get { self[OracleSectionAccentKey.self] }
        set { self[OracleSectionAccentKey.self] = newValue }
    }
}

struct OracleCard<Content: View>: View {
    var section: OracleHomeSection?
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OracleTheme.cardRadius, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.35)
            }
            .background {
                ZStack(alignment: .top) {
                    OracleTheme.cardFill
                    if let section {
                        LinearGradient(
                            colors: [section.fillWash, section.fillWash.opacity(0.35), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(OracleTheme.cardStroke, lineWidth: 1)
            }
            .overlay {
                if let section {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [section.borderTint, OracleTheme.cardBorder, OracleTheme.cardBorder],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
            }
            .overlay(alignment: .leading) {
                if let section {
                    Capsule(style: .continuous)
                        .fill(section.accent.opacity(0.92))
                        .frame(width: 3.5)
                        .padding(.vertical, 14)
                        .padding(.leading, 1)
                }
            }
            .shadow(color: .black.opacity(0.40), radius: 18, y: 10)
            .shadow(color: section?.shadowTint ?? .clear, radius: 14, y: 6)
            .environment(\.oracleSectionAccent, section?.accent)
    }
}

/// Small uppercase caption used as a section label inside cards.
struct OracleEyebrow: View {
    let text: String
    @Environment(\.oracleSectionAccent) private var sectionAccent

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(sectionAccent ?? OracleTheme.textSecondary)
    }
}

struct OraclePerformButton: View {
    let title: String
    let gradient: LinearGradient
    let disabled: Bool
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text(title)
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
            }
            .shadow(color: OracleTheme.gold.opacity(disabled ? 0 : 0.28), radius: 14, y: 6)
            .scaleEffect(pressed ? 0.98 : 1)
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.12)) { pressed = false } }
        )
    }
}
