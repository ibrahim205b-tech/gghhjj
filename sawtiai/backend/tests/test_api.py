"""API behaviour: auth, validation, voice lifecycle, generation, deletion."""

from __future__ import annotations

import io
import time

import soundfile as sf

from conftest import AUTH, ToneTestEngine, make_speech_like, to_format, wait_job


def upload(client, path, name="صوتي", transcript="مرحبا هذا صوتي", mime="audio/wav"):
    with open(path, "rb") as f:
        return client.post("/api/voice/upload", headers=AUTH,
                           files={"file": (path.name, f, mime)},
                           data={"name": name, "transcript": transcript})


def ready_voice(client, path) -> str:
    r = upload(client, path)
    assert r.status_code == 201, r.text
    vid = r.json()["voice_id"]
    r = client.post("/api/voice/prepare", headers=AUTH, json={"voice_id": vid})
    assert r.status_code == 202, r.text
    j = wait_job(client, r.json()["job_id"])
    assert j["status"] == "done", j
    return vid


# -- health / auth -----------------------------------------------------------

def test_health_is_public(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_api_requires_key(client):
    assert client.get("/api/status").status_code == 401
    assert client.get("/api/status", headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.post("/api/tts/generate", json={"voice_id": "x", "text": "مرحبا"}).status_code == 401


def test_x_api_key_header_also_works(client):
    from conftest import API_KEY
    assert client.get("/api/status", headers={"X-API-Key": API_KEY}).status_code == 200


def test_status(client):
    r = client.get("/api/status", headers=AUTH)
    assert r.status_code == 200
    body = r.json()
    assert body["engine_state"] == "ready"
    assert body["limits"]["max_text_chars"] > 0


def test_openapi_documents_all_routes(client):
    paths = client.get("/openapi.json").json()["paths"]
    for p in ["/health", "/api/status", "/api/voice/upload", "/api/voice/prepare", "/api/voice/status",
              "/api/voice", "/api/tts/generate", "/api/tts/status", "/api/audio/{audio_id}", "/api/data"]:
        assert p in paths, p


# -- upload validation ---------------------------------------------------------

def test_upload_wav_mp3_m4a(client, tmp_audio):
    for ext, mime in [(".wav", "audio/wav"), (".mp3", "audio/mpeg"), (".m4a", "audio/mp4")]:
        path = tmp_audio if ext == ".wav" else to_format(tmp_audio, ext)
        r = upload(client, path, mime=mime)
        assert r.status_code == 201, (ext, r.text)
        body = r.json()
        assert body["status"] == "uploaded"
        assert 5.5 < body["quality"]["duration_seconds"] < 6.6
        assert body["quality"]["label"]


def test_reject_unsupported_extension(client, tmp_path):
    p = tmp_path / "notes.txt"
    p.write_text("hello")
    r = upload(client, p, mime="text/plain")
    assert r.status_code == 415
    assert r.json()["detail"]["code"] == "unsupported_type"


def test_reject_fake_audio_with_audio_extension(client, tmp_path):
    p = tmp_path / "fake.mp3"
    p.write_bytes(b"this is not audio at all" * 100)
    r = upload(client, p, mime="audio/mpeg")
    assert r.status_code in (415, 422)
    assert r.json()["detail"]["code"] in ("invalid_audio", "no_audio_stream", "unsupported_codec")


def test_reject_empty_file(client, tmp_path):
    p = tmp_path / "empty.wav"
    p.write_bytes(b"")
    r = upload(client, p)
    assert r.status_code == 400


def test_reject_too_short(client, tmp_path):
    p = make_speech_like(tmp_path / "short.wav", seconds=1.0)
    r = upload(client, p)
    assert r.status_code == 422
    assert r.json()["detail"]["code"] == "sample_too_short"


def test_reject_too_large(client, tmp_path, monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, "max_upload_mb", 0)
    p = make_speech_like(tmp_path / "big.wav", seconds=4)
    r = upload(client, p)
    assert r.status_code == 413


def test_reject_silence(client, tmp_path):
    p = tmp_path / "silence.wav"
    sf.write(str(p), [0.0] * 24000 * 5, 24000)
    r = upload(client, p)
    assert r.status_code == 422


# -- voice lifecycle ------------------------------------------------------------

def test_prepare_and_status_and_delete(client, tmp_audio):
    vid = ready_voice(client, tmp_audio)
    r = client.get("/api/voice/status", params={"voice_id": vid}, headers=AUTH)
    assert r.status_code == 200 and r.json()["status"] == "ready"
    assert vid in [v["voice_id"] for v in client.get("/api/voices", headers=AUTH).json()["voices"]]
    # delete original only
    r = client.delete(f"/api/voice/{vid}/original", headers=AUTH)
    assert r.status_code == 200 and r.json()["has_original"] is False
    # still usable for generation (reference clip kept)
    r = client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "مرحبا"})
    assert wait_job(client, r.json()["job_id"])["status"] == "done"
    # full delete
    assert client.delete("/api/voice", params={"voice_id": vid}, headers=AUTH).status_code == 200
    assert client.get("/api/voice/status", params={"voice_id": vid}, headers=AUTH).status_code == 404
    assert client.delete(f"/api/voice/{vid}", headers=AUTH).status_code == 404


