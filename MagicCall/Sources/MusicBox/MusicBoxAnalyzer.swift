import Accelerate
import AVFoundation

/// One melody note heard in the preview.
struct MusicBoxMelodyNote: Hashable, Sendable {
    var start: Double
    var duration: Double
    var midi: Int
    /// 0…1, relative to the loudest melody frames of the song.
    var strength: Float
}

struct MusicBoxAnalysis: Sendable {
    var duration: Double
    var melody: [MusicBoxMelodyNote]
    var keyTonic: Int
    var keyIsMinor: Bool
    var bpm: Double?
    var beatTimes: [Double]
    /// Bass pitch class heard from each beat to the next (nil = unclear).
    var beatBassRoots: [Int?]

    var keyName: String {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        return names[keyTonic] + (keyIsMinor ? " minor" : " major")
    }
}

enum MusicBoxAnalyzerError: LocalizedError {
    case unreadableAudio
    case tooShort

    var errorDescription: String? {
        switch self {
        case .unreadableAudio: return "Could not decode the song preview."
        case .tooShort: return "The preview is too short to find a melody."
        }
    }
}

/// Predominant-melody transcription from a full mix (no source separation):
/// harmonic-summation salience → Viterbi pitch path → voicing → semitone notes, plus key, tempo and bass roots.
enum MusicBoxAnalyzer {
    static let sampleRate: Double = 22050
    private static let fftLog2 = 12
    private static let fftSize = 1 << fftLog2
    private static let hop = 256
    /// Above bass fundamentals: a low voice is then tracked an octave up, which the arranger folds away anyway.
    private static let minMidi = 55
    private static let maxMidi = 88
    private static let binsPerSemitone = 5
    private static let pitchBins = (maxMidi - minMidi) * binsPerSemitone + 1
    private static var framesPerSecond: Double { sampleRate / Double(hop) }
    /// Pitch frames are stamped at the window centre.
    private static var frameCentre: Double { Double(fftSize / 2) / sampleRate }
    /// Log flux already reacts when a note enters the leading edge of the window.
    private static let onsetFrameShift = fftSize / 2 / hop

    static func analyze(data: Data, fileTypeHint: String) throws -> MusicBoxAnalysis {
        try analyze(samples: decodeMono(data: data, fileTypeHint: fileTypeHint))
    }

    static func analyze(samples: [Float]) throws -> MusicBoxAnalysis {
        guard samples.count > fftSize * 4 else { throw MusicBoxAnalyzerError.tooShort }
        let spectra = spectra(samples)
        let frames = spectra.frameCount
        let path = trackPitch(salience: spectra.salience, frames: frames)
        let onsetEnvelope = onsetStrength(spectra.flux)
        let onsets = Set(pickOnsets(onsetEnvelope).map { $0 + onsetFrameShift })
        let melody = segmentNotes(path: path, onsets: onsets)
        let key = estimateKey(melody)
        let beats = estimateBeats(onsetEnvelope)
        let roots = bassRoots(chroma: spectra.bassChroma, frames: frames, beatTimes: beats.times)
        return MusicBoxAnalysis(
            duration: Double(samples.count) / sampleRate,
            melody: melody,
            keyTonic: key.tonic,
            keyIsMinor: key.minor,
            bpm: beats.bpm,
            beatTimes: beats.times,
            beatBassRoots: roots
        )
    }

    // MARK: Decode

