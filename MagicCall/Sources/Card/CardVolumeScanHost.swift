import AVKit
import SwiftUI
import UIKit

/// Invisible host for `AVCaptureEventInteraction` — **Camera Control** (iPhone 16+) OCR trigger. Side **volume** buttons use `AppModel` volume KVO during Card Perform.
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
                    guard AppModel.shared.acceptsCardVolumeScanTrigger() else { return }
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
