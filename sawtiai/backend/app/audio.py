"""Audio helpers: format detection, conversion (ffmpeg), quality analysis."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf

ALLOWED_EXTENSIONS = {".wav", ".mp3", ".m4a", ".aac", ".mp4", ".ogg", ".opus", ".flac", ".webm", ".3gp", ".amr"}
ALLOWED_CODECS = {"pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le", "pcm_u8", "mp3", "aac", "alac",
                  "opus", "vorbis", "flac", "amr_nb", "amr_wb", "pcm_mulaw", "pcm_alaw"}


class AudioError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None


def probe(path: Path) -> dict:
    """Inspect the real content of a file (not its extension)."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", "-show_format", str(path)],
            capture_output=True, timeout=30, check=False)
    except subprocess.TimeoutExpired as e:
        raise AudioError("probe_timeout", "تعذر قراءة الملف الصوتي في الوقت المحدد.") from e
    if out.returncode != 0:
        raise AudioError("invalid_audio", "الملف ليس ملفاً صوتياً صالحاً أو أنه تالف.")
    info = json.loads(out.stdout or b"{}")
    audio = [s for s in info.get("streams", []) if s.get("codec_type") == "audio"]
    if not audio:
        raise AudioError("no_audio_stream", "لا يحتوي الملف على مسار صوتي.")
    codec = audio[0].get("codec_name", "")
    if codec not in ALLOWED_CODECS:
        raise AudioError("unsupported_codec", f"ترميز الصوت غير مدعوم ({codec}). استخدم WAV أو MP3 أو M4A.")
    duration = float(info.get("format", {}).get("duration") or audio[0].get("duration") or 0)
    return {"codec": codec, "duration": duration,
            "sample_rate": int(audio[0].get("sample_rate") or 0),
            "channels": int(audio[0].get("channels") or 0),
            "format": info.get("format", {}).get("format_name", "")}


def convert_to_wav(src: Path, dst: Path, sample_rate: int = 24000) -> None:
    """Decode anything ffmpeg understands to mono 16-bit PCM WAV."""
    cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(src),
           "-vn", "-ac", "1", "-ar", str(sample_rate), "-sample_fmt", "s16", str(dst)]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=120, check=False)
    except subprocess.TimeoutExpired as e:
        raise AudioError("convert_timeout", "استغرق تحويل الملف وقتاً طويلاً.") from e
    if r.returncode != 0 or not dst.exists() or dst.stat().st_size < 100:
        raise AudioError("convert_failed", "تعذر تحويل الملف الصوتي إلى الصيغة المطلوبة.")


def encode(src_wav: Path, dst: Path, fmt: str) -> None:
    if fmt == "wav":
        shutil.copyfile(src_wav, dst)
        return
    codec = {"mp3": ["-c:a", "libmp3lame", "-b:a", "128k"],
             "m4a": ["-c:a", "aac", "-b:a", "128k"]}[fmt]
    r = subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(src_wav),
                        *codec, str(dst)], capture_output=True, timeout=300, check=False)
    if r.returncode != 0:
        raise AudioError("encode_failed", "تعذر ترميز الملف الناتج.")


def analyze(wav: Path) -> dict:
    """Objective sample-quality report used to guide the user."""
    y, sr = sf.read(str(wav), dtype="float32", always_2d=False)
    if y.ndim > 1:
        y = y.mean(axis=1)
    duration = len(y) / sr if sr else 0.0
    if len(y) == 0:
        raise AudioError("empty_audio", "الملف الصوتي فارغ.")
    peak = float(np.max(np.abs(y)))
    clipped = float(np.mean(np.abs(y) >= 0.98))
    frame = max(1, int(sr * 0.03))
    n = len(y) // frame
    rms = np.sqrt(np.mean(y[: n * frame].reshape(n, frame) ** 2, axis=1) + 1e-12) if n else np.array([1e-6])
    db = 20 * np.log10(rms + 1e-9)
    speech_thr = max(np.percentile(db, 90) - 25, -55)
    speech = db > speech_thr
    speech_seconds = float(speech.sum() * frame / sr)
    noise_floor = float(np.percentile(db, 10))
    speech_level = float(np.percentile(db, 90))
    snr = speech_level - noise_floor

    warnings: list[str] = []
    if speech_seconds < 2.5:
        warnings.append("مدة الكلام الفعلي قصيرة جداً.")
    if peak < 0.05:
        warnings.append("الصوت منخفض جداً. اقترب من الميكروفون.")
    if clipped > 0.002:
        warnings.append("يوجد تشويه بسبب ارتفاع الصوت. ابتعد قليلاً عن الميكروفون أو اخفض صوتك.")
    if snr < 15:
        warnings.append("الضوضاء المحيطة مرتفعة. سجّل في مكان أهدأ.")
    elif snr < 25:
        warnings.append("توجد ضوضاء خفيفة في الخلفية.")
    score = 100
    score -= 35 if speech_seconds < 2.5 else 0
    score -= 25 if peak < 0.05 else 0
    score -= min(30, int(clipped * 5000))
    score -= 30 if snr < 15 else (12 if snr < 25 else 0)
    score = max(0, min(100, score))
    label = "ممتازة" if score >= 85 else "جيدة" if score >= 65 else "مقبولة" if score >= 45 else "ضعيفة"
    return {"duration_seconds": round(duration, 2), "speech_seconds": round(speech_seconds, 2),
            "peak": round(peak, 3), "clipped_ratio": round(clipped, 4),
            "noise_floor_db": round(noise_floor, 1), "snr_db": round(snr, 1),
            "score": score, "label": label, "warnings": warnings}


def concat(chunks: list[np.ndarray], sr: int, pause_seconds: float = 0.25) -> np.ndarray:
    """Join chunk waveforms with a short natural pause and tiny fades (no clicks)."""
    if not chunks:
        return np.zeros(0, dtype=np.float32)
    fade = int(sr * 0.01)
    gap = np.zeros(int(sr * pause_seconds), dtype=np.float32)
    out = []
    for i, c in enumerate(chunks):
        c = np.asarray(c, dtype=np.float32).reshape(-1).copy()
        if len(c) > 2 * fade:
            ramp = np.linspace(0, 1, fade, dtype=np.float32)
            c[:fade] *= ramp
            c[-fade:] *= ramp[::-1]
        out.append(c)
        if i < len(chunks) - 1:
            out.append(gap)
    y = np.concatenate(out)
    peak = float(np.max(np.abs(y))) if y.size else 0
    if peak > 0.99:
        y = y * (0.99 / peak)
    return y
