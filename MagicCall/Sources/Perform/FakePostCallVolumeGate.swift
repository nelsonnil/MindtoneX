import Foundation

/// Fake Ringtone: when hardware volume buttons may toggle playback (Advanced).
enum FakePostCallVolumeGate {
    static func shouldTogglePlayOnVolume(
        volumeButtonTrigger: Bool,
        isArmed: Bool,
        performed: Bool,
        cardCaptureUsesVolume: Bool = false
    ) -> Bool {
        if cardCaptureUsesVolume { return false }
        return volumeButtonTrigger && isArmed && !performed
    }
}

/// Fake Ringtone: long-press on stage opens Share only after the spectator’s call ends.
enum FakePostCallShareGate {
    static func shouldOpenShareOnLongPress(
        phase: AppModel.Phase,
        performed: Bool,
        isArmed: Bool
    ) -> Bool {
        phase == .stage && performed && isArmed
    }
}

#if DEBUG
enum FakePostCallVolumeGateSelfTest {
    static func run() {
        assert(FakePostCallVolumeGate.shouldTogglePlayOnVolume(
            volumeButtonTrigger: true, isArmed: true, performed: false))
        assert(!FakePostCallVolumeGate.shouldTogglePlayOnVolume(
            volumeButtonTrigger: true, isArmed: true, performed: true))
        assert(FakePostCallShareGate.shouldOpenShareOnLongPress(
            phase: .stage, performed: true, isArmed: true))
        assert(!FakePostCallShareGate.shouldOpenShareOnLongPress(
            phase: .stage, performed: false, isArmed: true))
    }
}
#endif
