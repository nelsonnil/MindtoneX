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

    /// First snapshot per card wins: a second apply in the same session must not record album art as the "previous" photo.
    static func mergeEntries(_ list: [AlbumArtContactRestoreEntry]) {
        var merged = entries
        for entry in list where !merged.contains(where: { $0.identifier == entry.identifier }) {
            merged.append(entry)
        }
        replaceEntries(merged)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
