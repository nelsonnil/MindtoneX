import QuartzCore
import UIKit

/// Full-screen Cardphone «Proximity Rise» (`.ascent`) over the stage screenshot, timed to interference morph audio.
final class StageProximityRippleHost: UIView {
    static let shaderDuration: TimeInterval = 6.0

    private var renderer: ProximityRippleRenderer?
    private var displayLink: CADisplayLink?
    private var morphStart: CFTimeInterval?
    private var contentImage: CGImage?
    private var isDarkStage = true

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
        contentImage = image
        isDarkStage = isDark
        rebuildRendererIfNeeded()
    }

    /// Starts ascent ripple synced to `InterferenceAudioEngine` morph (~3.95 s → maps to 6 s shader timeline).
    func beginMorph() {
        rebuildRendererIfNeeded()
        morphStart = CACurrentMediaTime()
        startDisplayLink()
    }

    /// Finishes on the clean frame (brief whiteout tail per Cardphone QA).
    func endMorph() {
        morphStart = nil
        stopDisplayLink()
        renderer?.render(time: 5.9)
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
        renderer?.layer.frame = bounds
        if bounds.width > 0, bounds.height > 0 {
            let scale = window?.screen.scale ?? UIScreen.main.scale
            renderer?.layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        }
    }

    private func rebuildRendererIfNeeded() {
        guard bounds.width > 1, bounds.height > 1, let contentImage else { return }
        let islandY = dynamicIslandNormalizedY
        guard let built = ProximityRippleRenderer(
            variant: .ascent,
            content: contentImage,
            bounds: bounds,
            dialFrame: bounds,
            isDark: isDarkStage,
            dynamicIslandNormalizedY: islandY
        ) else {
            return
        }
        renderer?.layer.removeFromSuperlayer()
        layer.addSublayer(built.layer)
        renderer = built
        built.layer.frame = bounds
    }

    private var dynamicIslandNormalizedY: CGFloat {
        guard bounds.height > 0 else { return 0.06 }
        let topInset = safeAreaInsets.top > 0 ? safeAreaInsets.top : (window?.safeAreaInsets.top ?? 59)
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
        let morphDuration = InterferenceAudioEngine.morphDuration
        let t = min(Self.shaderDuration, elapsed * (Self.shaderDuration / morphDuration))
        renderer.render(time: t)
        if elapsed >= morphDuration + 0.15 {
            endMorph()
        }
    }
}
