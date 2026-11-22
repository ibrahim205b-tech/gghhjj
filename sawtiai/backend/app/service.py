"""Voice storage, engine lifecycle, a single-worker job queue and cleanup.

CPU hosts can only run one synthesis at a time efficiently, so all model work
goes through one worker thread. Jobs are polled by the app; nothing is
reported as done until a real audio file exists on disk.
"""

from __future__ import annotations

import json
import logging
import queue
import secrets
import shutil
import threading
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np
import soundfile as sf

from . import audio as audio_utils
from .config import settings
from .engines import create as create_engine
from .engines.base import Engine, VoiceProfile
from .text.arabic import normalize_arabic, split_into_chunks

log = logging.getLogger("sawti")


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_urlsafe(12)}"


def _safe_id(value: str, prefix: str) -> str:
    if not value or not value.startswith(prefix + "_") or len(value) > 64:
        raise KeyError(value)
    if any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for c in value):
        raise KeyError(value)
    return value


# ---------------------------------------------------------------------------
# Engine holder
# ---------------------------------------------------------------------------

class EngineHolder:
    def __init__(self) -> None:
        self.engine: Engine | None = None
        self.state = "not_loaded"  # not_loaded | loading | ready | failed
        self.error: str | None = None
        self.loaded_at: float | None = None
        self.load_seconds: float | None = None
        self._lock = threading.Lock()

    def set_engine(self, engine: Engine) -> None:
        self.engine = engine

    def start_loading(self) -> None:
        with self._lock:
            if self.state in ("loading", "ready"):
                return
            self.state = "loading"
        threading.Thread(target=self._load, name="engine-loader", daemon=True).start()

    def _load(self) -> None:
        t = time.time()
        try:
            if self.engine is None:
                self.engine = create_engine(settings.engine)
            try:
                import torch
                torch.set_num_threads(max(1, settings.threads))
            except Exception:  # torch optional for non-torch engines
                pass
            self.engine.load()
            self.load_seconds = round(time.time() - t, 1)
            self.loaded_at = time.time()
            self.state = "ready"
            log.info("engine %s ready in %.1fs", settings.engine, self.load_seconds)
        except Exception as e:
            self.state = "failed"
            self.error = f"{type(e).__name__}: {e}"
            log.exception("engine load failed")

    def require(self) -> Engine:
        if self.state != "ready" or self.engine is None:
            raise RuntimeError("engine_not_ready")
        return self.engine


engine_holder = EngineHolder()


# ---------------------------------------------------------------------------
# Voices
# ---------------------------------------------------------------------------

class VoiceStore:
    def _dir(self, voice_id: str) -> Path:
        return settings.voices_dir / _safe_id(voice_id, "voice")

    def _meta_path(self, voice_id: str) -> Path:
        return self._dir(voice_id) / "meta.json"

    def get(self, voice_id: str) -> dict:
        p = self._meta_path(voice_id)
        if not p.exists():
            raise KeyError(voice_id)
        return json.loads(p.read_text(encoding="utf-8"))

    def save(self, meta: dict) -> None:
        d = self._dir(meta["voice_id"])
        d.mkdir(parents=True, exist_ok=True)
        tmp = d / "meta.json.tmp"
        tmp.write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
        tmp.replace(d / "meta.json")

    def update(self, voice_id: str, **changes) -> dict:
        meta = self.get(voice_id)
        meta.update(changes)
        self.save(meta)
        return meta

    def list(self) -> list[dict]:
        out = []
        if settings.voices_dir.exists():
            for d in settings.voices_dir.iterdir():
                p = d / "meta.json"
                if p.exists():
                    try:
                        out.append(json.loads(p.read_text(encoding="utf-8")))
                    except (OSError, json.JSONDecodeError):
                        continue
        return sorted(out, key=lambda m: m.get("created_at", 0), reverse=True)

    def create(self, name: str, sample_wav: Path, transcript: str, quality: dict, source_format: str) -> dict:
        voice_id = new_id("voice")
        d = self._dir(voice_id)
        d.mkdir(parents=True, exist_ok=True)
        shutil.move(str(sample_wav), d / "original.wav")
        meta = {
            "voice_id": voice_id, "name": name or "صوتي", "status": "uploaded",
            "engine": settings.engine, "created_at": time.time(), "prepared_at": None,
            "transcript": transcript, "transcript_provided": bool(transcript),
            "quality": quality, "source_format": source_format,
            "has_original": True, "has_reference": False, "error": None,
        }
        self.save(meta)
        return meta

    def original_path(self, voice_id: str) -> Path:
        return self._dir(voice_id) / "original.wav"

    def profile(self, voice_id: str) -> VoiceProfile:
        meta = self.get(voice_id)
        if meta.get("status") != "ready":
            raise PermissionError(voice_id)
        return VoiceProfile(voice_id=voice_id, reference_wav=self._dir(voice_id) / "reference.wav",
                            transcript=meta.get("reference_transcript") or meta.get("transcript") or "")

    def workdir(self, voice_id: str) -> Path:
        return self._dir(voice_id)

    def delete_original(self, voice_id: str) -> dict:
        self.get(voice_id)
        self.original_path(voice_id).unlink(missing_ok=True)
        return self.update(voice_id, has_original=False)

    def delete(self, voice_id: str) -> None:
        d = self._dir(voice_id)
        if not d.exists():
            raise KeyError(voice_id)
        shutil.rmtree(d, ignore_errors=True)

    def delete_all(self) -> int:
        n = 0
        if settings.voices_dir.exists():
            for d in settings.voices_dir.iterdir():
                shutil.rmtree(d, ignore_errors=True)
                n += 1
        return n


