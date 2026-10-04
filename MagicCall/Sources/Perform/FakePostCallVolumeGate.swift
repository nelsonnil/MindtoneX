import Foundation

/// Pure gating for Fake Ringtone: hardware volume opens Share only after the spectator’s call ends.
enum FakePostCallVolumeGate {
    static func shouldOpenShareOnVolume(
        performanceMode: Prefs.PerformanceMode,
        phase: AppModel.Phase,
        performed: Bool,
        isArmed: Bool,
        volumeDownOpensShare: Bool,
        oldVolume: Float,
        newVolume: Float
    ) -> Bool {
        guard volumeDownOpensShare else { return false }
        guard performanceMode == .fakeRingtone, phase == .stage, performed, isArmed else { return false }
        return newVolume < oldVolume - 0.001
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
            performanceMode: .fakeRingtone, phase: .stage, performed: true, isArmed: true,
            volumeDownOpensShare: true, oldVolume: 0.6, newVolume: 0.4))
        assert(!FakePostCallVolumeGate.shouldOpenShareOnVolume(
            performanceMode: .fakeRingtone, phase: .stage, performed: true, isArmed: true,
            volumeDownOpensShare: true, oldVolume: 0.4, newVolume: 0.6))
        assert(!FakePostCallVolumeGate.shouldOpenShareOnVolume(
            performanceMode: .fakeRingtone, phase: .stage, performed: false, isArmed: true,
            volumeDownOpensShare: true, oldVolume: 0.6, newVolume: 0.4))
        assert(!FakePostCallVolumeGate.shouldOpenShareOnVolume(
            performanceMode: .shareRingtone, phase: .stage, performed: true, isArmed: true,
            volumeDownOpensShare: true, oldVolume: 0.6, newVolume: 0.4))
        assert(!FakePostCallVolumeGate.shouldOpenShareOnVolume(
            performanceMode: .fakeRingtone, phase: .stage, performed: true, isArmed: true,
            volumeDownOpensShare: false, oldVolume: 0.6, newVolume: 0.4))
        assert(FakePostCallVolumeGate.shouldTogglePlayOnVolume(
            volumeButtonTrigger: true, isArmed: true, performed: false))
        assert(!FakePostCallVolumeGate.shouldTogglePlayOnVolume(
            volumeButtonTrigger: true, isArmed: true, performed: true))
    }
}
#endif
