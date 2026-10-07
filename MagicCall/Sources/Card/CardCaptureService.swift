import AVFoundation
import CoreMedia
import UIKit

/// Back-camera video frames without shutter sound. Optional preview layer for Setup practice only.
final class CardCaptureService: NSObject {
    enum CaptureError: LocalizedError {
        case noCamera
        case cannotAddInput
        case cannotAddOutput
        case notRunning

        var errorDescription: String? {
            switch self {
            case .noCamera: return "No camera available for the selected facing."
            case .cannotAddInput: return "Could not open the camera."
            case .cannotAddOutput: return "Could not read video frames."
            case .notRunning: return "Camera is not running."
            }
        }
    }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "MagicCall.CardCapture", qos: .userInitiated)
    private var latestBuffer: CVPixelBuffer?
    private var frameLock = NSLock()
    private var configuredPosition: AVCaptureDevice.Position?
    private var sessionBasicsConfigured = false

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    func configureIfNeeded() throws {
        let position = CardSettings.cameraFacing.capturePosition
        if configuredPosition == position, !session.inputs.isEmpty { return }
        if configuredPosition != nil, configuredPosition != position {
            removeVideoInputs()
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if !sessionBasicsConfigured {
            session.sessionPreset = .hd1920x1080
            session.automaticallyConfiguresApplicationAudioSession = false

            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
            session.addOutput(output)
            sessionBasicsConfigured = true
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CaptureError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }

        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
        device.unlockForConfiguration()

        configuredPosition = position
        dlog("[CARD] capture configured · \(position == .back ? "back" : "front") · preset=\(session.sessionPreset.rawValue)")
    }

    /// Call after changing `CardSettings.cameraFacing` while the session may be running.
    func invalidateConfiguration() {
        if session.isRunning {
            session.stopRunning()
        }
        removeVideoInputs()
        frameLock.lock()
        latestBuffer = nil
        frameLock.unlock()
    }

    private func removeVideoInputs() {
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        session.commitConfiguration()
        configuredPosition = nil
    }

    func start() throws {
        try configureIfNeeded()
        guard !session.isRunning else { return }
        queue.async { [weak self] in
            self?.session.startRunning()
            dlog("[CARD] camera started")
        }
    }

    func stop() {
        guard session.isRunning else { return }
        queue.async { [weak self] in
            self?.session.stopRunning()
            dlog("[CARD] camera stopped")
        }
        frameLock.lock()
        latestBuffer = nil
        frameLock.unlock()
    }

    /// Collects frames for `duration` seconds and returns the sharpest buffers (up to `maxFrames`).
    func collectBurst(duration: TimeInterval, maxFrames: Int = 9, scanPulse: Bool = true) async -> [CVPixelBuffer] {
        var collected: [(buffer: CVPixelBuffer, score: Double)] = []
        let end = Date().addingTimeInterval(duration)
        if scanPulse {
            await MainActor.run {
                PerformanceCues.cardScanningPulse()
            }
        }
        while Date() < end {
            if let buf = copyLatestBuffer() {
                let score = Self.sharpnessScore(for: buf)
                collected.append((buf, score))
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        collected.sort { $0.score > $1.score }
        let top = collected.prefix(maxFrames).map(\.buffer)
        dlog("[OCR] snapshot \(String(format: "%.2f", duration))s → \(collected.count) frames, using top \(top.count)")
        return top
    }

    /// Frames with most recognized text (for volume-trigger snapshot).
    func collectFramesRankedByText(duration: TimeInterval, maxCandidates: Int = 4) async -> [(buffer: CVPixelBuffer, readings: [CardOCRReading], textScore: Double)] {
        var samples: [(CVPixelBuffer, [CardOCRReading], Double)] = []
        let end = Date().addingTimeInterval(duration)
        while Date() < end {
            if let buf = copyLatestBuffer() {
                let lines = await CardOCRProcessor.recognize(buf)
                let chars = lines.reduce(0) { $0 + $1.text.count }
                let score = Double(chars) + CardOCRProcessor.lineScore(lines) * 12
                if chars >= 2 {
                    samples.append((buf, lines, score))
                }
            }
            try? await Task.sleep(nanoseconds: 55_000_000)
        }
        samples.sort { $0.2 > $1.2 }
        let top = samples.prefix(maxCandidates)
        if let best = top.first {
            dlog("[OCR] best text frame score=\(Int(best.2)) lines=\(best.1.map(\.text).joined(separator: " | "))")
        } else {
            dlog("[OCR] snapshot \(String(format: "%.2f", duration))s → no readable text")
        }
        return top.map { ($0.0, $0.1, $0.2) }
    }

    func hasFrame() -> Bool {
        frameLock.lock()
        defer { frameLock.unlock() }
        return latestBuffer != nil
    }

    /// Wait until at least one video frame arrives (session must be running).
    func waitForFirstFrame(timeout: TimeInterval) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if hasFrame() { return true }
            try? await Task.sleep(nanoseconds: 45_000_000)
        }
        return false
    }

    private func copyLatestBuffer() -> CVPixelBuffer? {
        frameLock.lock()
        defer { frameLock.unlock() }
        guard let latestBuffer else { return nil }
        return latestBuffer
    }

    /// Laplacian variance on center crop (cheap sharpness proxy).
    static func sharpnessScore(for pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let row = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let x0 = w / 6
        let x1 = w - w / 6
        let y0 = h / 6
        let y1 = h - h / 6
        var sum: Double = 0
        var sumSq: Double = 0
        var n = 0
        for y in stride(from: y0, to: y1, by: 4) {
            let rowPtr = base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: x0, to: x1, by: 4) {
                let g = Double(rowPtr[x * 4])
                sum += g
                sumSq += g * g
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        let mean = sum / Double(n)
        return max(0, sumSq / Double(n) - mean * mean)
    }
}

extension CardCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buf = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock()
        latestBuffer = buf
        frameLock.unlock()
    }
}
