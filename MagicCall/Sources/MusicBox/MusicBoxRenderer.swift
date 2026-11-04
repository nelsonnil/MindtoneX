import Accelerate
import AVFoundation

/// Instrument the transcribed melody is replayed with.
enum MusicBoxStyle: String, CaseIterable, Identifiable, Sendable {
    case musicBox
    case nokia
    case polyphonic
    case marimba

    var id: String { rawValue }

    var title: String {
        switch self {
        case .musicBox: return "Music box"
        case .nokia: return "Nokia"
        case .polyphonic: return "Polyphonic"
        case .marimba: return "Marimba"
        }
    }

    var icon: String {
        switch self {
        case .musicBox: return "sparkles"
        case .nokia: return "candybarphone"
        case .polyphonic: return "pianokeys"
        case .marimba: return "music.note"
        }
    }

    var blurb: String {
        switch self {
        case .musicBox: return "Ballerina box: steel comb, bass every two beats, spring winding down."
        case .nokia: return "90s monophonic phone: one square-wave note at a time, rigid rhythm."
        case .polyphonic: return "2000s MIDI ringtone: melody, bass line and a light beat tick."
        case .marimba: return "iPhone-style marimba: soft wooden mallets with bass."
        }
    }

    var allowsWindDown: Bool { self == .musicBox }
    var allowsHumanize: Bool { self == .musicBox || self == .marimba }
    var allowsBass: Bool { self != .nokia }

    fileprivate var profile: StyleProfile {
        switch self {
        case .musicBox:
            return StyleProfile(melodyRange: 67...96, melodyCentre: 79, bassRange: 55...66, bassEveryBeats: 2,
                                minGap: 0.07, sameNoteGap: 0.12, quantize: false, ticks: false)
        case .nokia:
            return StyleProfile(melodyRange: 72...91, melodyCentre: 79, bassRange: nil, bassEveryBeats: 0,
                                minGap: 0.06, sameNoteGap: 0.06, quantize: true, ticks: false)
        case .polyphonic:
            return StyleProfile(melodyRange: 67...88, melodyCentre: 76, bassRange: 48...59, bassEveryBeats: 2,
                                minGap: 0.06, sameNoteGap: 0.08, quantize: true, ticks: true)
        case .marimba:
            return StyleProfile(melodyRange: 64...88, melodyCentre: 74, bassRange: 48...59, bassEveryBeats: 2,
                                minGap: 0.07, sameNoteGap: 0.1, quantize: false, ticks: false)
        }
    }
}

fileprivate struct StyleProfile {
    var melodyRange: ClosedRange<Int>
    var melodyCentre: Int
    var bassRange: ClosedRange<Int>?
    var bassEveryBeats: Int
    var minGap: Double
    var sameNoteGap: Double
    /// Snap onsets to a 16th-note grid (needs a tempo).
    var quantize: Bool
    var ticks: Bool
}

struct MusicBoxOptions: Equatable, Sendable {
    var style: MusicBoxStyle = .musicBox
    /// Playback rate of the arrangement (music boxes tend to play a little slower than the record).
    var speed: Double = 0.9
    var bass = true
    var snapToKey = true
    /// Spring running out: the last seconds slow down and soften.
    var windDown = true
    /// Small timing and loudness irregularities of a mechanical cylinder or a player.
    var humanize = true
}

struct MusicBoxEvent: Hashable, Sendable {
    enum Voice: Hashable, Sendable {
        case melody
        case bass
        case tick
    }

    var time: Double
    /// Held length for gated voices (Nokia, polyphonic); plucked voices ring on their own.
    var duration: Double
    var midi: Int
    var velocity: Float
    var voice: Voice
}

/// Turns a transcription into what the chosen instrument could play.
enum MusicBoxArranger {
    private static let leadIn = 0.35

    /// Lowest and highest MIDI note any style may use (piano-roll bounds).
    static let displayRange = 48...96

