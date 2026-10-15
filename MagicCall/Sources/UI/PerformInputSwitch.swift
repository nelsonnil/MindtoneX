import SwiftUI
import UIKit

/// Large invisible hold pad for switching song input during Perform.
/// Bottom-left on the stage; the same pad sits just above the keyboard on Notes.
enum PerformInputSwitchLayout {
    /// Bottom of the pad is the closest target for the thumb.
    static let modes: [VoiceSettings.InputMode] = [.notes, .card, .api, .aiVoice]
    /// Finger must travel this far after the hold before a release commits.
    static let commitTravel: CGFloat = 28

    static func pad(in size: CGSize, keyboardTop: CGFloat?) -> CGRect {
        let width = min(300, max(230, size.width * 0.70))
        let visibleBottom = min(size.height, keyboardTop ?? size.height)
        let available = visibleBottom - 12
        let height = min(380, max(0, available))
        return CGRect(x: 0, y: visibleBottom - height, width: width, height: height)
    }

    static func rowFrames(in pad: CGRect) -> [CGRect] {
        guard !modes.isEmpty, pad.height > 0 else { return [] }
        let rowHeight = pad.height / CGFloat(modes.count)
        return modes.indices.map { index in
            CGRect(
                x: pad.minX,
                y: pad.maxY - CGFloat(index + 1) * rowHeight,
                width: pad.width,
                height: rowHeight
            )
        }
    }

    static func mode(at point: CGPoint, pad: CGRect) -> VoiceSettings.InputMode? {
        guard point.x >= pad.minX - 20, point.x <= pad.maxX + 44 else { return nil }
        let frames = rowFrames(in: pad)
        if let index = frames.firstIndex(where: { point.y >= $0.minY && point.y < $0.maxY }) {
            return modes[index]
        }
        if point.y >= pad.maxY { return modes.first }
        if point.y < pad.minY { return modes.last }
        return nil
    }
}

struct PerformInputSwitchHost: View {
    @EnvironmentObject private var model: AppModel
    @State private var armed = false
    @State private var highlighted: VoiceSettings.InputMode?
    @State private var keyboardTop: CGFloat?

    var body: some View {
        ZStack {
            PerformInputSwitchInstaller(
                armed: $armed,
                highlighted: $highlighted,
                keyboardTop: $keyboardTop,
                onCommit: { model.switchPerformInput(to: $0) }
            )
            if armed {
                PerformInputSwitchRail(highlighted: highlighted, keyboardTop: keyboardTop)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.1), value: armed)
        .animation(.easeOut(duration: 0.08), value: highlighted)
    }
}

