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
            "Ask the spectator to name any song. The AI ignores the example songs you mention and follows changes of mind (“no, better…”).",
            "As soon as it hears a song, it finds it and gets it ready.",
            "It waits **\(lockSeconds) seconds** (adjustable in Voice settings) in case the spectator corrects or names another song.",
            "After \(lockSeconds) seconds with no change, the song is **locked** and listening stops completely.",
            "When the call comes, that song plays.",
            "Leaving Perform (or going back to this screen) resets everything — what it heard, the guess and the locked song — for the next performance.",
        ]
    }

    static func shareSteps(voice: Bool, lockSeconds: Int) -> [String] {
        var steps = ["Press **Perform** — the screen goes black."]
        if voice {
            steps.append("The app listens while the spectator names a song (same \(lockSeconds)-second lock as above), then stops the microphone.")
        } else {
            steps.append("The app uses the song you typed above.")
        }
        steps += [
            "The Share pop-up opens by itself. Tap **Use as Ringtone** (in Favorites).",
            "Right after **Use as Ringtone**, the app goes to your Home Screen **by itself**. If you closed the pop-up without choosing, the screen stays black — tap it to open the pop-up again.",
            "The real ringtone is now set, so the call rings with the song from anywhere.",
        ]
        return steps
    }

    static func shareTiming(lockSeconds: Int) -> [String] {
        [
            "Ask the spectator to name a song. Wait about \(lockSeconds) seconds — the Share pop-up appears.",
            "Tap **Use as Ringtone** (in Favorites).",
            "The app jumps to your Home Screen by itself — to the spectator it just looks like you’re unlocking your phone.",
            "While you do all this, keep talking: tell them you’ll give them your number and ask them to call you. With natural timing, nothing looks unusual.",
        ]
    }

    static let shareCaveats = [
        "**Silent must be OFF** in this mode — the real ringtone is what plays.",
        "If iOS opens **Settings → Ringtone** after “Use as Ringtone”, swipe up to Home, or switch back to MagicCall — it jumps Home by itself (or tap the black screen once).",
        "If it doesn’t go Home by itself, tap the black screen; if that doesn’t work either, swipe up from the bottom.",
        "Every performance adds a new ringtone with a slightly different name, so iOS never says “duplicate”. To remove old ones: **Settings → Sounds & Haptics → Ringtone**, swipe left on a ringtone → Delete. The app can’t remove them for you.",
    ]

    static let fakeTiming = [
        "Turn **Silent ON** before you press Perform.",
        "Stay on the black (or screenshot) screen and keep the phone unlocked — don’t press the side button.",
        "Keep talking while the spectator names the song and while you give them your number; ask them to call you.",
        "When the call arrives the song plays by itself. Hold two fingers for 1.5 s to leave afterwards.",
    ]
}
