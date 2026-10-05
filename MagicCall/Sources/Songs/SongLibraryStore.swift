import Foundation

/// Persisted recent picks and user favorites (`PreviewTrack` in UserDefaults JSON).
@MainActor
final class SongLibraryStore: ObservableObject {
    static let shared = SongLibraryStore()

    private enum Keys {
        static let recent = "songLibrary.recent.v1"
        static let favorites = "songLibrary.favorites.v1"
        static let performSnapshots = "songLibrary.performSnapshots.v1"
    }

    private static let maxRecent = 20

    @Published private(set) var recent: [PreviewTrack] = []
    @Published private(set) var favorites: [PreviewTrack] = []
    @Published private(set) var performSnapshots: [RecentPerformSnapshot] = []
    /// Last loaded/locked track during Perform — for Home UI after clear.
    @Published private(set) var lastPerformTrack: PreviewTrack?

    private init() {
        reloadFromDisk()
    }

    /// Recent rows for UI: snapshots not yet in JSON recents + persisted recents.
    var recentDisplayTracks: [PreviewTrack] {
        let snapTracks = performSnapshots
            .sorted { $0.lockedAt > $1.lockedAt }
            .filter { snap in !recent.contains(where: { snap.matches($0) }) }
            .map { $0.asSyntheticPreviewTrack() }
        var merged = snapTracks + recent
        if let last = lastPerformTrack, !merged.contains(where: { $0.id == last.id }) {
            merged.insert(last, at: 0)
        }
        if merged.count > Self.maxRecent {
            merged = Array(merged.prefix(Self.maxRecent))
        }
        return merged
    }

    func logRecentDisplayMerge(context: String) {
        let merged = recentDisplayTracks
        let snapOnly = merged.filter { RecentPerformSnapshot.isSnapshotPlaceholder($0) }.count
        dlog("[LIBRARY] recentDisplayTracks (\(context)) merged=\(merged.count) snapOnly=\(snapOnly) recent=\(recent.count) snapshots=\(performSnapshots.count) lastPerform=\(lastPerformTrack?.title ?? "nil")")
    }

    /// Re-read persisted lists (e.g. after another code path wrote UserDefaults).
    func reloadFromDisk() {
        let loadedRecent = Self.loadTracks(forKey: Keys.recent)
        let loadedFavorites = Self.loadTracks(forKey: Keys.favorites)
        let loadedSnapshots = Self.loadSnapshots()
        recent = loadedRecent
        favorites = loadedFavorites
        performSnapshots = loadedSnapshots
        if lastPerformTrack == nil, let first = loadedSnapshots.first {
            lastPerformTrack = first.asPreviewTrackIfPossible() ?? first.asSyntheticPreviewTrack()
        }
        dlog("[LIBRARY] reloadFromDisk recent=\(loadedRecent.count) favorites=\(loadedFavorites.count) snapshots=\(loadedSnapshots.count)")
    }

    func searchQuery(forDisplayTrack track: PreviewTrack) -> String? {
        if RecentPerformSnapshot.isSnapshotPlaceholder(track) {
            if let snap = performSnapshots.first(where: { $0.asSyntheticPreviewTrack().id == track.id }) {
                return snap.searchQuery
            }
            return track.album
        }
        return nil
    }

    func isFavorite(_ track: PreviewTrack) -> Bool {
        favorites.contains { $0.id == track.id }
    }

    func commitPerformSnapshot(_ snapshot: RecentPerformSnapshot) {
        var snaps = performSnapshots.filter { $0.dedupeKey != snapshot.dedupeKey }
        snaps.insert(snapshot, at: 0)
        if snaps.count > Self.maxRecent {
            snaps = Array(snaps.prefix(Self.maxRecent))
        }
        performSnapshots = snaps
        persistSnapshots(snaps)
        let display = snapshot.asPreviewTrackIfPossible() ?? snapshot.asSyntheticPreviewTrack()
        lastPerformTrack = display
        dlog("[LIBRARY] lock snapshot “\(snapshot.title) — \(snapshot.artist)” query=\(snapshot.searchQuery) preview=\(snapshot.previewURL ?? "nil") · snapshots=\(snaps.count)")

        if let track = snapshot.asPreviewTrackIfPossible() {
            recordRecent(track, reason: "performSnapshot")
        }
    }

