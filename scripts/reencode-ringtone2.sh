#!/usr/bin/env bash
# Regenerate ringtone2-optional.m4a from Source/abertura_master_ringtone2.wav
# (44.1 kHz, trim leading silence, 12 s max, peak −1 dBFS, AAC 128 kbps).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_WAV="$ROOT/MagicCall/Resources/InterferenceRingtone/Source/abertura_master_ringtone2.wav"
OUT_M4A="$ROOT/MagicCall/Resources/InterferenceRingtone/ringtone2-optional.m4a"
SHA_FILE="${SRC_WAV}.sha256"
BUILT_SHA_FILE="${OUT_M4A}.source-sha256"

if [[ ! -f "$SRC_WAV" ]]; then
  echo "Missing source WAV: $SRC_WAV" >&2
  exit 1
fi

WAV_SHA="$(shasum -a 256 "$SRC_WAV" | awk '{print $1}')"
if [[ -f "$BUILT_SHA_FILE" ]] && [[ "$(cat "$BUILT_SHA_FILE")" == "$WAV_SHA" ]] && [[ -f "$OUT_M4A" ]]; then
  echo "ringtone2-optional.m4a already built from this WAV ($WAV_SHA); skipping."
  exit 0
fi

python3 - "$SRC_WAV" "$OUT_M4A" <<'PY'
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile

src_wav, out_m4a = Path(sys.argv[1]), Path(sys.argv[2])
tmp = out_m4a.parent / ".reencode-ringtone2-tmp.wav"
proc = out_m4a.parent / ".reencode-ringtone2-proc.wav"

subprocess.run(
    ["afconvert", "-f", "WAVE", "-d", "LEI32@44100", str(src_wav), str(tmp)],
    check=True,
)
rate, data = wavfile.read(tmp)
samples = data.astype(np.float64) / (2**31)
if samples.ndim == 1:
    samples = np.stack([samples, samples], axis=1)

mono = np.max(np.abs(samples), axis=1)
threshold = 10 ** (-55 / 20)
need = max(1, int(round(0.01 * rate)))
run = 0
start = 0
for i, v in enumerate(mono):
    run = run + 1 if v > threshold else 0
    if run >= need:
        start = i - need + 1
        break

max_frames = int(round(12.0 * rate))
segment = samples[start : start + max_frames, :]
if segment.shape[0] < max_frames:
    pad = np.zeros((max_frames - segment.shape[0], 2), dtype=segment.dtype)
    segment = np.vstack([segment, pad])

peak_target = 10 ** (-1 / 20)
peak = float(np.max(np.abs(segment)))
if peak > 0:
    segment = segment * (peak_target / peak)

pcm = (np.clip(segment, -1.0, 1.0) * (2**31 - 1)).astype(np.int32)
wavfile.write(proc, rate, pcm)
subprocess.run(
    [
        "afconvert",
        "-f",
        "m4af",
        "-d",
        "aac",
        "-b",
        "128000",
        "-q",
        "127",
        str(proc),
        str(out_m4a),
    ],
    check=True,
)
tmp.unlink(missing_ok=True)
proc.unlink(missing_ok=True)
PY

echo "$WAV_SHA" > "$BUILT_SHA_FILE"
printf '%s\n' "$WAV_SHA" > "$SHA_FILE"
echo "Wrote $OUT_M4A (source sha256 $WAV_SHA)"