def test_path_traversal_ids_rejected(client):
    for bad in ["../../etc/passwd", "voice_../x", "voice_" + "a" * 100]:
        r = client.get("/api/voice/status", params={"voice_id": bad}, headers=AUTH)
        assert r.status_code in (404, 422)
    assert client.get("/api/audio/..%2F..%2Fetc", headers=AUTH).status_code == 404


# -- generation -----------------------------------------------------------------

def test_generate_returns_real_audio(client, tmp_audio):
    vid = ready_voice(client, tmp_audio)
    text = "الرقم 07700240001، والتاريخ 22 نوفمبر 2026. " * 3
    r = client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": text, "speed": 1.0})
    assert r.status_code == 202, r.text
    j = wait_job(client, r.json()["job_id"])
    assert j["status"] == "done", j
    assert j["chunks_total"] > 1 and j["chunks_done"] == j["chunks_total"]
    audio_id = j["result"]["audio_id"]
    info = client.get(f"/api/audio/{audio_id}/info", headers=AUTH).json()
    assert info["size_bytes"] > 1000
    r = client.get(f"/api/audio/{audio_id}", headers=AUTH)
    assert r.status_code == 200 and r.headers["content-type"] == "audio/wav"
    y, sr = sf.read(io.BytesIO(r.content))
    assert sr == 16000 and len(y) / sr > 1.0
    r = client.get(f"/api/audio/{audio_id}", params={"format": "mp3"}, headers=AUTH)
    assert r.status_code == 200 and r.headers["content-type"] == "audio/mpeg" and len(r.content) > 500
    # audio requires auth
    assert client.get(f"/api/audio/{audio_id}").status_code == 401
    assert client.delete(f"/api/audio/{audio_id}", headers=AUTH).status_code == 200
    assert client.get(f"/api/audio/{audio_id}", headers=AUTH).status_code == 404


def test_generate_validation(client, tmp_audio):
    vid = ready_voice(client, tmp_audio)
    assert client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "   "}).status_code == 422
    assert client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "123 ..."}).status_code == 422
    assert client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "ا" * 5000}).status_code == 413
    assert client.post("/api/tts/generate", headers=AUTH, json={"voice_id": "voice_nope", "text": "مرحبا"}).status_code == 404
    assert client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid}).status_code == 422


def test_generate_unprepared_voice_conflict(client, tmp_audio):
    vid = upload(client, tmp_audio).json()["voice_id"]
    r = client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "مرحبا"})
    assert r.status_code == 409


def test_duplicate_request_id_is_deduplicated(client, tmp_audio):
    vid = ready_voice(client, tmp_audio)
    body = {"voice_id": vid, "text": "مرحبا بكم", "request_id": "req-abc-1"}
    a = client.post("/api/tts/generate", headers=AUTH, json=body).json()["job_id"]
    b = client.post("/api/tts/generate", headers=AUTH, json=body).json()["job_id"]
    assert a == b


def test_engine_failure_reported_not_faked(client, tmp_audio):
    vid = ready_voice(client, tmp_audio)
    ToneTestEngine.fail_next = True
    r = client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "مرحبا"})
    j = wait_job(client, r.json()["job_id"])
    assert j["status"] == "failed"
    assert j["error_code"] == "engine_error"
    assert j["result"] is None


def test_timeout(client, tmp_audio, monkeypatch):
    from app.config import settings
    vid = ready_voice(client, tmp_audio)
    monkeypatch.setattr(settings, "job_timeout_seconds", 0)
    ToneTestEngine.delay = 0.05
    try:
        r = client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "جملة. " * 30})
        time.sleep(0.1)
        j = wait_job(client, r.json()["job_id"])
    finally:
        ToneTestEngine.delay = 0.0
    assert j["status"] == "failed" and j["error_code"] == "timeout"


def test_engine_not_ready(client, tmp_audio, monkeypatch):
    from app.service import engine_holder
    vid = ready_voice(client, tmp_audio)
    monkeypatch.setattr(engine_holder, "state", "loading")
    r = client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "مرحبا"})
    assert r.status_code == 503 and r.json()["detail"]["code"] == "engine_not_ready"


def test_unknown_job(client):
    assert client.get("/api/tts/status/job_doesnotexist", headers=AUTH).status_code == 404
    assert client.get("/api/tts/status", params={"job_id": "job_x"}, headers=AUTH).status_code == 404


def test_delete_all_data(client, tmp_audio):
    ready_voice(client, tmp_audio)
    r = client.delete("/api/data", headers=AUTH)
    assert r.status_code == 200 and r.json()["voices"] >= 1
    assert client.get("/api/voices", headers=AUTH).json()["voices"] == []


def test_expired_audio_cleanup(client, tmp_audio):
    from app.config import settings
    from app.service import cleanup_once
    vid = ready_voice(client, tmp_audio)
    r = client.post("/api/tts/generate", headers=AUTH, json={"voice_id": vid, "text": "مرحبا"})
    aid = wait_job(client, r.json()["job_id"])["result"]["audio_id"]
    old = settings.audio_ttl_minutes
    import json
    meta_p = settings.audio_dir / f"{aid}.json"
    m = json.loads(meta_p.read_text())
    m["expires_at"] = 0
    meta_p.write_text(json.dumps(m))
    assert cleanup_once()["audio"] >= 1
    assert not (settings.audio_dir / f"{aid}.wav").exists()
    settings.audio_ttl_minutes = old