voices = VoiceStore()


# ---------------------------------------------------------------------------
# Generated audio
# ---------------------------------------------------------------------------

class AudioStore:
    def path(self, audio_id: str, fmt: str = "wav") -> Path:
        return settings.audio_dir / f"{_safe_id(audio_id, 'audio')}.{fmt}"

    def meta(self, audio_id: str) -> dict:
        p = settings.audio_dir / f"{_safe_id(audio_id, 'audio')}.json"
        if not p.exists():
            raise KeyError(audio_id)
        m = json.loads(p.read_text(encoding="utf-8"))
        if m["expires_at"] < time.time():
            self.delete(audio_id)
            raise KeyError(audio_id)
        return m

    def save(self, y: np.ndarray, sr: int, voice_id: str) -> dict:
        audio_id = new_id("audio")
        wav = self.path(audio_id)
        sf.write(str(wav), y, sr, subtype="PCM_16")
        meta = {"audio_id": audio_id, "voice_id": voice_id, "sample_rate": sr,
                "duration_seconds": round(len(y) / sr, 2), "size_bytes": wav.stat().st_size,
                "created_at": time.time(), "expires_at": time.time() + settings.audio_ttl_minutes * 60}
        (settings.audio_dir / f"{audio_id}.json").write_text(json.dumps(meta), encoding="utf-8")
        return meta

    def file_for(self, audio_id: str, fmt: str) -> Path:
        self.meta(audio_id)
        src = self.path(audio_id, "wav")
        if fmt == "wav":
            return src
        dst = self.path(audio_id, fmt)
        if not dst.exists():
            audio_utils.encode(src, dst, fmt)
        return dst

    def delete(self, audio_id: str) -> bool:
        found = False
        for ext in ("wav", "mp3", "m4a", "json"):
            p = settings.audio_dir / f"{_safe_id(audio_id, 'audio')}.{ext}"
            if p.exists():
                p.unlink(missing_ok=True)
                found = True
        return found

    def delete_all(self) -> int:
        n = 0
        if settings.audio_dir.exists():
            for p in settings.audio_dir.iterdir():
                p.unlink(missing_ok=True)
                n += 1
        return n


audio_store = AudioStore()


# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------

@dataclass
class Job:
    job_id: str
    kind: str  # prepare | tts
    voice_id: str
    params: dict = field(default_factory=dict)
    status: str = "queued"  # queued | running | done | failed
    progress: float = 0.0
    chunks_total: int = 0
    chunks_done: int = 0
    created_at: float = field(default_factory=time.time)
    started_at: float | None = None
    finished_at: float | None = None
    error_code: str | None = None
    error_message: str | None = None
    result: dict | None = None
    idempotency_key: str | None = None

    def public(self, queue_position: int | None = None) -> dict:
        d = asdict(self)
        d.pop("params", None)
        d.pop("idempotency_key", None)
        d["queue_position"] = queue_position
        if self.started_at:
            d["elapsed_seconds"] = round((self.finished_at or time.time()) - self.started_at, 1)
        return d


