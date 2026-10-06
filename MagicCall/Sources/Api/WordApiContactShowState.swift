import Foundation

@MainActor
final class WordApiContactShowState: ObservableObject {
    static let shared = WordApiContactShowState()

    /// Set after word lock renames the picked contact (known mode).
    var knownContactRenamedForShow = false

    private init() {}
}
