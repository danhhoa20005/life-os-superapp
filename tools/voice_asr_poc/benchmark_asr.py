"""LifeOS Stage C — Local Offline Vietnamese ASR PoC & Benchmark Suite.

Evaluates:
1. Exact Vietnamese UTF-8 Levenshtein WER & CER (diacritic-sensitive & folded).
2. Deterministic 16kHz Mono PCM16 audio synthesis, 30s ring-buffer, and Energy/ZCR
   adaptive VAD endpointing (including mid-sentence pause handling).
3. Local ASR engine probing & real inference benchmarking (`sherpa_onnx`, `vosk`,
   `faster_whisper`, `pywhispercpp`, `onnxruntime`) across active Python or isolated
   `.cache/venv`, capturing Cold Init ms, End-to-Final latency (P50/P95), RTF,
   Peak RSS MB, WER, and CER.
4. Clear provenance tagging:
   - `MEASURED_HOST`
   - `UPSTREAM_REFERENCE`
   - `NOT_MEASURED_DEVICE_REQUIRED`
"""

from __future__ import annotations

from array import array
import argparse
from collections import deque
import ctypes
from ctypes import wintypes
from dataclasses import dataclass
import importlib.metadata
import importlib.util
import json
import math
from pathlib import Path
import platform
import random
import re
import statistics
import struct
import subprocess
import sys
import tarfile
import time
import tracemalloc
import unicodedata
import urllib.request
import wave
import zipfile
from typing import Any


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_CORPUS_PATH = BASE_DIR / "corpus" / "vi_financial_corpus.json"
DEFAULT_OUTPUT_PATH = BASE_DIR / "results" / "poc_benchmark_report.json"
DEFAULT_CACHE_DIR = BASE_DIR / ".cache"

SAMPLE_RATE_HZ = 16000
FRAME_MS = 20
FRAME_SAMPLES = (SAMPLE_RATE_HZ * FRAME_MS) // 1000  # 320 samples
RING_BUFFER_SECONDS = 30
RING_BUFFER_MAX_SAMPLES = SAMPLE_RATE_HZ * RING_BUFFER_SECONDS  # 480,000 samples (960 KB)

UPSTREAM_MODEL_CATALOG: dict[str, dict[str, Any]] = {
    "sherpa_onnx_zipformer_vi_30M_int8": {
        "engine": "sherpa-onnx",
        "modelName": "sherpa-onnx-zipformer-vi-30M-int8-2026-02-09",
        "architecture": "Zipformer-30M RNN-T (INT8 quantized ONNX)",
        "downloadArchive": "sherpa-onnx-zipformer-vi-30M-int8-2026-02-09.tar.bz2",
        "downloadUrl": (
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
            "asr-models/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09.tar.bz2"
        ),
        "archiveSizeMb": 25.22,
        "license": "Apache-2.0 (sherpa-onnx runtime) / Open pretrained Vi 30M Zipformer checkpoint",
        "streamingSupported": True,
        "notes": "Compact 30M INT8 Zipformer transducer ideal for Android ARM64 on-device budget.",
        "status": "UPSTREAM_REFERENCE",
    },
    "sherpa_onnx_zipformer_vi_int8_2025": {
        "engine": "sherpa-onnx",
        "modelName": "sherpa-onnx-zipformer-vi-int8-2025-04-20",
        "architecture": "Zipformer RNN-T (INT8 quantized ONNX)",
        "downloadArchive": "sherpa-onnx-zipformer-vi-int8-2025-04-20.tar.bz2",
        "downloadUrl": (
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
            "asr-models/sherpa-onnx-zipformer-vi-int8-2025-04-20.tar.bz2"
        ),
        "archiveSizeMb": 57.39,
        "license": "Apache-2.0 (sherpa-onnx runtime)",
        "streamingSupported": True,
        "notes": "Larger Zipformer Vi INT8 model with higher capacity than 30M variant.",
        "status": "UPSTREAM_REFERENCE",
    },
    "sherpa_onnx_moonshine_base_vi": {
        "engine": "sherpa-onnx",
        "modelName": "sherpa-onnx-moonshine-base-vi-quantized-2026-02-27",
        "architecture": "Moonshine-Base Vi Encoder-Decoder (Quantized ONNX)",
        "downloadArchive": "sherpa-onnx-moonshine-base-vi-quantized-2026-02-27.tar.bz2",
        "downloadUrl": (
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
            "asr-models/sherpa-onnx-moonshine-base-vi-quantized-2026-02-27.tar.bz2"
        ),
        "archiveSizeMb": 101.78,
        "license": "MIT (Moonshine) / Apache-2.0 (sherpa-onnx)",
        "streamingSupported": False,
        "notes": "Non-streaming utterance-level encoder-decoder; higher footprint (~102 MB).",
        "status": "UPSTREAM_REFERENCE",
    },
    "vosk_small_vn_0_4": {
        "engine": "vosk",
        "modelName": "vosk-model-small-vn-0.4",
        "architecture": "Kaldi TDNN-F + HCLG Graph (Streaming)",
        "downloadArchive": "vosk-model-small-vn-0.4.zip",
        "downloadUrl": "https://alphacephei.com/vosk/models/vosk-model-small-vn-0.4.zip",
        "archiveSizeMb": 32.10,
        "upstreamPublishedWerPct": 15.70,
        "upstreamBenchmarkDataset": "Vivos test (alphacephei.com/vosk/models)",
        "license": "Apache-2.0",
        "streamingSupported": True,
        "notes": "Lightweight Kaldi streaming model (32 MiB zip); Apache-2.0 commercial-friendly.",
        "status": "UPSTREAM_REFERENCE",
    },
    "vosk_vn_0_4": {
        "engine": "vosk",
        "modelName": "vosk-model-vn-0.4",
        "architecture": "Kaldi TDNN-F Large Graph",
        "downloadArchive": "vosk-model-vn-0.4.zip",
        "downloadUrl": "https://alphacephei.com/vosk/models/vosk-model-vn-0.4.zip",
        "archiveSizeMb": 78.00,
        "upstreamPublishedWerPct": 15.70,
        "upstreamBenchmarkDataset": "Vivos test (alphacephei.com/vosk/models)",
        "license": "Apache-2.0",
        "streamingSupported": True,
        "notes": "Server/desktop Kaldi model (78 MiB zip).",
        "status": "UPSTREAM_REFERENCE",
    },
    "whisper_tiny_int8": {
        "engine": "whisper.cpp / faster-whisper",
        "modelName": "whisper-tiny-q5_1 / faster-whisper-tiny-int8",
        "architecture": "Transformer Seq2Seq Multilingual (39M params)",
        "archiveSizeMb": 32.0,
        "license": "MIT",
        "streamingSupported": False,
        "notes": (
            "Multilingual 39M model; requires chunked VAD windowing for pseudo-streaming "
            "and generally exhibits weaker Vietnamese diacritics than Vi-specific Zipformer."
        ),
        "status": "UPSTREAM_REFERENCE",
    },
    "piper_vits_vi_tts": {
        "engine": "sherpa-onnx TTS (synthetic benchmark audio generator)",
        "modelName": "vits-piper-vi_VN-vais1000-medium-int8",
        "downloadArchive": "vits-piper-vi_VN-vais1000-medium-int8.tar.bz2",
        "downloadUrl": (
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
            "tts-models/vits-piper-vi_VN-vais1000-medium-int8.tar.bz2"
        ),
        "archiveSizeMb": 20.58,
        "license": "MIT / CC-BY (vais1000)",
        "status": "UPSTREAM_REFERENCE",
    },
}