    static func arrange(_ analysis: MusicBoxAnalysis, options: MusicBoxOptions, seed: UInt64) -> [MusicBoxEvent] {
        guard !analysis.melody.isEmpty else { return [] }
        let style = options.style
        let profile = style.profile
        let midis = analysis.melody.map(\.midi).sorted()
        let median = midis[midis.count / 2]
        let shift = 12 * Int((Double(profile.melodyCentre - median) / 12).rounded())
        let scale = scalePitchClasses(tonic: analysis.keyTonic, minor: analysis.keyIsMinor)

        var notes = analysis.melody
        if profile.quantize, let bpm = analysis.bpm {
            let grid = 60 / bpm / 4
            notes = notes.map { note in
                var n = note
                n.start = (note.start / grid).rounded() * grid
                return n
            }
        }

        var events: [MusicBoxEvent] = []
        var lastTime = -Double.infinity
        var lastMidi: Int?
        for note in notes {
            var m = note.midi + shift
            // Long notes are trusted: a wrong key guess must not bend a held melody note.
            if options.snapToKey, note.duration < 0.25, !scale.contains(mod12(m)) {
                m = nearestInScale(m, scale: scale, toward: lastMidi)
            }
            while m < profile.melodyRange.lowerBound { m += 12 }
            while m > profile.melodyRange.upperBound { m -= 12 }
            let gap = note.start - lastTime
            if gap < profile.minGap || (m == lastMidi && gap < profile.sameNoteGap) { continue }
            events.append(MusicBoxEvent(time: note.start, duration: note.duration, midi: m,
                                        velocity: 0.55 + 0.45 * note.strength, voice: .melody))
            lastTime = note.start
            lastMidi = m
        }
        for i in events.indices {
            let next = i + 1 < events.count ? events[i + 1].time : .infinity
            events[i].duration = max(0.06, min(events[i].duration, next - events[i].time - 0.02, 1.5))
        }

        if let first = events.first?.time, let last = events.last.map({ $0.time + $0.duration }) {
            let beats = analysis.beatTimes
            let beatLength = analysis.bpm.map { 60 / $0 } ?? 0.5
            if options.bass, let bassRange = profile.bassRange {
                for (i, beat) in beats.enumerated() where i % profile.bassEveryBeats == 0 {
                    guard beat >= first - 0.3, beat <= last else { continue }
                    let root = analysis.beatBassRoots[i] ?? (i + 1 < analysis.beatBassRoots.count ? analysis.beatBassRoots[i + 1] : nil)
                    guard let root else { continue }
                    let m = bassRange.lowerBound + mod12(root - bassRange.lowerBound)
                    events.append(MusicBoxEvent(time: beat, duration: beatLength * Double(profile.bassEveryBeats) * 0.9,
                                                midi: m, velocity: 0.5, voice: .bass))
                }
            }
            if profile.ticks {
                for (i, beat) in beats.enumerated() where beat >= first - 0.3 && beat <= last {
                    events.append(MusicBoxEvent(time: beat, duration: 0.03, midi: 0,
                                                velocity: i % 2 == 0 ? 0.6 : 0.4, voice: .tick))
                }
            }
        }
        events.sort { $0.time < $1.time }
        guard let origin = events.first?.time else { return [] }

        var rng = SeededRandom(seed: seed)
        let end = ((events.last?.time ?? origin) - origin) / options.speed
        let slowLength = min(4, end * 0.3)
        let slowStart = end - slowLength
        let windDown = options.windDown && style.allowsWindDown
        let humanize = options.humanize && style.allowsHumanize
        return events.map { event in
            var e = event
            var t = (e.time - origin) / options.speed
            e.duration /= options.speed
            if windDown, slowLength > 0.5, t > slowStart {
                let u = t - slowStart
                t = slowStart + u + 0.9 * u * u / (2 * slowLength)
                e.velocity *= Float(1 - 0.3 * u / slowLength)
            }
            if humanize {
                t += rng.uniform(-0.008, 0.008)
                e.velocity *= Float(rng.uniform(0.88, 1.08))
            }
            e.time = leadIn + max(0, t)
            e.velocity = min(1, max(0.15, e.velocity))
            return e
        }
    }

    private static func scalePitchClasses(tonic: Int, minor: Bool) -> Set<Int> {
        // Minor keeps the raised 7th: melodies lean on it constantly.
        let steps = minor ? [0, 2, 3, 5, 7, 8, 10, 11] : [0, 2, 4, 5, 7, 9, 11]
        return Set(steps.map { mod12(tonic + $0) })
    }

    private static func nearestInScale(_ midi: Int, scale: Set<Int>, toward previous: Int?) -> Int {
        let up = midi + 1, down = midi - 1
        let upOK = scale.contains(mod12(up)), downOK = scale.contains(mod12(down))
        if upOK, downOK, let previous { return abs(up - previous) <= abs(down - previous) ? up : down }
        if downOK { return down }
        return upOK ? up : midi
    }

    private static func mod12(_ v: Int) -> Int { ((v % 12) + 12) % 12 }
}

