import Foundation

// Shared with main app — keep in sync with MagicCall/Sources/Calls/CallerLabelStore.swift
enum CallerLabelStore {
    static let appGroupID = "group.com.nelson.tono"
    static let extensionBundleID = "com.nelson.tono.CallDirectory"
    enum SharedKey {
        static let performArmed = "performArmed"
        static let lockedLabel = "lockedLabel"
        static let labelEnabled = "labelEnabled"
        static let identificationPhoneNumbers = "identificationPhoneNumbers"
        static let extensionLastLoadAt = "extensionLastLoadAt"
        static let extensionLastLoadArmed = "extensionLastLoadArmed"
        static let extensionLastLoadLabel = "extensionLastLoadLabel"
        static let extensionLastLoadEntries = "extensionLastLoadEntries"
    }

    static var shared: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    struct Snapshot: Equatable {
        var performArmed: Bool
        var labelEnabled: Bool
        var lockedLabel: String
        var identificationPhoneNumbers: [Int64]
    }

    static func load() -> Snapshot {
        let d = shared
        let armed = d.bool(forKey: SharedKey.performArmed)
        let enabled = d.object(forKey: SharedKey.labelEnabled) as? Bool ?? true
        let label = d.string(forKey: SharedKey.lockedLabel) ?? ""
        let raw = d.stringArray(forKey: SharedKey.identificationPhoneNumbers) ?? []
        let numbers = Array(Set(raw.compactMap { Int64($0) })).sorted()
        return Snapshot(performArmed: armed, labelEnabled: enabled, lockedLabel: label, identificationPhoneNumbers: numbers)
    }

    /// Lets the app confirm this process actually read the shared state (fails silently without the App Group).
    static func recordLoad(_ snapshot: Snapshot, entries: Int) {
        let d = shared
        d.set(Date().timeIntervalSince1970, forKey: SharedKey.extensionLastLoadAt)
        d.set(snapshot.performArmed, forKey: SharedKey.extensionLastLoadArmed)
        d.set(snapshot.lockedLabel, forKey: SharedKey.extensionLastLoadLabel)
        d.set(entries, forKey: SharedKey.extensionLastLoadEntries)
        d.synchronize()
    }
}