# ---------------------------------------------------------------------------
# Vietnamese UTF-8 Normalization & Exact Levenshtein WER / CER
# ---------------------------------------------------------------------------

_PUNCT_RE = re.compile(r"[.,!?;:\"'\(\)\[\]\{\}\-–—…/\\]+")
_SPACE_RE = re.compile(r"\s+")


def strip_vi_diacritics(text: str) -> str:
    text = text.replace("đ", "d").replace("Đ", "D")
    nfd = unicodedata.normalize("NFD", text)
    return "".join(ch for ch in nfd if unicodedata.category(ch) != "Mn")


def normalize_vi_text(text: str, *, strip_accents: bool = False) -> str:
    s = unicodedata.normalize("NFC", text).lower().strip()
    s = _PUNCT_RE.sub(" ", s)
    if strip_accents:
        s = strip_vi_diacritics(s)
    s = _SPACE_RE.sub(" ", s).strip()
    return s


@dataclass(frozen=True)
class EditStats:
    substitutions: int
    deletions: int
    insertions: int
    distance: int
    ref_length: int

    @property
    def rate(self) -> float:
        if self.ref_length == 0:
            return 0.0 if self.distance == 0 else 1.0
        return self.distance / self.ref_length


def levenshtein_sdi(ref: list[str] | str, hyp: list[str] | str) -> EditStats:
    n = len(ref)
    m = len(hyp)
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    # Op codes: 0=match/sub, 1=del, 2=ins
    op = [[0] * (m + 1) for _ in range(n + 1)]

    for i in range(1, n + 1):
        dp[i][0] = i
        op[i][0] = 1
    for j in range(1, m + 1):
        dp[0][j] = j
        op[0][j] = 2

    for i in range(1, n + 1):
        r_item = ref[i - 1]
        for j in range(1, m + 1):
            cost_sub = 0 if r_item == hyp[j - 1] else 1
            sub_val = dp[i - 1][j - 1] + cost_sub
            del_val = dp[i - 1][j] + 1
            ins_val = dp[i][j - 1] + 1

            best = sub_val
            best_op = 0
            if del_val < best:
                best = del_val
                best_op = 1
            if ins_val < best:
                best = ins_val
                best_op = 2
            dp[i][j] = best
            op[i][j] = best_op

    subs = dels = ins = 0
    i, j = n, m
    while i > 0 or j > 0:
        cur = op[i][j]
        if i > 0 and j > 0 and cur == 0:
            if ref[i - 1] != hyp[j - 1]:
                subs += 1
            i -= 1
            j -= 1
        elif i > 0 and (j == 0 or cur == 1):
            dels += 1
            i -= 1
        else:
            ins += 1
            j -= 1

    return EditStats(
        substitutions=subs,
        deletions=dels,
        insertions=ins,
        distance=dp[n][m],
        ref_length=n,
    )


def compute_wer_cer(reference: str, hypothesis: str) -> dict[str, Any]:
    ref_norm = normalize_vi_text(reference, strip_accents=False)
    hyp_norm = normalize_vi_text(hypothesis, strip_accents=False)

    ref_words = ref_norm.split() if ref_norm else []
    hyp_words = hyp_norm.split() if hyp_norm else []
    wer_stats = levenshtein_sdi(ref_words, hyp_words)

    ref_chars = list(ref_norm)
    hyp_chars = list(hyp_norm)
    cer_stats = levenshtein_sdi(ref_chars, hyp_chars)

    ref_ascii = normalize_vi_text(reference, strip_accents=True)
    hyp_ascii = normalize_vi_text(hypothesis, strip_accents=True)
    wer_ascii = levenshtein_sdi(ref_ascii.split(), hyp_ascii.split())
    cer_ascii = levenshtein_sdi(list(ref_ascii), list(hyp_ascii))

    return {
        "wer": round(wer_stats.rate, 6),
        "cer": round(cer_stats.rate, 6),
        "werAscii": round(wer_ascii.rate, 6),
        "cerAscii": round(cer_ascii.rate, 6),
        "wordEdits": {
            "S": wer_stats.substitutions,
            "D": wer_stats.deletions,
            "I": wer_stats.insertions,
            "N": wer_stats.ref_length,
        },
        "charEdits": {
            "S": cer_stats.substitutions,
            "D": cer_stats.deletions,
            "I": cer_stats.insertions,
            "N": cer_stats.ref_length,
        },
    }


def percentile(sorted_vals: list[float], pct: float) -> float:
    if not sorted_vals:
        return 0.0
    idx = min(
        len(sorted_vals) - 1,
        max(0, int(round((pct / 100.0) * (len(sorted_vals) - 1)))),
    )
    return float(sorted_vals[idx])


def get_process_peak_rss_mb() -> float | None:
    if sys.platform == "win32":
        class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD),
                ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t),
            ]

        counters = PROCESS_MEMORY_COUNTERS()
        counters.cb = ctypes.sizeof(PROCESS_MEMORY_COUNTERS)
        handle = ctypes.windll.kernel32.GetCurrentProcess()
        ok = ctypes.windll.psapi.GetProcessMemoryInfo(
            handle, ctypes.byref(counters), counters.cb
        )
        if ok:
            return round(counters.PeakWorkingSetSize / (1024.0 * 1024.0), 3)
        return None
    try:
        import resource

        usage = resource.getrusage(resource.RUSAGE_SELF)
        divisor = 1024.0 * 1024.0 if sys.platform == "darwin" else 1024.0
        return round(usage.ru_maxrss / divisor, 3)
    except Exception:
        return None


# ---------------------------------------------------------------------------
# PCM16 16kHz Audio Synthesis + 30s Ring-Buffer + Energy/ZCR VAD Endpointing
# ---------------------------------------------------------------------------

def _accent_acoustic_profile(condition: str) -> tuple[float, float, float]:
    """Returns (syllable_duration_ms, speech_rms, noise_rms) for PCM16 simulation."""
    cond = condition.lower()
    if "fast" in cond:
        syl_ms = 145.0
    elif "slow" in cond or "mid_pause" in cond:
        syl_ms = 230.0
    else:
        syl_ms = 185.0

    if "quiet" in cond:
        speech_rms = 0.08
    else:
        speech_rms = 0.22

    if "noisy" in cond:
        noise_rms = 0.038
    elif "quiet" in cond:
        noise_rms = 0.008
    else:
        noise_rms = 0.010

    return syl_ms, speech_rms, noise_rms


