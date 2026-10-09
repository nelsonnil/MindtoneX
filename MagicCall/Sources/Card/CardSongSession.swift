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
    /// Spectators = 2: song 1 loaded by an earlier scan of this Perform; the next scan only looks for song 2.
    private var twoSongFirstReady = false

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
        twoSongFirstReady = false
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
            if SpectatorSettings.isTwo {
                SecondSpectatorSong.shared.abandon(reason: "call before song 2")
            }
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
            if VoiceSettings.apiKey != nil {
                PerformUserLog.shared.log(
                    "Camera · snapshot + OpenAI (~\(String(format: "%.1f", CardSettings.burstSeconds)) s)"
                )
            } else {
                PerformUserLog.shared.log(
                    "Camera · OpenAI skipped (no API key — add under Performance settings)"
                )
                PerformUserLog.shared.log(
                    "Camera · snapshot + local OCR (~\(String(format: "%.1f", CardSettings.burstSeconds)) s)"
                )
            }
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
        if !CardSettings.cameraAuthorized {
            if context == .perform {
                PerformUserLog.shared.log("Camera · OCR failed · camera access denied (Settings → MindtoneX → Camera)")
            }
            await handleScanOutcome(gen: gen, vote: nil, query: nil, ocrSample: "")
            return
        }
        let gotFrame = await capture.waitForFirstFrame(timeout: 0.85)
        guard gen == generation else { return }
        if !gotFrame {
            if context == .perform {
                PerformUserLog.shared.log("Camera · OCR failed · camera not running (no video frame yet — try volume up again)")
            }
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
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
                if context == .perform {
                    PerformUserLog.shared.log("Camera · OCR failed · blank frame (no pixels captured)")
                }
                await handleScanOutcome(gen: gen, vote: nil, query: nil, ocrSample: "")
                return
            }
            bestBuffer = frames.first
            var maxObservations = 0
            for (i, buf) in frames.prefix(4).enumerated() {
                let vision = await CardOCRProcessor.recognizeDetailed(buf)
                maxObservations = max(maxObservations, vision.observationCount)
                let lines = vision.readings
                if !lines.isEmpty {
                    dlog("[OCR] frame \(i + 1): \(lines.map(\.text).joined(separator: " | "))")
                }
                frameTexts.append(lines)
                if CardOCRProcessor.lineScore(lines) > CardOCRProcessor.lineScore(bestLineReadings) {
                    bestLineReadings = lines
                    bestBuffer = buf
                }
            }
            if context == .perform, bestLineReadings.isEmpty {
                logLocalOCRFailure(observationCount: maxObservations, gotFrame: gotFrame)
            }
        } else {
            for (i, sample) in ranked.enumerated() {
                dlog("[OCR] ranked \(i + 1): \(sample.readings.map(\.text).joined(separator: " | "))")
            }
            if context == .perform, bestLineReadings.isEmpty {
                logLocalOCRFailure(observationCount: 0, gotFrame: gotFrame)
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

        if SpectatorSettings.isTwo {
            var jpeg: Data?
            if VoiceSettings.apiKey != nil, let buf = bestBuffer {
                jpeg = CardImageEncoder.jpegData(from: buf)
            }
            stopCaptureIfNeeded()
            if context == .perform, !snapshotCuePlayed, jpeg != nil {
                snapshotCuePlayed = true
                PerformanceCues.cardSnapshotSent()
                PerformUserLog.shared.log("Camera · photo sent · reading two songs…")
            }
            await runTwoSongRead(gen: gen, jpeg: jpeg, bestLineReadings: bestLineReadings)
            return
        }

        if VoiceSettings.apiKey != nil, bestBuffer == nil, context == .perform {
            PerformUserLog.shared.log("Camera · OpenAI skipped · no snapshot frame")
        }
        if VoiceSettings.apiKey != nil, let buf = bestBuffer, CardImageEncoder.jpegData(from: buf) == nil, context == .perform {
            PerformUserLog.shared.log("Camera · OpenAI skipped · could not encode photo · local OCR")
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
                let tOpenAI = CACurrentMediaTime()
                let ai = try await CardHandwritingPicker.pick(
                    jpeg: jpeg,
                    visionOCRHint: hint,
                    expectCallerLine: CardOCRLayout.usesCallerLine,
                    expectNotesLine: CardOCRLayout.usesNotesLine
                )
                let openAIMs = PreviewService.ms(since: tOpenAI)
                dlog("[CARD] OpenAI vision · \(ai.reasoning) · conf=\(String(format: "%.2f", ai.confidence)) · query=\(ai.searchQuery)")
                if context == .perform {
                    PerformLogReporter.logOpenAICardAnswer(ai, ms: openAIMs)
                }
                let ocr = ai.asOCRParse(
                    expectCaller: CardOCRLayout.usesCallerLine,
                    expectNotes: CardOCRLayout.usesNotesLine
                )
                applyCardWordsIfNeeded(ocr)
                if ai.hasSong {
                    var queryBatches: [[String]] = [ai.storeSearchQueries()]
                    let retry = ai.storeSearchRetryQueries()
                    if !retry.isEmpty { queryBatches.append(retry) }
                    for (batchIndex, batch) in queryBatches.enumerated() {
                        if let match = await searchCardSongWithQueries(
                            batch,
                            pick: ai,
                            gen: gen,
                            retryPass: batchIndex > 0
                        ) {
                            await handleScanOutcome(
                                gen: gen,
                                vote: (match.key, 2),
                                query: match.query,
                                ocrSample: hint,
                                track: match.track,
                                ocrParse: ocr,
                                skipRecognizedCue: snapshotCuePlayed
                            )
                            return
                        }
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
            if orderedLines.isEmpty {
                PerformUserLog.shared.log("Camera · OCR lines: (none — zero text recognized)")
            } else {
                PerformUserLog.shared.log("Camera · OCR lines: \(orderedLines.joined(separator: " | "))")
            }
            let l1 = ocr.songQuery.isEmpty ? "—" : WordApiInputPanel.truncated(ocr.songQuery, max: 28)
            let l2 = ocr.callerLine.map { WordApiInputPanel.truncated($0, max: 24) } ?? "—"
            let l3 = ocr.notesLine.map { WordApiInputPanel.truncated($0, max: 24) } ?? "—"
            PerformUserLog.shared.log("Camera · OCR read · L1 «\(l1)» · L2 «\(l2)» · L3 «\(l3)»")
            if ocr.songQuery.isEmpty {
                PerformUserLog.shared.log("Camera · song line empty — caller/notes lines do not block song search")
            }
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
            if queriesToTry.isEmpty {
                PerformUserLog.shared.log("Camera · song search skipped — no line-1 text (add OpenAI key for best read)")
            } else {
                PerformUserLog.shared.log("Camera · song search tries: \(queriesToTry.joined(separator: " · "))")
            }
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

    private func searchCardSongWithQueries(
        _ queries: [String],
        pick: CardHandwritingPick,
        gen: Int,
        retryPass: Bool
    ) async -> (track: PreviewTrack, query: String, key: String)? {
        for query in queries {
            guard query.count >= 2 else { continue }
            if context == .perform {
                let label = WordApiInputPanel.truncated(query, max: 40)
                if retryPass {
                    PerformUserLog.shared.log("Song search · retry «\(label)»")
                } else {
                    PerformUserLog.shared.log("Song search · try «\(label)»")
                }
            }
            let ok = await AppModel.shared.prepareCardQuery(query)
            guard gen == generation else { return nil }
            guard ok, let track = AppModel.shared.selected else {
                dlog("[CARD] OpenAI try “\(query)” → no match")
                continue
            }
            guard trackMatchesCardPick(track, pick: pick) else {
                dlog("[CARD] OpenAI reject store mismatch · wanted «\(pick.title)» got «\(track.title)»")
                continue
            }
            let key = CardTextMapper.canonicalKey(from: track)
            if context == .perform {
                PerformUserLog.shared.log("Song search · winner «\(query)» → \(track.title) — \(track.artist)")
            }
            return (track, query, key)
        }
        return nil
    }

    private func trackMatchesCardPick(_ track: PreviewTrack, pick: CardHandwritingPick) -> Bool {
        pick.accepts(track)
    }

    // MARK: Two spectators

    /// Spectators = 2: one card, two titles. Song 1 (top) loads into the normal slot exactly like one
    /// spectator; song 2 (below) loads next to it. Both are needed to lock, except on the last allowed scan.
    private func runTwoSongRead(gen: Int, jpeg: Data?, bestLineReadings: [CardOCRReading]) async {
        let hintLines = CardLineParser.expandMergedOCRLines(CardOCRProcessor.orderedLineTexts(from: bestLineReadings))
        let hint = hintLines.joined(separator: "\n")
        let lookupContext: SecondSpectatorSong.Context = context == .perform ? .perform : .test
        SecondSpectatorSong.shared.beginWaiting(source: "Camera", context: lookupContext)

        var firstPick: CardHandwritingPick?
        var secondPick: CardHandwritingPick?
        var words: CardOCRParse?
        var visionAnswered = false
        if let jpeg {
            do {
                let t0 = CACurrentMediaTime()
                let ai = try await CardHandwritingPicker.pickTwoSongs(
                    jpeg: jpeg,
                    visionOCRHint: hint,
                    expectCallerLine: CardOCRLayout.usesCallerLine,
                    expectNotesLine: CardOCRLayout.usesNotesLine
                )
                guard gen == generation else { return }
                let ms = PreviewService.ms(since: t0)
                dlog("[CARD] OpenAI two songs · 1=“\(ai.searchQuery1)” · 2=“\(ai.searchQuery2)” · conf=\(String(format: "%.2f", ai.confidence)) · \(ai.reasoning)")
                if context == .perform {
                    let one = ai.hasSong1 ? WordApiInputPanel.truncated(ai.searchQuery1, max: 32) : "—"
                    let two = ai.hasSong2 ? WordApiInputPanel.truncated(ai.searchQuery2, max: 32) : "—"
                    PerformUserLog.shared.log("OpenAI · card · song 1 «\(one)» · song 2 «\(two)» · \(Int((ai.confidence * 100).rounded()))% (\(ms) ms)")
                }
                let first = ai.firstSong
                let second = ai.secondSong
                if first.hasSong { firstPick = first }
                if second.hasSong { secondPick = second }
                words = ai.wordsParse(expectCaller: CardOCRLayout.usesCallerLine, expectNotes: CardOCRLayout.usesNotesLine)
                visionAnswered = true
            } catch {
                dlog("[CARD] OpenAI two songs fallback: \(error.localizedDescription)")
                if context == .perform {
                    PerformUserLog.shared.log("Camera · OpenAI failed · local OCR")
                }
            }
        }

        // Vision's answer decides the layout; local OCR lines are only a fallback when vision did not answer
        // (its "line 2" may be song 1's artist).
        let local = CardLineParser.parseTwoSongs(orderedLines: hintLines)
        let firstQueries: [String]
        let secondQueries: [String]
        if visionAnswered {
            firstQueries = Self.uniqueQueries(firstPick.map { $0.storeSearchQueries() + $0.storeSearchRetryQueries() } ?? [])
            secondQueries = Self.uniqueQueries(secondPick.map { $0.storeSearchQueries() + $0.storeSearchRetryQueries() } ?? [])
        } else {
            firstQueries = Self.uniqueQueries(CardTextMapper.songSearchVariants(from: local.song1))
            secondQueries = Self.uniqueQueries(CardTextMapper.songSearchVariants(from: local.song2))
        }
        if words == nil {
            words = CardOCRParse(songQuery: local.song1, callerLine: local.callerLine, notesLine: local.notesLine)
        }
        lastOCRText = hint
        dlog("[CARD] two songs · lines \(hintLines.joined(separator: " | ")) · song 1 tries \(firstQueries.joined(separator: " · ")) · song 2 tries \(secondQueries.joined(separator: " · "))")
        if context == .perform {
            let l1 = firstQueries.first.map { WordApiInputPanel.truncated($0, max: 28) } ?? "—"
            let l2 = secondQueries.first.map { WordApiInputPanel.truncated($0, max: 28) } ?? "—"
            PerformUserLog.shared.log("Camera · 2 spectators · song 1 «\(l1)» · song 2 «\(l2)»")
        }

        var songTwoTask: Task<PreviewTrack?, Never>?
        if !secondQueries.isEmpty {
            let pickForCheck = secondPick
            songTwoTask = Task { @MainActor in
                await SecondSpectatorSong.shared.lookup(
                    queries: secondQueries,
                    source: "Camera · song 2",
                    context: lookupContext,
                    accept: { track in pickForCheck?.accepts(track) ?? true }
                )
            }
        }

        var match: (track: PreviewTrack, query: String, key: String)?
        if twoSongFirstReady, AppModel.shared.loadState == .ready, let loaded = AppModel.shared.selected, let key = pendingCandidateKey {
            match = (loaded, pendingCandidateQuery, key)
            dlog("[CARD] two songs · song 1 already loaded (\(loaded.title)) — this scan only reads song 2")
        } else if let pick = firstPick {
            match = await searchCardSongWithQueries(firstQueries, pick: pick, gen: gen, retryPass: false)
        } else {
            for query in firstQueries {
                let ok = await AppModel.shared.prepareCardQuery(query)
                guard gen == generation else { return }
                if ok, let track = AppModel.shared.selected {
                    match = (track, query, CardTextMapper.canonicalKey(from: track))
                    if context == .perform {
                        PerformUserLog.shared.log("Camera · song 1 «\(query)» → \(track.title) — \(track.artist)")
                    }
                    break
                }
            }
        }
        guard gen == generation else { return }
        let secondTrack: PreviewTrack? = await songTwoTask?.value
        guard gen == generation else { return }

        guard let match else {
            dlog("[CARD] two songs · song 1 not found\(secondTrack != nil ? " (song 2 ready)" : "")")
            await handleScanOutcome(gen: gen, vote: nil, query: nil, ocrSample: hint, ocrParse: words)
            return
        }

        if secondTrack != nil || scanAttempts >= CardSettings.maxScanRetries {
            twoSongFirstReady = false
            await handleScanOutcome(
                gen: gen,
                vote: (match.key, 2),
                query: match.query,
                ocrSample: hint,
                track: match.track,
                ocrParse: words,
                skipRecognizedCue: snapshotCuePlayed
            )
            guard gen == generation else { return }
            if secondTrack != nil {
                SecondSpectatorSong.shared.confirm(source: "Camera · song 2", vibrationDelay: 1.4)
            } else {
                SecondSpectatorSong.shared.abandon(reason: "song 2 unreadable after \(scanAttempts) scans")
            }
            return
        }

        twoSongFirstReady = true
        candidateLabel = "\(match.track.title) — \(match.track.artist)"
        pendingCandidateKey = match.key
        pendingCandidateQuery = match.query
        state = .armed
        AppModel.shared.primeCardVolumeScanHeadroom(reason: "song 2 retry armed")
        PerformanceCues.cardCandidateUncertain()
        dlog("[CARD] two songs · song 1 ready, song 2 not read — waiting for another volume-up scan")
        if context == .perform {
            PerformUserLog.shared.log("Camera · song 1 ready · song 2 not read — press volume up to scan again")
        }
    }

    private static func uniqueQueries(_ raw: [String]) -> [String] {
        var out: [String] = []
        for query in raw {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, !out.contains(where: { ApiJSON.sameText($0, trimmed) }) else { continue }
            out.append(trimmed)
        }
        return out
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

    private func logLocalOCRFailure(observationCount: Int, gotFrame: Bool) {
        guard context == .perform else { return }
        if observationCount == 0 {
            PerformUserLog.shared.log("Camera · OCR failed · Vision saw 0 text regions (lighting, focus, or card too small)")
        } else {
            PerformUserLog.shared.log("Camera · OCR failed · Vision saw \(observationCount) region(s) but no readable lines")
        }
        if !gotFrame {
            PerformUserLog.shared.log("Camera · OCR hint · no frame before scan — hold card steady, then volume up")
        }
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

    /// After changing camera facing in Settings, swap the live capture device without leaving test/practice running.
    func restartCameraIfRunning() {
        guard captureRunning else { return }
        capture.invalidateConfiguration()
        do {
            try capture.start()
            dlog("[CARD] camera restarted · \(CardSettings.cameraFacing.segmentTitle)")
        } catch {
            captureRunning = false
            fail(error.localizedDescription)
        }
    }

}
