import SwiftUI
import UIKit

extension Notification.Name {
    static let carphoneDialSystemStyleDidChange = Notification.Name("carphoneDialSystemStyleDidChange")
}

/// Device light/dark for the in-app Phone dial — not MindtoneX home `.preferredColorScheme(.dark)`.
enum CarphoneDialSystemAppearance {
    static var preferredColorScheme: ColorScheme {
        userInterfaceStyle == .dark ? .dark : .light
    }

    static var userInterfaceStyle: UIUserInterfaceStyle {
        SystemStyleProbe.shared.resolvedStyle
    }

    static func apply(to viewController: UIViewController) {
        let style = userInterfaceStyle
        viewController.overrideUserInterfaceStyle = style
        viewController.view.overrideUserInterfaceStyle = style
    }

    static func startObservingSystemStyle() {
        SystemStyleProbe.shared.ensureInstalled()
    }
}

/// Reads the **system** interface style (Settings → Appearance), not the app’s forced dark chrome.
private final class SystemStyleProbe {
    static let shared = SystemStyleProbe()

    private var window: UIWindow?
    private var host: UIViewController?

    var resolvedStyle: UIUserInterfaceStyle {
        ensureInstalled()
        let fromProbe = window?.traitCollection.userInterfaceStyle ?? UIUserInterfaceStyle.unspecified
        if fromProbe == .light || fromProbe == .dark {
            return fromProbe
        }
        switch UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
        case "Dark":
            return .dark
        case "Light":
            return .light
        default:
            return .light
        }
    }

    func ensureInstalled() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }) ?? scenes.first
        guard let scene else { return }

        let controller = StyleHostController()
        controller.onStyleChange = { [weak self] in
            guard self != nil else { return }
            NotificationCenter.default.post(name: .carphoneDialSystemStyleDidChange, object: nil)
        }
        host = controller

        let probeWindow = UIWindow(windowScene: scene)
        probeWindow.frame = CGRect(x: -200, y: -200, width: 1, height: 1)
        probeWindow.overrideUserInterfaceStyle = UIUserInterfaceStyle.unspecified
        probeWindow.windowLevel = UIWindow.Level(rawValue: -1000)
        probeWindow.rootViewController = controller
        probeWindow.isHidden = false
        window = probeWindow
    }
}

private final class StyleHostController: UIViewController {
    var onStyleChange: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = UIUserInterfaceStyle.unspecified
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: StyleHostController, _: UITraitCollection) in
                controller.onStyleChange?()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            onStyleChange?()
        }
    }
}
