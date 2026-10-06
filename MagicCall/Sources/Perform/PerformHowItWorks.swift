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
        "On home, open **Word API (caller label)** — turn **Caller label (incoming call banner)** **ON**, then choose **Inject**, **Elips**, or **Custom API** (separate from the song API).",
        "Press **Perform**. With the toggle on, the app polls your word endpoint every \(Int(WordApiSettings.pollInterval)) seconds **in parallel** with your song input.",
        "The **first reading** is the old word on the backend; the **next change** is the spectator’s word — it **locks** (three short buzzes).",
        "Pause, then have the spectator call you. The incoming-call **banner** should show the locked word (Stage still plays the song from song input).",
        "Enable **Settings → Phone → Call Blocking & Identification → MindtoneX Caller Label**. For **any number** on iOS 18+, Live Caller ID Lookup needs a PIR backend (see repo notes).",
    ]

    /// Testers often ask for “voicemail says the prediction” — iOS/carrier limits (shown in Instructions).
    static let voicemailAndMissedCall = [
        "**Voicemail with the song name?** No app (including MindtoneX) can speak a **new prediction** on your **carrier voicemail** when you don’t answer. After the ring, callers hear **your carrier’s voicemail** and a **fixed greeting** you set in **Settings → Phone**, not text generated per show.",
        "**Stage Ringtone:** if you don’t pick up, the caller hears normal ringing; **your song plays on your iPhone** during the ring — not as their voicemail message.",
        "**Phone Ringtone:** callers may hear your **custom ringtone** while it rings; when it goes to voicemail, the greeting is still **static**, not the app’s guess.",
        "**What works instead:** answer for the full effect; or use a **pre-recorded** generic greeting; or a **separate** phone/service (e.g. Twilio) — outside this app.",
    ]
}
