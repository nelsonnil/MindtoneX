import Foundation
import Vision

struct CardOCRReading: Sendable {
    let text: String
    let confidence: Float
}

/// Vision text recognition (revision 3, accurate, EN+ES).
enum CardOCRProcessor {
    static func recognize(_ pixelBuffer: CVPixelBuffer) async -> [CardOCRReading] {
        await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err {
                    dlog("[OCR] Vision error: \(err.localizedDescription)")
                    cont.resume(returning: [])
                    return
                }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [CardOCRReading] = []
                for obs in observations {
                    guard let best = obs.topCandidates(1).first else { continue }
                    let t = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard t.count >= 2 else { continue }
                    lines.append(CardOCRReading(text: t, confidence: best.confidence))
                }
                cont.resume(returning: lines)
            }
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "es-ES"]
            request.minimumTextHeight = 0.03

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                dlog("[OCR] perform failed: \(error.localizedDescription)")
                cont.resume(returning: [])
            }
        }
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