/// Additive voices, one per style. Music box: steel comb tooth (near-harmonic body, detuned twin,
/// fast inharmonic cantilever modes, pluck click). Marimba: wooden bar modes. Nokia: band-limited square.
/// Polyphonic: bright MIDI-like lead, round bass and a noise tick.
enum MusicBoxSynth {
    static let sampleRate: Double = 44100
    private static let maxToneSeconds: Float = 3

    private struct Partial {
        var ratio: Float
        var amp: Float
        /// Multiplies the note's main decay; ignored when `fixedDecay` is set.
        var decayScale: Float = 1
        var fixedDecay: Float?
    }

    private static let combPartials: [Partial] = [
        Partial(ratio: 1, amp: 1),
        Partial(ratio: 1.0012, amp: 0.3, decayScale: 0.9),
        Partial(ratio: 2, amp: 0.22, decayScale: 0.4),
        Partial(ratio: 3, amp: 0.07, decayScale: 0.25),
        Partial(ratio: 5.93, amp: 0.16, fixedDecay: 0.12),
        Partial(ratio: 9.6, amp: 0.08, fixedDecay: 0.05),
    ]

    private static let marimbaPartials: [Partial] = [
        Partial(ratio: 1, amp: 1),
        Partial(ratio: 3.93, amp: 0.25, fixedDecay: 0.08),
        Partial(ratio: 9.2, amp: 0.06, fixedDecay: 0.03),
    ]

    private static let squarePartials: [Partial] = stride(from: 1, through: 11, by: 2).map {
        Partial(ratio: Float($0), amp: 1 / Float($0))
    }

    private static let leadPartials: [Partial] = [
        Partial(ratio: 1, amp: 1),
        Partial(ratio: 1.003, amp: 0.4),
        Partial(ratio: 2, amp: 0.35),
        Partial(ratio: 3, amp: 0.25),
        Partial(ratio: 4, amp: 0.1),
        Partial(ratio: 5, amp: 0.08),
    ]

    private static let polyBassPartials: [Partial] = [
        Partial(ratio: 1, amp: 1),
        Partial(ratio: 2, amp: 0.5),
        Partial(ratio: 3, amp: 0.2),
    ]

    static func render(_ events: [MusicBoxEvent], style: MusicBoxStyle, seed: UInt64) -> AVAudioPCMBuffer? {
        guard !events.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else { return nil }
        let tail: Double
        switch style {
        case .musicBox: tail = 3
        case .marimba: tail = 1.5
        case .polyphonic: tail = 1
        case .nokia: tail = 0.5
        }
        let end = events.map { $0.time + $0.duration }.max() ?? 0
        let mixer = Mixer(sampleCount: Int((end + tail) * sampleRate), sampleRate: Float(sampleRate),
                          maxToneSamples: Int(maxToneSeconds * Float(sampleRate)))
        var rng = SeededRandom(seed: seed &+ 1)

        for event in events {
            let start = Int(event.time * sampleRate)
            guard start < mixer.out.count else { continue }
            if event.voice == .tick {
                mixer.addNoise(start: start, seconds: 0.03, decay: 0.006, gain: 0.08 * event.velocity, rng: &rng)
                continue
            }
            let f = MusicBoxAnalyzer.midiToHz(Float(event.midi))
            let isBass = event.voice == .bass
            switch style {
            case .musicBox:
                let main = min(2.6, max(0.5, 1.9 * (523.25 / f).squareRoot()))
                mixer.addPartials(combPartials, start: start, f: f, mainDecay: main, ringFactor: 7,
                                  gain: event.velocity * 0.3 * (isBass ? 0.85 : 1), attack: 0.0005, rng: &rng)
                mixer.addNoise(start: start, seconds: 0.004, decay: 0.0008, gain: 0.05 * event.velocity, rng: &rng)
            case .marimba:
                let main = min(1.2, max(0.25, 0.9 * (262 / f).squareRoot())) * (isBass ? 1.3 : 1)
                mixer.addPartials(marimbaPartials, start: start, f: f, mainDecay: main, ringFactor: 6,
                                  gain: event.velocity * 0.35 * (isBass ? 0.8 : 1), attack: 0.003, rng: &rng)
            case .nokia:
                mixer.addPartials(squarePartials, start: start, f: f, gate: Float(event.duration),
                                  gain: 0.3, attack: 0.002, release: 0.004, rng: &rng)
            case .polyphonic:
                if isBass {
                    mixer.addPartials(polyBassPartials, start: start, f: f, gate: Float(event.duration), mainDecay: 2,
                                      gain: 0.32 * event.velocity, attack: 0.006, release: 0.05, rng: &rng)
                } else {
                    mixer.addPartials(leadPartials, start: start, f: f, gate: Float(event.duration) + 0.05, mainDecay: 1.5,
                                      gain: 0.22 * event.velocity, attack: 0.004, release: 0.04, rng: &rng)
                }
            }
        }
        return mixer.finish(format: format)
    }