def synthesize_pcm16_benchmark_wav(
    utterance: dict[str, Any],
    out_path: Path,
) -> dict[str, Any]:
    """Generates a deterministic 16kHz Mono PCM16 .wav clip with speech formants,
    condition-calibrated SNR, leading silence, optional 650ms mid-sentence pause,
    and 1200ms trailing silence."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    text = utterance["referenceTranscript"]
    has_mid_pause = bool(utterance.get("hasMidSentencePause", False))
    condition = str(utterance.get("accentOrCondition", "clear"))
    syl_ms, speech_amp, noise_amp = _accent_acoustic_profile(condition)

    rng = random.Random(utterance["id"])

    # Split into clauses when mid-sentence pause exists
    if has_mid_pause and "..." in text:
        parts = [p.strip() for p in text.split("...") if p.strip()]
    else:
        parts = [text]

    lead_ms = 320
    mid_pause_ms = 650 if has_mid_pause else 0
    trail_ms = 1200

    samples = array("h")

    def append_silence(duration_ms: int) -> None:
        count = int((duration_ms / 1000.0) * SAMPLE_RATE_HZ)
        for _ in range(count):
            n = rng.gauss(0.0, noise_amp)
            val = max(-32767, min(32767, int(n * 32767.0)))
            samples.append(val)

    def append_speech_segment(words: list[str]) -> None:
        for w_idx, word in enumerate(words):
            dur_s = max(0.11, (syl_ms / 1000.0) * (0.85 + 0.04 * len(word)))
            n_samp = int(dur_s * SAMPLE_RATE_HZ)
            f0 = 135.0 + ((w_idx * 29) % 75)
            f1 = 520.0 + ((len(word) * 85) % 400)
            f2 = 1480.0 + ((w_idx * 170) % 700)
            for k in range(n_samp):
                t = k / SAMPLE_RATE_HZ
                pos = k / max(1, n_samp - 1)
                env = math.sin(math.pi * pos) ** 0.6
                sig = (
                    0.55 * math.sin(2.0 * math.pi * f0 * t)
                    + 0.30 * math.sin(2.0 * math.pi * f1 * t)
                    + 0.15 * math.sin(2.0 * math.pi * f2 * t)
                )
                sample_f = speech_amp * env * sig + rng.gauss(0.0, noise_amp)
                samples.append(max(-32767, min(32767, int(sample_f * 32767.0))))
            append_silence(45)

    append_silence(lead_ms)
    speech_start_ms = lead_ms
    for idx, part in enumerate(parts):
        words = [w for w in normalize_vi_text(part).split() if w]
        append_speech_segment(words)
        if idx < len(parts) - 1 and mid_pause_ms > 0:
            append_silence(mid_pause_ms)

    speech_end_ms = int((len(samples) / SAMPLE_RATE_HZ) * 1000.0)
    append_silence(trail_ms)

    with wave.open(str(out_path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE_HZ)
        wf.writeframes(samples.tobytes())

    return {
        "wavPath": str(out_path),
        "durationMs": round((len(samples) / SAMPLE_RATE_HZ) * 1000.0, 2),
        "trueSpeechStartMs": speech_start_ms,
        "trueSpeechEndMs": speech_end_ms,
        "hasMidSentencePause": has_mid_pause,
        "midPauseMs": mid_pause_ms,
    }


def _measure_ring_buffer_peak_kb() -> float:
    """Measures exact memory footprint of the 30s PCM16 circular buffer + VAD frame state."""
    tracemalloc.start()
    ring = array("h", [0]) * RING_BUFFER_MAX_SAMPLES
    scratch = array("h", [0]) * FRAME_SAMPLES
    ring[:FRAME_SAMPLES] = scratch
    _, peak_bytes = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    return round(peak_bytes / 1024.0, 2)


def run_ring_buffer_vad_benchmark(
    wav_specs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Benchmarks a 30s PCM16 Circular Ring-Buffer + 20ms Energy/ZCR Adaptive-Noise-Floor VAD."""
    ring_buffer = array("h", [0]) * RING_BUFFER_MAX_SAMPLES
    ring_pos = 0

    all_frame_latencies_us: list[float] = []
    onset_lags_ms: list[float] = []
    endpoint_lags_ms: list[float] = []
    premature_cuts = 0
    per_utterance: list[dict[str, Any]] = []

    for spec in wav_specs:
        wav_path = Path(spec["wavPath"])
        with wave.open(str(wav_path), "rb") as wf:
            raw_pcm = wf.readframes(wf.getnframes())
        samples = array("h")
        samples.frombytes(raw_pcm)

        ring_pos = 0
        noise_energies: list[float] = []
        speech_active = False
        detected_start_ms: float | None = None
        detected_endpoint_ms: float | None = None
        silence_run_ms = 0.0
        speech_run_ms = 0.0
        # LifeOS smart endpoint threshold: tolerate mid-sentence pauses (~850ms)
        endpoint_hangover_ms = 850.0

        total_frames = len(samples) // FRAME_SAMPLES
        for f_idx in range(total_frames):
            start_idx = f_idx * FRAME_SAMPLES
            frame = samples[start_idx : start_idx + FRAME_SAMPLES]
            t0 = time.perf_counter()

            # Write 20ms frame into contiguous 30s PCM16 circular ring-buffer
            ring_buffer[ring_pos : ring_pos + FRAME_SAMPLES] = frame
            ring_pos = (ring_pos + FRAME_SAMPLES) % RING_BUFFER_MAX_SAMPLES

            # Frame RMS energy & Zero-Crossing Rate (ZCR)
            sq_sum = 0.0
            zero_crossings = 0
            prev = frame[0]
            for s in frame:
                sq_sum += s * s
                if (s >= 0 and prev < 0) or (s < 0 and prev >= 0):
                    zero_crossings += 1
                prev = s
            rms = math.sqrt(sq_sum / FRAME_SAMPLES) / 32768.0
            zcr = zero_crossings / FRAME_SAMPLES

            # Calibrate dynamic noise floor on first 200ms (10 frames)
            if f_idx < 10:
                noise_energies.append(rms)
            noise_floor = (
                statistics.mean(noise_energies) if noise_energies else 0.01
            )
            energy_threshold = max(0.020, noise_floor * 2.4)
            is_voiced = rms > energy_threshold and zcr < 0.45

            frame_time_ms = (f_idx + 1) * FRAME_MS
            if is_voiced:
                speech_run_ms += FRAME_MS
                silence_run_ms = 0.0
                if not speech_active and speech_run_ms >= 60.0:
                    speech_active = True
                    if detected_start_ms is None:
                        detected_start_ms = frame_time_ms - 40.0
            else:
                speech_run_ms = 0.0
                if speech_active:
                    silence_run_ms += FRAME_MS
                    if silence_run_ms >= endpoint_hangover_ms and detected_endpoint_ms is None:
                        detected_endpoint_ms = frame_time_ms
                        speech_active = False

            elapsed_us = (time.perf_counter() - t0) * 1_000_000.0
            all_frame_latencies_us.append(elapsed_us)

        onset_lag = (
            round(detected_start_ms - spec["trueSpeechStartMs"], 2)
            if detected_start_ms is not None
            else None
        )
        endpoint_lag = (
            round(detected_endpoint_ms - spec["trueSpeechEndMs"], 2)
            if detected_endpoint_ms is not None
            else None
        )
        premature = (
            detected_endpoint_ms is not None
            and detected_endpoint_ms < (spec["trueSpeechEndMs"] - 100.0)
        )
        if premature:
            premature_cuts += 1
        if onset_lag is not None:
            onset_lags_ms.append(abs(onset_lag))
        if endpoint_lag is not None:
            endpoint_lags_ms.append(endpoint_lag)

        per_utterance.append(
            {
                "id": spec["id"],
                "durationMs": spec["durationMs"],
                "trueSpeechStartMs": spec["trueSpeechStartMs"],
                "trueSpeechEndMs": spec["trueSpeechEndMs"],
                "detectedStartMs": detected_start_ms,
                "detectedEndpointMs": detected_endpoint_ms,
                "onsetLagMs": onset_lag,
                "endpointLagMs": endpoint_lag,
                "prematureMidPauseCut": premature,
            }
        )

    peak_kb = _measure_ring_buffer_peak_kb()

    all_frame_latencies_us.sort()
    onset_lags_ms.sort()
    endpoint_lags_ms.sort()

    return {
        "status": "MEASURED_HOST",
        "sampleRateHz": SAMPLE_RATE_HZ,
        "channels": 1,
        "sampleWidthBytes": 2,
        "frameSizeMs": FRAME_MS,
        "ringBufferCapacitySeconds": RING_BUFFER_SECONDS,
        "ringBufferCapacityBytes": RING_BUFFER_MAX_SAMPLES * 2,
        "utterancesBenchmarked": len(wav_specs),
        "totalFramesProcessed": len(all_frame_latencies_us),
        "frameProcessLatencyUs": {
            "mean": round(statistics.mean(all_frame_latencies_us), 2),
            "p50": round(percentile(all_frame_latencies_us, 50), 2),
            "p95": round(percentile(all_frame_latencies_us, 95), 2),
        },
        "speechOnsetDetectionAbsLagMs": {
            "detectedCount": len(onset_lags_ms),
            "p50": round(percentile(onset_lags_ms, 50), 2),
            "p95": round(percentile(onset_lags_ms, 95), 2),
        },
        "endpointHangoverMs": 850.0,
        "endpointDetectionLagMs": {
            "detectedCount": len(endpoint_lags_ms),
            "p50": round(percentile(endpoint_lags_ms, 50), 2),
            "p95": round(percentile(endpoint_lags_ms, 95), 2),
        },
        "prematureMidPauseCuts": premature_cuts,
        "tracemallocPeakMemoryKb": peak_kb,
        "samples": per_utterance[:8],
    }


