import Foundation

/// Persisted recent picks and user favorites (`PreviewTrack` in UserDefaults JSON).
@MainActor
final class SongLibraryStore: ObservableObject {
    static let shared = SongLibraryStore()

    private enum Keys {
        static let recent = "songLibrary.recent.v1"
        static let favorites = "songLibrary.favorites.v1"
    }

    private static let maxRecent = 20

    @Published private(set) var recent: [PreviewTrack] = []
    @Published private(set) var favorites: [PreviewTrack] = []

    private init() {
        recent = Self.loadTracks(forKey: Keys.recent)
        favorites = Self.loadTracks(forKey: Keys.favorites)
    }

    func isFavorite(_ track: PreviewTrack) -> Bool {
        favorites.contains { $0.id == track.id }
    }

    func recordRecent(_ track: PreviewTrack) {
        var list = recent.filter { $0.id != track.id }
        list.insert(track, at: 0)
        if list.count > Self.maxRecent {
            list = Array(list.prefix(Self.maxRecent))
        }
        recent = list
        persist(list, forKey: Keys.recent)
    }

    func toggleFavorite(_ track: PreviewTrack) {
        if let index = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(track, at: 0)
        }
        persist(favorites, forKey: Keys.favorites)
    }

    private func persist(_ tracks: [PreviewTrack], forKey key: String) {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadTracks(forKey key: String) -> [PreviewTrack] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PreviewTrack].self, from: data) else {
            return []
        }
        return decoded
    }
}
