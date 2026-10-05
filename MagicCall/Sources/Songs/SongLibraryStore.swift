import Foundation

/// Persisted recent picks and user favorites (`PreviewTrack` in UserDefaults JSON).
@MainActor
final class SongLibraryStore: ObservableObject {
    static let shared = SongLibraryStore()

    private enum Keys {
        static let recent = "songLibrary.recent.v1"
        static let favorites = "songLibrary.favorites.v1"
        static let performSnapshot = "songLibrary.performSnapshot.v1"
    }

    private static let maxRecent = 20

    @Published private(set) var recent: [PreviewTrack] = []
    @Published private(set) var favorites: [PreviewTrack] = []
    /// Last song heard/locked during Perform — survives `clearSongForNextPerformance` for Home + Recent merge.
    @Published private(set) var lastPerformTrack: PreviewTrack?

    private init() {
        reloadFromDisk()
    }

    /// Recent list plus perform snapshot when JSON recent lagged or was cleared.
    var recentDisplayTracks: [PreviewTrack] {
        mergeRecentWithSnapshot(recent, snapshot: lastPerformTrack)
    }

    /// Re-read persisted lists (e.g. after another code path wrote UserDefaults).
    func reloadFromDisk() {
        let loadedRecent = Self.loadTracks(forKey: Keys.recent)
        let loadedFav = Self.loadTracks(forKey: Keys.favorites)
        let snap = Self.loadSnapshot(forKey: Keys.performSnapshot)
        recent = loadedRecent
        favorites = loadedFav
        lastPerformTrack = snap
        dlog("[LIBRARY] reloadFromDisk recent=\(loadedRecent.count) favorites=\(loadedFav.count) snapshot=\(snap?.title ?? "nil")")
    }

    func isFavorite(_ track: PreviewTrack) -> Bool {
        favorites.contains { $0.id == track.id }
    }

    func recordRecent(_ track: PreviewTrack, reason: String = "recordRecent") {
        var list = recent.filter { $0.id != track.id }
        list.insert(track, at: 0)
        if list.count > Self.maxRecent {
            list = Array(list.prefix(Self.maxRecent))
        }
        recent = list
        let ok = persist(list, forKey: Keys.recent)
        dlog("[LIBRARY] recordRecent (\(reason)) “\(track.title)” ok=\(ok) count=\(list.count)")
    }

    /// Call when a Perform run produced a loaded/locked song (AI Voice, Notes, API, or manual trigger).
    func commitPerformTrack(_ track: PreviewTrack, reason: String) {
        lastPerformTrack = track
        let snapOk = persistSnapshot(track)
        recordRecent(track, reason: "perform:\(reason)")
        dlog("[LIBRARY] commitPerformTrack (\(reason)) “\(track.title) — \(track.artist)” snapOk=\(snapOk)")
    }

    func toggleFavorite(_ track: PreviewTrack) {
        if let index = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(track, at: 0)
        }
        _ = persist(favorites, forKey: Keys.favorites)
    }

    func removeRecent(at index: Int) {
        guard recent.indices.contains(index) else { return }
        recent.remove(at: index)
        _ = persist(recent, forKey: Keys.recent)
    }

    func removeRecent(_ track: PreviewTrack) {
        let before = recent.count
        recent.removeAll { $0.id == track.id }
        guard recent.count != before else { return }
        _ = persist(recent, forKey: Keys.recent)
        if lastPerformTrack?.id == track.id {
            lastPerformTrack = nil
            UserDefaults.standard.removeObject(forKey: Keys.performSnapshot)
        }
    }

    func clearRecent() {
        guard !recent.isEmpty || lastPerformTrack != nil else { return }
        recent = []
        lastPerformTrack = nil
        UserDefaults.standard.removeObject(forKey: Keys.recent)
        UserDefaults.standard.removeObject(forKey: Keys.performSnapshot)
        dlog("[LIBRARY] clearRecent")
    }

    func removeFavorite(_ track: PreviewTrack) {
        let before = favorites.count
        favorites.removeAll { $0.id == track.id }
        guard favorites.count != before else { return }
        _ = persist(favorites, forKey: Keys.favorites)
    }

    @discardableResult
    private func persist(_ tracks: [PreviewTrack], forKey key: String) -> Bool {
        do {
            let data = try JSONEncoder().encode(tracks)
            UserDefaults.standard.set(data, forKey: key)
            return true
        } catch {
            dlog("[LIBRARY] ✗ persist \(key): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func persistSnapshot(_ track: PreviewTrack) -> Bool {
        do {
            let data = try JSONEncoder().encode(track)
            UserDefaults.standard.set(data, forKey: Keys.performSnapshot)
            return true
        } catch {
            dlog("[LIBRARY] ✗ persist snapshot: \(error.localizedDescription)")
            return false
        }
    }

    private static func loadTracks(forKey key: String) -> [PreviewTrack] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([PreviewTrack].self, from: data)
        } catch {
            dlog("[LIBRARY] ✗ decode \(key): \(error.localizedDescription)")
            return []
        }
    }

    private static func loadSnapshot(forKey key: String) -> PreviewTrack? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(PreviewTrack.self, from: data)
        } catch {
            dlog("[LIBRARY] ✗ decode snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    private func mergeRecentWithSnapshot(_ recent: [PreviewTrack], snapshot: PreviewTrack?) -> [PreviewTrack] {
        guard let snap = snapshot else { return recent }
        if recent.contains(where: { $0.id == snap.id }) { return recent }
        var merged = recent
        merged.insert(snap, at: 0)
        if merged.count > Self.maxRecent {
            merged = Array(merged.prefix(Self.maxRecent))
        }
        return merged
    }
}