class JobError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


ERRORS = {
    "engine_not_ready": "محرك الصوت لم يجهز بعد. انتظر قليلاً ثم أعد المحاولة.",
    "timeout": "انتهت مهلة المعالجة. جرّب نصاً أقصر.",
    "voice_missing": "النسخة الصوتية غير موجودة على الخادم.",
    "transcript_failed": "تعذر استخراج نص العينة. اكتب النص الذي قلته في التسجيل.",
    "engine_error": "فشل محرك الصوت أثناء المعالجة.",
    "empty_output": "لم يُنتج المحرك صوتاً صالحاً.",
}


class JobManager:
    def __init__(self) -> None:
        self.jobs: dict[str, Job] = {}
        self._q: queue.Queue[str] = queue.Queue()
        self._lock = threading.Lock()
        self._worker: threading.Thread | None = None

    def start(self) -> None:
        if self._worker is None or not self._worker.is_alive():
            self._worker = threading.Thread(target=self._run, name="job-worker", daemon=True)
            self._worker.start()

    def pending(self) -> list[Job]:
        return [j for j in self.jobs.values() if j.status in ("queued", "running")]

    def position(self, job: Job) -> int | None:
        if job.status != "queued":
            return None
        queued = sorted((j for j in self.jobs.values() if j.status == "queued"), key=lambda j: j.created_at)
        return [j.job_id for j in queued].index(job.job_id) + 1

    def submit(self, kind: str, voice_id: str, params: dict, idempotency_key: str | None = None) -> tuple[Job, bool]:
        with self._lock:
            if idempotency_key:
                for j in self.jobs.values():
                    if j.idempotency_key == idempotency_key and j.status in ("queued", "running", "done"):
                        return j, False
            if len(self.pending()) >= settings.max_queue:
                raise JobError("queue_full", "الخادم مشغول بطلبات أخرى. حاول بعد قليل.")
            job = Job(job_id=new_id("job"), kind=kind, voice_id=voice_id, params=params,
                      idempotency_key=idempotency_key)
            self.jobs[job.job_id] = job
        self._q.put(job.job_id)
        self.start()
        return job, True

    def get(self, job_id: str) -> Job:
        job = self.jobs.get(_safe_id(job_id, "job"))
        if job is None:
            raise KeyError(job_id)
        return job

    def _run(self) -> None:
        while True:
            job_id = self._q.get()
            job = self.jobs.get(job_id)
            if job is None or job.status != "queued":
                continue
            job.status, job.started_at = "running", time.time()
            try:
                if job.kind == "prepare":
                    self._prepare(job)
                else:
                    self._tts(job)
                job.status, job.progress = "done", 1.0
            except JobError as e:
                job.status, job.error_code, job.error_message = "failed", e.code, e.message
            except Exception as e:  # unexpected engine failure
                code = str(e) if str(e) in ERRORS else "engine_error"
                job.status, job.error_code, job.error_message = "failed", code, ERRORS[code]
                log.exception("job %s (%s) failed", job.job_id, job.kind)
            finally:
                job.finished_at = time.time()
                log.info("job %s kind=%s status=%s seconds=%.1f", job.job_id, job.kind, job.status,
                         job.finished_at - (job.started_at or job.finished_at))

    # -- job bodies ---------------------------------------------------------

    def _prepare(self, job: Job) -> None:
        engine = engine_holder.require()
        try:
            meta = voices.get(job.voice_id)
        except KeyError as e:
            raise JobError("voice_missing", ERRORS["voice_missing"]) from e
        original = voices.original_path(job.voice_id)
        if not original.exists():
            raise JobError("voice_missing", "العينة الأصلية محذوفة. ارفع عينة جديدة.")
        voices.update(job.voice_id, status="preparing", error=None)
        try:
            profile = engine.prepare_voice(job.voice_id, original, meta.get("transcript") or "",
                                           voices.workdir(job.voice_id))
        except Exception as e:
            code = str(e) if str(e) in ERRORS else "engine_error"
            voices.update(job.voice_id, status="failed", error=code)
            raise JobError(code, ERRORS[code]) from e
        ref_seconds = sf.info(str(profile.reference_wav)).duration
        voices.update(job.voice_id, status="ready", prepared_at=time.time(), has_reference=True,
                      reference_transcript=profile.transcript, reference_seconds=round(ref_seconds, 2))
        job.result = {"voice_id": job.voice_id, "reference_seconds": round(ref_seconds, 2)}

    def _tts(self, job: Job) -> None:
        engine = engine_holder.require()
        try:
            profile = voices.profile(job.voice_id)
        except (KeyError, PermissionError) as e:
            raise JobError("voice_missing", ERRORS["voice_missing"]) from e
        p = job.params
        text = normalize_arabic(p["text"], keep_tashkeel=True)
        chunks = split_into_chunks(text, engine.info.max_chunk_chars)
        if not chunks:
            raise JobError("empty_text", "النص فارغ بعد المعالجة.")
        job.chunks_total = len(chunks)
        sr = engine.info.sample_rate
        waves = []
        for i, chunk in enumerate(chunks):
            if time.time() - (job.started_at or time.time()) > settings.job_timeout_seconds:
                raise JobError("timeout", ERRORS["timeout"])
            y = engine.synthesize(chunk, profile, language=p.get("language", "ar"),
                                  speed=p.get("speed", 1.0), style=p.get("style"), quality=p.get("quality"))
            if y is None or y.size < sr * 0.1 or not np.isfinite(y).all():
                raise JobError("empty_output", ERRORS["empty_output"])
            waves.append(y)
            job.chunks_done = i + 1
            job.progress = round((i + 1) / len(chunks), 3)
        y = audio_utils.concat(waves, sr)
        meta = audio_store.save(y, sr, job.voice_id)
        job.result = {"audio_id": meta["audio_id"], "duration_seconds": meta["duration_seconds"],
                      "size_bytes": meta["size_bytes"], "sample_rate": sr,
                      "expires_at": meta["expires_at"], "chunks": len(chunks)}

    def forget_voice(self, voice_id: str) -> None:
        with self._lock:
            for jid in [j.job_id for j in self.jobs.values() if j.voice_id == voice_id and j.status not in ("queued", "running")]:
                self.jobs.pop(jid, None)

    def cleanup(self, max_age: float = 3600 * 6) -> None:
        now = time.time()
        with self._lock:
            for jid in [j.job_id for j in self.jobs.values()
                        if j.finished_at and now - j.finished_at > max_age]:
                self.jobs.pop(jid, None)


