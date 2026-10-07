import SwiftUI
import UIKit

/// CarphoneCALL `PhoneKeyboard` embedded in MindtoneX (Perform → unknown spectator).
struct WordApiCarphoneDialHost: UIViewControllerRepresentable {
    @Binding var phoneDigits: String
    var onCall: () -> Void

    func makeUIViewController(context: Context) -> CarphoneDialViewController {
        let controller = CarphoneDialViewController()
        controller.initialDigits = phoneDigits
        controller.onCall = onCall
        controller.onDigitsChange = { phoneDigits = $0 }
        return controller
    }

    func updateUIViewController(_ controller: CarphoneDialViewController, context: Context) {
        if controller.phoneView.telephone != phoneDigits, !controller.isEditingLocally {
            controller.setTelephone(phoneDigits)
        }
    }
}

final class CarphoneDialViewController: UIViewController {
    var initialDigits = ""
    var onCall: (() -> Void)?
    var onDigitsChange: ((String) -> Void)?
    private(set) var isEditingLocally = false

    let phoneView = PhoneKeyboard(frame: .zero)

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "Background") ?? .systemBackground

        phoneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phoneView)
        phoneView.carphoneDialPinEdges(to: view)

        phoneView.format = CarphoneDialFormat.patternForDeviceRegion()
        phoneView.isReverse = false
        phoneView.applyLocalizedAddNumberCaption()
        phoneView.themeFromDefaults()

        phoneView.buttonPressed = { [weak self] digit in
            guard let self else { return }
            self.isEditingLocally = true
            self.phoneView.digitPressed(value: digit)
            self.isEditingLocally = false
        }
        phoneView.pressCallButton = { [weak self] in
            self?.onCall?()
        }
        phoneView.telephoneDidChange = { [weak self] _, newValue in
            self?.onDigitsChange?(newValue)
        }

        if !initialDigits.isEmpty {
            setTelephone(CarphoneDialFormat.digitsOnly(initialDigits))
        }

        applyInterfaceStyle()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyInterfaceStyle()
    }

    func setTelephone(_ digits: String) {
        phoneView.telephone = digits
        phoneView.syncTelephoneDisplay(animated: false)
    }

    private func applyInterfaceStyle() {
        phoneView.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}

enum CarphoneDialFormat {
    static func digitsOnly(_ raw: String) -> String {
        raw.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
    }

    /// Default display pattern aligned with Carphone settings previews (ES mobile spacing).
    static func patternForDeviceRegion() -> String {
        switch Locale.current.region?.identifier.uppercased() {
        case "ES":
            return "xxx xxx xxx"
        case "US", "CA":
            return "(xxx) xxx-xxxx"
        default:
            return "xxx xxx xxxx"
        }
    }
}
