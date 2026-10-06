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
            case .noCamera: return "No back camera available."
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
    private var isConfigured = false

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080
        session.automaticallyConfiguresApplicationAudioSession = false

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutput(output)

        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }

        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
        device.unlockForConfiguration()

        isConfigured = true
        dlog("[CARD] capture configured · preset=\(session.sessionPreset.rawValue)")
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
    func collectBurst(duration: TimeInterval, maxFrames: Int = 9) async -> [CVPixelBuffer] {
        var collected: [(buffer: CVPixelBuffer, score: Double)] = []
        let end = Date().addingTimeInterval(duration)
        PerformanceCues.cardScanningPulse()
        while Date() < end {
            if let buf = copyLatestBuffer() {
                let score = Self.sharpnessScore(for: buf)
                collected.append((buf, score))
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        collected.sort { $0.score > $1.score }
        let top = collected.prefix(maxFrames).map(\.buffer)
        dlog("[OCR] burst \(String(format: "%.1f", duration))s → \(collected.count) frames, using top \(top.count)")
        return top
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