    private final class Mixer {
        var out: [Float]
        let sr: Float
        let maxTone: Int
        private var a: [Float]
        private var b: [Float]
        private var c: [Float]

        init(sampleCount: Int, sampleRate: Float, maxToneSamples: Int) {
            out = [Float](repeating: 0, count: sampleCount)
            sr = sampleRate
            maxTone = maxToneSamples
            a = [Float](repeating: 0, count: maxToneSamples)
            b = a
            c = a
        }

        /// Plucked (`gate == nil`, rings for `ringFactor` × decay) or held for `gate` seconds.
        func addPartials(
            _ partials: [Partial], start: Int, f: Float, gate: Float? = nil, mainDecay: Float? = nil,
            ringFactor: Float = 7, gain: Float, attack: Float, release: Float = 0.02, rng: inout SeededRandom
        ) {
            for p in partials {
                let decay = p.fixedDecay ?? mainDecay.map { $0 * p.decayScale }
                let seconds = gate ?? min(MusicBoxSynth.maxToneSeconds, ringFactor * (decay ?? 1))
                addTone(start: start, seconds: seconds, freq: f * p.ratio, gain: gain * p.amp, decay: decay,
                        attack: attack, release: release, phase: Float(rng.uniform(0, 0.2)))
            }
        }

        func addTone(start: Int, seconds: Float, freq: Float, gain: Float, decay: Float?,
                              attack: Float, release: Float, phase: Float) {
            let n = min(maxTone, Int(seconds * sr), out.count - start)
            guard n > 0, freq < sr * 0.45 else { return }
            var count = Int32(n)
            var phase0 = phase
            var phaseStep = 2 * Float.pi * freq / sr
            vDSP_vramp(&phase0, &phaseStep, &a, 1, vDSP_Length(n))
            vvsinf(&b, a, &count)
            if let decay {
                var env0: Float = 0
                var envStep = -1 / (decay * sr)
                vDSP_vramp(&env0, &envStep, &a, 1, vDSP_Length(n))
                vvexpf(&c, a, &count)
            } else {
                var one: Float = 1
                vDSP_vfill(&one, &c, 1, vDSP_Length(n))
            }
            let attackSamples = min(n, Int(attack * sr))
            for i in 0..<attackSamples { c[i] *= Float(i) / Float(attackSamples) }
            let releaseSamples = min(n - attackSamples, Int(release * sr))
            for i in 0..<releaseSamples { c[n - 1 - i] *= Float(i) / Float(releaseSamples) }
            vDSP_vmul(b, 1, c, 1, &a, 1, vDSP_Length(n))
            var g = gain
            out.withUnsafeMutableBufferPointer { o in
                let dst = o.baseAddress! + start
                vDSP_vsma(a, 1, &g, dst, 1, dst, 1, vDSP_Length(n))
            }
        }

        /// High-passed noise burst (pluck click, beat tick).
        func addNoise(start: Int, seconds: Float, decay: Float, gain: Float, rng: inout SeededRandom) {
            let n = min(Int(seconds * sr), out.count - start)
            var previous: Float = 0
            for i in 0..<max(0, n) {
                let noise = Float(rng.uniform(-1, 1))
                out[start + i] += (noise - previous) * expf(-Float(i) / (decay * sr)) * gain
                previous = noise
            }
        }

        func finish(format: AVAudioFormat) -> AVAudioPCMBuffer? {
            let total = out.count
            var peak: Float = 0
            vDSP_maxmgv(out, 1, &peak, vDSP_Length(total))
            if peak > 0 {
                var scale = 0.89 / peak
                out.withUnsafeMutableBufferPointer { o in
                    vDSP_vsmul(o.baseAddress!, 1, &scale, o.baseAddress!, 1, vDSP_Length(total))
                }
            }
            let fade = min(total, Int(0.05 * sr))
            for i in 0..<fade { out[total - 1 - i] *= Float(i) / Float(fade) }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
                  let channel = buffer.floatChannelData?[0]
            else { return nil }
            buffer.frameLength = AVAudioFrameCount(total)
            out.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: total) }
            return buffer
        }
    }
}

/// Deterministic per song so re-rendering with the same options sounds the same.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * Double(next() >> 11) / Double(1 << 53)
    }
}