private struct PerformInputSwitchRail: View {
    @AppStorage(VoiceSettings.Key.inputMode) private var inputModeRaw = VoiceSettings.InputMode.card.rawValue
    let highlighted: VoiceSettings.InputMode?
    let keyboardTop: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let pad = PerformInputSwitchLayout.pad(in: UIScreen.main.bounds.size, keyboardTop: keyboardTop)
                .offsetBy(dx: -origin.x, dy: -origin.y)
            let frames = PerformInputSwitchLayout.rowFrames(in: pad)
            if frames.count == PerformInputSwitchLayout.modes.count {
                ForEach(Array(PerformInputSwitchLayout.modes.enumerated()), id: \.element.rawValue) { index, mode in
                    let frame = frames[index]
                    let selected = highlighted == mode
                    railButton(mode, selected: selected, isCurrent: inputModeRaw == mode.rawValue)
                        .frame(width: max(0, frame.width - 8), height: max(0, frame.height - 8))
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func railButton(_ mode: VoiceSettings.InputMode, selected: Bool, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mode.pickerSymbol)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 34)
            Text(mode.title)
                .font(.title2.weight(.bold))
            Spacer(minLength: 0)
            if isCurrent {
                Circle()
                    .fill(selected ? Color.black.opacity(0.45) : Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
            }
        }
        .foregroundStyle(selected ? Color.black : Color.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selected ? Color.white : Color.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0 : 0.38), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

private struct PerformInputSwitchInstaller: UIViewRepresentable {
    @Binding var armed: Bool
    @Binding var highlighted: VoiceSettings.InputMode?
    @Binding var keyboardTop: CGFloat?
    let onCommit: (VoiceSettings.InputMode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(armed: $armed, highlighted: $highlighted, keyboardTop: $keyboardTop, onCommit: onCommit)
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onMoveToWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.attach(to: view.window)
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.armed = $armed
        context.coordinator.highlighted = $highlighted
        context.coordinator.keyboardTop = $keyboardTop
        context.coordinator.onCommit = onCommit
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        uiView.onMoveToWindow = nil
        coordinator.detach()
    }

    final class AnchorView: UIView {
        var onMoveToWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveToWindow?(window)
        }
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var armed: Binding<Bool>
        var highlighted: Binding<VoiceSettings.InputMode?>
        var keyboardTop: Binding<CGFloat?>
        var onCommit: (VoiceSettings.InputMode) -> Void

        private var origin: CGPoint = .zero
        private var choice: VoiceSettings.InputMode?
        private weak var installedOn: UIWindow?
        private var press: UILongPressGestureRecognizer?
        private var keyboardObservers: [NSObjectProtocol] = []
        private let armHaptic = UIImpactFeedbackGenerator(style: .medium)
        private let tickHaptic = UISelectionFeedbackGenerator()
        private let cancelHaptic = UIImpactFeedbackGenerator(style: .soft)

        init(
            armed: Binding<Bool>,
            highlighted: Binding<VoiceSettings.InputMode?>,
            keyboardTop: Binding<CGFloat?>,
            onCommit: @escaping (VoiceSettings.InputMode) -> Void
        ) {
            self.armed = armed
            self.highlighted = highlighted
            self.keyboardTop = keyboardTop
            self.onCommit = onCommit
        }

        func attach(to window: UIWindow?) {
            guard installedOn !== window else { return }
            detachRecognizer()
            installedOn = window
            guard let window else { return }
            let press = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            press.minimumPressDuration = 0.2
            press.allowableMovement = 40
            press.cancelsTouchesInView = true
            press.delaysTouchesBegan = false
            press.delaysTouchesEnded = false
            press.delegate = self
            window.addGestureRecognizer(press)
            self.press = press
            if keyboardObservers.isEmpty {
                watchKeyboard()
            }
            armHaptic.prepare()
            tickHaptic.prepare()
        }

        func detach() {
            detachRecognizer()
            installedOn = nil
            for observer in keyboardObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            keyboardObservers.removeAll()
        }

        private func detachRecognizer() {
            if let installedOn, let press {
                installedOn.removeGestureRecognizer(press)
            }
            press = nil
        }

        private func watchKeyboard() {
            let center = NotificationCenter.default
            keyboardObservers.append(center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                self?.applyKeyboard(note)
            })
            keyboardObservers.append(center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.keyboardTop.wrappedValue = nil
            })
        }

        private func applyKeyboard(_ note: Notification) {
            guard installedOn != nil,
                  let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else { return }
            let screenHeight = UIScreen.main.bounds.height
            keyboardTop.wrappedValue = frame.minY >= screenHeight - 1 ? nil : frame.minY
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let window = gestureRecognizer.view as? UIWindow else { return false }
            let point = Self.screenPoint(of: gestureRecognizer, in: window)
            let pad = PerformInputSwitchLayout.pad(in: UIScreen.main.bounds.size, keyboardTop: keyboardTop.wrappedValue)
            return pad.contains(point)
        }

        private static func screenPoint(of recognizer: UIGestureRecognizer, in window: UIWindow) -> CGPoint {
            window.convert(recognizer.location(in: window), to: nil)
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard let window = recognizer.view as? UIWindow else { return }
            let point = Self.screenPoint(of: recognizer, in: window)
            let pad = PerformInputSwitchLayout.pad(in: UIScreen.main.bounds.size, keyboardTop: keyboardTop.wrappedValue)
            switch recognizer.state {
            case .began:
                origin = point
                choice = nil
                highlighted.wrappedValue = nil
                armed.wrappedValue = true
                armHaptic.impactOccurred()
                tickHaptic.prepare()
            case .changed:
                let travel = hypot(point.x - origin.x, point.y - origin.y)
                let next: VoiceSettings.InputMode? = travel >= PerformInputSwitchLayout.commitTravel
                    ? PerformInputSwitchLayout.mode(at: point, pad: pad)
                    : nil
                guard next != choice else { return }
                choice = next
                highlighted.wrappedValue = next
                if next != nil {
                    tickHaptic.selectionChanged()
                    tickHaptic.prepare()
                }
            case .ended:
                let next = choice
                clearRail()
                if let next {
                    onCommit(next)
                } else {
                    cancelHaptic.impactOccurred()
                }
            case .cancelled, .failed:
                clearRail()
            default:
                break
            }
        }

        private func clearRail() {
            choice = nil
            highlighted.wrappedValue = nil
            armed.wrappedValue = false
        }
    }
}
