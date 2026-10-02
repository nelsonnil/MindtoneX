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

    /// iOS 26 exige clips de menos de 30 s; los previews de iTunes duran 30,0 s, así que se recortan.
    static func export(data: Data, fileTypeHint: String, title: String,
                       startAt: Double, maxSeconds: Double = 28) async throws -> URL {
        let ext = fileTypeHint == AVFileType.mp3.rawValue ? "mp3" : "m4a"
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString).\(ext)")
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let begin = min(max(0, startAt), max(0, duration - 5))
        let length = min(maxSeconds, duration - begin)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(safeFileName(title) + ".m4a")
        try? FileManager.default.removeItem(at: output)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.cannotCreateSession
        }
        session.outputURL = output
        session.outputFileType = .m4a
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
        dlog("Tono exportado: \(output.lastPathComponent) · \(String(format: "%.1f", length)) s desde \(String(format: "%.1f", begin)) s")
        return output
    }

    @MainActor
    static func presentShareSheet(for url: URL) {
        guard let root = UIApplication.mcKeyWindow?.rootViewController else {
            dlog("✗ No hay ventana para presentar Compartir")
            return
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { activity, completed, _, error in
            dlog("Compartir: actividad=\(activity?.rawValue ?? "ninguna") completado=\(completed)\(error.map { " error=\($0.localizedDescription)" } ?? "")")
        }
        top.present(sheet, animated: true)
        dlog("Hoja Compartir abierta. Busca “Usar como tono” (puede estar en “Más”).")
    }

    private static func safeFileName(_ s: String) -> String {
        let cleaned = s.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
        return String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
    }
}
