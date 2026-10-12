import QuartzCore
import UIKit

/// Full-screen Cardphone «Proximity Rise» (`.ascent`) over the stage screenshot, timed so the lens collapses
/// under the Dynamic Island exactly as the flash clip ends and the song comes in.
final class StageProximityRippleHost: UIView {
    private var renderer: ProximityRippleRenderer?
    private var displayLink: CADisplayLink?
    private var morphStart: CFTimeInterval?
    private var contentImage: CGImage?
    private var isDarkStage = true
    private var builtSize: CGSize = .zero
    /// Seconds from the open hand until the lens has vanished at the top (flash clip length).
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
        renderer.render(time: Self.entryTime)
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
        let t = choreographyTime(elapsed: CACurrentMediaTime() - start)
        renderer.render(time: min(ProximityRippleRenderer.duration, t))
        if t >= ProximityRippleRenderer.duration {
            stopAndClear()
        }
    }

    /// Timeline position for real time since the open hand: the lens skips the empty first frames and grows at
    /// the bottom at double speed, rises, then collapses in `collapseSeconds` so it is gone at `riseDuration`.
    private func choreographyTime(elapsed: TimeInterval) -> Double {
        let entry = Self.entryTime, hold = Self.holdEnd
        let arrival = ProximityRippleRenderer.arrivalTime, end = ProximityRippleRenderer.duration
        let total = max(1.5, riseDuration)
        let growSeconds = (hold - entry) / (arrival / total * Self.growSpeedup)
        let collapseStart = total - Self.collapseSeconds
        if elapsed < growSeconds {
            return entry + elapsed / growSeconds * (hold - entry)
        }
        if elapsed < collapseStart {
            return hold + (elapsed - growSeconds) / (collapseStart - growSeconds) * (arrival - hold)
        }
        return arrival + (elapsed - collapseStart) / Self.collapseSeconds * (end - arrival)
    }

    /// First visible lens frame and the end of the bottom hold in the `.ascent` keys.
    private static let entryTime = 0.3
    private static let holdEnd = 1.2
    private static let growSpeedup = 2.0
    /// Matches `InterferenceAudioEngine.Timeline.flashSongCrossfade`: the song comes in while the lens shrinks.
    static let collapseSeconds: TimeInterval = 0.3
}
