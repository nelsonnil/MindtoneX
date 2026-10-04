import AVFoundation
import UIKit

/// Ruta "tono real" de iOS 26: exporta el preview recortado a < 30 s como .m4a en
/// Documentos/Canciones (visible en la app Archivos) y abre la hoja de Compartir para que el mago
/// pulse "Usar como tono". Es una función de usuario documentada; no usa APIs privadas.
enum RingtoneExporter {
    enum ExportError: LocalizedError {
        case cannotCreateSession
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateSession: return "No se pudo crear AVAssetExportSession."
            case .failed(let message): return "Exportación fallida: \(message)"
            }
        }
    }

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Canciones", isDirectory: true)
    }

    /// Apple accepts custom ringtones only under ~30 s; export targets `RingtoneLimits.exportMaxSeconds`.
    ///
    /// “Use as Ringtone” may reject duplicates: each export gets a distinct name, metadata title, and trim jitter.
    static func export(data: Data, fileTypeHint: String, title: String, artist: String,
                       startAt: Double, maxSeconds: Double = RingtoneLimits.exportMaxSeconds) async throws -> URL {
        let ext = fileTypeHint == AVFileType.mp3.rawValue ? "mp3" : "m4a"
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString).\(ext)")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let jitter = Double(Int.random(in: 1...40)) / 100
        let begin = min(max(0, startAt) + jitter, max(0, duration - 5))
        let length = min(maxSeconds - Double(Int.random(in: 0...30)) / 100, duration - begin)

        let suffix = uniqueSuffix()
        let uniqueTitle = "\(title) \(suffix)"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeOldExports()
        let output = directory.appendingPathComponent(safeFilename(uniqueTitle) + ".m4a")

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.cannotCreateSession
        }
        session.outputURL = output
        session.outputFileType = .m4a
        session.metadata = metadata(title: uniqueTitle, artist: artist, comment: UUID().uuidString)
        session.timeRange = CMTimeRange(start: CMTime(seconds: begin, preferredTimescale: 600),
                                        duration: CMTime(seconds: length, preferredTimescale: 600))
        if #available(iOS 18.0, *) {
            do {
                try await session.export(to: output, as: .m4a)
            } catch {
                throw ExportError.failed(error.localizedDescription)
            }
        } else {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else {
                throw ExportError.failed(session.error?.localizedDescription ?? "estado \(session.status.rawValue)")
            }
        }
        dlog("Tono exportado: \(output.lastPathComponent) · título “\(uniqueTitle)” · \(String(format: "%.2f", length)) s desde \(String(format: "%.2f", begin)) s")
        return output
    }

    /// Hora + 2 letras al azar, p. ej. «1142a7»: corto y distinto en cada exportación.
    private static func uniqueSuffix() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HHmm"
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return f.string(from: Date()) + String((0..<2).map { _ in chars.randomElement()! })
    }

    private static func safeFilename(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = String(s.unicodeScalars.map { bad.contains($0) ? "-" : Character($0) })
        return String(cleaned.prefix(80))
    }

    private static func metadata(title: String, artist: String, comment: String) -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m
        }
        let date = ISO8601DateFormatter().string(from: Date())
        return [
            item(.commonIdentifierTitle, title),
            item(.commonIdentifierArtist, artist),
            item(.commonIdentifierCreationDate, date),
            item(.iTunesMetadataUserComment, comment),
        ]
    }

    /// Solo borra los archivos de esta app; los tonos ya añadidos a iOS no se pueden borrar desde aquí.
    static func removeOldExports() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        var removed = 0
        for url in files where ["m4a", "mp3", "m4r"].contains(url.pathExtension.lowercased()) {
            if (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        if removed > 0 { dlog("Tonos antiguos borrados de la carpeta de la app: \(removed)") }
    }

    @MainActor
    static func presentShareSheet(for url: URL, displayTitle: String) {
        RingtoneSharePresenter.present(url: url, title: displayTitle)
    }

    @MainActor
    static func presentQuickLook(for url: URL, displayTitle: String) {
        RingtoneSharePresenter.presentQuickLook(url: url, title: displayTitle)
    }
}
