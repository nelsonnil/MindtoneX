import QuartzCore
import UIKit

/// Full-screen Cardphone «Proximity Rise» (`.ascent`) over the stage screenshot, timed to the flash interference clip.
final class StageProximityRippleHost: UIView {
    static let shaderDuration: TimeInterval = 6.0

    private var renderer: ProximityRippleRenderer?
    private var displayLink: CADisplayLink?
    private var morphStart: CFTimeInterval?
    private var contentImage: CGImage?
    private var isDarkStage = true
    private var builtSize: CGSize = .zero
    var morphDuration: TimeInterval = InterferenceSettings.flashInterferenceDuration

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayLink?.invalidate()
    }

    func updateContent(_ image: CGImage?, isDark: Bool) {
        guard image !== contentImage || isDark != isDarkStage else { return }
        contentImage = image
        isDarkStage = isDark
        builtSize = .zero
        rebuildRendererIfNeeded()
    }

    /// Lens starts at the bottom edge now and reaches the top after `morphDuration`.
    func beginMorph() {
        rebuildRendererIfNeeded()
        morphStart = CACurrentMediaTime()
        renderer?.render(time: 0)
        startDisplayLink()
    }

    func endMorph() {
        morphStart = nil
        stopDisplayLink()
        renderer?.render(time: Self.shaderDuration)
    }

    func stopAndClear() {
        morphStart = nil
        stopDisplayLink()
        renderer?.layer.removeFromSuperlayer()
        renderer = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildRendererIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        }
    }

    private func rebuildRendererIfNeeded() {
        guard bounds.width > 1, bounds.height > 1, let contentImage, bounds.size != builtSize else { return }
        guard let built = ProximityRippleRenderer(
            variant: .ascent,
            content: contentImage,
            bounds: bounds,
            dialFrame: bounds,
            isDark: isDarkStage,
            dynamicIslandNormalizedY: dynamicIslandNormalizedY
        ) else {
            return
        }
        renderer?.layer.removeFromSuperlayer()
        layer.addSublayer(built.layer)
        renderer = built
        builtSize = bounds.size
    }

    private var dynamicIslandNormalizedY: CGFloat {
        guard bounds.height > 0 else { return 0.06 }
        let topInset = window?.safeAreaInsets.top ?? 59
        return max(0.04, min(0.12, (topInset * 0.5) / bounds.height))
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
        let elapsed = CACurrentMediaTime() - start
        renderer.render(time: min(Self.shaderDuration, elapsed * Self.shaderDuration / morphDuration))
        if elapsed >= morphDuration {
            endMorph()
        }
    }
}
