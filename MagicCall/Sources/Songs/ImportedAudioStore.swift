import Foundation
import UniformTypeIdentifiers

enum ImportedAudioError: LocalizedError {
    case copyFailed(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .copyFailed(let detail): return "Could not import audio: \(detail)"
        case .unreadable: return "Could not read the selected file."
        }
    }
}

/// Copies user-picked audio into the app sandbox (Caches) and builds a library `PreviewTrack`.
enum ImportedAudioStore {
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("imported-audio", isDirectory: true)
    }

    /// Security-scoped URL from `.fileImporter` or an in-sandbox file URL.
    static func importTrack(from sourceURL: URL) throws -> PreviewTrack {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let dest = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")

        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            throw ImportedAudioError.copyFailed(error.localizedDescription)
        }

        guard fm.isReadableFile(atPath: dest.path) else { throw ImportedAudioError.unreadable }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let title = Self.displayTitle(from: stem)
        return PreviewTrack(
            title: title,
            artist: "Imported",
            album: nil,
            artworkURL: nil,
            previewURL: dest,
            source: .imported
        )
    }

    static var fileImporterTypes: [UTType] {
        var types: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]
        if let caf = UTType(filenameExtension: "caf") { types.append(caf) }
        return types
    }

    private static func displayTitle(from filenameStem: String) -> String {
        let trimmed = filenameStem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Imported audio" }
        let spaced = trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return spaced.split(separator: " ").map(String.init).joined(separator: " ")
    }
}
