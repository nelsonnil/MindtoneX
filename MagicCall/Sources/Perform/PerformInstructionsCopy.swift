import Foundation

/// Full Instructions content — mirrors Home sections (Performance, Song input, Caller name, Feedback, Library).
enum PerformInstructionsCopy {
    // MARK: - Guide tabs (Overview map)

    static let guideTabMap: [String] = [
        "**Overview** — **iPhone setup (Banner + ring time)**, quick start, Performance settings, During Perform, contact primer, Feedback, Library, log, community.",
        "**Song** — Camera, Voice, Notes, API, normal vs **Interference ringtone**, **1 or 2 songs**, optional **Use as Ringtone**.",
        "**Caller name** — word on incoming call, word sources, full **Known vs Unknown** comparison.",
        "**Album** — cover on contact photo, **Save to Photos**, restore after Perform.",
        "**Notes** — Contacts **Notes** field, `{word}` marker, word sources (separate from Caller name).",
    ]

    static let contactSetupOverview: [String] = [
        "**Song / ringtone** needs **no** contact — use the **Song** tab for inputs and ringtones.",
        "**Caller name**, **Album artwork**, and **Notes contact** need the spectator’s card **before** callback — pick **Unknown** or **Known** once; **same choice on all three Home cards**.",
        "Use the mini picker below (mirrors Home). Full **Known vs Unknown** table → **Caller name** tab.",
    ]

    static let songNoContactNote: [String] = [
        "Song input, **Interference ringtone**, and **2 songs** work **without** Contacts setup. **Known / Unknown** does not apply here.",
    ]

