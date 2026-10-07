import CallKit
import Contacts
import Foundation

extension AppModel {
    /// Pantalla de escena (screenshot) mientras la llamada saliente al espectador está en curso.
    func showStageShellForOutgoingSpectatorCall() {
        phase = .stage
        Self.setScreenAwakeWhileInForeground(true)
        dlog("[CONTACT] outgoing dial → stage screenshot")
    }

    func runPerformWithWordContactPrep() {
        WordApiContactPerformGate.prepareForPerform(
            presentDial: { [weak self] in
                self?.wordSpectatorDialSheet = true
            },
            presentPicker: { [weak self] in
                self?.wordKnownContactPicker = true
            },
            then: { [weak self] in
                self?.wordSpectatorDialSheet = false
                self?.wordKnownContactPicker = false
                self?.performNowAfterWordContactPrep()
            }
        )
    }

    func handleKnownContactPicked(_ contact: CNContact) {
        guard let e164 = WordApiContactPhoneParsing.e164(from: contact) else {
            PerformUserLog.shared.log("That contact has no usable phone number")
            WordApiContactPerformGate.cancelPendingPerform()
            wordKnownContactPicker = false
            return
        }
        SpectatorWordContactService.recordKnownContactPicked(contact, phoneE164: e164)
        wordKnownContactPicker = false
        WordApiContactPerformGate.contactPickedFinishPerform()
    }

    func handleKnownContactPickerCancelled() {
        WordApiContactPerformGate.cancelPendingPerform()
        wordKnownContactPicker = false
    }

    func noteWordContactCallEvent(_ event: CallMonitor.Event, uuid: UUID, call: CXCall) {
        switch event {
        case .outgoing:
            WordApiContactPerformGate.noteOutgoingCall(uuid: uuid)
        case .ended:
            WordApiContactPerformGate.noteCallEnded(uuid: uuid, wasOutgoing: call.isOutgoing)
            if !WordApiContactPerformGate.awaitingOutgoingEnd {
                wordSpectatorDialSheet = false
            }
        default:
            break
        }
    }
}
