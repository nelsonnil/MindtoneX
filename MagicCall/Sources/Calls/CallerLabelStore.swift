import Foundation

/// App Group state shared with the Call Directory extension.
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

    /// `UserDefaults(suiteName:)` silently falls back to a per-process store when the group is not signed in.
    static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    struct ExtensionLoad {
        var at: Date
        var performArmed: Bool
        var label: String
        var entries: Int
    }

    static func lastExtensionLoad() -> ExtensionLoad? {
        let d = shared
        let at = d.double(forKey: SharedKey.extensionLastLoadAt)
        guard at > 0 else { return nil }
        return ExtensionLoad(at: Date(timeIntervalSince1970: at),
                             performArmed: d.bool(forKey: SharedKey.extensionLastLoadArmed),
                             label: d.string(forKey: SharedKey.extensionLastLoadLabel) ?? "",
                             entries: d.integer(forKey: SharedKey.extensionLastLoadEntries))
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
