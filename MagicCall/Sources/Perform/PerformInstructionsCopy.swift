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
        "**Song search region:** On the same card, pick the **iTunes storefront** (Automatic = iPhone region, or **CN** / **TW** / **HK** for Chinese catalogs). Optional **Deezer fallback** when Apple has no preview.",
        "**Phone → Incoming Calls:** iOS may show a **banner** or **full-screen** incoming UI — MindtoneX works with **either**. Keep **Silent mode** how you prefer; the trick is **in-app playback** when the call arrives, not changing the carrier ringtone unless you choose the optional Share step below.",
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
            lines.append("On this device, **Auto-open Share** is **ON** — Share opens when the song locks (no volume button needed for that step).")
        } else {
            lines.append("On this device, **Auto-open Share** is **OFF**.")
            lines.append("**Manual Share after the call:** When the spectator **hangs up**, press the **volume down** button on the **side of the iPhone** (lower rocker) **once**. iOS opens the Share sheet → tap **Use as Ringtone**. The app briefly restores the previous volume level so the press stays invisible to the audience.")
            lines.append("This uses the **hardware volume down** key — **not** a long press on the screen — so it does **not** conflict with **hold-to-peek** (Feedback).")
        }
        lines.append("After **Use as Ringtone**, iOS may open **Settings → Ringtone** — press **Home once** to return; the tone is already saved.")
        return lines
    }

    static let duringPerform: [String] = [
        "Tap **Perform** on Home. The stage shows your screenshot — **no on-screen controls** for the audience.",
        "Arm song + words using your chosen inputs (same session — they run **in parallel**).",
        "**Unknown contact (Caller name):** Perform may open a **Phone-style dial** inside MindtoneX. Enter their number and tap call — iOS opens the **real Phone app**; when you return, the **stage screenshot** is showing again and the app arms after that outgoing call ends.",
        "Give your number; when they call back, the app plays the locked song. Hang-up = music stops.",
        "**Performer peek (Feedback):** **Hold** your finger on the screen (~instant) to see **Song**, **Caller name**, and **Notes** lines; **release** to hide. Empty fields show **— —**. **ON by default** — tune position, size, and color under **Feedback**.",
        "**Optional real ringtone (manual):** If **Auto-open Share** is **OFF**, after hang-up press **volume down** on the side of the phone once → Share → **Use as Ringtone** (see **Optional: real ringtone** below).",
        "Exit Perform: **two-finger swipe down** from the middle of the screen.",
    ]

    // MARK: - Song input

    static let songInputOverview: [String] = [
        "Pick **one** method for the **song** on the **Song input** card. During Perform, that method finds and **locks** a track before (or as) they call.",
        "This is separate from **Caller name** and **Notes contact** — you can combine them (example: **Camera** for song + **Voice** for both words).",
    ]

    static var songInputCamera: [String] {
        var lines = [
            "**Camera:** Press **volume** when the card is in focus (short snapshot; green dot only while capturing).",
            "**Card layout:** \(CardOCRLayout.lineAssignmentSummary).",
            "White card, thick marker, ALL CAPS helps. Labels: `SONG:`, `WORD:`/`CALLER:`, `NOTES:`/`CHIP:`.",
        ]
        if CardOCRLayout.songOnlyOnCard {
            lines.append("**Song only:** Title and artist can be on one line or split — the app does not require fixed line numbers.")
        } else {
            lines.append("One volume scan can return **song + caller word + Notes word** when those inputs use Camera OCR.")
        }
        return lines
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
        "Home → **Caller name**. Turn **Show word on incoming call** **ON** to replace the number with a **word** on the incoming call (**banner or full-screen** — needs **Settings → Phone → Call Blocking & Identification → MindtoneX**).",
        "**Inject / Elips / Custom API:** Polls every \(Int(WordApiSettings.pollInterval)) s during Perform. First reading = old word on server; **next change** = spectator’s word → lock.",
        "**Camera (OCR):** **One word** on the line **under the song** (song may use one or two lines above). Requires Song input = **Camera**.",
        "**Voice (AI):** Same mic as Song = Voice; ask what word they think you saved as their contact (script on the card).",
    ]

    /// Known vs Unknown — how MindtoneX links a phone number to the forced word in Contacts.
    static let callerNameKnownUnknown: [String] = [
        "Turn **Save locked word as contact name** **ON** on the **Caller name** card, then pick **How to link the number**: **Known** or **Unknown**. MindtoneX needs **Contacts** permission to write the name (Call Directory is backup if Contacts is denied).",
        "**Unknown** (stranger, one-off number): Before the rest of Perform arms, MindtoneX opens the **Phone-style dial inside the app**. Enter their number and tap the **green call button** — iOS places a **real outgoing call** in the Phone app. When you return to MindtoneX, the **stage screenshot** shows again; after that call **ends**, the app **saves their number** and continues Perform. You **must** complete this dial once so the app knows which number to use.",
        "**Unknown → Contacts:** When the word **locks**, MindtoneX writes the **prediction word** as the contact **first name** for that saved number. **If that phone number is not in Contacts yet** → the app **creates a new contact** (mobile + name + optional Notes). **If a contact with that number already exists** → the app **updates that same card** (replaces **first name** with the word; updates Notes if configured). It does **not** create a duplicate for the same number.",
        "**Known** (repeat volunteer, friend): Choose **Known** → **Choose contact** and pick their card **before** Perform. When the word locks, MindtoneX **updates that existing contact only** — it **replaces the first name** with the prediction word (same person, same card; **not** a new contact). Optional **Restore original name when leaving Caller name connection** puts their real first name back when you close connection details after the show.",
        "**Perform log:** **Contact saved** = Unknown create/update · **Contact renamed** = Known first name replaced · **Spectator number saved** = dial step finished · errors explain missing dial or missing contact pick.",
    ]

    // MARK: - Notes contact

    static let notesContact: [String] = [
        "Home → **Notes contact**. Sets the **Contacts → Notes** field on the spectator’s card (preview matches the real call sheet).",
        "**Note text** is empty by default — only what you type is saved. Tap **`{word}`** in the editor to insert the marker where the forced word should go; during the show, **`{word}`** is replaced by the locked **Notes chip** word (Inject / OCR line 3 / Voice). No separate placeholder field.",
        "Uses its **own** word source — independent from Caller name.",
        "**Camera:** **Line 3** on the card (line 1 = song, line 2 = caller if enabled).",
    ]

    // MARK: - Feedback

    static let feedback: [String] = [
        "Home → **Feedback** (optional performer cues).",
        "**Hold-to-peek (default ON):** While your finger stays on the screen, you see live **Song**, **Caller name** (if armed), and **Notes** (if configured). Drag the **preview** to set position; adjust **size** and **color**. Release to hide — the audience still only sees the screenshot.",
        "**Vibration when song locks:** Two long buzzes so you know the track is ready without looking.",
        "**Status dot when song ready:** Small dot on the **top-right of the screen** after the song locks (Voice / API / Camera). Toggle color and size to taste.",
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
        "Use it after rehearsal to confirm Camera lines, API polls, or Voice picks matched what you expected. With **Voice (AI)**, each **OpenAI** line shows the model’s answer and **reasoning**, even when it returns **none**.",
    ]
}
