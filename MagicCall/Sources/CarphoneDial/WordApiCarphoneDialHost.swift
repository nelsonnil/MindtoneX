import SwiftUI
import UIKit

/// CarphoneCALL `PhoneKeyboard` embedded in MindtoneX (Perform → unknown spectator).
struct WordApiCarphoneDialHost: UIViewControllerRepresentable {
    @Binding var phoneDigits: String
    var onCall: () -> Void

    func makeUIViewController(context: Context) -> CarphoneDialViewController {
        let controller = CarphoneDialViewController()
        CarphoneDialSystemAppearance.apply(to: controller)
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

        phoneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phoneView)
        phoneView.carphoneDialPinEdges(to: view)

        phoneView.format = CarphoneDialFormat.patternForDeviceRegion()
        phoneView.isReverse = false

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
        } else {
            setTelephone("")
        }

        applySystemPhoneAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let previous = previousTraitCollection?.userInterfaceStyle
        let current = CarphoneDialSystemAppearance.userInterfaceStyle
        if previous != current || traitCollection.userInterfaceStyle != previous {
            applySystemPhoneAppearance()
        }
    }

    func setTelephone(_ digits: String) {
        phoneView.telephone = digits
        phoneView.syncTelephoneDisplay(animated: false)
    }

    /// Match the real Phone app: device light/dark, not MindtoneX forced dark shell.
    private func applySystemPhoneAppearance() {
        CarphoneDialSystemAppearance.apply(to: self)
        phoneView.overrideUserInterfaceStyle = CarphoneDialSystemAppearance.userInterfaceStyle
        view.backgroundColor = .systemBackground
        phoneView.backgroundColor = .systemBackground
        phoneView.themeFromDefaults()
        phoneView.applyLocalizedAddNumberCaption()
        phoneView.setNeedsLayout()
    }
}