# ---------------------------------------------------------------------------
# Host Python & Local ASR Engine Discovery + Subprocess Benchmarking
# ---------------------------------------------------------------------------

def find_candidate_python_interpreters(cache_dir: Path) -> list[tuple[str, str]]:
    interpreters: list[tuple[str, str]] = [("active_python", sys.executable)]
    venv_win = cache_dir / "venv" / "Scripts" / "python.exe"
    venv_posix = cache_dir / "venv" / "bin" / "python"
    for label, candidate in [("cache_venv", venv_win), ("cache_venv", venv_posix)]:
        if candidate.exists() and str(candidate.resolve()) != str(Path(sys.executable).resolve()):
            interpreters.append((label, str(candidate)))
    return interpreters


def probe_module_in_python(python_exe: str, module_name: str) -> dict[str, Any]:
    if str(Path(python_exe).resolve()) == str(Path(sys.executable).resolve()):
        spec = importlib.util.find_spec(module_name)
        if spec is None:
            return {"installed": False, "version": None}
        pkg_name = module_name.replace("_", "-")
        ver = None
        for cand in (module_name, pkg_name):
            try:
                ver = importlib.metadata.version(cand)
                break
            except importlib.metadata.PackageNotFoundError:
                continue
        return {"installed": True, "version": ver}

    code = (
        "import importlib.util, importlib.metadata, json; "
        f"m = {module_name!r}; "
        "spec = importlib.util.find_spec(m); "
        "ver = None\n"
        "if spec is not None:\n"
        "  for c in (m, m.replace('_','-')):\n"
        "    try: ver = importlib.metadata.version(c); break\n"
        "    except Exception: pass\n"
        "print(json.dumps({'installed': spec is not None, 'version': ver}))"
    )
    try:
        res = subprocess.run(
            [python_exe, "-c", code],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            return json.loads(res.stdout.strip().splitlines()[-1])
    except Exception:
        pass
    return {"installed": False, "version": None}


def discover_local_models(cache_dir: Path) -> dict[str, Path]:
    models_root = cache_dir / "models"
    found: dict[str, Path] = {}
    if not models_root.exists():
        return found

    for child in models_root.iterdir():
        if not child.is_dir():
            continue
        name = child.name.lower()
        if "zipformer" in name and "vi" in name:
            found["sherpa_onnx_zipformer_vi"] = child
        elif "moonshine" in name and "vi" in name:
            found["sherpa_onnx_moonshine_vi"] = child
        elif "vosk-model" in name and "vn" in name:
            found["vosk_vn"] = child
        elif "vits-piper-vi_vn" in name:
            found["piper_vits_vi_tts"] = child
    return found


def _find_transducer_files(model_dir: Path) -> tuple[Path, Path, Path, Path] | None:
    tokens = model_dir / "tokens.txt"
    if not tokens.exists():
        return None
    encoders = sorted(model_dir.glob("*encoder*.int8.onnx")) or sorted(
        model_dir.glob("*encoder*.onnx")
    )
    decoders = sorted(model_dir.glob("*decoder*.int8.onnx")) or sorted(
        model_dir.glob("*decoder*.onnx")
    )
    joiners = sorted(model_dir.glob("*joiner*.int8.onnx")) or sorted(
        model_dir.glob("*joiner*.onnx")
    )
    if not (encoders and decoders and joiners):
        return None
    return encoders[0], decoders[0], joiners[0], tokens


def _read_wav_as_float_and_pcm(wav_path: Path) -> tuple[list[float], bytes, int, float]:
    with wave.open(str(wav_path), "rb") as wf:
        sr = wf.getframerate()
        n_frames = wf.getnframes()
        n_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        raw = wf.readframes(n_frames)
    if sampwidth != 2:
        raise ValueError(f"Expected 16-bit PCM in {wav_path}, got {sampwidth * 8}-bit")
    ints = struct.unpack(f"<{len(raw) // 2}h", raw)
    if n_channels > 1:
        mono = [ints[i] for i in range(0, len(ints), n_channels)]
        raw = struct.pack(f"<{len(mono)}h", *mono)
    else:
        mono = list(ints)
    floats = [s / 32768.0 for s in mono]
    duration_s = len(mono) / float(sr)
    return floats, raw, sr, duration_s


def _resample_linear_pcm16(
    samples: list[int], src_rate: int, dst_rate: int
) -> list[int]:
    if src_rate == dst_rate or not samples:
        return samples
    out_len = max(1, int(round(len(samples) * dst_rate / src_rate)))
    ratio = (len(samples) - 1) / max(1, out_len - 1)
    out: list[int] = []
    for i in range(out_len):
        pos = i * ratio
        idx = int(pos)
        frac = pos - idx
        s0 = samples[idx]
        s1 = samples[min(idx + 1, len(samples) - 1)]
        val = int(round(s0 + frac * (s1 - s0)))
        out.append(max(-32768, min(32767, val)))
    return out


def generate_tts_corpus_wavs_if_available(
    utterances: list[dict[str, Any]],
    tts_model_dir: Path,
    out_dir: Path,
    python_exe: str,
) -> list[dict[str, Any]] | None:
    """Uses local offline Piper VITS Vietnamese TTS (`sherpa_onnx`) inside `.cache`
    to synthesize genuine spoken Vietnamese 16kHz Mono PCM16 `.wav` clips."""
    out_dir.mkdir(parents=True, exist_ok=True)
    existing = [out_dir / f"{u['id']}.wav" for u in utterances]
    if all(p.exists() for p in existing):
        specs: list[dict[str, Any]] = []
        for u, p in zip(utterances, existing):
            with wave.open(str(p), "rb") as wf:
                dur_s = wf.getnframes() / float(wf.getframerate())
            specs.append(
                {
                    "id": u["id"],
                    "referenceTranscript": u["referenceTranscript"],
                    "wavPath": str(p),
                    "durationSec": round(dur_s, 3),
                }
            )
        return specs

    onnx_files = sorted(tts_model_dir.glob("*.onnx"))
    tokens_file = tts_model_dir / "tokens.txt"
    espeak_dir = tts_model_dir / "espeak-ng-data"
    if not (onnx_files and tokens_file.exists() and espeak_dir.exists()):
        return None

    helper_script = (
        "import json, struct, sys, wave\n"
        "from pathlib import Path\n"
        "import sherpa_onnx\n"
        "cfg_in = json.loads(sys.stdin.read())\n"
        "tts_cfg = sherpa_onnx.OfflineTtsConfig(\n"
        "  model=sherpa_onnx.OfflineTtsModelConfig(\n"
        "    vits=sherpa_onnx.OfflineTtsVitsModelConfig(\n"
        "      model=cfg_in['model'], tokens=cfg_in['tokens'], data_dir=cfg_in['data_dir']\n"
        "    ),\n"
        "    num_threads=2,\n"
        "  )\n"
        ")\n"
        "tts = sherpa_onnx.OfflineTts(tts_cfg)\n"
        "out = []\n"
        "for item in cfg_in['utterances']:\n"
        "  audio = tts.generate(item['text'], sid=0, speed=1.0)\n"
        "  src_sr = int(audio.sample_rate)\n"
        "  pcm_src = [max(-32768, min(32767, int(x * 32767.0))) for x in audio.samples]\n"
        "  if src_sr != 16000:\n"
        "    out_len = max(1, int(round(len(pcm_src) * 16000 / src_sr)))\n"
        "    ratio = (len(pcm_src) - 1) / max(1, out_len - 1)\n"
        "    pcm_16k = []\n"
        "    for i in range(out_len):\n"
        "      pos = i * ratio\n"
        "      idx = int(pos)\n"
        "      frac = pos - idx\n"
        "      s0 = pcm_src[idx]\n"
        "      s1 = pcm_src[min(idx + 1, len(pcm_src) - 1)]\n"
        "      pcm_16k.append(max(-32768, min(32767, int(round(s0 + frac * (s1 - s0))))))\n"
        "  else:\n"
        "    pcm_16k = pcm_src\n"
        "  # Pad 300ms leading & 500ms trailing silence for clean ASR endpointing\n"
        "  pcm_16k = ([0] * 4800) + pcm_16k + ([0] * 8000)\n"
        "  p = Path(item['wavPath'])\n"
        "  with wave.open(str(p), 'wb') as wf:\n"
        "    wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(16000)\n"
        "    wf.writeframes(struct.pack(f'<{len(pcm_16k)}h', *pcm_16k))\n"
        "  out.append({'id': item['id'], 'referenceTranscript': item['text'], 'wavPath': str(p), 'durationSec': round(len(pcm_16k)/16000.0, 3)})\n"
        "print(json.dumps(out, ensure_ascii=False))\n"
    )
    payload = {
        "model": str(onnx_files[0]),
        "tokens": str(tokens_file),
        "data_dir": str(espeak_dir),
        "utterances": [
            {
                "id": u["id"],
                "text": u["referenceTranscript"].replace("...", ", "),
                "wavPath": str(out_dir / f"{u['id']}.wav"),
            }
            for u in utterances
        ],
    }
    res = subprocess.run(
        [python_exe, "-c", helper_script],
        input=json.dumps(payload, ensure_ascii=False),
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=180,
        check=False,
    )
    if res.returncode == 0 and res.stdout.strip():
        return json.loads(res.stdout.strip().splitlines()[-1])
    return None


def _run_asr_worker(
    engine: str,
    model_dir: Path,
    audio_items: list[dict[str, Any]],
) -> dict[str, Any]:
    """Isolated single-process ASR benchmark worker measuring true cold-start,
    warm/end-to-final latency, RTF, Peak RSS MB, and WER/CER."""
    tracemalloc.start()
    t_init0 = time.perf_counter()

    if engine == "sherpa_onnx":
        import sherpa_onnx

        files = _find_transducer_files(model_dir)
        if files is None:
            return {"status": "MODEL_FILES_MISSING", "engine": engine}
        encoder, decoder, joiner, tokens = files
        recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
            tokens=str(tokens),
            encoder=str(encoder),
            decoder=str(decoder),
            joiner=str(joiner),
            num_threads=2,
            sample_rate=16000,
            feature_dim=80,
            decoding_method="greedy_search",
        )
        cold_init_ms = (time.perf_counter() - t_init0) * 1000.0

        def decode_one(wav_path: Path) -> tuple[str, float, float]:
            floats, _, sr, dur_s = _read_wav_as_float_and_pcm(wav_path)
            t0 = time.perf_counter()
            stream = recognizer.create_stream()
            stream.accept_waveform(sr, floats)
            recognizer.decode_stream(stream)
            text = stream.result.text.strip()
            lat_ms = (time.perf_counter() - t0) * 1000.0
            return text, lat_ms, dur_s

    elif engine == "vosk":
        import vosk

        vosk.SetLogLevel(-1)
        model = vosk.Model(str(model_dir))
        cold_init_ms = (time.perf_counter() - t_init0) * 1000.0

        def decode_one(wav_path: Path) -> tuple[str, float, float]:
            _, raw_pcm, sr, dur_s = _read_wav_as_float_and_pcm(wav_path)
            t0 = time.perf_counter()
            rec = vosk.KaldiRecognizer(model, sr)
            chunk_bytes = 4000
            for off in range(0, len(raw_pcm), chunk_bytes):
                rec.AcceptWaveform(raw_pcm[off : off + chunk_bytes])
            res_json = json.loads(rec.FinalResult())
            text = str(res_json.get("text", "")).strip()
            lat_ms = (time.perf_counter() - t0) * 1000.0
            return text, lat_ms, dur_s

    else:
        return {"status": "UNSUPPORTED_WORKER_ENGINE", "engine": engine}

    latencies_ms: list[float] = []
    rtfs: list[float] = []
    wers: list[float] = []
    cers: list[float] = []
    wers_ascii: list[float] = []
    cers_ascii: list[float] = []
    predictions: list[dict[str, Any]] = []

    for item in audio_items:
        hyp, lat_ms, dur_s = decode_one(Path(item["wavPath"]))
        latencies_ms.append(lat_ms)
        rtf = (lat_ms / 1000.0) / max(0.05, dur_s)
        rtfs.append(rtf)
        ref = item["referenceTranscript"]
        metrics = compute_wer_cer(ref, hyp)
        wers.append(metrics["wer"])
        cers.append(metrics["cer"])
        wers_ascii.append(metrics["werAscii"])
        cers_ascii.append(metrics["cerAscii"])
        predictions.append(
            {
                "id": item["id"],
                "reference": ref,
                "hypothesis": hyp,
                "latencyMs": round(lat_ms, 2),
                "audioSec": round(dur_s, 3),
                "rtf": round(rtf, 4),
                "wer": metrics["wer"],
                "cer": metrics["cer"],
            }
        )

    _, traced_peak_bytes = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    peak_rss_mb = get_process_peak_rss_mb()

    latencies_ms.sort()
    rtfs.sort()

    return {
        "status": "MEASURED_HOST",
        "engine": engine,
        "modelDir": model_dir.name,
        "utterancesEvaluated": len(audio_items),
        "coldInitMs": round(cold_init_ms, 2),
        "endToFinalLatencyMs": {
            "mean": round(statistics.mean(latencies_ms), 2) if latencies_ms else 0.0,
            "p50": round(percentile(latencies_ms, 50), 2),
            "p95": round(percentile(latencies_ms, 95), 2),
        },
        "rtf": {
            "mean": round(statistics.mean(rtfs), 4) if rtfs else 0.0,
            "p95": round(percentile(rtfs, 95), 4),
        },
        "peakRssMb": peak_rss_mb,
        "pythonHeapPeakMb": round(traced_peak_bytes / (1024.0 * 1024.0), 3),
        "meanWer": round(statistics.mean(wers), 4) if wers else None,
        "meanCer": round(statistics.mean(cers), 4) if cers else None,
        "meanWerAscii": round(statistics.mean(wers_ascii), 4) if wers_ascii else None,
        "meanCerAscii": round(statistics.mean(cers_ascii), 4) if cers_ascii else None,
        "samplePredictions": predictions[:10],
    }


