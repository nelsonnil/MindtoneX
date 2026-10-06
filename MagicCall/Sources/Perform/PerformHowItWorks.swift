import SwiftUI

/// Plain-language explainers shown on the setup screen.
struct HowItWorksCard: View {
    let title: String
    let icon: String
    let steps: [String]
    var footer: String?
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.accentColor))
                        Text(.init(step))
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let footer {
                    Text(.init(footer))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct TipCard: View {
    let title: String
    let icon: String
    let tint: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(tint)
                    Text(.init(line))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum PerformCopy {
    static func aiVoiceSteps(lockSeconds: Int) -> [String] {
        [
            "Press **Perform** (or **Start test** below) — the app starts listening.",
            "Ask the spectator to name any song. It ignores the example songs you mention and follows changes of mind (“no, better…”).",
            "As soon as it hears a song, it finds it and gets it ready.",
            "It waits **\(lockSeconds) seconds** (adjustable in Voice settings) in case the spectator corrects or names another song.",
            "After \(lockSeconds) seconds with no change, the song is **locked** and listening stops completely.",
            "When the call comes, that song plays.",
            "Leaving Perform (or going back to this screen) resets everything — what it heard, the guess and the locked song — for the next performance.",
        ]
    }

    static func shareSteps(input: VoiceSettings.InputMode, lockSeconds: Int) -> [String] {
        var steps = ["Press **Perform** — the full-screen stage appears."]
        switch input {
        case .aiVoice:
            steps.append("The app listens while the spectator names a song (same \(lockSeconds)-second lock as above), then stops the microphone.")
        case .api:
            steps.append("Ask the spectator to search a song in \(ApiSettings.provider.title). The app checks every \(Int(ApiSettings.pollInterval)) seconds and locks their search as soon as the preview is loaded.")
        case .notes:
            steps.append("A white note opens instead. The song written in it is searched and loaded in the background.")
        case .card:
            steps.append("The back camera reads the spectator’s handwritten card when you press a **volume button** (no screen touch). ALL CAPS on white card works best.")
        case .manual:
            steps.append("The app uses the song you typed above.")
        }
        steps += [
            "The Share pop-up opens by itself. Tap **Use as Ringtone** (in Favorites).",
            "You feel a soft vibration: the ringtone is added. iOS now opens **Settings → Ringtone** by itself — **press Home once (or swipe up)**. The app can’t close Settings for you.",
            "The real ringtone is now set, so the call rings with the song from anywhere. If you closed the pop-up without choosing, return to the stage screen and tap to open the Share sheet again.",
        ]
        return steps
    }

    /// Shown as its own highlighted card: the one manual step left in Share Ringtone.
    static let shareHomeStep = "After **Use as Ringtone**, iOS opens **Settings → Ringtone**. Press **Home once** (or swipe up) to return to your Home Screen. The ringtone is already saved."

    static func shareTiming(lockSeconds: Int) -> [String] {
        [
            "Ask the spectator to name a song. Wait about \(lockSeconds) seconds — the Share pop-up appears.",
            "Tap **Use as Ringtone** (in Favorites). Soft vibration = done.",
            "When **Settings → Ringtone** opens, **press Home once (or swipe up)** to return.",
            "Continue your performance and have them place the test call when you are ready.",
        ]
    }

    static let shareCaveats = [
        "**Silent must be OFF** in this mode — the real ringtone is what plays. With the “MindtoneX Silent Off” shortcut installed, Perform turns it off for you.",
        "iOS always opens **Settings → Ringtone** after “Use as Ringtone”. Apps can’t prevent or close it — one Home press (or swipe up) is needed.",
        "When you return to the stage screen, tap it once or swipe down with two fingers to leave Perform.",
        "Each export uses a distinct name so you can add it again. Manage older ringtones in **Settings → Sounds & Haptics → Ringtone** (swipe left → Delete). The app can’t remove them for you.",
    ]

    static let fakeTiming = [
        "**Silent must be ON.** With the “MindtoneX Silent On” shortcut installed, Perform turns it on for you (Shortcuts flashes briefly — press Perform before you begin the performance). Otherwise turn it on by hand.",
        "Stay on the stage screen in MindtoneX — the app keeps the display awake. Don’t press the side button or lock the phone.",
        "While the spectator names the song, share your number and ask them to call you when you are ready.",
        "When the call arrives the song plays by itself. When the caller hangs up it stops for good — nothing plays again until you swipe down with two fingers to leave.",
    ]

    static let wordApiSteps: [String] = [
        "On home, open **Word API (caller label)** (below Song input). Turn **Caller label** **ON** and connect **Inject**, **Elips**, or **Custom API** — this is a **second endpoint**, separate from the song API under Song input.",
        "During **Perform**, MindtoneX polls the word URL every \(Int(WordApiSettings.pollInterval)) s **in parallel** with however you load the song (**AI Voice**, **API song input**, **Notes**, **Card**, or manual search). Song and word are independent streams into one performance.",
        "**Elips example:** enable **API** for the song (spectator searches a title in Elips) and **Elips** for the word (spectator submits a word — often one they chose from the lyrics). When the word **locks**, that text can appear as the **incoming caller name** while your stage plays the locked song.",
        "The **first poll** is the old value on the server (baseline). The **next change** is the spectator’s new word → **lock** (three short taps). Then have them call you — the banner should show the word, not only the digits.",
        "Turn on **Settings → Phone → Call Blocking & Identification → MindtoneX**. Optional: **Save locked word as contact name** (below) so iOS shows the prediction even more reliably than Call Directory alone.",
    ]

    /// Known vs Unknown contact — prediction on the incoming-call name.
    static let wordApiContactPrediction: [String] = [
        "**The idea:** the spectator’s word from the API becomes the **name** on the incoming call — a contact “prediction” instead of an anonymous number.",
        "**Known** (friend, family, repeat volunteer): turn **Save locked word as contact name** **ON** → **Known** → **Choose contact**. When the word locks, MindtoneX **replaces that contact’s first name** with the API word. After the show, close **Word API connection details** with **Restore original name when leaving Word API settings** **ON** — the app puts their real name back.",
        "**Unknown** (stranger, one-off): same save toggle **ON** → **Unknown**. Press **Perform** — a **dial sheet** appears. Tell the spectator you need their number for a **missed-call** bit and that they should keep your number. Place the outgoing call; when it ends, MindtoneX arms. You are **not** saving their real name — when the word locks, the app **creates or updates** a contact for that number with the **prediction word** as the display name.",
        "**Routine timing:** run song input and word API together — e.g. spectator searches the song in Elips while you submit their lyric word on the word endpoint; both lock during the same Perform. Then the callback shows **song on stage** + **word on caller ID**.",
    ]

    /// Testers often ask for “voicemail says the prediction” — iOS/carrier limits (shown in Instructions).
    static let voicemailAndMissedCall = [
        "**Voicemail with the song name?** No app (including MindtoneX) can speak a **new prediction** on your **carrier voicemail** when you don’t answer. After the ring, callers hear **your carrier’s voicemail** and a **fixed greeting** you set in **Settings → Phone**, not text generated per show.",
        "**Stage Ringtone:** if you don’t pick up, the caller hears normal ringing; **your song plays on your iPhone** during the ring — not as their voicemail message.",
        "**Phone Ringtone:** callers may hear your **custom ringtone** while it rings; when it goes to voicemail, the greeting is still **static**, not the app’s guess.",
        "**What works instead:** answer for the full effect; or use a **pre-recorded** generic greeting; or a **separate** phone/service (e.g. Twilio) — outside this app.",
    ]
}
