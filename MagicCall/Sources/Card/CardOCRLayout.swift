import Foundation

/// Describes which card lines are used for the current home setup (for UI + Instructions).
enum CardOCRLayout {
    static var usesCallerLine: Bool {
        WordApiSettings.callerLabelEnabled && WordApiSettings.provider == .card
    }

    static var usesNotesLine: Bool {
        NotesContactWordSettings.wordInputEnabled && NotesContactWordSettings.provider == .card
    }

    /// Song = Camera and no caller / Notes word on the card.
    static var songOnlyOnCard: Bool {
        !usesCallerLine && !usesNotesLine
    }

    static var activeWordLineCount: Int {
        (usesCallerLine ? 1 : 0) + (usesNotesLine ? 1 : 0)
    }

    /// One-line summary for Card input tips.
    static var lineAssignmentSummary: String {
        if songOnlyOnCard {
            return "detect **song title** (artist optional — most popular recording) anywhere on the card"
        }
        var parts = ["**top** = song (title and/or artist — one or two lines; OpenAI can merge if layout differs)"]
        if usesCallerLine { parts.append("**next line down** = caller name (one word)") }
        if usesNotesLine { parts.append("**bottom line** = Notes chip word (one word)") }
        return parts.joined(separator: " · ")
    }

    /// Rules block for OpenAI vision (matches active Home setup).
    static var openAIVisionRules: String {
        if songOnlyOnCard {
            return """
            **Song only:** Read the **entire card** for the song (OCR line count is irrelevant). Title alone is a complete choice — infer the **most popular recording** and main artist (e.g. "GASOLINA" / "LA GASOLINA" → Daddy Yankee — Gasolina; "BULERÍA" → David Bisbal). If two artists share a similar title, pick the famous hit. \
            One row ("EMINEM - LOSE YOURSELF") or two lines in any order — merge correctly. Ignore empty space. \
            search_query = "Title Artist" with the inferred artist. has_caller_word=false, has_notes_word=false always.
            """
        }
        var rules = """
        **Song block (top):** All lines above the word lines are the song. Artist + title may share one line or split across two — merge correctly.
        """
        if usesCallerLine {
            rules += """

            **Caller word:** The first **single-word** line below the song block (convention: line under the song). \
            If the spectator wrote artist/title on two lines then the caller word on the third, use that third line. \
            OpenAI may still infer if spacing differs — never use a word from the song title as caller_word.
            """
        } else {
            rules += "\n\nCaller word: not used (has_caller_word=false)."
        }
        if usesNotesLine {
            rules += """

            **Notes chip word:** The **bottom** single-word line on the card (below caller when caller is enabled).
            """
        } else {
            rules += "\n\nNotes word: not used (has_notes_word=false)."
        }
        rules += "\n\nsearch_query = \"Title Artist\". Title alone is enough — infer the most popular artist (e.g. \"Gasolina\" → \"Gasolina Daddy Yankee\"). Never duplicate artist."
        return rules
    }

    /// English steps for Instructions sheet.
    static var instructionLines: [String] {
        var lines = [
            "**Song input = Camera.** Write on a white card in ALL CAPS when you can.",
            "Press **volume** when the card is in focus — snapshot + **OpenAI vision** (Voice token) or local OCR.",
        ]
        if songOnlyOnCard {
            lines.append("**Song only:** Title and artist, or **title alone** — the app looks up the most popular recording (`GASOLINA` → Daddy Yankee). One line (`ARTIST - TITLE`) or two lines.")
        } else {
            lines.append("**Lines (top → bottom):** \(lineAssignmentSummary).")
            if usesCallerLine {
                lines.append("**Caller name (Camera):** One word on the line **under** the song (OpenAI can adapt if artist/title use two lines).")
            }
            if usesNotesLine {
                lines.append("**Notes word (Camera):** One word on the **third** line when caller is on; otherwise the line under the song.")
            }
        }
        lines.append("Optional labels: `SONG:` · `WORD:`/`CALLER:` · `NOTES:`/`CHIP:`.")
        return lines
    }
}