jobs = JobManager()


# ---------------------------------------------------------------------------
# Periodic cleanup of temporary and expired files
# ---------------------------------------------------------------------------

def cleanup_once() -> dict:
    now = time.time()
    removed = {"audio": 0, "uploads": 0}
    if settings.audio_dir.exists():
        for p in settings.audio_dir.glob("*.json"):
            try:
                m = json.loads(p.read_text(encoding="utf-8"))
                if m.get("expires_at", 0) < now and audio_store.delete(m["audio_id"]):
                    removed["audio"] += 1
            except (OSError, json.JSONDecodeError, KeyError):
                p.unlink(missing_ok=True)
    if settings.uploads_dir.exists():
        for p in settings.uploads_dir.iterdir():
            if now - p.stat().st_mtime > settings.upload_ttl_minutes * 60:
                p.unlink(missing_ok=True)
                removed["uploads"] += 1
    # Voices that were uploaded but never prepared are removed after the upload TTL.
    for meta in voices.list():
        if meta.get("status") in ("uploaded", "failed") and now - meta.get("created_at", now) > settings.upload_ttl_minutes * 60 * 4:
            try:
                voices.delete(meta["voice_id"])
            except KeyError:
                pass
    jobs.cleanup()
    return removed


def start_cleanup_thread(interval: float = 60.0) -> None:
    def loop() -> None:
        while True:
            try:
                cleanup_once()
            except Exception:
                log.exception("cleanup failed")
            time.sleep(interval)
    threading.Thread(target=loop, name="cleanup", daemon=True).start()
