#!/usr/bin/env python3
"""Re-encode interferencia-audio2.m4a from interferenciaradio2.mov (trim + EQ + peak match)."""
from __future__ import annotations

import math
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter

REPO = Path(__file__).resolve().parents[1]
RINGTONE_DIR = REPO / "MagicCall/Resources/InterferenceRingtone"
REF_M4A = RINGTONE_DIR / "interferencia-radio.m4a"
OUT_M4A = RINGTONE_DIR / "interferencia-audio2.m4a"
SRC_MOV = REPO / "interferenciaradio2.mov"


def af_to_wav(src: Path, wav: Path) -> None:
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", "LEI32@44100", str(src), str(wav)],
        check=True,
    )


def wav_to_m4a(wav: Path, dst: Path) -> None:
    subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", "-q", "127", str(wav), str(dst)],
        check=True,
    )


def read_wav_mono_stereo(path: Path) -> tuple[np.ndarray, int]:
    rate, data = wavfile.read(path)
    if data.dtype == np.int32:
        samples = data.astype(np.float64) / (2**31)
    elif data.dtype == np.int16:
        samples = data.astype(np.float64) / (2**15)
    else:
        samples = data.astype(np.float64)
    if samples.ndim == 1:
        samples = np.stack([samples, samples], axis=1)
    return samples, rate


def write_wav(path: Path, samples: np.ndarray, rate: int) -> None:
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = (clipped * (2**31 - 1)).astype(np.int32)
    wavfile.write(path, rate, pcm)


def peak_db(samples: np.ndarray) -> float:
    peak = float(np.max(np.abs(samples)))
    if peak <= 0:
        return -math.inf
    return 20.0 * math.log10(peak)


def rms_db(samples: np.ndarray) -> float:
    rms = float(np.sqrt(np.mean(samples**2)))
    if rms <= 0:
        return -math.inf
    return 20.0 * math.log10(rms)


def low_shelf_biquad(fs: float, f0: float, gain_db: float, q: float = 0.707) -> tuple[np.ndarray, np.ndarray]:
    """RBJ Audio EQ Cookbook low-shelf."""
    a = 10 ** (gain_db / 40.0)
    w0 = 2.0 * math.pi * f0 / fs
    cos_w0 = math.cos(w0)
    sin_w0 = math.sin(w0)
    alpha = sin_w0 / (2.0 * q)
    two_sqrt_a_alpha = 2.0 * math.sqrt(a) * alpha

    b0 = a * ((a + 1) - (a - 1) * cos_w0 + two_sqrt_a_alpha)
    b1 = 2.0 * a * ((a - 1) - (a + 1) * cos_w0)
    b2 = a * ((a + 1) - (a - 1) * cos_w0 - two_sqrt_a_alpha)
    a0 = (a + 1) + (a - 1) * cos_w0 + two_sqrt_a_alpha
    a1 = -2.0 * ((a - 1) + (a + 1) * cos_w0)
    a2 = (a + 1) + (a - 1) * cos_w0 - two_sqrt_a_alpha

    b = np.array([b0, b1, b2], dtype=np.float64) / a0
    a = np.array([1.0, a1 / a0, a2 / a0], dtype=np.float64)
    return b, a


def apply_shelf(stereo: np.ndarray, fs: int, f0: float, gain_db: float) -> np.ndarray:
    b, a = low_shelf_biquad(fs, f0, gain_db)
    out = np.empty_like(stereo)
    for ch in range(stereo.shape[1]):
        out[:, ch] = lfilter(b, a, stereo[:, ch])
    return out


def trim_to_duration(stereo: np.ndarray, rate: int, target_sec: float) -> np.ndarray:
    n = int(round(target_sec * rate))
    if stereo.shape[0] >= n:
        return stereo[:n, :]
    pad = np.zeros((n - stereo.shape[0], stereo.shape[1]), dtype=stereo.dtype)
    return np.vstack([stereo, pad])


def normalize_peak(stereo: np.ndarray, target_peak: float) -> np.ndarray:
    peak = float(np.max(np.abs(stereo)))
    if peak <= 0:
        return stereo
    gain = target_peak / peak
    out = stereo * gain
    peak2 = float(np.max(np.abs(out)))
    if peak2 > 0.999:
        out *= 0.999 / peak2
    return out


def saturate_for_rms(stereo: np.ndarray, drive: float) -> np.ndarray:
    """Soft saturation lifts sparse static RMS while bounding peaks before final scaling."""
    denom = math.tanh(drive)
    if denom <= 0:
        return stereo
    return np.tanh(stereo * drive) / denom


def main() -> int:
    if not SRC_MOV.is_file():
        print(f"Missing source: {SRC_MOV}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        ref_wav = tmp_path / "ref.wav"
        src_wav = tmp_path / "src.wav"
        proc_wav = tmp_path / "proc.wav"

        af_to_wav(REF_M4A, ref_wav)
        af_to_wav(SRC_MOV, src_wav)

        ref, rate = read_wav_mono_stereo(ref_wav)
        src, _ = read_wav_mono_stereo(src_wav)
        target_sec = ref.shape[0] / rate

        trimmed = trim_to_duration(src, rate, target_sec)

        ref_peak = peak_db(ref)
        before_peak = peak_db(trimmed)

        ref_rms = rms_db(ref)
        # Low shelf + soft saturation so sparse static matches ref RMS without hard clipping.
        eq = apply_shelf(trimmed, rate, f0=280.0, gain_db=4.0)
        saturated = saturate_for_rms(eq, drive=6.5)
        gain_rms = 10 ** ((ref_rms - rms_db(saturated)) / 20.0)
        scaled = saturated * gain_rms
        peak_ceiling = ref_peak - 1.05
        pk = peak_db(scaled)
        if pk > peak_ceiling:
            scaled *= 10 ** ((peak_ceiling - pk) / 20.0)
        normalized = normalize_peak(scaled, 10 ** (peak_ceiling / 20.0))

        after_peak = peak_db(normalized)

        write_wav(proc_wav, normalized, rate)
        wav_to_m4a(proc_wav, OUT_M4A)

        print(
            f"duration={normalized.shape[0] / rate:.3f}s "
            f"ref_peak={ref_peak:.2f}dBFS audio2_before={before_peak:.2f}dBFS audio2_after={after_peak:.2f}dBFS "
            f"ref_rms={rms_db(ref):.2f}dBFS audio2_after_rms={rms_db(normalized):.2f}dBFS"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
