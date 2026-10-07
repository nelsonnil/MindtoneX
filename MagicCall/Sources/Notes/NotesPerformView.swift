import SwiftUI
import UIKit

/// Notes Perform surface, a copy of G-Sensor `NotesView`: white sheet, round back button,
/// share/ellipsis capsule and a gold checkmark on top, one plain text view underneath.
/// The spectator writes; `NotesSongSession` looks the song up in the background.
struct NotesPerformView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var session = NotesSongSession.shared
    static let gold = Color(red: 0.91, green: 0.73, blue: 0.02)
    static let goldUIColor = UIColor(red: 0.91, green: 0.73, blue: 0.02, alpha: 1)

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                NotesNativeTextView(
                    text: session.text,
                    onChange: { session.textChanged($0) },
                    onReturn: { session.returnPressed() },
                    onTwoFingerSwipeDown: { model.disarm() }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            HiddenVolumeView().frame(width: 1, height: 1)

            if model.showDebugOverlay {
                DebugOverlay().transition(.opacity)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.2), value: model.showDebugOverlay)
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "chevron.left")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.black)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 0.45) {
                    dlog("[NOTES] long-press back → leave Perform")
                    model.disarm()
                }
                .accessibilityLabel("Back")

            Spacer()

            HStack(spacing: 18) {
                Button {} label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 23, weight: .regular))
                }
                Button {} label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 24, weight: .semibold))
                }
            }
            .foregroundColor(.black.opacity(0.62))
            .frame(width: 112, height: 50)
            .background(Capsule().fill(Color.white))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .simultaneousGesture(TapGesture(count: 3).onEnded { model.showDebugOverlay.toggle() })

            Button {
                session.donePressed()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Self.gold))
                    .shadow(color: Self.gold.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}

/// UITextView matching G-Sensor `NotesNativeTextView`: 22 pt black text, gold caret, no insets,
/// keyboard up 250 ms after appearing, re-focused on every update, no swipe-to-dismiss.
struct NotesNativeTextView: UIViewRepresentable {
    let text: String
    let onChange: (String) -> Void
    let onReturn: () -> Void
    let onTwoFingerSwipeDown: () -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.parent = self
        return coordinator
    }

    func makeUIView(context: Context) -> AutoFocusTextView {
        let view = AutoFocusTextView()
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 22, weight: .regular)
        view.textColor = .black
        view.tintColor = NotesPerformView.goldUIColor
        view.autocorrectionType = .yes
        view.spellCheckingType = .yes
        view.keyboardDismissMode = .none
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.text = text

        let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeDown(_:)))
        swipe.numberOfTouchesRequired = 2
        swipe.direction = .down
        swipe.delegate = context.coordinator
        view.addGestureRecognizer(swipe)
        return view
    }

    func updateUIView(_ uiView: AutoFocusTextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text { uiView.text = text }
        if !uiView.isFirstResponder, uiView.window != nil {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: NotesNativeTextView?

        func textViewDidChange(_ textView: UITextView) {
            parent?.onChange(textView.text)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" { DispatchQueue.main.async { self.parent?.onReturn() } }
            return true
        }

        @objc func swipeDown(_ recognizer: UISwipeGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            dlog("[NOTES] two-finger swipe down → leave Perform")
            parent?.onTwoFingerSwipeDown()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

final class AutoFocusTextView: UITextView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.window != nil, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }
}
