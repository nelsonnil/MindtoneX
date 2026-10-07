import AVFoundation
import CryptoKit
import Foundation
import QuartzCore

struct PreviewTrack: Identifiable, Hashable, Codable {
    enum Source: String, Codable {
        case itunes = "iTunes"
        case deezer = "Deezer"
        case imported = "Imported"
    }

    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let previewURL: URL
    let source: Source

    var id: String { source.rawValue + "|" + previewURL.absoluteString }

    var fileTypeHint: String {
        switch source {
        case .deezer:
            return AVFileType.mp3.rawValue
        case .itunes:
            return AVFileType.m4a.rawValue
        case .imported:
            switch previewURL.pathExtension.lowercased() {
            case "mp3": return AVFileType.mp3.rawValue
            case "wav": return AVFileType.wav.rawValue
            case "caf": return AVFileType.caf.rawValue
            case "aiff", "aif": return AVFileType.aiff.rawValue
            default: return AVFileType.m4a.rawValue
            }
        }
    }
}

enum PreviewError: LocalizedError {
    case noResults(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .noResults(let q): return "No se encontró ningún preview para “\(q)”."
        case .badResponse(let code): return "Respuesta HTTP \(code)."
        }
    }
}

/// Búsqueda de previews: iTunes Search API (tienda local → US) y Deezer como respaldo.
/// La caché en memoria siempre está activa; la de disco es opcional (ver notas de licencia).
actor PreviewService {
    private let session: URLSession
    private var searchCache: [String: [PreviewTrack]] = [:]
    private var audioCache: [URL: Data] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    /// Abre conexiones TLS por adelantado para que la primera búsqueda real sea más rápida.
    func warmUp() async {
        for host in ["https://itunes.apple.com/", "https://audio-ssl.itunes.apple.com/", "https://api.deezer.com/"] {
            guard let url = URL(string: host) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            let t0 = CACurrentMediaTime()
            _ = try? await session.data(for: req)
            dlog("Precalentado \(url.host ?? host): \(Self.ms(since: t0)) ms")
        }
    }

    func search(_ rawQuery: String) async throws -> [PreviewTrack] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.normalize(query)
        if let cached = searchCache[key] {
            dlog("Búsqueda en caché: “\(query)”")
            return cached
        }

        let storefront = Self.storefront()
        var found: [PreviewTrack] = []
        do {
            found = try await itunes(query, country: storefront)
        } catch {
            dlog("iTunes (\(storefront)) falló: \(error.localizedDescription)")
        }
        if found.isEmpty && storefront != "US" {
            found = (try? await itunes(query, country: "US")) ?? []
        }
        if found.isEmpty && Prefs.deezerFallback {
            do { found = try await deezer(query) } catch { dlog("Deezer falló: \(error.localizedDescription)") }
        }
        let ranked = Self.rank(found, for: query)
        guard !ranked.isEmpty else { throw PreviewError.noResults(query) }
        searchCache[key] = ranked
        return ranked
    }

    func audioData(for track: PreviewTrack) async throws -> Data {
        if track.source == .imported {
            if let data = audioCache[track.previewURL] {
                dlog("Imported audio en caché de memoria (\(data.count / 1024) KB)")
                return data
            }
            let data = try Data(contentsOf: track.previewURL)
            guard !data.isEmpty else { throw ImportedAudioError.unreadable }
            audioCache[track.previewURL] = data
            dlog("Imported audio leído (\(data.count / 1024) KB)")
            return data
        }
        if let data = audioCache[track.previewURL] {
            dlog("Audio en caché de memoria (\(data.count / 1024) KB)")
            return data
        }
        let diskURL = Self.diskURL(for: track.previewURL)
        if Prefs.diskCache, let data = try? Data(contentsOf: diskURL) {
            audioCache[track.previewURL] = data
            dlog("Audio en caché de disco (\(data.count / 1024) KB)")
            return data
        }
        let t0 = CACurrentMediaTime()
        let (data, response) = try await session.data(from: track.previewURL)
        try Self.check(response)
        dlog("Descarga preview \(track.source.rawValue): \(data.count / 1024) KB en \(Self.ms(since: t0)) ms")
        audioCache[track.previewURL] = data
        if Prefs.diskCache {
            try? FileManager.default.createDirectory(at: diskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: diskURL)
        }
        return data
    }

    func clearCaches() {
        searchCache.removeAll()
        audioCache.removeAll()
        try? FileManager.default.removeItem(at: Self.diskDirectory)
        dlog("Cachés de previews borradas")
    }

    // MARK: Fuentes

    private struct ITunesResponse: Decodable {
        struct Item: Decodable {
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let previewUrl: String?
            let artworkUrl100: String?
        }
        let results: [Item]
    }

    private func itunes(_ query: String, country: String) async throws -> [PreviewTrack] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "country", value: country),
        ]
        let t0 = CACurrentMediaTime()
        let (data, response) = try await session.data(from: comps.url!)
        try Self.check(response)
        let decoded = try JSONDecoder().decode(ITunesResponse.self, from: data)
        let tracks = decoded.results.compactMap { item -> PreviewTrack? in
            guard let title = item.trackName, let artist = item.artistName,
                  let p = item.previewUrl, let url = URL(string: p) else { return nil }
            return PreviewTrack(title: title, artist: artist, album: item.collectionName,
                                artworkURL: item.artworkUrl100.flatMap(URL.init(string:)),
                                previewURL: url, source: .itunes)
        }
        dlog("iTunes \(country): \(tracks.count) con preview en \(Self.ms(since: t0)) ms")
        return tracks
    }

    private struct DeezerResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let title: String?; let cover_medium: String? }
            let title: String
            let preview: String?
            let artist: Artist
            let album: Album?
        }
        let data: [Item]
    }

    private func deezer(_ query: String) async throws -> [PreviewTrack] {
        var comps = URLComponents(string: "https://api.deezer.com/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "15")]
        let t0 = CACurrentMediaTime()
        let (data, response) = try await session.data(from: comps.url!)
        try Self.check(response)
        let decoded = try JSONDecoder().decode(DeezerResponse.self, from: data)
        let tracks = decoded.data.compactMap { item -> PreviewTrack? in
            guard let p = item.preview, !p.isEmpty, let url = URL(string: p) else { return nil }
            return PreviewTrack(title: item.title, artist: item.artist.name, album: item.album?.title,
                                artworkURL: item.album?.cover_medium.flatMap(URL.init(string:)),
                                previewURL: url, source: .deezer)
        }
        dlog("Deezer: \(tracks.count) con preview en \(Self.ms(since: t0)) ms")
        return tracks
    }

    // MARK: Ranking

    private static let suspiciousWords = ["karaoke", "tribute", "tributo", "cover", "instrumental",
                                          "in the style of", "made famous", "originally performed",
                                          "live", "en vivo", "directo", "remix", "8-bit", "lullaby",
                                          "piano version", "acoustic"]

    static func rank(_ tracks: [PreviewTrack], for query: String) -> [PreviewTrack] {
        let q = normalize(query)
        let tokens = Set(q.split(separator: " ").map(String.init).filter { $0.count > 1 })
        var seen = Set<String>()
        let scored = tracks.enumerated().map { index, track -> (PreviewTrack, Double) in
            let hay = normalize(track.title + " " + track.artist)
            let hits = tokens.filter { hay.contains($0) }.count
            var score = tokens.isEmpty ? 0 : Double(hits) / Double(tokens.count) * 10
            let titleNorm = normalize(track.title)
            if q.contains(titleNorm) { score += 3 }
            for w in suspiciousWords where hay.contains(w) && !q.contains(w) { score -= 4 }
            score -= Double(index) * 0.25
            if track.source == .deezer { score -= 0.5 }
            return (track, score)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0).filter {
            seen.insert(normalize($0.title + "|" + $0.artist)).inserted
        }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9ñ ]", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: Utilidades

    private static func storefront() -> String {
        SongStorefront.effectiveCode()
    }

    private static var diskDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("previews", isDirectory: true)
    }

    private static func diskURL(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return diskDirectory.appendingPathComponent(hash + ".bin")
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PreviewError.badResponse(http.statusCode)
        }
    }

    static func ms(since t0: CFTimeInterval) -> Int {
        Int((CACurrentMediaTime() - t0) * 1000)
    }
}
