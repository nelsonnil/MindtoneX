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
    private var snapshotCuePlayed = false

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
        snapshotCuePlayed = false
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
        AppModel.shared.primeCardVolumeScanHeadroom(reason: "pre card scan")
        if context == .perform {
            let mode = VoiceSettings.apiKey != nil ? "snapshot + OpenAI" : "snapshot + local OCR"
            PerformUserLog.shared.log("Camera · \(mode) (~\(String(format: "%.1f", CardSettings.burstSeconds)) s)")
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
        var cameraStopped = false
        func stopCaptureIfNeeded() {
            guard !cameraStopped else { return }
            cameraStopped = true
            stopCamera()
        }
        defer { stopCaptureIfNeeded() }
        try? await Task.sleep(nanoseconds: 320_000_000)
        guard gen == generation else { return }
        await MainActor.run { PerformanceCues.cardScanningPulse() }

        let ranked = await capture.collectFramesRankedByText(duration: CardSettings.burstSeconds, maxCandidates: 3)
        var frameTexts: [[CardOCRReading]] = ranked.map(\.readings)
        var bestLineReadings = ranked.first?.readings ?? []
        var bestBuffer = ranked.first?.buffer

        if ranked.isEmpty {
            let frames = await capture.collectBurst(duration: CardSettings.burstSeconds, scanPulse: false)
            guard gen == generation else { return }
            guard !frames.isEmpty else {
                dlog("[OCR] no frames in snapshot")
                await handleScanOutcome(gen: gen, vote: nil, query: nil, ocrSample: "")
                return
            }
            bestBuffer = frames.first
            for (i, buf) in frames.prefix(4).enumerated() {
                let lines = await CardOCRProcessor.recognize(buf)
                if !lines.isEmpty {
                    dlog("[OCR] frame \(i + 1): \(lines.map(\.text).joined(separator: " | "))")
                }
                frameTexts.append(lines)
                if CardOCRProcessor.lineScore(lines) > CardOCRProcessor.lineScore(bestLineReadings) {
                    bestLineReadings = lines
                    bestBuffer = buf
                }
            }
        } else {
            for (i, sample) in ranked.enumerated() {
                dlog("[OCR] ranked \(i + 1): \(sample.readings.map(\.text).joined(separator: " | "))")
            }
        }

        guard gen == generation else { return }

        if let buf = bestBuffer, VoiceSettings.apiKey == nil || CardImageEncoder.jpegData(from: buf) == nil {
            stopCaptureIfNeeded()
            if context == .perform, !snapshotCuePlayed {
                snapshotCuePlayed = true
                PerformanceCues.cardSnapshotSent()
            }
        }

        if VoiceSettings.apiKey != nil, let buf = bestBuffer, let jpeg = CardImageEncoder.jpegData(from: buf) {
            let hint = CardOCRProcessor.orderedLineTexts(from: bestLineReadings).joined(separator: "\n")
            stopCaptureIfNeeded()
            if context == .perform, !snapshotCuePlayed {
                snapshotCuePlayed = true
                PerformanceCues.cardSnapshotSent()
                PerformUserLog.shared.log("Camera · photo sent · reading card…")
            }
            do {
                let ai = try await CardHandwritingPicker.pick(
                    jpeg: jpeg,
                    visionOCRHint: hint,
                    expectCallerLine: CardOCRLayout.usesCallerLine,
                    expectNotesLine: CardOCRLayout.usesNotesLine
                )
                dlog("[CARD] OpenAI vision · \(ai.reasoning) · conf=\(String(format: "%.2f", ai.confidence)) · query=\(ai.searchQuery)")
                if context == .perform {
                    PerformUserLog.shared.log("Camera · OpenAI · \(WordApiInputPanel.truncated(ai.reasoning, max: 48))")
                }
                let ocr = ai.asOCRParse(
                    expectCaller: CardOCRLayout.usesCallerLine,
                    expectNotes: CardOCRLayout.usesNotesLine
                )
                if ai.hasSong {
                    for query in ai.storeSearchQueries() {
                        let ok = await AppModel.shared.prepareCardQuery(query)
                        guard gen == generation else { return }
                        guard ok, let track = AppModel.shared.selected else {
                            dlog("[CARD] OpenAI try “\(query)” → no match")
                            continue
                        }
                        guard trackMatchesCardPick(track, pick: ai) else {
                            dlog("[CARD] OpenAI reject store mismatch · wanted «\(ai.title)» got «\(track.title)»")
                            continue
                        }
                        let key = CardTextMapper.canonicalKey(from: track)
                        await handleScanOutcome(
                            gen: gen,
                            vote: (key, 2),
                            query: query,
                            ocrSample: hint,
                            track: track,
                            ocrParse: ocr,
                            skipRecognizedCue: snapshotCuePlayed
                        )
                        return
                    }
                    dlog("[CARD] OpenAI song queries exhausted · no acceptable preview")
                }
            } catch {
                dlog("[CARD] OpenAI vision fallback: \(error.localizedDescription)")
                if context == .perform {
                    PerformUserLog.shared.log("Camera · OpenAI failed · local OCR")
                }
            }
        }

        let texts = CardOCRProcessor.mergedText(from: frameTexts)
        let rawOrdered = CardOCRProcessor.orderedLineTexts(from: bestLineReadings)
        let orderedLines = CardLineParser.expandMergedOCRLines(rawOrdered)
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

        var queriesToTry = songSearchQueries(ocr: ocr, orderedLines: orderedLines, mergedTexts: texts)
        for frame in frameTexts {
            let frameLines = CardLineParser.expandMergedOCRLines(CardOCRProcessor.orderedLineTexts(from: frame))
            let frameOcr = CardLineParser.parse(orderedLines: frameLines)
            for q in songSearchQueries(ocr: frameOcr, orderedLines: frameLines, mergedTexts: []) where !queriesToTry.contains(where: { ApiJSON.sameText($0, q) }) {
                queriesToTry.append(q)
            }
        }
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

    private func trackMatchesCardPick(_ track: PreviewTrack, pick: CardHandwritingPick) -> Bool {
        let wantTitle = PreviewService.normalize(pick.title)
        guard wantTitle.count >= 3 else { return true }
        let gotTitle = PreviewService.normalize(track.title)
        if gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) { return true }
        let wantArtist = PreviewService.normalize(pick.artist)
        if !wantArtist.isEmpty, gotTitle.contains(wantArtist), wantTitle.count < 4 { return false }
        return wantTitle.split(separator: " ").count <= 1
    }

    private func handleScanOutcome(
        gen: Int,
        vote: (key: String, value: Int)?,
        query: String?,
        ocrSample: String,
        track: PreviewTrack? = nil,
        ocrParse: CardOCRParse? = nil,
        skipRecognizedCue: Bool = false
    ) async {
        guard gen == generation else { return }
        lastOCRText = ocrSample

        guard let vote, vote.value >= 1, let query, let track else {
            dlog("[CARD] scan #\(scanAttempts): no confident song")
            if let ocrParse {
                applyCardWordsIfNeeded(ocrParse)
            }
            if scanAttempts >= CardSettings.maxScanRetries {
                failScanMaxRetries()
            } else {
                state = .armed
                AppModel.shared.primeCardVolumeScanHeadroom(reason: "scan retry armed")
                PerformanceCues.cardScanFailed()
            }
            return
        }

        let highConfidence = vote.value >= 2
        candidateLabel = "\(track.title) — \(track.artist)"
        pendingCandidateKey = vote.key
        pendingCandidateQuery = query

        if context == .perform {
            if !skipRecognizedCue {
                PerformanceCues.cardSongRecognized()
            }
            if AppModel.shared.loadState == .ready {
                PerformanceCues.cardSongReady()
            }
        }

        if highConfidence {
            dlog("[CARD] ★ auto-lock (\(vote.value) votes) · \(candidateLabel ?? "?")")
            lock(reason: "OCR consensus", auto: true, playLockHaptic: false)
        } else {
            dlog("[CARD] ? candidate (1 vote) · \(candidateLabel ?? "?") — volume up again to confirm")
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
            for q in CardTextMapper.songSearchVariants(from: raw) {
                guard q.count >= 2 else { continue }
                if skipWords.contains(where: { ApiJSON.sameText(q, $0) }) {
                    dlog("[CARD] skip song query (matches word line): “\(q)”")
                    continue
                }
                guard !queries.contains(where: { ApiJSON.sameText($0, q) }) else { continue }
                queries.append(q)
            }
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
