import QuartzCore
import UIKit

/// Full-screen Cardphone «Proximity Rise» (`.ascent`) over the stage screenshot. The 6 s choreography is played
/// at the rate that lands the lens under the Dynamic Island when the flash clip ends; the whiteout tail then
/// finishes over the incoming song and the host hides itself.
final class StageProximityRippleHost: UIView {
    private var renderer: ProximityRippleRenderer?
    private var displayLink: CADisplayLink?
    private var morphStart: CFTimeInterval?
    private var contentImage: CGImage?
    private var isDarkStage = true
    private var builtSize: CGSize = .zero
    /// Seconds from the open hand to the lens reaching the top (flash clip length).
    var riseDuration: TimeInterval = InterferenceSettings.flashInterferenceDuration

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayLink?.invalidate()
    }

    var isAnimating: Bool { morphStart != nil }

    func updateContent(_ image: CGImage?, isDark: Bool) {
        guard image !== contentImage || isDark != isDarkStage else { return }
        contentImage = image
        isDarkStage = isDark
        builtSize = .zero
        rebuildRendererIfNeeded()
    }

    func beginMorph() {
        rebuildRendererIfNeeded()
        guard let renderer else {
            dlogDebug("[INTERF] proximity rise · no renderer (bounds \(bounds.size), image \(contentImage != nil))")
            return
        }
        dlogDebug("[INTERF] proximity rise · start \(bounds.size) · rise \(String(format: "%.2f", riseDuration)) s")
        morphStart = CACurrentMediaTime()
        renderer.render(time: 0)
        alpha = 1
        startDisplayLink()
    }

    func stopAndClear() {
        morphStart = nil
        stopDisplayLink()
        alpha = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildRendererIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopAndClear()
        }
    }

    private func rebuildRendererIfNeeded() {
        guard bounds.width > 1, bounds.height > 1, let contentImage, bounds.size != builtSize else { return }
        guard let built = ProximityRippleRenderer(
            variant: .ascent,
            content: contentImage,
            bounds: bounds,
            dialFrame: bounds,
            isDark: isDarkStage
        ) else {
            dlogDebug("[INTERF] proximity rise · Metal renderer unavailable")
            return
        }
        renderer?.layer.removeFromSuperlayer()
        layer.addSublayer(built.layer)
        renderer = built
        builtSize = bounds.size
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step() {
        guard let start = morphStart, let renderer else { return }
        let rate = ProximityRippleRenderer.arrivalTime / max(0.5, riseDuration)
        let t = (CACurrentMediaTime() - start) * rate
        renderer.render(time: min(ProximityRippleRenderer.duration, t))
        if t >= ProximityRippleRenderer.duration {
            stopAndClear()
        }
    }
}