    static func decodeMono(data: Data, fileTypeHint: String) throws -> [Float] {
        let ext: String
        switch fileTypeHint {
        case AVFileType.mp3.rawValue: ext = "mp3"
        case AVFileType.wav.rawValue: ext = "wav"
        case AVFileType.caf.rawValue: ext = "caf"
        case AVFileType.aiff.rawValue: ext = "aiff"
        default: ext = "m4a"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("musicbox-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard file.length > 0,
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else { throw MusicBoxAnalyzerError.unreadableAudio }
        try file.read(into: input)
        converter.downmix = true

        let capacity = AVAudioFrameCount(Double(input.frameLength) * sampleRate / inFormat.sampleRate) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            throw MusicBoxAnalyzerError.unreadableAudio
        }
        var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if fed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let channel = output.floatChannelData?[0], output.frameLength > 0 else {
            throw conversionError ?? MusicBoxAnalyzerError.unreadableAudio
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    // MARK: Spectra

    private struct Spectra {
        var frameCount: Int
        /// frameCount × pitchBins
        var salience: [Float]
        var flux: [Float]
        /// frameCount × 12, energy of 60–260 Hz peaks per pitch class.
        var bassChroma: [Float]
    }

    private static func spectra(_ x: [Float]) -> Spectra {
        let n = fftSize
        let half = n / 2
        let frameCount = (x.count - n) / hop + 1
        let bins = pitchBins
        var salience = [Float](repeating: 0, count: frameCount * bins)
        var flux = [Float](repeating: 0, count: frameCount)
        var chroma = [Float](repeating: 0, count: frameCount * 12)
        guard let setup = vDSP_create_fftsetup(vDSP_Length(fftLog2), FFTRadix(kFFTRadix2)) else {
            return Spectra(frameCount: 0, salience: [], flux: [], bassChroma: [])
        }
        defer { vDSP_destroy_fftsetup(setup) }

        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        var frame = [Float](repeating: 0, count: n)
        var re = [Float](repeating: 0, count: half)
        var im = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        var mag = [Float](repeating: 0, count: half)
        var prevLog = [Float](repeating: 0, count: half)
        var peaks: [(freq: Float, amp: Float)] = []
        peaks.reserveCapacity(256)

        let binHz = Float(sampleRate) / Float(n)
        let maxPeakBin = min(half - 2, Int(5000 / binHz))
        let minF0 = midiToHz(Float(minMidi) - 0.5)
        let maxPos = Float(bins - 1)
        let span = Float(binsPerSemitone)

        for f in 0..<frameCount {
            let start = f * hop
            x.withUnsafeBufferPointer { xp in
                vDSP_vmul(xp.baseAddress! + start, 1, window, 1, &frame, 1, vDSP_Length(n))
            }
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, vDSP_Length(fftLog2), FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
                }
            }
            power[0] = 0
            var count = Int32(half)
            vvsqrtf(&mag, power, &count)

            var fl: Float = 0
            var frameMax: Float = 0
            for k in 1...maxPeakBin {
                let l = log1pf(mag[k])
                let d = l - prevLog[k]
                if d > 0 { fl += d }
                prevLog[k] = l
                if mag[k] > frameMax { frameMax = mag[k] }
            }
            flux[f] = fl
            guard frameMax > 0 else { continue }

            peaks.removeAll(keepingCapacity: true)
            let floor = frameMax * 0.01
            for k in 2..<maxPeakBin {
                let b = mag[k]
                guard b > floor, b > mag[k - 1], b >= mag[k + 1] else { continue }
                let a = mag[k - 1], c = mag[k + 1]
                let denom = a - 2 * b + c
                let p: Float = denom != 0 ? 0.5 * (a - c) / denom : 0
                peaks.append(((Float(k) + p) * binHz, b - 0.25 * (a - c) * p))
            }
            if peaks.count > 40 {
                peaks.sort { $0.amp > $1.amp }
                peaks.removeLast(peaks.count - 40)
            }

            let base = f * bins
            salience.withUnsafeMutableBufferPointer { sal in
                for peak in peaks {
                    if peak.freq >= 60, peak.freq < 260 {
                        chroma[f * 12 + pitchClass(ofHz: peak.freq)] += peak.amp
                    }
                    let a = peak.amp * melodyWeight(peak.freq)
                    var harmonicWeight: Float = 1
                    for h in 1...10 {
                        let f0 = peak.freq / Float(h)
                        if f0 < minF0 { break }
                        let pos = (hzToMidi(f0) - Float(minMidi)) * span
                        if pos <= maxPos + span {
                            let lo = max(0, Int((pos - span).rounded(.up)))
                            let hi = min(bins - 1, Int((pos + span).rounded(.down)))
                            if lo <= hi {
                                for j in lo...hi {
                                    let c = cosf((Float(j) - pos) / span * .pi / 2)
                                    sal[base + j] += a * harmonicWeight * c * c
                                }
                            }
                        }
                        harmonicWeight *= 0.8
                    }
                }
            }
        }
        return Spectra(frameCount: frameCount, salience: salience, flux: flux, bassChroma: chroma)
    }

    /// Keeps bass and hi-hats from winning the melody salience.
    private static func melodyWeight(_ f: Float) -> Float {
        if f < 150 { return 0 }
        if f < 300 { return (f - 150) / 150 }
        if f > 3000 { return 3000 / f }
        return 1
    }

    // MARK: Pitch path

    private struct PitchPath {
        /// Fractional MIDI per frame, nil when no melody is sounding.
        var midi: [Float?]
        /// 0…1 per frame.
        var strength: [Float]
    }

    private static func trackPitch(salience: [Float], frames: Int) -> PitchPath {
        let bins = pitchBins
        guard frames > 1 else { return PitchPath(midi: [], strength: []) }

        var emission = [Float](repeating: 0, count: frames * bins)
        var rowMax = [Float](repeating: 0, count: frames)
        var rowMean = [Float](repeating: 0, count: frames)
        salience.withUnsafeBufferPointer { sal in
            for t in 0..<frames {
                let row = sal.baseAddress! + t * bins
                var m: Float = 0
                var mean: Float = 0
                vDSP_maxv(row, 1, &m, vDSP_Length(bins))
                vDSP_meanv(row, 1, &mean, vDSP_Length(bins))
                rowMax[t] = m
                rowMean[t] = mean
                if m > 0 {
                    var scale = 1 / m
                    emission.withUnsafeMutableBufferPointer { em in
                        vDSP_vsmul(row, 1, &scale, em.baseAddress! + t * bins, 1, vDSP_Length(bins))
                    }
                }
            }
        }

        let window = 7 * binsPerSemitone
        let stepCost: Float = 0.15 / Float(binsPerSemitone)
        let jumpCost: Float = 1.2
        var score = Array(emission[0..<bins])
        var next = [Float](repeating: 0, count: bins)
        var back = [Int16](repeating: 0, count: frames * bins)

        emission.withUnsafeBufferPointer { em in
            back.withUnsafeMutableBufferPointer { bp in
                for t in 1..<frames {
                    score.withUnsafeBufferPointer { s in
                        next.withUnsafeMutableBufferPointer { nx in
                            var bestPrev = -Float.infinity
                            var bestIdx = 0
                            for i in 0..<bins where s[i] > bestPrev {
                                bestPrev = s[i]
                                bestIdx = i
                            }
                            for j in 0..<bins {
                                var best = bestPrev - jumpCost
                                var arg = bestIdx
                                let lo = max(0, j - window), hi = min(bins - 1, j + window)
                                for i in lo...hi {
                                    let v = s[i] - stepCost * Float(abs(i - j))
                                    if v > best {
                                        best = v
                                        arg = i
                                    }
                                }
                                nx[j] = best + em[t * bins + j]
                                bp[t * bins + j] = Int16(arg)
                            }
                        }
                    }
                    swap(&score, &next)
                }
            }
        }

        var path = [Int](repeating: 0, count: frames)
        var last = 0
        for i in 0..<bins where score[i] > score[last] { last = i }
        path[frames - 1] = last
        for t in stride(from: frames - 1, to: 0, by: -1) {
            path[t - 1] = Int(back[t * bins + path[t]])
        }

        var raw = [Float](repeating: 0, count: frames)
        for t in 0..<frames { raw[t] = salience[t * bins + path[t]] }
        let p90 = percentile(raw, 0.9)
        var midi = [Float?](repeating: nil, count: frames)
        var strength = [Float](repeating: 0, count: frames)
        for t in 0..<frames {
            let s = raw[t]
            strength[t] = p90 > 0 ? min(1, s / p90) : 0
            guard p90 > 0, s >= 0.18 * p90, s >= 1.6 * rowMean[t] else { continue }
            let j = path[t]
            var offset: Float = 0
            if j > 0, j < bins - 1 {
                let a = salience[t * bins + j - 1], b = s, c = salience[t * bins + j + 1]
                let denom = a - 2 * b + c
                if denom < 0 { offset = max(-0.5, min(0.5, 0.5 * (a - c) / denom)) }
            }
            midi[t] = Float(minMidi) + (Float(j) + offset) / Float(binsPerSemitone)
        }
        return PitchPath(midi: midi, strength: strength)
    }

    // MARK: Onsets

    /// Spectral flux minus its local mean, half-wave rectified.
    private static func onsetStrength(_ flux: [Float]) -> [Float] {
        let n = flux.count
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        let radius = 8
        var sum: Float = 0
        var lo = 0, hi = -1
        for t in 0..<n {
            while hi < min(n - 1, t + radius) { hi += 1; sum += flux[hi] }
            while lo < max(0, t - radius) { sum -= flux[lo]; lo += 1 }
            out[t] = max(0, flux[t] - sum / Float(hi - lo + 1))
        }
        return out
    }

    private static func pickOnsets(_ env: [Float]) -> Set<Int> {
        let positive = env.filter { $0 > 0 }
        guard !positive.isEmpty else { return [] }
        let threshold = 1.5 * positive.reduce(0, +) / Float(positive.count)
        var onsets = Set<Int>()
        for t in 0..<env.count where env[t] > threshold {
            let lo = max(0, t - 3), hi = min(env.count - 1, t + 3)
            if (lo...hi).allSatisfy({ env[$0] <= env[t] }) { onsets.insert(t) }
        }
        return onsets
    }

    // MARK: Notes

    private static func segmentNotes(path: PitchPath, onsets: Set<Int>) -> [MusicBoxMelodyNote] {
        let frames = path.midi.count
        let deviations = path.midi.compactMap { $0.map { $0 - $0.rounded() } }
        guard !deviations.isEmpty else { return [] }
        let tuning = deviations.sorted()[deviations.count / 2]

        let rawSemis: [Int?] = path.midi.map { $0.map { Int(($0 - tuning).rounded()) } }
        var semis = [Int?](repeating: nil, count: frames)
        for t in 0..<frames {
            let lo = max(0, t - 2), hi = min(frames - 1, t + 2)
            let values = (lo...hi).compactMap { rawSemis[$0] }.sorted()
            if values.count >= 3 { semis[t] = values[values.count / 2] }
        }

        struct Run { var start: Int; var end: Int; var midi: Int }
        var runs: [Run] = []
        var t = 0
        while t < frames {
            guard let m = semis[t] else { t += 1; continue }
            var end = t
            while end + 1 < frames, semis[end + 1] == m { end += 1 }
            runs.append(Run(start: t, end: end, midi: m))
            t = end + 1
        }

        let minFrames = 7
        runs = runs.filter { $0.end - $0.start + 1 >= minFrames }

        var merged: [Run] = []
        for run in runs {
            if var last = merged.last, last.midi == run.midi, run.start - last.end <= 5,
               !(last.end...run.start).contains(where: { onsets.contains($0) }) {
                last.end = run.end
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }

        var split: [Run] = []
        for run in merged {
            var start = run.start
            for o in onsets.sorted() where o > run.start && o < run.end {
                if o - start >= minFrames, run.end - o >= 4 {
                    split.append(Run(start: start, end: o - 1, midi: run.midi))
                    start = o
                }
            }
            split.append(Run(start: start, end: run.end, midi: run.midi))
        }

        let fps = framesPerSecond
        return split.map { run in
            let s = path.strength[run.start...run.end]
            return MusicBoxMelodyNote(
                start: Double(run.start) / fps + frameCentre,
                duration: Double(run.end - run.start + 1) / fps,
                midi: run.midi,
                strength: s.reduce(0, +) / Float(s.count)
            )
        }
    }

    // MARK: Key

    private static func estimateKey(_ notes: [MusicBoxMelodyNote]) -> (tonic: Int, minor: Bool) {
        let major: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        var hist = [Double](repeating: 0, count: 12)
        for n in notes { hist[((n.midi % 12) + 12) % 12] += n.duration }
        guard hist.contains(where: { $0 > 0 }) else { return (0, false) }

        func correlation(_ profile: [Double], rotated by: Int) -> Double {
            let p = (0..<12).map { profile[(($0 - by) % 12 + 12) % 12] }
            let mh = hist.reduce(0, +) / 12, mp = p.reduce(0, +) / 12
            var num = 0.0, dh = 0.0, dp = 0.0
            for i in 0..<12 {
                num += (hist[i] - mh) * (p[i] - mp)
                dh += (hist[i] - mh) * (hist[i] - mh)
                dp += (p[i] - mp) * (p[i] - mp)
            }
            return dh > 0 && dp > 0 ? num / (dh * dp).squareRoot() : 0
        }

        var best = (tonic: 0, minor: false, r: -Double.infinity)
        for tonic in 0..<12 {
            let rMajor = correlation(major, rotated: tonic)
            if rMajor > best.r { best = (tonic, false, rMajor) }
            let rMinor = correlation(minor, rotated: tonic)
            if rMinor > best.r { best = (tonic, true, rMinor) }
        }
        return (best.tonic, best.minor)
    }

    // MARK: Tempo

    private static func estimateBeats(_ env: [Float]) -> (bpm: Double?, times: [Double]) {
        let fps = framesPerSecond
        let lagMin = Int(60 / 160 * fps), lagMax = Int(60 / 70 * fps)
        guard env.count > lagMax * 4 else { return (nil, []) }

        var ac = [Double](repeating: 0, count: lagMax + 2)
        for lag in (lagMin - 1)...(lagMax + 1) {
            var sum: Float = 0
            env.withUnsafeBufferPointer { e in
                vDSP_dotpr(e.baseAddress!, 1, e.baseAddress! + lag, 1, &sum, vDSP_Length(env.count - lag))
            }
            ac[lag] = Double(sum) / Double(env.count - lag)
        }
        let window = Array(ac[lagMin...lagMax])
        let mean = window.reduce(0, +) / Double(window.count)
        var bestLag = lagMin
        var bestScore = -Double.infinity
        for lag in lagMin...lagMax {
            let bpm = 60 * fps / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / 110) / 0.6, 2))
            let score = ac[lag] * prior
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard mean > 0, ac[bestLag] > 1.1 * mean else { return (nil, []) }

        let a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1]
        let denom = a - 2 * b + c
        let lag = Double(bestLag) + (denom < 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / denom)) : 0)

        var bestPhase = 0
        var bestSum: Float = -1
        for phase in 0..<Int(lag) {
            var sum: Float = 0
            var pos = Double(phase)
            while Int(pos.rounded()) < env.count {
                sum += env[Int(pos.rounded())]
                pos += lag
            }
            if sum > bestSum { bestSum = sum; bestPhase = phase }
        }

        let onsetDelay = Double(fftSize) / sampleRate
        var times: [Double] = []
        var pos = Double(bestPhase)
        while pos < Double(env.count) {
            times.append(pos / fps + onsetDelay)
            pos += lag
        }
        return (60 * fps / lag, times)
    }

    private static func bassRoots(chroma: [Float], frames: Int, beatTimes: [Double]) -> [Int?] {
        let fps = framesPerSecond
        func frame(_ time: Double) -> Int { max(0, Int((time - frameCentre) * fps)) }
        return beatTimes.indices.map { i in
            let a = frame(beatTimes[i])
            let b = min(frames, i + 1 < beatTimes.count ? frame(beatTimes[i + 1]) : a + Int(fps / 2))
            guard a < b else { return nil }
            var sums = [Float](repeating: 0, count: 12)
            for t in a..<b {
                for pc in 0..<12 { sums[pc] += chroma[t * 12 + pc] }
            }
            let total = sums.reduce(0, +)
            guard total > 0, let maxValue = sums.max(), maxValue / total > 0.22 else { return nil }
            return sums.firstIndex(of: maxValue)
        }
    }

    // MARK: Helpers

    private static func percentile(_ values: [Float], _ q: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))]
    }

    static func hzToMidi(_ hz: Float) -> Float { 69 + 12 * log2f(hz / 440) }
    static func midiToHz(_ midi: Float) -> Float { 440 * powf(2, (midi - 69) / 12) }

    private static func pitchClass(ofHz hz: Float) -> Int {
        ((Int(hzToMidi(hz).rounded()) % 12) + 12) % 12
    }
}
