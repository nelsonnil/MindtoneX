import AVKit
import SwiftUI
import UIKit

/// Invisible host for `AVCaptureEventInteraction` — volume / Camera Control triggers OCR burst (iOS 17.2+).
struct CardVolumeScanHost: UIViewRepresentable {
    func makeUIView(context: Context) -> CardVolumeScanView {
        let view = CardVolumeScanView()
        view.isUserInteractionEnabled = true
        return view
    }

    func updateUIView(_ uiView: CardVolumeScanView, context: Context) {
        uiView.isHidden = !CardSongSession.shared.capturesVolumeButtons
    }
}

final class CardVolumeScanView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction { event in
                guard event.phase == .ended else { return }
                Task { @MainActor in
                    CardSongSession.shared.volumeScanTriggered()
                }
            }
            addInteraction(interaction)
        }
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
