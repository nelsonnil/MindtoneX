import Foundation

/// Contacts touched at word lock — restored after Perform when the toggle is on.
struct WordApiContactRestoreEntry: Codable, Equatable {
    var identifier: String
    var givenName: String
    /// Contact created by MindtoneX for this show (restore = delete card).
    var createdForShow: Bool
}

enum WordApiContactRestoreStore {
    private static let key = "wordApi.contactRestore.snapshots"

    static var entries: [WordApiContactRestoreEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WordApiContactRestoreEntry].self, from: data)) ?? []
    }

    static var hasPendingRestore: Bool { !entries.isEmpty }

    static func replaceEntries(_ list: [WordApiContactRestoreEntry]) {
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
