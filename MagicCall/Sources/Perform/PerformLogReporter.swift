import Foundation

/// Plain-English Perform log lines: which inputs are armed and what was recognized.
enum PerformLogReporter {
    enum Recognition: String {
        case song
        case callerName
        case notesContact
    }

    /// Call once when Perform arms (after `beginSession`).
    @MainActor
    static func logConfiguredInputs() {
        PerformUserLog.shared.log("── Inputs this perform ──")
        PerformUserLog.shared.log("Song · \(VoiceSettings.inputMode.title)")

        if WordApiSettings.callerLabelEnabled {
            PerformUserLog.shared.log("Caller name · \(WordApiSettings.provider.title) · on")
        } else {
            PerformUserLog.shared.log("Caller name · off")
        }

        if NotesContactWordSettings.wordInputEnabled {
            PerformUserLog.shared.log("Notes chip word · \(NotesContactWordSettings.provider.title) · on")
        } else {
            PerformUserLog.shared.log("Notes chip word · off")
        }

        if VoiceSettings.inputMode == .api, ApiSettings.isConfigured {
            PerformUserLog.shared.log("Song API · \(ApiSettings.provider.title)")
        }

        let plan = VoiceListenPlan.current
        if plan.activeChannels.count > 1 || (plan.song && VoiceSettings.inputMode == .aiVoice) {
            let names = plan.activeChannels.map(\.title).joined(separator: ", ")
            PerformUserLog.shared.log("Voice AI channels · \(names)")
        }

        if VoiceSettings.inputMode == .card {
            PerformUserLog.shared.log("Camera layout · \(CardOCRLayout.lineAssignmentSummary)")
        }
    }

    @MainActor
    static func logRecognition(_ kind: Recognition, value: String, via source: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let label = WordApiInputPanel.truncated(trimmed, max: 48)
        switch kind {
        case .song:
            PerformUserLog.shared.log("Recognized · song · «\(label)» · via \(source)")
        case .callerName:
            PerformUserLog.shared.log("Recognized · caller name · «\(label)» · via \(source)")
        case .notesContact:
            PerformUserLog.shared.log("Recognized · Notes chip · «\(label)» · via \(source)")
        }
    }

    /// Short title for the Perform log session header.
    static func sessionTitle() -> String {
        var parts = [VoiceSettings.inputMode.title]
        if WordApiSettings.callerLabelEnabled {
            parts.append("Caller \(WordApiSettings.provider.gridTitle)")
        }
        if NotesContactWordSettings.wordInputEnabled {
            parts.append("Notes \(NotesContactWordSettings.provider.gridTitle)")
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    static func logRecapOnDisarm() {
        var lines: [String] = []
        if let track = AppModel.shared.selected ?? AppModel.shared.lastReadyTrack,
           AppModel.shared.loadState == .ready || AppModel.shared.hasSongLockedForCurrentPerform() {
            lines.append("song «\(WordApiInputPanel.truncated(track.title + " — " + track.artist, max: 44))»")
        }
        if let w = WordApiSession.shared.lockedReading?.label, !w.isEmpty {
            lines.append("caller «\(WordApiInputPanel.truncated(w, max: 32))»")
        }
        if let w = NotesContactWordSession.shared.lockedReading?.label, !w.isEmpty {
            lines.append("Notes «\(WordApiInputPanel.truncated(w, max: 32))»")
        }
        guard !lines.isEmpty else { return }
        PerformUserLog.shared.log("── Recognized this perform ──")
        PerformUserLog.shared.log(lines.joined(separator: " · "))
    }
}
