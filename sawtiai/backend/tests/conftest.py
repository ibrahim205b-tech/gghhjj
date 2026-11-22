"""Test fixtures.

`ToneTestEngine` exists ONLY in the test suite to exercise API logic (auth,
validation, job queue, file lifecycle) quickly and deterministically. It is
never registered in production code. Real-model behaviour is covered by
tests/test_real_engine.py, which runs the actual SILMA engine in CI.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import time
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf

_TMP = Path(tempfile.mkdtemp(prefix="sawti-test-"))
os.environ.setdefault("SAWTI_DATA_DIR", str(_TMP / "data"))
os.environ.setdefault("SAWTI_API_KEY", "test-key-123")
os.environ.setdefault("SAWTI_PRELOAD", "0")
os.environ.setdefault("SAWTI_RATE_LIMIT_PER_MINUTE", "10000")

from app.engines import register  # noqa: E402
from app.engines.base import Engine, EngineInfo, VoiceProfile  # noqa: E402

API_KEY = os.environ["SAWTI_API_KEY"]
AUTH = {"Authorization": f"Bearer {API_KEY}"}


class ToneTestEngine(Engine):
    info = EngineInfo(
        id="tone-test", name="Test tone engine", version="0", license="test-only",
        source_url="", model_url="", languages=["ar", "en"], sample_rate=16000,
        min_sample_seconds=3.0, recommended_sample_seconds=7.0, max_useful_sample_seconds=8.0,
        needs_transcript=False, supports_speed=True, speed_range=(0.7, 1.3), max_chunk_chars=40)
    fail_next = False
    delay = 0.0

    def load(self) -> None:
        pass

    def prepare_voice(self, voice_id, sample_wav, transcript, workdir):
        dst = workdir / "reference.wav"
        y, sr = sf.read(str(sample_wav))
        sf.write(str(dst), y[: sr * 8], sr)
        return VoiceProfile(voice_id, dst, transcript or "نص")

    def synthesize(self, text, profile, *, language, speed, style, quality):
        if ToneTestEngine.fail_next:
            ToneTestEngine.fail_next = False
            raise RuntimeError("boom")
        time.sleep(self.delay)
        sr = self.info.sample_rate
        n = int(sr * max(0.3, 0.05 * len(text)) / speed)
        t = np.arange(n) / sr
        return (0.2 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


register("tone-test", ToneTestEngine)


def make_speech_like(path: Path, seconds: float = 6.0, sr: int = 24000, noise: float = 0.002) -> Path:
    """Synthetic voiced signal with syllable-like on/off envelope (test input only)."""
    t = np.arange(int(sr * seconds)) / sr
    f0 = 140 + 20 * np.sin(2 * np.pi * 0.5 * t)
    phase = 2 * np.pi * np.cumsum(f0) / sr
    voiced = sum(np.sin(k * phase) / k for k in range(1, 8))
    env = (np.sin(2 * np.pi * 3 * t) > -0.2).astype(float)
    y = 0.25 * voiced * env + noise * np.random.default_rng(0).standard_normal(len(t))
    sf.write(str(path), y.astype(np.float32), sr)
    return path


def to_format(src: Path, ext: str) -> Path:
    dst = src.with_suffix(ext)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(src), str(dst)], check=True)
    return dst


@pytest.fixture(scope="session")
def client():
    from fastapi.testclient import TestClient

    from app import main
    from app.config import settings
    from app.service import engine_holder

    settings.engine = "tone-test"
    engine_holder.set_engine(ToneTestEngine())
    engine_holder.start_loading()
    for _ in range(50):
        if engine_holder.state == "ready":
            break
        time.sleep(0.05)
    with TestClient(main.app) as c:
        yield c


@pytest.fixture()
def tmp_audio(tmp_path):
    return make_speech_like(tmp_path / "sample.wav")


def wait_job(client, job_id: str, timeout: float = 30) -> dict:
    end = time.time() + timeout
    while time.time() < end:
        r = client.get(f"/api/tts/status/{job_id}", headers=AUTH)
        assert r.status_code == 200, r.text
        j = r.json()
        if j["status"] in ("done", "failed"):
            return j
        time.sleep(0.05)
    raise AssertionError("job did not finish")
