import Metal
import MetalKit
import UIKit

/// Light-refraction glitches: a white light born at the screen center whose wavefronts bend the dial like a
/// wave passing through glass (keys squash at the front and stretch on either side) with a moving prismatic rim.
/// Core Animation cannot displace pixels, so the dial is redrawn through a Metal shader every frame.
final class ProximityRippleRenderer {
    /// MindtoneX Perform uses **ascent** only (Cardphone «Proximity Rise» — vertical drift to Dynamic Island).
    enum Variant {
        case ascent
    }

    /// Opacity of this hidden layer is animated 0 → 1 over the glitch, so the timeline follows the view's
    /// Core Animation clock (loop, once, frozen) without a separate time source.
    let driver = CALayer()
    let layer = CAMetalLayer()

    private let variant: Variant
    private let texture: MTLTexture
    private let pipeline: MTLRenderPipelineState
    private let queue: MTLCommandQueue
    private let size: CGSize
    private let dialFrame: CGRect
    private let isDark: Bool
    private let dynamicIslandNormalizedY: CGFloat

    init?(variant: Variant, content: CGImage?, bounds: CGRect, dialFrame: CGRect, isDark: Bool,
          dynamicIslandNormalizedY: CGFloat = 0.06) {
        guard let content, let shared = Self.shared, !bounds.isEmpty,
              let texture = try? MTKTextureLoader(device: shared.device)
                .newTexture(cgImage: content, options: [.SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
        else {
            return nil
        }
        self.variant = variant
        self.texture = texture
        pipeline = shared.pipeline
        queue = shared.queue
        size = bounds.size
        self.dialFrame = dialFrame
        self.isDark = isDark
        self.dynamicIslandNormalizedY = dynamicIslandNormalizedY

        let scale = UIScreen.main.scale
        layer.device = shared.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.frame = bounds
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        driver.frame = .zero
        driver.opacity = 0
    }

    /// Current timeline position (0...1) from the animated driver layer.
    var progress: Double {
        Double(driver.presentation()?.opacity ?? driver.opacity)
    }

    func render(time: Double) {
        guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else {
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        var uniforms = uniforms(at: time)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    // MARK: Choreography (seconds; every variant ends on the untouched dial by 5.9 s)

    /// Values in screen widths / points before conversion to shader uniforms.
    private struct Frame {
        var center = CGPoint(x: 0.5, y: 0.5)
        /// Front 0 carries the white fill and the prismatic rim; fronts 1–3 are extra wavefronts.
        var radius = SIMD4<Double>(repeating: 0)
        var amp = SIMD4<Double>(repeating: 0)
        var trail = 0.0
        var rim = 0.0
        var glow = 0.0
        var dim = 0.0
        var whiteout = 0.0
        var hue = 0.0
        var swirl = 0.0
    }

    private func frame(at t: Double) -> Frame {
        var f = Frame()
        let k = Self.keys
        let dimPeak = isDark ? 0.2 : 0.35
        switch variant {
        case .ascent:
            let islandY = Double(dynamicIslandNormalizedY)
            f.center = CGPoint(
                x: 0.5,
                y: k(t, [(0, 1.06), (0.2, 1.06), (3.6, islandY), (5.9, islandY)], true)
            )
            f.radius.x = k(t, [(0.15, 0), (0.8, 0.22), (2.8, 0.38), (3.6, 0.42)], true)
            f.amp.x = k(t, [(0.15, 0), (0.9, 16), (3.2, 18), (4.0, 0)], true)
            f.trail = f.amp.x * 0.6
            f.rim = k(t, [(0.15, 0), (0.7, 1), (3.4, 1), (4.0, 0)], true)
            f.glow = k(t, [(0.3, 0), (1.2, 0.75), (3.4, 0.85), (4.0, 0)], true)
            f.dim = k(t, [(0, 0), (0.9, dimPeak), (4.2, dimPeak), (5.8, 0)], true)
            f.whiteout = k(t, [(3.5, 0), (4.2, 0.9), (5.9, 0)], true)
            f.hue = t * 0.35
        }
        return f
    }

    private func uniforms(at t: Double) -> Uniforms {
        let f = frame(at: t)
        let w = Float(size.width)
        let radius = SIMD4<Float>(f.radius) * w
        return Uniforms(
            radius: radius,
            amp: SIMD4<Float>(f.amp),
            size: SIMD2(w, Float(size.height)),
            dialOrigin: SIMD2(Float(dialFrame.minX), Float(dialFrame.minY)),
            dialSize: SIMD2(Float(dialFrame.width), Float(dialFrame.height)),
            center: SIMD2(Float(f.center.x) * w, Float(f.center.y * size.height)),
            width: 22 + radius.x / w * 28,
            trail: Float(f.trail),
            rim: Float(f.rim),
            glow: Float(f.glow),
            dim: Float(f.dim),
            phase: Float(t * 6),
            hue: Float(f.hue),
            swirl: Float(f.swirl),
            whiteout: Float(f.whiteout),
            glowWhite: isDark ? 0.82 : 1)
    }

    /// Piecewise interpolation that holds the first/last value outside the keys.
    private static func keys(_ t: Double, _ keys: [(Double, Double)], _ smooth: Bool) -> Double {
        guard let first = keys.first, let last = keys.last else {
            return 0
        }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for (a, b) in zip(keys, keys.dropFirst()) where t <= b.0 {
            var f = (t - a.0) / (b.0 - a.0)
            if smooth { f = f * f * (3 - 2 * f) }
            return a.1 + (b.1 - a.1) * f
        }
        return last.1
    }

    // MARK: Metal

    /// Layout mirrors the `Uniforms` struct in `shaderSource` (float4s first keeps both sides at 16-byte alignment).
    private struct Uniforms {
        var radius: SIMD4<Float>
        var amp: SIMD4<Float>
        var size: SIMD2<Float>
        var dialOrigin: SIMD2<Float>
        var dialSize: SIMD2<Float>
        var center: SIMD2<Float>
        var width: Float
        var trail: Float
        var rim: Float
        var glow: Float
        var dim: Float
        var phase: Float
        var hue: Float
        var swirl: Float
        var whiteout: Float
        var glowWhite: Float
    }

    private struct Shared {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
    }

    /// Compiled from source at runtime so the effect needs no `.metal` build phase.
    private static let shared: Shared? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: shaderSource, options: nil) else {
            return nil
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "ripple_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "ripple_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        return Shared(device: device, queue: queue, pipeline: pipeline)
    }()

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut ripple_vertex(uint vid [[vertex_id]]) {
        float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        VOut out;
        out.position = float4(pos[vid], 0, 1);
        out.uv = float2((pos[vid].x + 1) * 0.5, 1 - (pos[vid].y + 1) * 0.5);
        return out;
    }

    struct Uniforms {
        float4 radius; float4 amp;
        float2 size; float2 dialOrigin; float2 dialSize; float2 center;
        float width; float trail; float rim; float glow; float dim; float phase; float hue; float swirl;
        float whiteout; float glowWhite;
    };

    static float3 dial(texture2d<float> tex, sampler s, constant Uniforms &u, float2 p) {
        return tex.sample(s, (p - u.dialOrigin) / u.dialSize).rgb;
    }

    fragment float4 ripple_fragment(VOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]],
                                    constant Uniforms &u [[buffer(0)]]) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);
        float2 p = in.uv * u.size;
        float2 d = p - u.center;
        float dist = length(d);
        float2 dir = dist > 0.001 ? d / dist : float2(0);
        float angle = atan2(d.y, d.x) / 6.2831;

