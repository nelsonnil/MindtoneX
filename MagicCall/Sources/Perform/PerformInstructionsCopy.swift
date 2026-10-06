import Foundation

/// Full Instructions content — mirrors Home sections (Performance, Song input, Caller name, Feedback, Library).
enum PerformInstructionsCopy {
    // MARK: - Core effect

    static let howTheTrickWorks: [String] = [
        "MindtoneX **does not replace the Phone app**. During **Perform**, your iPhone shows a **full-screen screenshot** of your Home (or Lock) screen while the app stays in the **foreground**.",
        "You get the song ready using **Song input** (Voice, Camera, Notes, API, etc.). When a **real incoming call** arrives, the app **detects the call** and **plays that song** through the speaker at your **Playback volume** (set it high — many magicians use **100%**).",
        "When the caller **hangs up**, playback **stops**. The screen stays on your screenshot until you exit Perform.",
        "**Why foreground + screenshot?** iOS only lets the app control audio reliably while MindtoneX is active and visible. The screenshot sells the idea that they are looking at a normal iPhone Home screen, not the app UI.",
        "**Song**, **Caller name**, and **Notes contact word** are **independent**. You can enable **one, two, or all three** for the same performance — each uses its own source (see below).",
    ]

    // MARK: - Performance settings (Home → Performance settings)

    static let performanceSettings: [String] = [
        "**Stage screenshot (required):** On the **Performance settings** card, tap **Choose screenshot**. Use a **full-screen capture of your real Home Screen** (or Lock screen). During Perform, the audience only sees that image.",
        "**Status bar:** The thin strip at the top (time, signal, battery). In Performance settings, use the preview to pick **Auto**, **Dark**, or **Light** so icons match your wallpaper — it should look like a real iPhone, not a floating wallpaper.",
        "**Playback volume:** Set the slider to **100%** (or as loud as you need) so the song is audible when the call rings. You can still adjust with the side buttons during Perform.",
        "**Phone → Incoming Calls:** Banner (standard iOS). Keep **Silent mode** how you prefer for your show; the trick is **in-app playback** when the call arrives, not changing the carrier ringtone unless you choose the optional Share step below.",
        "Do **not** lock the phone or switch apps during Perform — MindtoneX keeps the screen awake, but leaving the app stops the effect.",
    ]

    static func optionalRealRingtone(autoShareOn: Bool) -> [String] {
        var lines = [
            "**Not required for the core trick.** The call effect works with in-app audio only.",
            "If you want the **same song as the system ringtone** (e.g. the spectator might call again later), turn on **Auto-open Share when song locks** on the Performance card.",
            "When a song **locks during Perform**, iOS opens Share → tap **Use as Ringtone** (add it to Favorites once for one-tap access). A couple of taps before you hand the phone back is enough.",
            "Only songs that **lock live during Perform** count — not tracks picked from Library on Home.",
        ]
        if autoShareOn {
            lines.append("On this device, **Auto-open Share** is **ON**.")
        } else {
            lines.append("On this device, **Auto-open Share** is **OFF**. After the call ends, you can **long-press** the stage ~0.5 s to open Share manually.")
        }
        lines.append("After **Use as Ringtone**, iOS may open **Settings → Ringtone** — press **Home once** to return; the tone is already saved.")
        return lines
    }

    static let duringPerform: [String] = [
        "Tap **Perform** on Home. The stage shows your screenshot.",
        "Arm song + words using your chosen inputs (same session — they run **in parallel**).",
        "Give your number; when they call, the app plays the locked song. Hang-up = music stops.",
        "Exit: **two-finger swipe down** from the middle of the stage.",
    ]

    // MARK: - Song input

    static let songInputOverview: [String] = [
        "Pick **one** method for the **song** on the **Song input** card. During Perform, that method finds and **locks** a track before (or as) they call.",
        "This is separate from **Caller name** and **Notes contact** — you can combine them (example: **Camera** for song + **Voice** for both words).",
    ]

    static var songInputCamera: [String] {
        [
            "**Camera:** Press **volume up/down** during Perform (green camera dot while reading).",
            "**Lines on the card:** \(CardOCRLayout.lineAssignmentSummary).",
            "White card, thick marker, ALL CAPS helps. Labels: `SONG:`, `WORD:`/`CALLER:`, `NOTES:`/`CHIP:`.",
            "One scan can feed **song + caller line 2 + Notes line 3** if those features use Camera OCR too.",
        ]
    }