    /// Required iPhone setting — show prominently on Overview (not buried in Performance settings).
    static let iphoneSetupRequired: [String] = [
        "**Incoming calls = Banner (required):** iPhone **Settings → Phone → Incoming Calls → Banner** — not **Full Screen**. (If you use **FaceTime** for callbacks, also **Settings → FaceTime → Incoming Calls → Banner**.)",
        "**Why:** MindtoneX keeps your **stage screenshot** and **in-app song playback** while the real call arrives. **Full Screen** takes over the phone, stops the show flow, and breaks **Interference ringtone** (front camera needs the app visible under the call UI).",
        "**Voicemail / ring time:** Turn **voicemail off** or set **more rings before pickup** (carrier settings, Phone → Voicemail, or your carrier’s app/code). If the call jumps to mailbox too fast, the audience may never hear the **in-app song** or **Interference** reveal — you need enough ring time while the banner is showing.",
        "**Keep the iPhone unlocked** with MindtoneX in **Perform** — do not switch apps or lock during the routine.",
        "**Permissions (when you use the feature):** **Contacts** for Caller name / Album / Notes · **Microphone** for Voice · **Camera** for card OCR and Interference — grant in **Settings → MindtoneX** if iOS asks.",
    ]

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
        "**Song search storefront:** Same card — **Apple iTunes catalog country**, not app language. **Automatic** uses your iPhone region; tap to search all storefronts (e.g. **SA**, **AE**, **EG**) if the catalog differs. No Apple preview → **US**, then **Deezer**.",
        "**OpenAI API key:** Same card — **one key** for **Song → Voice (AI)** and **Song → Camera** card vision (not two keys). Tap **Test** after pasting. Use the **info** icon for create-key and billing steps on platform.openai.com.",
        "**Incoming calls:** Set **Banner** on the iPhone (see **iPhone setup** above) — required for the show. **Silent mode** is your choice; the core effect is **in-app playback** when the call arrives, not changing the carrier ringtone unless you use the optional Share step on the **Song** tab.",
        "Do **not** lock the phone or switch apps during Perform — MindtoneX keeps the screen awake, but leaving the app stops the effect.",
        "**Perform URL scheme:** Home → **Performance settings** → **Copy URL scheme** (`magiccall://start-perform`). Opening that link starts Perform like tapping the Perform button (Shortcuts, NFC, QR).",
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
        "**Caller name (Contacts):** Only when **Show word on incoming call** and **Save locked word as contact name** are ON. Pick **Known** or **Unknown** on the Caller name card (default **Unknown**). **Unknown** → Perform opens the in-app dial first (real outgoing call → save number → stage). **Known** → no dial if you already **Choose contact**; straight to the stage screenshot. **Swipe down with two fingers** on the dial to cancel (same as exiting Perform). With **Camera** song input, media volume resets to about **half** so **volume up** can scan.",
        "Give your number; when they call back (with **Banner** call style), the app plays the locked song (**song 1** if **2 songs** is on). With **Interference ringtone**, an **open hand** during the ring brings static → song 1; a **second hand** (with **2 songs**) brings song 2. Hang-up = music stops.",
        "**Performer peek (Feedback):** **Hold** your finger on the screen (~instant) to see **Song**, **Caller name**, and **Notes** lines; **release** to hide. Empty fields show **— —**. **ON by default** — tune position, size, and color under **Feedback**.",
        "**Optional real ringtone (manual):** If **Auto-open Share** is **OFF**, after hang-up press **volume down** on the side of the phone once → Share → **Use as Ringtone** (see **Optional: real ringtone** below).",
        "Exit Perform: **two-finger swipe down** from the middle of the screen.",
    ]

    // MARK: - Song input

    static let songInputOverview: [String] = [
        "Pick **one** method for the **song** on the **Song input** card. During Perform, that method finds and **locks** a track before (or as) they call.",
        "**Interference ringtone only:** Under **Catalog & ringtone → Interference ringtone**, choose **1 song** or **2 songs on call**. **Normal ringtone** always plays **one** song (no second hand). Two songs = hand 1 → song 1, hand 2 → song 2 — one spectator can use both hands.",
        "This is separate from **Caller name** and **Notes contact** — you can combine them (example: **Camera** for song + **Voice** for both words). **Caller name** is a poor fit with **2 songs** — turn it off for a clean routine.",
    ]

    static let twoSongsExperimental: [String] = [
        "Toggle **1 song / 2 songs** inside **Interference ringtone** (not available for Normal ringtone).",
        "**Song 1** lives in the normal slot — **Normal ringtone** incoming calls always play **song 1** only.",
        "**Song 2** is stored separately (Home shows **Song 2** status when armed). It does **not** replace song 1 on a standard ring.",
        "**Camera:** two ALL CAPS title lines on one card — **top = song 1**, **bottom = song 2** — one **volume up** scan can read both.",
        "**Voice:** song 1 locks with the usual delay; the mic **keeps listening** until song 2 locks (same or another person).",
        "**Notes:** **line 1 = song 1**, **line 2 = song 2** (one title per line).",
        "**API:** first **new** search after Perform starts → song 1; the **next new** search → song 2; polling stops after song 2 locks.",
    ]

    static let interferenceRingtone: [String] = [
        "Song card → **Catalog & ringtone** → **Interference ringtone** (experimental). Pick **Ringtone 1/2** and the **interference sound** (.m4a files in the app bundle).",
        "Flow on the call: **your ringtone** → front camera sees an **open hand** (5 fingers, palm toward the phone) → **radio interference** morphs into **song 1**.",
        "With **2 songs** enabled: after interference finishes and **song 1** plays, the **first ~2 s** of that clean song ignore hand 2; **after 2 s**, an **open hand** → **interference audio 2** → **song 2**.",
        "Requires **Banner** incoming calls (Overview → **iPhone setup**) so the front camera stays live under the call UI. **Back Tap** or your **volume trigger** can substitute for the hand in rehearsal.",
        "Use **Open test mode** on the same card to practice ringtone, hands, and songs without placing a call.",
        "Allow **Camera** in iOS Settings → MindtoneX — without it, Perform falls back to the **normal ringtone**.",
    ]

    static var songInputCamera: [String] {
        var lines = [
            "**Camera:** Press **volume up** when the card is in focus (short snapshot; green dot only while capturing). With your **Performance settings** OpenAI key, **vision reads the whole card** in any language (local OCR is only a fallback when the key is missing). **Volume down** does not scan — use it after the call for **Use as Ringtone** when Auto-open Share is off.",
            "**Card layout:** \(CardOCRLayout.lineAssignmentSummary).",
            "White card, thick marker, ALL CAPS helps. Labels: `SONG:`, `WORD:`/`CALLER:`, `NOTES:`/`CHIP:`.",
        ]
        if CardOCRLayout.songOnlyOnCard {
            lines.append("**Song only:** Title and artist can be on one line or split — the app does not require fixed line numbers.")
        } else {
            lines.append("One volume scan can return **song + caller word + Notes word** when those inputs use Camera OCR.")
        }
        lines.append("**2 songs:** two title lines on the card (top = song 1, bottom = song 2). Pair with **Interference ringtone** for hand 1 → song 1, hand 2 → song 2 on the call.")
        return lines
    }

    static func songInputVoice(lockSeconds: Int) -> [String] {
        [
            "**Voice:** OpenAI key under **Performance settings** (same key as Camera). The mic listens; AI picks the spectator’s **final** song (ignores your examples).",
            "Locks after **\(lockSeconds) s** without a change (adjustable in Voice settings).",
            "**2 songs:** after song 1 locks, listening **continues** for song 2 (must be a **different** title).",
            "Same mic can run **extra AI prompts** for Caller name and Notes if those cards use **Voice (AI)**.",
        ]
    }

    static let songInputNotes: [String] = [
        "**Notes:** During Perform a note opens; the app searches the text you prepared (idle timer / Return / checkmark — see Notes controls on Home).",
        "Good when the song is written in Apple Notes instead of spoken or scanned.",
        "**2 songs:** **line 1 = song 1**, **line 2 = song 2**. The incoming call plays song 1; **Interference ringtone** + second hand plays song 2.",
    ]

    static let songInputAPI: [String] = [
        "**API:** Spectator searches in Inject / Elips / your endpoint; MindtoneX polls every \(Int(ApiSettings.pollInterval)) s and locks when their search loads.",
        "**2 songs:** first **new** search → song 1; **next new** search → song 2. Plain calls play song 1 only.",
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
        "Home → **Caller name**. Turn **Show word on incoming call** **ON**. With **Save locked word as contact name** on, pick **Known** or **Unknown** (default **Unknown**) — see the table below.",
        "When the word **locks** (Inject / Elips / Camera / Voice / etc.), MindtoneX writes **Contacts** so iOS can show that word on the callback. **Restore contact names after Perform** puts cards back how they were.",
        "**Inject / Elips / Custom API:** Polls every \(Int(WordApiSettings.pollInterval)) s. First reading = old word; **next change** = spectator’s word → lock.",
        "**Camera (OCR):** One word on the line under the song. **Voice (AI):** same mic script as on the card.",
    ]

    /// Known vs Unknown — comparison table for Instructions.
    static let callerNameKnownUnknown: [String] = [
        "**Known vs Unknown** (requires **Save locked word as contact name** + **Show word on incoming call**):",
        "",
        "**When you tap Perform**",
        "• **Known:** Stage screenshot **immediately** (no dial) if you already tapped **Choose contact**. If not, iOS asks you to pick their card first.",
        "• **Unknown:** In-app **Phone-style dial** → you place a **real outgoing call** → when it **ends**, MindtoneX saves the number and shows the stage.",
        "",
        "**Who / number**",
        "• **Known:** Friend or family **already in Contacts** — you link **one** contact on the Caller name card.",
        "• **Unknown:** Stranger or one-off — number comes from the **outgoing call** you just made.",
        "",
        "**When the word locks** (before they call you back)",
        "• **Known:** Renames **that contact only** — first name becomes the word.",
        "• **Unknown:** Finds **every** contact with that number and renames them, or **creates** a new contact if the number is new.",
        "",
        "**After Perform** (toggle **Restore contact names after Perform**)",
        "• Both modes: revert renamed cards; **delete** contacts MindtoneX created in Unknown mode.",
        "",
        "**Cancel Unknown dial:** **Two-finger swipe down** on the dial — same as Exit Perform. No number saved until the outgoing call completes.",
        "**Optional backup:** Manual **Call identification** number + **MindtoneX Caller Label** in Phone settings — only if you are **not** using Contacts rename.",
    ]

    // MARK: - Album artwork

    static let albumArtwork: [String] = [
        "Home → **Album artwork**. Turn on **Album art on contact**: when the song locks during Perform, its cover becomes the spectator’s **contact photo** (the round photo on the incoming call, in Recents and on their card).",
        "**Same Unknown / Known contact** as **Caller name** and **Notes contact** — change it on any of those cards.",
        "**Save album art to Photos** is separate and needs no contact.",
        "**Restore contact photo after Perform** puts the old photo back when the toggle is on.",
    ]

    // MARK: - Notes contact

    static let notesContact: [String] = [
        "Home → **Notes contact**. Sets the **Contacts → Notes** field on the spectator’s card (preview matches the real call sheet).",
        "**Same Unknown / Known contact** as **Caller name** and **Album artwork** — change it on any of those cards.",
        "**Note text** is empty by default — only what you type is saved. Tap **`{word}`** in the editor to insert the marker where the forced word should go; during the show, **`{word}`** is replaced by the locked **Notes chip** word (Inject / OCR line 3 / Voice).",
        "Uses its **own** word source — independent from Caller name.",
        "**Camera:** **Line 3** on the card (line 1 = song, line 2 = caller if enabled).",
    ]

    // MARK: - Feedback

    static let feedback: [String] = [
        "Home → **Feedback** (optional performer cues).",
        "**Hold-to-peek (default ON):** While your finger stays on the screen, you see live **Song** (or **Song 1** / **Song 2** when **2 songs** is enabled), **Caller name** (if armed), and **Notes** (if configured). Drag the **preview** to set position; adjust **size** and **color**. Release to hide — the audience still only sees the screenshot.",
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

    // MARK: - Community

    static let facebookUsersGroupURL = "https://www.facebook.com/share/g/1CGdX4UZcs/?mibextid=wwXIfr"

    static let facebookUsersGroup: [String] = [
        "Optional: join the **MindtoneX users** Facebook group — tips, questions, and updates from other performers.",
        "Link: [Open the Facebook group](\(facebookUsersGroupURL))",
        "If Facebook asks for a group password, enter: **`tone33`**",
    ]
}
