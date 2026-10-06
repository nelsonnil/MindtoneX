import AVFoundation
import AVFoundation
import Foundation
import QuartzCore
import UIKit

/// Card / OCR song input during Perform: camera runs without stage preview; volume button starts a burst scan.
@MainActor
final class CardSongSession: ObservableObject {
    static let shared = CardSongSession()

    enum Context { case perform, test }

    enum State: Equatable {
        case idle
        case armed
        case scanning
        case candidate
        case locked
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var context: Context = .test
    @Published private(set) var lastOCRText = ""
    @Published private(set) var candidateLabel: String?
    @Published private(set) var scanAttempts = 0

    var isActive: Bool {
        switch state {
        case .armed, .scanning, .candidate: return true
        default: return false
        }
    }

    var isLocked: Bool { state == .locked }

    /// While true, hardware volume must trigger OCR (not play toggle).
    var capturesVolumeButtons: Bool {
        context == .perform && isActive && !isLocked
    }

    /// Camera session running (perform window or practice).
    var isCameraRunning: Bool { captureRunning }

    private let capture = CardCaptureService()
    private var generation = 0
    private var captureRunning = false
    private var scanTask: Task<Void, Never>?
    private var pendingCandidateKey: String?
    private var pendingCandidateQuery = ""
    private var pendingConfirmSameKey: String?

    private init() {}

    // MARK: Lifecycle

    func start(context: Context) {
        reset(reason: "start")
        generation += 1
        self.context = context
        guard CardSettings.cameraAuthorized else {
            fail("Allow camera access in Settings to use Card input.")
            return
        }
        state = .armed
        scanAttempts = 0
        dlog("[CARD] ▶︎ start (\(context == .perform ? "perform" : "test")) · \(CardSettings.summary())")
        startCamera()
        if context == .perform {
            dlog("[CARD] press volume to scan (no screen touch)")
        }
    }

    func stopTest() {
        guard context == .test else { return }
        reset(reason: "test stop")
    }

    func reset(reason: String) {
        let had = state != .idle
        generation += 1
        scanTask?.cancel()
        scanTask = nil
        stopCamera()
        state = .idle
        lastOCRText = ""
        candidateLabel = nil
        scanAttempts = 0
        pendingCandidateKey = nil
        pendingCandidateQuery = ""
        pendingConfirmSameKey = nil
        if had { dlog("[CARD] ↺ reset (\(reason))") }
    }

    /// Incoming call: lock best candidate if not already locked (same idea as Voice).
    func callArrived(source: String) {
        guard context == .perform else { return }
        guard isActive || state == .candidate else { return }
        if isLocked { return }
        scanTask?.cancel()
        scanTask = nil
        if AppModel.shared.loadState == .ready, AppModel.shared.selected != nil {
            lock(reason: "call/trigger (\(source))", auto: true)
            return
        }
        dlog("[CARD] call/trigger (\(source)) with no song ready (state=\(state))")
        stopCamera()
        state = .idle
    }

    // MARK: Volume scan

    /// Fired by `AVCaptureEventInteraction` (iOS 17.2+) on volume press during Perform.
    func volumeScanTriggered() {
        guard context == .perform, isActive, !isLocked else { return }
        guard scanTask == nil else {
            dlog("[CARD] scan already in progress")
            return
        }

        // Second volume press while candidate: confirm if same song loaded, else retry scan.
        // Documented performer flow: 1st press = read; 2nd press on candidate = confirm lock.
        if state == .candidate,
           AppModel.shared.loadState == .ready,
           let key = pendingCandidateKey,
           let track = AppModel.shared.selected {
            let current = CardTextMapper.canonicalKey(from: track)
            if current == key {
                lock(reason: "volume confirm", auto: false)
                return
            }
        }

        beginBurstScan()
    }

    private func beginBurstScan() {
        scanAttempts += 1
        if scanAttempts > CardSettings.maxScanRetries {
            failScanMaxRetries()
            return
        }
        state = .scanning
        let gen = generation
        scanTask = Task { [weak self] in
            await self?.runBurstScan(gen: gen)
        }
    }