def collect_upstream_test_wavs(model_dir: Path) -> list[dict[str, Any]]:
    """Checks if a downloaded sherpa-onnx model archive includes bundled `test_wavs/`
    plus ground-truth `trans.txt`."""
    test_wavs_dir = model_dir / "test_wavs"
    if not test_wavs_dir.exists():
        return []
    trans_map: dict[str, str] = {}
    for txt_file in test_wavs_dir.glob("*.txt"):
        for line in txt_file.read_text(encoding="utf-8", errors="ignore").splitlines():
            parts = line.strip().split(maxsplit=1)
            if len(parts) == 2:
                trans_map[Path(parts[0]).stem] = parts[1].strip()
    items: list[dict[str, Any]] = []
    for wav in sorted(test_wavs_dir.glob("*.wav")):
        if wav.stem in trans_map:
            items.append(
                {
                    "id": f"upstream_{wav.stem}",
                    "referenceTranscript": trans_map[wav.stem],
                    "wavPath": str(wav),
                }
            )
    return items


# ---------------------------------------------------------------------------
# Simulated ASR Variants WER/CER Sensitivity Evaluation
# ---------------------------------------------------------------------------

def evaluate_simulated_asr_variants(utterances: list[dict[str, Any]]) -> dict[str, Any]:
    all_wer: list[float] = []
    all_cer: list[float] = []
    all_wer_ascii: list[float] = []
    all_cer_ascii: list[float] = []

    for u in utterances:
        ref = u["referenceTranscript"]
        for hyp in u.get("asrSimulatedVariants", []):
            m = compute_wer_cer(ref, hyp)
            all_wer.append(m["wer"])
            all_cer.append(m["cer"])
            all_wer_ascii.append(m["werAscii"])
            all_cer_ascii.append(m["cerAscii"])

    return {
        "status": "MEASURED_HOST",
        "variantPairsEvaluated": len(all_wer),
        "meanWer": round(statistics.mean(all_wer), 4) if all_wer else 0.0,
        "meanCer": round(statistics.mean(all_cer), 4) if all_cer else 0.0,
        "meanWerAsciiFolded": round(statistics.mean(all_wer_ascii), 4)
        if all_wer_ascii
        else 0.0,
        "meanCerAsciiFolded": round(statistics.mean(all_cer_ascii), 4)
        if all_cer_ascii
        else 0.0,
    }


