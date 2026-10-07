import SwiftUI
import UIKit

/// Teclado numérico al estilo app Teléfono de iOS (Keypad).
struct WordApiIOSPhoneDialView: View {
    @Binding var phoneDigits: String
    var onCancel: () -> Void
    var onCall: () -> Void
    var cancelEnabled: Bool

    private let keyBackground = Color(red: 0.22, green: 0.22, blue: 0.24)
    private let callGreen = Color(red: 0.20, green: 0.78, blue: 0.35)

    private struct KeySpec: Identifiable {
        let id: String
        let main: String
        let sub: String?
        let inserts: String?
    }

    private static let rows: [[KeySpec]] = [
        [
            KeySpec(id: "1", main: "1", sub: nil, inserts: "1"),
            KeySpec(id: "2", main: "2", sub: "ABC", inserts: "2"),
            KeySpec(id: "3", main: "3", sub: "DEF", inserts: "3"),
        ],
        [
            KeySpec(id: "4", main: "4", sub: "GHI", inserts: "4"),
            KeySpec(id: "5", main: "5", sub: "JKL", inserts: "5"),
            KeySpec(id: "6", main: "6", sub: "MNO", inserts: "6"),
        ],
        [
            KeySpec(id: "7", main: "7", sub: "PQRS", inserts: "7"),
            KeySpec(id: "8", main: "8", sub: "TUV", inserts: "8"),
            KeySpec(id: "9", main: "9", sub: "WXYZ", inserts: "9"),
        ],
        [
            KeySpec(id: "*", main: "*", sub: nil, inserts: "*"),
            KeySpec(id: "0", main: "0", sub: "+", inserts: "0"),
            KeySpec(id: "#", main: "#", sub: nil, inserts: "#"),
        ],
    ]

    var body: some View {
        GeometryReader { geo in
            let keySide = min(geo.size.width / 3.6, 84)
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                numberDisplay
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)

                Spacer(minLength: 16)

                VStack(spacing: 18) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 28) {
                            ForEach(row) { key in
                                dialKey(key, diameter: keySide)
                            }
                        }
                    }
                }

                Spacer(minLength: 22)

                HStack {
                    Spacer()
                    callButton(diameter: keySide)
                    Spacer()
                }
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            if cancelEnabled {
                Button("Cancelar", action: onCancel)
                    .font(.body)
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
            } else {
                Color.clear.frame(width: 72, height: 44)
            }
            Spacer()
        }
    }

    private var numberDisplay: some View {
        HStack(alignment: .center, spacing: 12) {
            Spacer(minLength: 44)
            Text(displayNumber)
                .font(.system(size: 36, weight: .light, design: .default))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button {
                deleteLast()
            } label: {
                Image(systemName: "delete.left.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(phoneDigits.isEmpty ? Color.clear : Color.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
            .disabled(phoneDigits.isEmpty)
            .accessibilityLabel("Borrar")
        }
    }

    private var displayNumber: String {
        let trimmed = phoneDigits.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return " " }
        let canonical = WordApiSettings.canonicalPhoneDigits(trimmed)
        if canonical.count >= 7 {
            return WordApiSettings.formatPhoneForDisplay(canonical)
        }
        return trimmed
    }

    private func dialKey(_ spec: KeySpec, diameter: CGFloat) -> some View {
        Button {
            append(spec.inserts ?? spec.main)
        } label: {
            ZStack {
                Circle()
                    .fill(keyBackground)
                    .frame(width: diameter, height: diameter)
                VStack(spacing: 1) {
                    Text(spec.main)
                        .font(.system(size: diameter * 0.42, weight: .light))
                        .foregroundStyle(.white)
                    if let sub = spec.sub {
                        Text(sub)
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.6)
                            .foregroundStyle(.white.opacity(0.95))
                            .offset(y: -2)
                    } else {
                        Spacer().frame(height: 12)
                    }
                }
                .offset(y: spec.sub == nil ? 0 : -2)
            }
        }
        .buttonStyle(DialKeyButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    if spec.id == "0" {
                        appendPlusPrefix()
                    }
                }
        )
        .accessibilityLabel(accessibilityLabel(for: spec))
    }

    private func callButton(diameter: CGFloat) -> some View {
        let size = diameter * 1.02
        let enabled = WordApiSettings.canonicalPhoneDigits(phoneDigits).count >= 7
        return Button(action: onCall) {
            ZStack {
                Circle()
                    .fill(callGreen.opacity(enabled ? 1 : 0.35))
                    .frame(width: size, height: size)
                Image(systemName: "phone.fill")
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-30))
            }
        }
        .disabled(!enabled)
        .accessibilityLabel("Llamar")
    }

    private func append(_ chunk: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        phoneDigits.append(contentsOf: chunk)
    }

    private func appendPlusPrefix() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !phoneDigits.hasPrefix("+") {
            phoneDigits = "+" + phoneDigits
        }
    }

    private func deleteLast() {
        guard !phoneDigits.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        phoneDigits.removeLast()
    }

    private func accessibilityLabel(for spec: KeySpec) -> String {
        if let sub = spec.sub, !sub.isEmpty {
            return "\(spec.main), \(sub.map(String.init).joined(separator: " "))"
        }
        return spec.main
    }
}

private struct DialKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
