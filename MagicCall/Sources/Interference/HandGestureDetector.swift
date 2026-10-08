import AVFoundation
import QuartzCore
import Vision

/// Front camera + Vision hand pose. Fires `onOpenHand` once per `start()` when ≥ 4 extended fingers
/// are seen continuously for `holdSeconds`. Video only (no mic input) so the app audio session is untouched.
final class HandGestureDetector: NSObject {
    enum DetectorError: LocalizedError {
        case noFrontCamera
        case cannotAddInput
        case cannotAddOutput

        var errorDescription: String? {
            switch self {
            case .noFrontCamera: return "No front camera available."
            case .cannotAddInput: return "Could not open the front camera."
            case .cannotAddOutput: return "Could not read camera frames."
            }
        }
    }

    static let requiredFingers = 4
    static let holdSeconds: CFTimeInterval = 0.3

    let session = AVCaptureSession()

    /// Called on the main queue.
    var onFingers: ((Int) -> Void)?
    /// Called on the main queue, at most once per `start()`.
    var onOpenHand: ((Int) -> Void)?
    /// Called on the main queue with a short reason.
    var onInterrupted: ((String) -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "MagicCall.HandGesture", qos: .userInitiated)
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    private var configured = false
    private var observers: [NSObjectProtocol] = []

    // Confined to `queue`.
    private var frameIndex = 0
    private var openSince: CFTimeInterval?
    private var missesInRow = 0
    private var fired = true
    private var lastReportedFingers = -1

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] note in
            let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? -1
            let reason = AVCaptureSession.InterruptionReason(rawValue: raw)
            let text: String
            switch reason {
            case .videoDeviceNotAvailableInBackground: text = "Camera paused — MindtoneX is not in front"
            case .videoDeviceInUseByAnotherClient: text = "Camera in use by another app"
            case .videoDeviceNotAvailableDueToSystemPressure: text = "Camera paused — iPhone too hot"
            default: text = "Camera interrupted by iOS"
            }
            dlog("[INTERF] camera interrupted · reason=\(raw)")
            self?.onInterrupted?(text)
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            dlog("[INTERF] camera runtime error · \(error?.localizedDescription ?? "unknown")")
            self?.onInterrupted?("Camera error")
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() throws {
        try configureIfNeeded()
        queue.async { [weak self] in
            guard let self else { return }
            self.frameIndex = 0
            self.openSince = nil
            self.missesInRow = 0
            self.lastReportedFingers = -1
            self.fired = false
            if !self.session.isRunning { self.session.startRunning() }
            dlog("[INTERF] front camera started")
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.fired = true
            if self.session.isRunning {
                self.session.stopRunning()
                dlog("[INTERF] front camera stopped")
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw DetectorError.noFrontCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw DetectorError.cannotAddInput }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw DetectorError.cannotAddOutput }
        session.addOutput(output)
        configured = true
    }

    private func handle(fingers: Int) {
        let now = CACurrentMediaTime()
        if fingers != lastReportedFingers {
            lastReportedFingers = fingers
            DispatchQueue.main.async { [weak self] in self?.onFingers?(fingers) }
        }
        if fingers >= Self.requiredFingers {
            missesInRow = 0
            let since = openSince ?? now
            openSince = since
            if now - since >= Self.holdSeconds {
                fired = true
                dlog("[INTERF] open hand · \(fingers) fingers held \(String(format: "%.2f", now - since)) s")
                DispatchQueue.main.async { [weak self] in self?.onOpenHand?(fingers) }
            }
        } else {
            missesInRow += 1
            if missesInRow >= 2 { openSince = nil }
        }
    }

    /// Counts extended fingers; distances are corrected for the portrait frame aspect (`xScale` = width / height).
    static func extendedFingers(_ observation: VNHumanHandPoseObservation, xScale: CGFloat, minConfidence: Float = 0.3) -> Int {
        guard let points = try? observation.recognizedPoints(.all),
              let wrist = points[.wrist], wrist.confidence >= minConfidence else { return 0 }
        func distance(_ a: VNRecognizedPoint, _ b: VNRecognizedPoint) -> CGFloat {
            hypot((a.location.x - b.location.x) * xScale, a.location.y - b.location.y)
        }
        let fingers: [(tip: VNHumanHandPoseObservation.JointName, pip: VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP), (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP),
        ]
        var count = fingers.filter { finger in
            guard let tip = points[finger.tip], let pip = points[finger.pip],
                  tip.confidence >= minConfidence, pip.confidence >= minConfidence else { return false }
            return distance(tip, wrist) > distance(pip, wrist) * 1.15
        }.count
        if let tip = points[.thumbTip], let ip = points[.thumbIP], let base = points[.littleMCP],
           min(tip.confidence, ip.confidence, base.confidence) >= minConfidence,
           distance(tip, base) > distance(ip, base) * 1.1 {
            count += 1
        }
        return count
    }
}

extension HandGestureDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !fired else { return }
        frameIndex += 1
        guard frameIndex % 2 == 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Front camera held in portrait: sensor frames are landscape, so Vision sees them rotated + mirrored.
        let width = CGFloat(CVPixelBufferGetWidth(pixels))
        let height = CGFloat(CVPixelBufferGetHeight(pixels))
        let xScale = width > 0 ? height / width : 0.75
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
        var fingers = 0
        do {
            try handler.perform([request])
            if let hand = request.results?.first {
                fingers = Self.extendedFingers(hand, xScale: xScale)
            }
        } catch {
            dlog("[INTERF] Vision error · \(error.localizedDescription)")
        }
        handle(fingers: fingers)
    }
}
