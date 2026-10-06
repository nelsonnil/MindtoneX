import Foundation

/// Describes which card lines are used for the current home setup (for UI + Instructions).
enum CardOCRLayout {
    static var usesCallerLine: Bool {
        WordApiSettings.callerLabelEnabled && WordApiSettings.provider == .card
    }

    static var usesNotesLine: Bool {
        NotesContactWordSettings.wordInputEnabled && NotesContactWordSettings.provider == .card
    }

    static var activeWordLineCount: Int {
        (usesCallerLine ? 1 : 0) + (usesNotesLine ? 1 : 0)
    }

    /// One-line summary for Card input tips.
    static var lineAssignmentSummary: String {
        var parts = ["**line 1** = song title"]
        if usesCallerLine { parts.append("**line 2** = caller name word") }
        if usesNotesLine { parts.append("**line 3** = Notes chip word") }
        return parts.joined(separator: " · ")
    }

    /// English steps for Instructions sheet.
    static var instructionLines: [String] {
        var lines = [
            "**Song input = Camera.** Write on a white card in ALL CAPS when you can.",
            "**Line 1 (top)** is always the **song title** — one volume scan loads and locks the track.",
        ]
        if usesCallerLine {
            lines.append("**Line 2** is the **incoming caller name** word when **Caller name → Card (OCR)** is on.")
        }
        if usesNotesLine {
            lines.append("**Line 3** is the **Notes contact chip** word when **Notes contact → Word for Notes chip → Card (OCR)** is on.")
        }
        if !usesCallerLine && !usesNotesLine {
            lines.append("Caller name and Notes word are not on Card OCR right now — only line 1 is read.")
        } else {
            lines.append("Optional labels: `SONG:` · `WORD:` / `CALLER:` (line 2) · `NOTES:` / `CHIP:` (line 3).")
            lines.append("Leave a line blank if you do not use that feature — the scan still reads the lines you need.")
        }
        return lines
    }
}
