# Performance & battery — Perform + Home

Notes for magicians and testers on **MindtoneX** (iPhone, especially older models). This is about heat, sluggish UI, and battery drain — not show logic.

---

## Quick checklist (before blaming the app)

1. **Live watch left running?** Home → API song → **Stop watching** when you are done rehearsing. Same for **Voice test** (mic + OpenAI realtime).
2. **Card practice?** Song input **Camera** test keeps the **back camera on** until you leave that test or switch input mode.
3. **Perform armed in pocket?** While **Perform** is active, the app keeps the screen awake, may run **hot standby** audio (silent loop), polls Elips/API every **2 s**, and checks for incoming calls every **350 ms** — by design for the trick.
4. **OpenAI key + Voice/Camera?** Network + CPU spikes are normal **during** listening or a volume scan; they should **stop** when the mic/camera stops.

---

## Camera session lifecycle

| Mode | When camera runs | When it stops |
|------|------------------|---------------|
| **Perform + Camera song** | Only during a **volume scan** burst (green dot while capturing) | Stops after frames are collected (often **before** OpenAI vision finishes) |
| **Home + Camera test** | From **Test** start until **Stop** or input change | `stopTest()` turns session off |
| **Perform idle (waiting for volume)** | **Off** — no green dot until scan | — |

**Preset:** 1080p back wide angle, continuous autofocus while running — meaningful GPU/ISP load while the session is open.

**Takeaway:** If the phone feels hot on **Home**, check Camera test. On **Perform**, brief heat on each volume scan is expected; constant green dot is not.

---

## OpenAI (Voice + Camera vision)

- **One API key** (Performance settings) powers **Voice AI** (realtime transcription + song picking) and **Camera** card vision (JPEG upload per scan).
- **Voice Perform / Voice test:** Mic capture + WebSocket-style realtime API while **listening**. Debounce timers coalesce transcript updates; song evaluation hits the Responses API when text changes.
- **Camera Perform:** OpenAI runs **after** the camera stops, on the best snapshot frame(s). Local Vision OCR also runs on-device during the burst (CPU).
- **Cost / network:** Voice is ongoing while listening; Camera is bursty per volume press.

Nothing runs “in the background” for OpenAI unless **Home test** modes were left active (see polling below).

---

## API polling (Elips / Inject / Custom)

| Source | Interval | When it runs |
|--------|----------|--------------|
| **Song API** (Perform) | **2 s** | From Perform start until song **locked** or call arrives |
| **Song API** (Home **Live watch**) | **2 s** | Until **Stop watching** or app leaves foreground |
| **Word API** (caller name, Elips/etc.) | **2 s** | During **Perform** only if **Show word on incoming call** is on and provider uses network (not Card/Voice-only) |
| **Word API** (Home test) | **2 s** | While word watch test is active in settings |

Song and Word API **do not poll together** on the same timer — two sessions if both are enabled for Perform.

**Recent fix (battery):** Live watch and word watch **tests** pause when the app goes to **background**; timers also skip network while backgrounded. Tap **Watch test** again after returning if you want to keep rehearsing.

---

## Screen awake

- While MindtoneX is **visible** (Home or Perform), auto-lock is **disabled** so the show is not interrupted.
- In **background**, auto-lock is restored.

Expect higher battery use if Home is left open on a bright screen — same as any show app that keeps the display on.

---

## Audio engine & hot standby

- **Hot standby** (preference): Before/during Perform, the ringtone clip may play at **volume 0** so the real ring can start instantly. This keeps **AVAudioSession** active and is intentional for reliability.
- **Background + Perform armed:** App may restart silent standby so iOS does not suspend audio — needed for incoming-call timing; uses some battery in pocket.
- **Disarm:** Playback stops and the session is **deactivated** (`deactivateSession`).

Home **preview** audition stops when you background or open Shortcuts (inactive).

---

## Timers on Home (continuous work)

| Activity | What keeps running |
|----------|-------------------|
| **Live watch** (song API) | 2 s HTTP polling |
| **Voice test** | Mic + OpenAI realtime |
| **Card test** | Camera session |
| **Word API connection test / watch** | 2 s polling when test session active |
| **Notes test** | Idle timer when typing (not network) |
| **Library search / preview** | Short bursts only |

**No polling** when you are simply browsing Home with tests **off** and Perform **disarmed**.

---

## Perform-only CPU (expected)

- **Call polling ~350 ms** while armed — backs up CallKit when the app is inactive (e.g. Shortcuts silent-mode hop).
- **Volume KVO** for Camera scan and fake ringtone media volume.
- **Elips + Word API** every 2 s until inputs lock (can be **two** parallel poll loops).

---

## What we changed (safe optimizations)

1. **Background Home:** Stopping Live watch, Voice test, Card test camera, Word test, and related audio when the app enters **background** (and when already pausing for inactive UI).
2. **Guard rails:** Song/Word **test** poll ticks skip network if the app is already backgrounded (belt-and-suspenders).

Perform behavior unchanged: API polling and hot standby while **armed** still run as before.

---

## Reporting issues to Nelson

Include:

- iPhone model + iOS version  
- Song input (Manual / Voice / Notes / API / **Camera**)  
- Caller name source (off / Elips / …)  
- Was **Live watch** or **Voice test** left on?  
- **Perform armed** vs **Home only**  
- Debug log lines: `[API]`, `[WORD]`, `[CARD]`, `[VOICE]`, `scenePhase → background`

---

## Related docs

- [camera-perform-test-notes.md](./camera-perform-test-notes.md) — Camera + OpenAI on stage  
- Perform log: **OpenAI · key configured** vs **skipped** at session start