    func commitPerformTrack(_ track: PreviewTrack, reason: String) {
        lastPerformTrack = track
        recordRecent(track, reason: "perform:\(reason)")
        dlog("[LIBRARY] commitPerformTrack (\(reason)) “\(track.title) — \(track.artist)”")
    }

    func recordRecent(_ track: PreviewTrack, reason: String = "recordRecent") {
        var list = recent.filter { $0.id != track.id }
        list.insert(track, at: 0)
        if list.count > Self.maxRecent {
            list = Array(list.prefix(Self.maxRecent))
        }
        recent = list
        let ok = persist(list, forKey: Keys.recent)
        dlog("[LIBRARY] recordRecent (\(reason)) “\(track.title) — \(track.artist)” ok=\(ok) count=\(list.count)")
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
        let tracks = recentDisplayTracks
        guard tracks.indices.contains(index) else { return }
        removeRecent(tracks[index])
    }

    func removeRecent(_ track: PreviewTrack) {
        let beforeRecent = recent.count
        recent.removeAll { $0.id == track.id }
        if recent.count != beforeRecent {
            _ = persist(recent, forKey: Keys.recent)
        }
        if lastPerformTrack?.id == track.id {
            lastPerformTrack = nil
        }
        if RecentPerformSnapshot.isSnapshotPlaceholder(track) {
            performSnapshots.removeAll { $0.asSyntheticPreviewTrack().id == track.id }
            persistSnapshots(performSnapshots)
        } else if let snap = performSnapshots.first(where: { $0.matches(track) }) {
            performSnapshots.removeAll { $0.id == snap.id }
            persistSnapshots(performSnapshots)
        }
        dlog("[LIBRARY] removeRecent “\(track.title)” · recent=\(recent.count) snapshots=\(performSnapshots.count)")
    }

    func clearRecent() {
        guard !recent.isEmpty || !performSnapshots.isEmpty || lastPerformTrack != nil else { return }
        recent = []
        performSnapshots = []
        lastPerformTrack = nil
        UserDefaults.standard.removeObject(forKey: Keys.recent)
        UserDefaults.standard.removeObject(forKey: Keys.performSnapshots)
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
            dlog("[LIBRARY] persist JSON key=\(key) bytes=\(data.count) tracks=\(tracks.count)")
            return true
        } catch {
            dlog("[LIBRARY] ✗ persist encode failed key=\(key): \(error.localizedDescription)")
            return false
        }
    }

    private func persistSnapshots(_ snapshots: [RecentPerformSnapshot]) {
        do {
            let data = try JSONEncoder().encode(snapshots)
            UserDefaults.standard.set(data, forKey: Keys.performSnapshots)
            dlog("[LIBRARY] persist snapshots bytes=\(data.count) count=\(snapshots.count)")
        } catch {
            dlog("[LIBRARY] ✗ persist snapshots encode failed: \(error.localizedDescription)")
        }
    }

    private static func loadTracks(forKey key: String) -> [PreviewTrack] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([PreviewTrack].self, from: data)
        } catch {
            dlog("[LIBRARY] ✗ loadTracks decode failed key=\(key): \(error.localizedDescription)")
            return []
        }
    }

    private static func loadSnapshots() -> [RecentPerformSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: Keys.performSnapshots) else { return [] }
        do {
            return try JSONDecoder().decode([RecentPerformSnapshot].self, from: data)
        } catch {
            dlog("[LIBRARY] ✗ loadSnapshots decode failed: \(error.localizedDescription)")
            return []
        }
    }
}
