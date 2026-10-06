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
        if context == .test {
            startCamera()
        } else {
            dlog("[CARD] back camera off until volume scan (no green dot until then)")
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
            lock(reason: "call/trigger (\(source))", auto: true, playLockHaptic: false)
            return
        }
        dlog("[CARD] call/trigger (\(source)) with no song ready (state=\(state))")
        stopCamera()
        state = .idle
    }

    // MARK: Volume scan

    /// Side volume (KVO) or Camera Control — gating happens in `AppModel` before this runs.
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
                lock(reason: "volume confirm", auto: false, playLockHaptic: false)
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
        SystemVolume.shared.ensureHeadroomForHardwareVolumeButtons(reason: "pre card scan")
        if context == .perform {
            PerformUserLog.shared.log("Camera · scanning — green dot on (~\(Int(CardSettings.burstSeconds)) s)")
        }
        let gen = generation
        scanTask = Task { [weak self] in
            await self?.runBurstScan(gen: gen)
        }
    }

    private func runBurstScan(gen: Int) async {
        defer {
            if gen == generation { scanTask = nil }
        }
        startCamera()
        defer { stopCamera() }
        try? await Task.sleep(nanoseconds: 280_000_000)
        guard gen == generation else { return }
        let frames = await capture.collectBurst(duration: CardSettings.burstSeconds, scanPulse: false)
        guard gen == generation else { return }
        guard !frames.isEmpty else {
            dlog("[OCR] no frames in burst")
            await handleScanOutcome(gen: gen, vote: nil, query: nil, ocrSample: "")
            return
        }

        var frameTexts: [[CardOCRReading]] = []
        var bestLineReadings: [CardOCRReading] = []
        for (i, buf) in frames.prefix(6).enumerated() {
            let lines = await CardOCRProcessor.recognize(buf)
            if !lines.isEmpty {
                dlog("[OCR] frame \(i + 1): \(lines.map(\.text).joined(separator: " | "))")
            }
            frameTexts.append(lines)
            if CardOCRProcessor.lineScore(lines) > CardOCRProcessor.lineScore(bestLineReadings) {
                bestLineReadings = lines
            }
        }
        let texts = CardOCRProcessor.mergedText(from: frameTexts)
        let orderedLines = CardOCRProcessor.orderedLineTexts(from: bestLineReadings)
        let ocr = CardLineParser.parse(orderedLines: orderedLines)
        if !orderedLines.isEmpty {
            dlog("[CARD] lines top→bottom: \(orderedLines.joined(separator: " | "))")
        }
        if context == .perform {
            PerformUserLog.shared.log("Camera · OCR lines: \(orderedLines.joined(separator: " | "))")
            let l2 = ocr.callerLine.map { WordApiInputPanel.truncated($0, max: 24) } ?? "—"
            let l3 = ocr.notesLine.map { WordApiInputPanel.truncated($0, max: 24) } ?? "—"
            PerformUserLog.shared.log(
                "Camera · OCR read · L1 «\(WordApiInputPanel.truncated(ocr.songQuery, max: 28))» · L2 «\(l2)» · L3 «\(l3)»"
            )
        }
        guard gen == generation else { return }

        let queriesToTry = songSearchQueries(ocr: ocr, orderedLines: orderedLines, mergedTexts: texts)
        dlog("[CARD] song queries (line 1 first): \(queriesToTry.joined(separator: " · "))")
        if context == .perform {
            PerformUserLog.shared.log("Camera · song search tries: \(queriesToTry.joined(separator: " · "))")
        }

        var votes: [String: Int] = [:]
        var queryByKey: [String: String] = [:]
        var trackByKey: [String: PreviewTrack] = [:]

        for query in queriesToTry {
            guard query.count >= 2 else { continue }
            let ok = await AppModel.shared.prepareCardQuery(query)
            guard gen == generation else { return }
            guard ok, let track = AppModel.shared.selected else {
                dlog("[CARD] song try “\(query)” → no match")
                if context == .perform {
                    PerformUserLog.shared.log("Camera · song try «\(query)» → no match")
                }
                continue
            }
            let key = CardTextMapper.canonicalKey(from: track)
            votes[key, default: 0] += 1
            queryByKey[key] = query
            trackByKey[key] = track
            dlog("[CARD] song try “\(query)” → \(track.title) — \(track.artist) (votes=\(votes[key] ?? 0))")
            if context == .perform {
                PerformUserLog.shared.log("Camera · song try «\(query)» → \(track.title) — \(track.artist)")
            }
        }

        let best = votes.max { $0.value < $1.value }
        if context == .perform, let best {
            let winner = trackByKey[best.key]
            PerformUserLog.shared.log(
                "Card · song winner «\(queryByKey[best.key] ?? "?")» → \(winner?.title ?? "?") — \(winner?.artist ?? "?") (\(best.value) vote(s))"
            )
        }
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
            track: best.flatMap { trackByKey[$0.key] },
            ocrParse: ocr
        )
    }

    private func handleScanOutcome(
        gen: Int,
        vote: (key: String, value: Int)?,
        query: String?,
        ocrSample: String,
        track: PreviewTrack? = nil,
        ocrParse: CardOCRParse? = nil
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

        if context == .perform {
            PerformanceCues.cardSongRecognized()
            if AppModel.shared.loadState == .ready {
                PerformanceCues.cardSongReady()
            }
        }

        if highConfidence {
            dlog("[CARD] ★ auto-lock (\(vote.value) votes) · \(candidateLabel ?? "?")")
            lock(reason: "OCR consensus", auto: true, playLockHaptic: false)
        } else {
            dlog("[CARD] ? candidate (1 vote) · \(candidateLabel ?? "?") — volume again to confirm")
            state = .candidate
        }

        applyCardWordsIfNeeded(ocrParse)
    }

    /// Prefer **line 1** for song lookup; never search word lines; full-frame OCR only as fallback.
    private func songSearchQueries(ocr: CardOCRParse, orderedLines: [String], mergedTexts: [String]) -> [String] {
        var queries: [String] = []
        let skipWords = [CardLineParser.normalizedCallerWord(from: ocr), CardLineParser.normalizedNotesWord(from: ocr)]
            .compactMap { $0 }
        func appendUnique(_ raw: String) {
            let q = CardTextMapper.clean(raw)
            guard q.count >= 2 else { return }
            if skipWords.contains(where: { ApiJSON.sameText(q, $0) }) {
                dlog("[CARD] skip song query (matches word line): “\(q)”")
                return
            }
            guard !queries.contains(where: { ApiJSON.sameText($0, q) }) else { return }
            queries.append(q)
        }

        appendUnique(ocr.songQuery)
        if queries.isEmpty, let first = orderedLines.first {
            appendUnique(first)
        }
        if queries.isEmpty {
            for text in mergedTexts { appendUnique(text) }
        }
        return queries
    }

    private func applyCardWordsIfNeeded(_ parse: CardOCRParse?) {
        guard let parse else { return }
        if CardOCRLayout.usesCallerLine {
            if let word = CardLineParser.normalizedCallerWord(from: parse) {
                WordApiSession.shared.ingestCardScanWord(word)
            } else if context == .perform {
                dlog("[CARD] caller Card OCR on — line 2 empty or unreadable")
            }
        }
        if CardOCRLayout.usesNotesLine {
            if let word = CardLineParser.normalizedNotesWord(from: parse) {
                NotesContactWordSession.shared.ingestCardScanWord(word)
            } else if context == .perform {
                dlog("[CARD] Notes Card OCR on — line 3 empty or unreadable")
            }
        }
    }

    private func lock(reason: String, auto: Bool, playLockHaptic: Bool = true) {
        scanTask?.cancel()
        scanTask = nil
        stopCamera()
        state = .locked
        dlog("[CARD] 🔒 locked · \(candidateLabel ?? pendingCandidateQuery) · \(reason)")
        if context == .perform, playLockHaptic {
            PerformanceCues.songLocked(source: "Card")
        }
        AppModel.shared.cardSongLocked(context: context)
    }

    private func fail(_ message: String) {
        stopCamera()
        state = .failed(message)
        if context == .perform {
            PerformUserLog.shared.log("Camera · \(message)")
        }
        dlog("✗ [CARD] \(message)")
    }

    private func failScanMaxRetries() {
        stopCamera()
        let message = "Could not read the card — try Notes or another input"
        state = .failed(message)
        if context == .perform {
            PerformUserLog.shared.log("Camera · \(message)")
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

}
