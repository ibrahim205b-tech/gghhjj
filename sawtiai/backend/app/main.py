"""Sawti AI backend - FastAPI.

Interactive docs: /docs (Swagger UI) and /openapi.json.
Every /api route requires the API key (see security.py). /health is public
and reveals nothing but liveness and engine state.
"""

from __future__ import annotations

import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, File, Form, HTTPException, Query, Request, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from . import audio as audio_utils
from .config import APP_VERSION, settings
from .security import Authorized
from .service import (JobError, audio_store, cleanup_once, engine_holder, jobs, start_cleanup_thread,
                      voices)
from .text.arabic import has_arabic

logging.basicConfig(level=os.environ.get("SAWTI_LOG_LEVEL", "INFO"),
                    format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("sawti")
# Access logs would contain ids only, but keep them quiet anyway.
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

STARTED_AT = time.time()


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings.ensure_dirs()
    cleanup_once()
    start_cleanup_thread()
    jobs.start()
    if settings.preload_model:
        engine_holder.start_loading()
    if not settings.api_key:
        log.warning("SAWTI_API_KEY is not set - all /api routes will refuse requests")
    yield


app = FastAPI(
    title="Sawti AI API — صوتي AI",
    version=APP_VERSION,
    description=(
        "واجهة خادم تطبيق «صوتي AI» لاستنساخ الصوت وتوليد الكلام.\n\n"
        "جميع مسارات `/api` تتطلب الترويسة `Authorization: Bearer <SAWTI_API_KEY>`.\n"
        "العمليات الثقيلة (تجهيز الصوت وتوليد الكلام) غير متزامنة: تُرجع `job_id` "
        "ثم يستعلم التطبيق عن حالتها حتى تكتمل."
    ),
    lifespan=lifespan,
)


def err(status_code: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code, detail={"code": code, "message": message})


@app.exception_handler(RequestValidationError)
async def validation_handler(_: Request, exc: RequestValidationError):
    return JSONResponse(status_code=422, content={"detail": {
        "code": "validation_error", "message": "بيانات الطلب غير صالحة.",
        "fields": [".".join(str(x) for x in e.get("loc", [])) for e in exc.errors()]}})


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


# ---------------------------------------------------------------------------
# Health / status
# ---------------------------------------------------------------------------

@app.get("/health", tags=["status"], summary="فحص الصحة (عام، بدون مصادقة)")
def health():
    return {"status": "ok", "engine_state": engine_holder.state, "version": APP_VERSION,
            "uptime_seconds": round(time.time() - STARTED_AT)}


@app.get("/api/status", tags=["status"], dependencies=[Authorized], summary="حالة الخادم والمحرك وحدوده")
def api_status():
    engine = engine_holder.engine
    info = engine.info.to_dict() if engine else None
    if info is None:
        try:
            from .engines import create
            info = create(settings.engine).info.to_dict()
        except Exception:
            info = {"id": settings.engine}
    return {
        "version": APP_VERSION,
        "engine": info,
        "engine_state": engine_holder.state,
        "engine_error": "فشل تحميل المحرك" if engine_holder.state == "failed" else None,
        "engine_load_seconds": engine_holder.load_seconds,
        "device": "cpu",
        "queue": {"pending": len(jobs.pending()), "max": settings.max_queue},
        "limits": {"max_upload_mb": settings.max_upload_mb, "max_sample_seconds": settings.max_sample_seconds,
                   "max_text_chars": settings.max_text_chars, "audio_ttl_minutes": settings.audio_ttl_minutes},
        "storage": {"persistent": os.path.ismount("/data") and str(settings.data_dir).startswith("/data"),
                    "voices": len(voices.list())},
        "ffmpeg": audio_utils.ffmpeg_available(),
    }


@app.post("/api/engine/load", tags=["status"], dependencies=[Authorized], summary="بدء تحميل المحرك (إن لم يكن محملاً)")
def engine_load():
    if engine_holder.state == "failed":
        engine_holder.state = "not_loaded"
    engine_holder.start_loading()
    return {"engine_state": engine_holder.state}


# ---------------------------------------------------------------------------
# Voice
# ---------------------------------------------------------------------------

async def _save_upload(file: UploadFile) -> Path:
    ext = Path(file.filename or "").suffix.lower()
    if ext and ext not in audio_utils.ALLOWED_EXTENSIONS:
        raise err(415, "unsupported_type", "نوع الملف غير مدعوم. الصيغ المدعومة: WAV, MP3, M4A.")
    limit = settings.max_upload_mb * 1024 * 1024
    dst = settings.uploads_dir / f"up_{uuid.uuid4().hex}{ext or '.bin'}"
    size = 0
    with dst.open("wb") as f:
        while chunk := await file.read(1024 * 1024):
            size += len(chunk)
            if size > limit:
                f.close()
                dst.unlink(missing_ok=True)
                raise err(413, "file_too_large", f"حجم الملف أكبر من الحد المسموح ({settings.max_upload_mb} ميغابايت).")
            f.write(chunk)
    if size == 0:
        dst.unlink(missing_ok=True)
        raise err(400, "empty_file", "الملف فارغ.")
    return dst


@app.post("/api/voice/upload", tags=["voice"], dependencies=[Authorized], status_code=201,
          summary="رفع عينة صوتية (WAV/MP3/M4A) وتحليل جودتها")
async def voice_upload(file: UploadFile = File(..., description="العينة الصوتية"),
                       name: str = Form("صوتي", max_length=60),
                       transcript: str = Form("", max_length=1000, description="النص المنطوق في العينة (مستحسن)")):
    raw = await _save_upload(file)
    wav = settings.uploads_dir / f"{raw.stem}_conv.wav"
    try:
        try:
            info = await run_in_threadpool(audio_utils.probe, raw)
            engine_info = (engine_holder.engine.info if engine_holder.engine else None)
            min_s = engine_info.min_sample_seconds if engine_info else 3.0
            if info["duration"] < min_s:
                raise err(422, "sample_too_short", f"العينة قصيرة جداً. المطلوب {min_s:g} ثوانٍ على الأقل.")
            if info["duration"] > settings.max_sample_seconds:
                raise err(422, "sample_too_long", f"العينة أطول من {settings.max_sample_seconds:g} ثانية.")
            await run_in_threadpool(audio_utils.convert_to_wav, raw, wav)
            quality = await run_in_threadpool(audio_utils.analyze, wav)
        except audio_utils.AudioError as e:
            raise err(422 if e.code != "unsupported_codec" else 415, e.code, e.message) from e
        if quality["speech_seconds"] < min(2.0, min_s):
            raise err(422, "no_speech", "لم يتم اكتشاف كلام واضح في العينة.")
        meta = voices.create(name.strip(), wav, transcript.strip(), quality, info["codec"])
        log.info("voice uploaded id=%s seconds=%.1f codec=%s", meta["voice_id"], quality["duration_seconds"], info["codec"])
        return meta
    finally:
        raw.unlink(missing_ok=True)
        wav.unlink(missing_ok=True)


class PrepareBody(BaseModel):
    voice_id: str = Field(..., max_length=64)


@app.post("/api/voice/prepare", tags=["voice"], dependencies=[Authorized], status_code=202,
          summary="تجهيز النسخة الصوتية من العينة المرفوعة (عملية غير متزامنة)")
def voice_prepare(body: PrepareBody):
    try:
        meta = voices.get(body.voice_id)
    except KeyError as e:
        raise err(404, "voice_not_found", "النسخة الصوتية غير موجودة.") from e
    if meta["status"] == "ready":
        return {"job_id": None, "voice": meta}
    if engine_holder.state != "ready":
        raise err(503, "engine_not_ready", "المحرك قيد التحميل. انتظر ثم أعد المحاولة.")
    try:
        job, _ = jobs.submit("prepare", body.voice_id, {}, idempotency_key=f"prepare:{body.voice_id}")
    except JobError as e:
        raise err(429, e.code, e.message) from e
    return {"job_id": job.job_id, "job": job.public(jobs.position(job)), "voice": voices.get(body.voice_id)}


@app.get("/api/voice/status", tags=["voice"], dependencies=[Authorized], summary="حالة نسخة صوتية")
def voice_status(voice_id: str = Query(..., max_length=64)):
    try:
        return voices.get(voice_id)
    except KeyError as e:
        raise err(404, "voice_not_found", "النسخة الصوتية غير موجودة.") from e


@app.get("/api/voices", tags=["voice"], dependencies=[Authorized], summary="قائمة النسخ الصوتية على الخادم")
def voice_list():
    return {"voices": voices.list()}


def _delete_voice(voice_id: str) -> dict:
    try:
        voices.delete(voice_id)
    except KeyError as e:
        raise err(404, "voice_not_found", "النسخة الصوتية غير موجودة.") from e
    jobs.forget_voice(voice_id)
    if engine_holder.engine:
        engine_holder.engine.purge_cache()
    log.info("voice deleted id=%s", voice_id)
    return {"deleted": True, "voice_id": voice_id}


@app.delete("/api/voice", tags=["voice"], dependencies=[Authorized], summary="حذف النسخة الصوتية وعينتها من الخادم")
def voice_delete_q(voice_id: str = Query(..., max_length=64)):
    return _delete_voice(voice_id)


@app.delete("/api/voice/{voice_id}", tags=["voice"], dependencies=[Authorized], summary="حذف النسخة الصوتية وعينتها من الخادم")
def voice_delete(voice_id: str):
    return _delete_voice(voice_id)


@app.delete("/api/voice/{voice_id}/original", tags=["voice"], dependencies=[Authorized],
            summary="حذف العينة الأصلية فقط (يبقى المقطع المرجعي القصير اللازم للتوليد)")
def voice_delete_original(voice_id: str):
    try:
        return voices.delete_original(voice_id)
    except KeyError as e:
        raise err(404, "voice_not_found", "النسخة الصوتية غير موجودة.") from e


# ---------------------------------------------------------------------------
# TTS
# ---------------------------------------------------------------------------

class GenerateBody(BaseModel):
    voice_id: str = Field(..., max_length=64)
    text: str = Field(..., description="النص المراد تحويله إلى كلام")
    language: str = Field("ar", max_length=8)
    speed: float = Field(1.0, ge=0.5, le=2.0)
    style: str | None = Field(None, max_length=32)
    quality: str | None = Field(None, max_length=32)
    request_id: str | None = Field(None, max_length=64, description="معرّف فريد من التطبيق لمنع التكرار")


@app.post("/api/tts/generate", tags=["tts"], dependencies=[Authorized], status_code=202,
          summary="توليد كلام بالصوت المستنسخ (عملية غير متزامنة)")
def tts_generate(body: GenerateBody):
    text = (body.text or "").strip()
    if not text:
        raise err(422, "empty_text", "اكتب نصاً أولاً.")
    if len(text) > settings.max_text_chars:
        raise err(413, "text_too_long", f"النص أطول من الحد المسموح ({settings.max_text_chars} حرف).")
    if not any(ch.isalpha() for ch in text):
        raise err(422, "no_words", "النص لا يحتوي على كلمات قابلة للنطق.")
    try:
        meta = voices.get(body.voice_id)
    except KeyError as e:
        raise err(404, "voice_not_found", "النسخة الصوتية غير موجودة على الخادم.") from e
    if meta["status"] != "ready":
        raise err(409, "voice_not_ready", "النسخة الصوتية لم تُجهز بعد.")
    if engine_holder.state != "ready":
        raise err(503, "engine_not_ready", "المحرك قيد التحميل. انتظر ثم أعد المحاولة.")
    engine = engine_holder.engine
    lang = body.language if body.language in engine.info.languages else ("ar" if has_arabic(text) else "en")
    speed = body.speed if engine.info.supports_speed else 1.0
    lo, hi = engine.info.speed_range
    speed = min(max(speed, lo), hi)
    style = body.style if any(s["id"] == body.style for s in engine.info.styles) else None
    quality = body.quality if any(q["id"] == body.quality for q in engine.info.qualities) else None
    try:
        job, created = jobs.submit("tts", body.voice_id,
                                   {"text": text, "language": lang, "speed": speed, "style": style, "quality": quality},
                                   idempotency_key=body.request_id and f"tts:{body.request_id}")
    except JobError as e:
        raise err(429, e.code, e.message) from e
    log.info("tts submitted job=%s chars=%d new=%s", job.job_id, len(text), created)
    return {"job_id": job.job_id, "job": job.public(jobs.position(job))}


def _job_status(job_id: str) -> dict:
    try:
        job = jobs.get(job_id)
    except KeyError as e:
        raise err(404, "job_not_found", "العملية غير موجودة (ربما أعيد تشغيل الخادم).") from e
    return job.public(jobs.position(job))


@app.get("/api/tts/status", tags=["tts"], dependencies=[Authorized], summary="حالة عملية (توليد أو تجهيز)")
def tts_status_q(job_id: str = Query(..., max_length=64)):
    return _job_status(job_id)


@app.get("/api/tts/status/{job_id}", tags=["tts"], dependencies=[Authorized], summary="حالة عملية (توليد أو تجهيز)")
def tts_status(job_id: str):
    return _job_status(job_id)


# ---------------------------------------------------------------------------
# Audio files
# ---------------------------------------------------------------------------

@app.get("/api/audio/{audio_id}", tags=["audio"], dependencies=[Authorized],
         summary="تنزيل الملف الصوتي الناتج (روابط مؤقتة ومحمية)")
def audio_get(audio_id: str, format: Literal["wav", "mp3", "m4a"] = "wav"):
    try:
        path = audio_store.file_for(audio_id, format)
    except KeyError as e:
        raise err(404, "audio_not_found", "الملف غير موجود أو انتهت صلاحيته.") from e
    except audio_utils.AudioError as e:
        raise err(500, e.code, e.message) from e
    media = {"wav": "audio/wav", "mp3": "audio/mpeg", "m4a": "audio/mp4"}[format]
    return FileResponse(path, media_type=media, filename=f"sawti_{audio_id[-8:]}.{format}")


@app.get("/api/audio/{audio_id}/info", tags=["audio"], dependencies=[Authorized], summary="معلومات الملف قبل تنزيله")
def audio_info(audio_id: str):
    try:
        return audio_store.meta(audio_id)
    except KeyError as e:
        raise err(404, "audio_not_found", "الملف غير موجود أو انتهت صلاحيته.") from e


@app.delete("/api/audio/{audio_id}", tags=["audio"], dependencies=[Authorized], summary="حذف ملف صوتي من الخادم")
def audio_delete(audio_id: str):
    try:
        ok = audio_store.delete(audio_id)
    except KeyError:
        ok = False
    if not ok:
        raise err(404, "audio_not_found", "الملف غير موجود.")
    return {"deleted": True, "audio_id": audio_id}


@app.delete("/api/data", tags=["privacy"], dependencies=[Authorized],
            summary="حذف جميع البيانات من الخادم (كل النسخ الصوتية والملفات)")
def delete_all_data():
    n_voices = voices.delete_all()
    n_audio = audio_store.delete_all()
    for d in (settings.uploads_dir,):
        for p in d.iterdir():
            p.unlink(missing_ok=True)
    if engine_holder.engine:
        engine_holder.engine.purge_cache()
    jobs.cleanup(max_age=0)
    return {"deleted": True, "voices": n_voices, "files": n_audio}


@app.get("/", include_in_schema=False)
def root():
    return {"name": "Sawti AI backend", "docs": "/docs", "health": "/health"}