    static func songInputVoice(lockSeconds: Int) -> [String] {
        [
            "**Voice:** OpenAI key under Voice settings. The mic listens; AI picks the spectator’s **final** song (ignores your examples).",
            "Locks after **\(lockSeconds) s** without a change (adjustable in Voice settings).",
            "Same mic can run **extra AI prompts** for Caller name and Notes if those cards use **Voice (AI)**.",
        ]
    }

    static let songInputNotes: [String] = [
        "**Notes:** During Perform a note opens; the app searches the text you prepared (idle timer / Return / checkmark — see Notes controls on Home).",
        "Good when the song is written in Apple Notes instead of spoken or scanned.",
    ]

    static let songInputAPI: [String] = [
        "**API:** Spectator searches in Inject / Elips / your endpoint; MindtoneX polls every \(Int(ApiSettings.pollInterval)) s and locks when their search loads.",
        "Song API is **separate** from Caller name / Notes word URLs unless you reuse the same service on purpose.",
    ]

    static let songInputCombinations: [String] = [
        "**Example A:** Song = **Voice**, Caller = **Inject**, Notes word = **Inject** (different IDs).",
        "**Example B:** Song = **Camera** (line 1), Caller = **Camera** (line 2), Notes = **Camera** (line 3) — one volume scan.",
        "**Example C:** Song = **Voice**, Caller = **Voice**, Notes = **Voice** — one conversation, three AI prompts.",
        "Open **Perform log** on Home after a run to see **Inputs** and **Recognized** lines for debugging.",
    ]

    // MARK: - Caller name

    static let callerName: [String] = [
        "Home → **Caller name**. Turn **Show word on incoming call** **ON** to replace the number with a **word** on the incoming-call banner (needs **Settings → Phone → Call Blocking & Identification → MindtoneX**).",
        "**Inject / Elips / Custom API:** Polls every \(Int(WordApiSettings.pollInterval)) s during Perform. First reading = old word on server; **next change** = spectator’s word → lock.",
        "**Camera (OCR):** Word on **line 2** of the same card as the song (line 1). Requires Song input = **Camera**.",
        "**Voice (AI):** Same mic as Song = Voice; ask what word they think you saved as their contact (script on the card).",
        "**Save locked word as contact name:** Optional but strong — updates Contacts so the **name** on the call matches the word. **Known** = pick their contact first; **Unknown** = dial them on Perform once so the app learns the number.",
    ]

    // MARK: - Notes contact

    static let notesContact: [String] = [
        "Home → **Notes contact**. Sets the **Contacts → Notes** field on the spectator’s card (preview matches the real call sheet).",
        "**Note text** is empty by default — only what you type is saved. Optional **word placeholder**: if that word appears in your note, it is replaced by the locked **Notes chip** word (Inject / OCR line 3 / Voice).",
        "Uses its **own** word source — independent from Caller name.",
        "**Camera:** **Line 3** on the card (line 1 = song, line 2 = caller if enabled).",
    ]

    // MARK: - Feedback

    static let feedback: [String] = [
        "Home → **Feedback** (optional performer cues).",
        "**Vibration when song locks:** Two long buzzes so you know the track is ready without looking.",
        "**Status dot when song ready:** Small dot on the **top-right of the stage** after the song locks (Voice / API / Camera). Toggle color and size to taste.",
        "Caller name lock uses a **different** vibration pattern (three short taps) when enabled.",
    ]

    // MARK: - Library

    static let library: [String] = [
        "**Library** is for **practice and prep**, not the live force.",
        "**Search song:** Try titles/artists and preview matches — same search as manual pickers.",
        "**Import audio / favorites / recent:** Reload a track you used before or export **Share as ringtone** from a ready row without entering Perform.",
        "To force a song **during a show**, use **Song input** (Voice, Camera, etc.) — not Library.",
    ]

    static let performLog: [String] = [
        "**Perform log** on Home records each run: which **inputs** were armed and every **Recognized** song/word.",
        "Use it after rehearsal to confirm Camera lines, API polls, or Voice picks matched what you expected.",
    ]
}
