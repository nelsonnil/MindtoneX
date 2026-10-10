import Foundation

struct AlbumArtContactRestoreEntry: Codable, Equatable {
    var identifier: String
    /// Previous image bytes when `hadImage` is true; ignored when false.
    var previousImageData: Data?
    /// False when the contact had no photo before MindtoneX applied album art.
    var hadImage: Bool
    /// Contact created only for album art (restore = delete card).
    var createdForShow: Bool
}

enum AlbumArtContactRestoreStore {
    private static let key = "albumArtContact.restore.snapshots"

    static var entries: [AlbumArtContactRestoreEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AlbumArtContactRestoreEntry].self, from: data)) ?? []
    }

    static var hasPendingRestore: Bool { !entries.isEmpty }

    static func replaceEntries(_ list: [AlbumArtContactRestoreEntry]) {
        if list.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