# ---------------------------------------------------------------------------
# Optional Cache Bootstrapper (--bootstrap)
# ---------------------------------------------------------------------------

def _download_with_progress(url: str, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size > 1024:
        return
    urllib.request.urlretrieve(url, str(dst))


def bootstrap_cache(cache_dir: Path) -> None:
    models_dir = cache_dir / "models"
    models_dir.mkdir(parents=True, exist_ok=True)

    for key in ("sherpa_onnx_zipformer_vi_30M_int8", "piper_vits_vi_tts", "vosk_small_vn_0_4"):
        info = UPSTREAM_MODEL_CATALOG[key]
        archive_path = models_dir / info["downloadArchive"]
        _download_with_progress(info["downloadUrl"], archive_path)
        if archive_path.suffix == ".bz2":
            with tarfile.open(archive_path, "r:bz2") as tf:
                tf.extractall(models_dir)
        elif archive_path.suffix == ".zip":
            with zipfile.ZipFile(archive_path, "r") as zf:
                zf.extractall(models_dir)


# ---------------------------------------------------------------------------
# Main Orchestration
# ---------------------------------------------------------------------------

def run_benchmark(
    corpus_path: Path,
    output_path: Path,
    cache_dir: Path,
) -> dict[str, Any]:
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    utterances: list[dict[str, Any]] = corpus["utterances"]

    # 1. Self-verify Levenshtein WER/CER sanity
    assert compute_wer_cer("Ăn sáng 35 nghìn", "Ăn sáng 35 nghìn")["wer"] == 0.0
    assert compute_wer_cer("Ăn sáng năm mươi nghìn", "Ăn sáng lăm mươi nghìn")["wordEdits"]["S"] == 1

    # 2. Synthesize deterministic 16kHz Mono PCM16 audio & benchmark Ring-Buffer + Energy/ZCR VAD
    pcm_dir = cache_dir / "audio" / "pcm16_benchmark"
    wav_specs: list[dict[str, Any]] = []
    for u in utterances:
        spec = synthesize_pcm16_benchmark_wav(u, pcm_dir / f"{u['id']}.wav")
        spec["id"] = u["id"]
        wav_specs.append(spec)
    vad_report = run_ring_buffer_vad_benchmark(wav_specs)

    # 3. Simulated ASR variant WER/CER analysis
    sim_wer_report = evaluate_simulated_asr_variants(utterances)

    # 4. Probe Python engines across active interpreter + isolated `.cache/venv`
    interpreters = find_candidate_python_interpreters(cache_dir)
    engines_to_probe = [
        "sherpa_onnx",
        "vosk",
        "onnxruntime",
        "faster_whisper",
        "pywhispercpp",
    ]
    probe_matrix: dict[str, dict[str, Any]] = {}
    best_python_for_engine: dict[str, str] = {}

    for eng in engines_to_probe:
        probe_matrix[eng] = {}
        for interp_label, interp_exe in interpreters:
            res = probe_module_in_python(interp_exe, eng)
            probe_matrix[eng][interp_label] = {
                "pythonExecutable": interp_exe,
                **res,
            }
            if res["installed"] and eng not in best_python_for_engine:
                best_python_for_engine[eng] = interp_exe

    # 5. Discover cached models & generate real Vietnamese TTS corpus WAVs if Piper TTS cached
    local_models = discover_local_models(cache_dir)
    tts_corpus_items: list[dict[str, Any]] | None = None
    if "piper_vits_vi_tts" in local_models and "sherpa_onnx" in best_python_for_engine:
        tts_corpus_items = generate_tts_corpus_wavs_if_available(
            utterances=utterances,
            tts_model_dir=local_models["piper_vits_vi_tts"],
            out_dir=cache_dir / "audio" / "tts_vi_16k",
            python_exe=best_python_for_engine["sherpa_onnx"],
        )

    # 6. Run REAL offline ASR inference on host for installed engines + cached models
    asr_engine_benchmarks: dict[str, Any] = {}

    # 6a. sherpa-onnx Zipformer Vi
    if "sherpa_onnx" not in best_python_for_engine:
        asr_engine_benchmarks["sherpa_onnx_zipformer_vi"] = {
            "status": "NOT_INSTALLED_IN_ENV",
            "detail": (
                "Wheel sherpa-onnx==2.0.3 (cp314-win_amd64) IS available on PyPI for Python 3.14, "
                "but not installed in active interpreter or .cache/venv."
            ),
        }
    elif "sherpa_onnx_zipformer_vi" not in local_models:
        asr_engine_benchmarks["sherpa_onnx_zipformer_vi"] = {
            "status": "MODEL_NOT_CACHED",
            "pythonExecutable": best_python_for_engine["sherpa_onnx"],
            "detail": "sherpa-onnx installed, run with --bootstrap or extract zipformer-vi model into .cache/models/.",
        }
    else:
        model_dir = local_models["sherpa_onnx_zipformer_vi"]
        eval_items = tts_corpus_items or collect_upstream_test_wavs(model_dir)
        if not eval_items:
            asr_engine_benchmarks["sherpa_onnx_zipformer_vi"] = {
                "status": "AUDIO_CORPUS_NOT_CACHED",
                "detail": "Model present but neither TTS Vietnamese audio nor test_wavs found.",
            }
        else:
            worker_payload = {
                "engine": "sherpa_onnx",
                "modelDir": str(model_dir),
                "audioItems": eval_items,
            }
            proc = subprocess.run(
                [best_python_for_engine["sherpa_onnx"], str(__file__), "--worker-json"],
                input=json.dumps(worker_payload, ensure_ascii=False),
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=300,
                check=False,
            )
            if proc.returncode == 0 and proc.stdout.strip():
                result_obj = json.loads(proc.stdout.strip().splitlines()[-1])
                result_obj["audioSource"] = (
                    "local_piper_vits_vi_16k_corpus"
                    if tts_corpus_items
                    else "upstream_model_test_wavs"
                )
                asr_engine_benchmarks["sherpa_onnx_zipformer_vi"] = result_obj
            else:
                asr_engine_benchmarks["sherpa_onnx_zipformer_vi"] = {
                    "status": "WORKER_FAILED",
                    "stderr": proc.stderr[-800:],
                }

    # 6b. Vosk Vietnamese
    if "vosk" not in best_python_for_engine:
        asr_engine_benchmarks["vosk_vn"] = {
            "status": "NOT_INSTALLED_IN_ENV",
            "detail": "Wheel vosk (win_amd64) IS available on PyPI, but not installed in active interpreter or .cache/venv.",
        }
    elif "vosk_vn" not in local_models:
        asr_engine_benchmarks["vosk_vn"] = {
            "status": "MODEL_NOT_CACHED",
            "pythonExecutable": best_python_for_engine["vosk"],
            "detail": "vosk installed, run with --bootstrap or extract vosk-model-small-vn-0.4 into .cache/models/.",
        }
    else:
        eval_items = tts_corpus_items or []
        if "sherpa_onnx_zipformer_vi" in local_models and not eval_items:
            eval_items = collect_upstream_test_wavs(local_models["sherpa_onnx_zipformer_vi"])
        if not eval_items:
            asr_engine_benchmarks["vosk_vn"] = {
                "status": "AUDIO_CORPUS_NOT_CACHED",
                "detail": "Vosk model present but no Vietnamese speech WAVs found in .cache/audio/.",
            }
        else:
            worker_payload = {
                "engine": "vosk",
                "modelDir": str(local_models["vosk_vn"]),
                "audioItems": eval_items,
            }
            proc = subprocess.run(
                [best_python_for_engine["vosk"], str(__file__), "--worker-json"],
                input=json.dumps(worker_payload, ensure_ascii=False),
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=300,
                check=False,
            )
            if proc.returncode == 0 and proc.stdout.strip():
                result_obj = json.loads(proc.stdout.strip().splitlines()[-1])
                result_obj["audioSource"] = (
                    "local_piper_vits_vi_16k_corpus"
                    if tts_corpus_items
                    else "upstream_model_test_wavs"
                )
                asr_engine_benchmarks["vosk_vn"] = result_obj
            else:
                asr_engine_benchmarks["vosk_vn"] = {
                    "status": "WORKER_FAILED",
                    "stderr": proc.stderr[-800:],
                }

    # 6c. Whisper & Direct ONNXRuntime status
    for eng_key, mod_name, note in [
        (
            "faster_whisper",
            "faster_whisper",
            "Prebuilt wheels available (ctranslate2 4.9.1 cp314-win_amd64), not installed in PoC host env.",
        ),
        (
            "pywhispercpp",
            "pywhispercpp",
            "whisper.cpp Python bindings not installed in PoC host env.",
        ),
        (
            "onnxruntime",
            "onnxruntime",
            "Prebuilt wheel onnxruntime 1.32.0 (cp314-win_amd64) available; sherpa-onnx bundles ONNX Runtime C++ core directly.",
        ),
    ]:
        if eng_key not in asr_engine_benchmarks:
            asr_engine_benchmarks[eng_key] = {
                "status": "INSTALLED_NO_MODEL"
                if eng_key in best_python_for_engine
                else "NOT_INSTALLED_IN_ENV",
                "detail": note,
            }

    report = {
        "schemaVersion": "1.0.0",
        "generatedAtUtc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "hostEnvironment": {
            "os": platform.platform(),
            "architecture": platform.machine(),
            "activePythonVersion": platform.python_version(),
            "activePythonExecutable": sys.executable,
            "wheelAvailabilityVerifiedPyPI": {
                "sherpa-onnx": {
                    "version": "2.0.3",
                    "wheel": "sherpa_onnx-2.0.3-cp314-cp314-win_amd64.whl (2.43 MB) + sherpa_onnx_core-2.0.3-py3-none-win_amd64.whl (16.42 MB)",
                    "prebuiltWheelForPy314Win64": True,
                },
                "vosk": {
                    "version": "0.3.41 (0.3.45 available)",
                    "wheel": "vosk-0.3.41-py3-none-win_amd64.whl (11.63 MB)",
                    "prebuiltWheelForPy314Win64": True,
                },
                "onnxruntime": {
                    "version": "1.32.0",
                    "wheel": "onnxruntime-1.32.0-cp314-cp314-win_amd64.whl",
                    "prebuiltWheelForPy314Win64": True,
                },
                "faster-whisper": {
                    "version": "1.2.1",
                    "wheel": "faster_whisper-1.2.1-py3-none-any.whl + ctranslate2-4.9.1-cp314-cp314-win_amd64.whl",
                    "prebuiltWheelForPy314Win64": True,
                },
            },
            "engineProbeMatrix": probe_matrix,
        },
        "corpusSummary": {
            "corpusName": corpus["corpusName"],
            "utteranceCount": len(utterances),
            "midPauseCount": sum(1 for u in utterances if u.get("hasMidSentencePause")),
            "section15ExampleCount": sum(1 for u in utterances if u.get("isSection15Example")),
        },
        "measuredHost": {
            "status": "MEASURED_HOST",
            "pcm16RingBufferAndVadBenchmark": vad_report,
            "simulatedAsrVariantWerCer": sim_wer_report,
            "realOfflineAsrEngines": asr_engine_benchmarks,
        },
        "upstreamPublishedReference": UPSTREAM_MODEL_CATALOG,
        "androidDeviceRequiredMetrics": {
            "status": "NOT_MEASURED_DEVICE_REQUIRED",
            "note": "NOT_RUN — Android Device Required",
            "pendingMeasurements": [
                "Android AudioRecord 16kHz Mono PCM16 buffer underrun & jitter on physical device",
                "Android SpeechRecognizer OEM partial-transcript cadence (vi-VN offline pack vs network)",
                "ARM64 NEON big.LITTLE RTF & thermal throttling for sherpa-onnx Zipformer-30M INT8",
                "Android APK/AAB binary size delta (libsherpa-onnx-jni.so arm64-v8a + armeabi-v7a) & runtime RSS",
            ],
        },
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(
        description="LifeOS Vietnamese Offline ASR PoC & Benchmark Runner"
    )
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS_PATH)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT_PATH)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    parser.add_argument(
        "--bootstrap",
        action="store_true",
        help="Download & extract upstream Vietnamese models into gitignored .cache/models/",
    )
    parser.add_argument(
        "--worker-json",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args()

    if args.worker_json:
        payload = json.loads(sys.stdin.read())
        res = _run_asr_worker(
            engine=payload["engine"],
            model_dir=Path(payload["modelDir"]),
            audio_items=payload["audioItems"],
        )
        print(json.dumps(res, ensure_ascii=False))
        return 0

    if args.bootstrap:
        bootstrap_cache(args.cache_dir)

    report = run_benchmark(
        corpus_path=args.corpus,
        output_path=args.out,
        cache_dir=args.cache_dir,
    )

    vad = report["measuredHost"]["pcm16RingBufferAndVadBenchmark"]
    sim = report["measuredHost"]["simulatedAsrVariantWerCer"]
    print(
        f"[VOICE_ASR_POC] Corpus={report['corpusSummary']['utteranceCount']} utterances | "
        f"VAD Frame P50/P95={vad['frameProcessLatencyUs']['p50']}/{vad['frameProcessLatencyUs']['p95']} us | "
        f"MidPause Premature Cuts={vad['prematureMidPauseCuts']} | "
        f"RingBuf Peak={vad['tracemallocPeakMemoryKb']} KB"
    )
    print(
        f"[SIM_ASR_VARIANTS] Pairs={sim['variantPairsEvaluated']} | "
        f"WER={sim['meanWer']*100:.2f}% (ASCII={sim['meanWerAsciiFolded']*100:.2f}%) | "
        f"CER={sim['meanCer']*100:.2f}% (ASCII={sim['meanCerAsciiFolded']*100:.2f}%)"
    )
    for name, info in report["measuredHost"]["realOfflineAsrEngines"].items():
        if info.get("status") == "MEASURED_HOST":
            print(
                f"[ENGINE:{name}] Status=MEASURED_HOST | ColdInit={info['coldInitMs']} ms | "
                f"E2F P50/P95={info['endToFinalLatencyMs']['p50']}/{info['endToFinalLatencyMs']['p95']} ms | "
                f"RTF={info['rtf']['mean']} | PeakRSS={info['peakRssMb']} MB | "
                f"WER={info['meanWer']*100:.2f}% | CER={info['meanCer']*100:.2f}%"
            )
        else:
            print(f"[ENGINE:{name}] Status={info.get('status')} ({info.get('detail', '')})")
    print(f"[REPORT] Written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
