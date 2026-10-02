import Foundation

/// Pure gating for Fake Ringtone: hardware volume opens Share only after the spectator’s call ends.
enum FakePostCallVolumeGate {
    static func shouldOpenShareOnVolume(
        performanceMode: Prefs.PerformanceMode,
        phase: AppModel.Phase,
        performed: Bool,
        isArmed: Bool
    ) -> Bool {
        performanceMode == .fakeRingtone && phase == .stage && performed && isArmed
    }

    static func shouldTogglePlayOnVolume(
        volumeButtonTrigger: Bool,
        isArmed: Bool,
        performed: Bool
    ) -> Bool {
        volumeButtonTrigger && isArmed && !performed
    }
}

#if DEBUG
enum FakePostCallVolumeGateSelfTest {
    static func run() {
        assert(FakePostCallVolumeGate.shouldOpenShareOnVolume(
            performanceMode: .fakeRingtone, phase: .stage, performed: true, isArmed: true))
        assert(!FakePostCallVolumeGate.shouldOpenShareOnVolume(
            performanceMode: .fakeRingtone, phase: .stage, performed: false, isArmed: true))
        assert(!FakePostCallVolumeGate.shouldOpenShareOnVolume(
            performanceMode: .shareRingtone, phase: .stage, performed: true, isArmed: true))
        assert(FakePostCallVolumeGate.shouldTogglePlayOnVolume(
            volumeButtonTrigger: true, isArmed: true, performed: false))
        assert(!FakePostCallVolumeGate.shouldTogglePlayOnVolume(
            volumeButtonTrigger: true, isArmed: true, performed: true))
    }
}
#endif
