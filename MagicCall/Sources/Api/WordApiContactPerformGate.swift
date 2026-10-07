import Foundation

@MainActor
enum WordApiContactPerformGate {
    private(set) static var awaitingOutgoingEnd = false
    private(set) static var outgoingCallUUID: UUID?
    private(set) static var dialedPhoneDigits = ""
    private static var pendingPerform: (() -> Void)?

    static func needsPreparation() -> Bool {
        guard WordApiSettings.callerLabelEnabled, WordApiSettings.saveWordAsContactEnabled else { return false }
        switch WordApiSettings.contactMode {
        case .unknown:
            return true
        case .known:
            return !WordApiSettings.hasKnownContactSelected
        }
    }

    static func prepareForPerform(presentDial: () -> Void, presentPicker: () -> Void, then: @escaping () -> Void) {
        guard WordApiSettings.callerLabelEnabled, WordApiSettings.saveWordAsContactEnabled else {
            then()
            return
        }
        switch WordApiSettings.contactMode {
        case .known:
            if WordApiSettings.hasKnownContactSelected {
                then()
            } else {
                pendingPerform = then
                presentPicker()
            }
        case .unknown:
            pendingPerform = then
            presentDial()
        }
    }

    static func cancelPendingPerform() {
        pendingPerform = nil
        awaitingOutgoingEnd = false
        outgoingCallUUID = nil
    }

    static func beginDialCapture(phoneDigits: String) {
        dialedPhoneDigits = WordApiSettings.canonicalPhoneDigits(phoneDigits)
        awaitingOutgoingEnd = true
        outgoingCallUUID = nil
    }

    static func noteOutgoingCall(uuid: UUID) {
        guard awaitingOutgoingEnd else { return }
        outgoingCallUUID = uuid
    }

    static func noteCallEnded(uuid: UUID, wasOutgoing: Bool) {
        guard awaitingOutgoingEnd, wasOutgoing else { return }
        guard outgoingCallUUID == nil || outgoingCallUUID == uuid else { return }
        guard !dialedPhoneDigits.isEmpty else { return }
        WordApiSettings.setLastDialedPhoneDigits(dialedPhoneDigits)
        awaitingOutgoingEnd = false
        outgoingCallUUID = nil
        dlog("[CONTACT] outgoing ended · saved identification \(dialedPhoneDigits)")
        PerformUserLog.shared.log("Spectator number saved · ready to arm")
        AppModel.shared.beginVolumeIgnoreAfterOutgoingSpectatorCall()
        finishPendingPerform()
    }

    static func skipDialAndUseManualDigits(then: @escaping () -> Void) {
        pendingPerform = then
        guard !WordApiSettings.fallbackPhoneDigits.isEmpty else {
            PerformUserLog.shared.log("Add a number in Word API settings or dial the spectator first")
            cancelPendingPerform()
            return
        }
        WordApiSettings.setLastDialedPhoneDigits(WordApiSettings.fallbackPhoneDigits)
        finishPendingPerform()
    }

    static func contactPickedFinishPerform() {
        finishPendingPerform()
    }

    private static func finishPendingPerform() {
        let next = pendingPerform
        pendingPerform = nil
        next?()
    }
}
