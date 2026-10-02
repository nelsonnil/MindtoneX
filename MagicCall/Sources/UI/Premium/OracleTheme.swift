import SwiftUI

enum OracleTheme {
    static let bgTop = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let bgBottom = Color(red: 0.07, green: 0.07, blue: 0.10)

    static let cardFill = Color(red: 0.11, green: 0.11, blue: 0.14).opacity(0.85)
    static let cardBorder = Color.white.opacity(0.08)

    static let gold = Color(red: 0.83, green: 0.69, blue: 0.22)
    static let goldLight = Color(red: 0.96, green: 0.84, blue: 0.43)
    static let indigo = Color(red: 0.39, green: 0.40, blue: 0.95)
    static let coral = Color(red: 0.98, green: 0.45, blue: 0.09)

    static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let textSecondary = Color(red: 0.60, green: 0.60, blue: 0.62)
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
}

struct OracleCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OracleTheme.cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: OracleTheme.cardRadius, style: .continuous)
                    .stroke(OracleTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: OracleTheme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
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
            .frame(height: 52)
            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.05))
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
