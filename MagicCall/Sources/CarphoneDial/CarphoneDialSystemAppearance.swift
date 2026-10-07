import SwiftUI
import UIKit

/// Device light/dark for the in-app Phone dial — not MindtoneX home `.preferredColorScheme(.dark)`.
enum CarphoneDialSystemAppearance {
    static var userInterfaceStyle: UIUserInterfaceStyle {
        let screen = UIScreen.main.traitCollection.userInterfaceStyle
        if screen == .light || screen == .dark {
            return screen
        }
        return .light
    }

    static var preferredColorScheme: ColorScheme {
        userInterfaceStyle == .dark ? .dark : .light
    }

    static func apply(to viewController: UIViewController) {
        let style = userInterfaceStyle
        viewController.overrideUserInterfaceStyle = style
        viewController.view.overrideUserInterfaceStyle = style
    }
}
