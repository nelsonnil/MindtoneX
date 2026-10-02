import UIKit

extension UIApplication {
    /// Sustituto de `UIWindowScene.keyWindow` (obsoleto en SDK recientes).
    @MainActor
    static var mcKeyWindow: UIWindow? {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