        // Derivative-of-gaussian bulge per front: content inside is pushed out, outside is pulled in,
        // so keys squash at the front and stretch on either side.
        float disp = 0;
        float frontGlow = 0;
        for (int i = 0; i < 4; i++) {
            if (u.amp[i] <= 0) { continue; }
            float xi = (dist - u.radius[i]) / u.width;
            float g = exp(-xi * xi);
            disp += u.amp[i] * (-2.0 * xi) * g;
            if (i > 0) { frontGlow += g * saturate(u.amp[i] / 12.0); }
        }
        float x = (dist - u.radius[0]) / u.width;
        if (x < 0) {
            disp += u.trail * sin(x * 3.2 - u.phase) * exp(x * 0.35);
        }
        disp *= smoothstep(0.0, u.width, dist);

        float front = exp(-x * x);
        float spread = 0.08 * fabs(disp) + 1.5 * (front * u.rim + frontGlow);
        float3 c;
        c.r = dial(tex, s, u, p - dir * (disp + spread)).r;
        c.g = dial(tex, s, u, p - dir * disp).g;
        c.b = dial(tex, s, u, p - dir * (disp - spread)).b;

        c *= 1.0 - u.dim;
        float inside = 1.0 - smoothstep(-1.5, 0.3, x);
        float halo = x > 0 ? exp(-x * 0.6) * 0.35 : 0;
        c = mix(c, float3(u.glowWhite), u.glow * (inside + halo));

        // Prismatic rim whose colors travel along the front (hue) and around it (swirl).
        float3 prism = 0.72 + 0.28 * cos(6.2831 * (x * 0.3 + u.hue + angle * u.swirl + float3(0.0, 0.33, 0.67)));
        float band = exp(-pow((x + 0.4) * 1.1, 2.0)) * u.rim + frontGlow * 0.5;
        c = mix(c, prism, saturate(band * 0.45));

        c = mix(c, float3(u.glowWhite), u.whiteout);
        return float4(saturate(c), 1);
    }
    """
}
