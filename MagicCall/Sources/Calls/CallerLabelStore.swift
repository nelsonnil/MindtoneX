import Foundation

/// App Group state shared with Call Directory / Live Caller ID extensions.
enum CallerLabelStore {
    static let appGroupID = "group.com.nelson.tono"
    static let extensionBundleID = "com.nelson.tono.CallDirectory"
    static let liveLookupExtensionBundleID = "com.nelson.tono.LiveCallerLookup"

    enum SharedKey {
        static let performArmed = "performArmed"
        static let lockedLabel = "lockedLabel"
        static let labelEnabled = "labelEnabled"
        static let identificationPhoneNumbers = "identificationPhoneNumbers"
    }

    static var shared: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func setPerformArmed(_ armed: Bool) {
        shared.set(armed, forKey: SharedKey.performArmed)
        if !armed {
            shared.removeObject(forKey: SharedKey.lockedLabel)
        }
        shared.synchronize()
    }

    static func applyLockedLabel(_ label: String) {
        shared.set(true, forKey: SharedKey.labelEnabled)
        shared.set(label.trimmingCharacters(in: .whitespacesAndNewlines), forKey: SharedKey.lockedLabel)
        shared.synchronize()
    }

    static func clearLockedLabel() {
        shared.removeObject(forKey: SharedKey.lockedLabel)
        shared.set(false, forKey: SharedKey.performArmed)
        shared.removeObject(forKey: SharedKey.identificationPhoneNumbers)
        shared.synchronize()
    }

    static func setIdentificationPhoneNumbers(_ numbers: [Int64]) {
        shared.set(numbers.sorted().map(String.init), forKey: SharedKey.identificationPhoneNumbers)
        shared.synchronize()
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
        let numbers = raw.compactMap { Int64($0) }.sorted()
        return Snapshot(performArmed: armed, labelEnabled: enabled, lockedLabel: label, identificationPhoneNumbers: numbers)
    }
}
