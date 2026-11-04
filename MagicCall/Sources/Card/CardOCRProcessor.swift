import Foundation
import Vision

struct CardOCRReading: Sendable {
    let text: String
    /// Other Vision candidates for the same physical line, ordered by confidence.
    let alternatives: [String]
    let confidence: Float
    /// Vision normalized Y (higher = closer to top of frame) for top-to-bottom line order.
    let topRank: CGFloat
}

struct CardOCRVisionResult: Sendable {
    let readings: [CardOCRReading]
    let observationCount: Int
    let visionError: String?
}

/// Vision text recognition (revision 3, accurate; languages from `CardSettings.visionRecognitionLanguages`).
enum CardOCRProcessor {
    static func recognize(_ pixelBuffer: CVPixelBuffer) async -> [CardOCRReading] {
        let result = await recognizeDetailed(pixelBuffer)
        return result.readings
    }

    static func recognizeDetailed(_ pixelBuffer: CVPixelBuffer) async -> CardOCRVisionResult {
        await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err {
                    dlog("[OCR] Vision error: \(err.localizedDescription)")
                    cont.resume(returning: CardOCRVisionResult(readings: [], observationCount: 0, visionError: err.localizedDescription))
                    return
                }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [CardOCRReading] = []
                for obs in observations {
                    let candidates = obs.topCandidates(3)
                    guard let best = candidates.first else { continue }
                    let t = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard t.count >= 2 else { continue }
                    let alternatives = candidates.dropFirst()
                        .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.count >= 2 && !ApiJSON.sameText($0, t) }
                    let box = obs.boundingBox
                    let topRank = box.origin.y + box.height
                    lines.append(CardOCRReading(
                        text: t,
                        alternatives: alternatives,
                        confidence: best.confidence,
                        topRank: topRank
                    ))
                }
                cont.resume(returning: CardOCRVisionResult(readings: lines, observationCount: observations.count, visionError: nil))
            }
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = CardSettings.visionRecognitionLanguages
            request.minimumTextHeight = 0.03

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                dlog("[OCR] perform failed: \(error.localizedDescription)")
                cont.resume(returning: CardOCRVisionResult(readings: [], observationCount: 0, visionError: error.localizedDescription))
            }
        }
    }

    static func orderedLineTexts(from readings: [CardOCRReading]) -> [String] {
        readings
            .sorted { $0.topRank > $1.topRank }
            .map(\.text)
    }

    /// Bounded line hypotheses: the best reading plus alternatives for one line at a time.
    /// This catches a single wrong letter without an exponential combination explosion.
    static func orderedLineHypotheses(from readings: [CardOCRReading]) -> [[String]] {
        let ordered = readings.sorted { $0.topRank > $1.topRank }
        guard !ordered.isEmpty else { return [] }
        let primary = ordered.map(\.text)
        var out = [primary]
        for (lineIndex, reading) in ordered.enumerated() {
            for alternative in reading.alternatives.prefix(2) {
                var variant = primary
                variant[lineIndex] = alternative
                if !out.contains(where: { linesEqual($0, variant) }) {
                    out.append(variant)
                }
            }
        }
        return Array(out.prefix(7))
    }

    private static func linesEqual(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { ApiJSON.sameText($0, $1) }
    }

    static func lineScore(_ readings: [CardOCRReading]) -> Double {
        readings.reduce(0) { $0 + Double($1.confidence) }
    }

    static func mergedText(from readings: [[CardOCRReading]]) -> [String] {
        readings.map { frame in
            frame
                .filter { $0.confidence >= 0.25 }
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { $0.count >= 2 }
    }
}