    private func runBurstScan(gen: Int) async {
        defer {
            if gen == generation { scanTask = nil }
        }
        let frames = await capture.collectBurst(duration: CardSettings.burstSeconds)
        guard gen == generation else { return }
        guard !frames.isEmpty else {
            dlog("[OCR] no frames in burst")
            await handleScanOutcome(gen: gen, vote: nil, query: nil, ocrSample: "")
            return
        }

        var frameTexts: [[CardOCRReading]] = []
        for (i, buf) in frames.prefix(6).enumerated() {
            let lines = await CardOCRProcessor.recognize(buf)
            if !lines.isEmpty {
                dlog("[OCR] frame \(i + 1): \(lines.map(\.text).joined(separator: " | "))")
            }
            frameTexts.append(lines)
        }
        let texts = CardOCRProcessor.mergedText(from: frameTexts)
        guard gen == generation else { return }

        var votes: [String: Int] = [:]
        var queryByKey: [String: String] = [:]
        var trackByKey: [String: PreviewTrack] = [:]

        for text in texts {
            let query = CardTextMapper.clean(text)
            guard query.count >= 2 else { continue }
            let ok = await AppModel.shared.prepareCardQuery(query)
            guard gen == generation else { return }
            guard ok, let track = AppModel.shared.selected else { continue }
            let key = CardTextMapper.canonicalKey(from: track)
            votes[key, default: 0] += 1
            queryByKey[key] = query
            trackByKey[key] = track
        }

        let best = votes.max { $0.value < $1.value }
        let sample = texts.first ?? ""
        if let best, let winQuery = queryByKey[best.key] {
            _ = await AppModel.shared.prepareCardQuery(winQuery)
            guard gen == generation else { return }
        }
        await handleScanOutcome(
            gen: gen,
            vote: best,
            query: best.flatMap { queryByKey[$0.key] },
            ocrSample: sample,
            track: best.flatMap { trackByKey[$0.key] }
        )
    }

    private func handleScanOutcome(
        gen: Int,
        vote: (key: String, value: Int)?,
        query: String?,
        ocrSample: String,
        track: PreviewTrack? = nil
    ) async {
        guard gen == generation else { return }
        lastOCRText = ocrSample

        guard let vote, vote.value >= 1, let query, let track else {
            dlog("[CARD] scan #\(scanAttempts): no confident song")
            if scanAttempts >= CardSettings.maxScanRetries {
                failScanMaxRetries()
            } else {
                state = .armed
                PerformanceCues.cardScanFailed()
            }
            return
        }

        let highConfidence = vote.value >= 2
        candidateLabel = "\(track.title) — \(track.artist)"
        pendingCandidateKey = vote.key
        pendingCandidateQuery = query

        if highConfidence {
            dlog("[CARD] ★ auto-lock (\(vote.value) votes) · \(candidateLabel ?? "?")")
            lock(reason: "OCR consensus", auto: true)
        } else {
            dlog("[CARD] ? candidate (1 vote) · \(candidateLabel ?? "?") — volume again to confirm")
            state = .candidate
            PerformanceCues.cardCandidateUncertain()
        }
    }

    private func lock(reason: String, auto: Bool) {
        scanTask?.cancel()
        scanTask = nil
        stopCamera()
        state = .locked
        dlog("[CARD] 🔒 locked · \(candidateLabel ?? pendingCandidateQuery) · \(reason)")
        if context == .perform {
            PerformanceCues.songLocked(source: "Card")
        }
        AppModel.shared.cardSongLocked(context: context)
    }

    private func fail(_ message: String) {
        stopCamera()
        state = .failed(message)
        if context == .perform {
            PerformUserLog.shared.log("Tarjeta · \(message)")
        }
        dlog("✗ [CARD] \(message)")
    }

    private func failScanMaxRetries() {
        stopCamera()
        let message = "No pude leer la tarjeta — prueba Notas u otro método"
        state = .failed(message)
        if context == .perform {
            PerformUserLog.shared.log("Tarjeta · \(message)")
        }
        PerformanceCues.cardScanFailed()
        dlog("[CARD] max scan retries reached")
    }

    // MARK: Camera

    func startCamera() {
        guard !captureRunning else { return }
        do {
            try capture.start()
            captureRunning = true
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stopCamera() {
        guard captureRunning else { return }
        capture.stop()
        captureRunning = false
    }

    /// Practice scan sheet: shared capture + preview layer.
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        capture.previewLayer
    }

    func practiceScanOnce() async -> String {
        let frames = await capture.collectBurst(duration: 2.0, maxFrames: 4)
        guard let buf = frames.first else { return "" }
        let lines = await CardOCRProcessor.recognize(buf)
        return CardOCRProcessor.mergedText(from: [lines]).first ?? ""
    }
}
