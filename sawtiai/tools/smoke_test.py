"""End-to-end test against a REAL running Sawti AI server (local or hosted).

  python tools/smoke_test.py --url https://<space>.hf.space --sample my_voice.wav \
      --transcript "النص الذي قلته في العينة" --out results/

API key is read from the SAWTI_API_KEY environment variable (never a flag, so it
does not end up in shell history or CI logs).

Steps: health -> wait for engine -> auth checks -> reject bad file -> upload ->
prepare -> generate the Arabic test sentences -> download and verify each WAV ->
delete audio -> delete voice -> confirm deletion. Exit code != 0 on any failure.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import time
import wave
from pathlib import Path

import httpx

TEXTS = [
    "مرحباً بك، هذا اختبار لتوليد الكلام باللغة العربية.",
    "أهلاً وسهلاً، شلونكم؟ اليوم راح نجرب نظام استنساخ الصوت.",
    "أريد إنشاء تسجيل صوتي واضح وطبيعي باللغة العربية.",
    "الرقم 07700240001، والتاريخ 22 نوفمبر 2026.",
]


class Fail(Exception):
    pass


def check(cond: bool, msg: str) -> None:
    if not cond:
        raise Fail(msg)
    print(f"  ✔ {msg}", flush=True)


def wait_job(c: httpx.Client, job_id: str, timeout: float) -> dict:
    end = time.time() + timeout
    last = None
    while time.time() < end:
        r = c.get(f"/api/tts/status/{job_id}")
        r.raise_for_status()
        j = r.json()
        if (j["status"], j.get("chunks_done")) != last:
            last = (j["status"], j.get("chunks_done"))
            print(f"    job {j['status']} {j.get('chunks_done')}/{j.get('chunks_total')}", flush=True)
        if j["status"] in ("done", "failed"):
            return j
        time.sleep(2)
    raise Fail(f"job {job_id} timed out after {timeout}s")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--sample", required=True)
    ap.add_argument("--transcript", default="")
    ap.add_argument("--out", default="smoke_out")
    ap.add_argument("--engine-wait", type=float, default=1800)
    ap.add_argument("--job-timeout", type=float, default=1800)
    ap.add_argument("--keep", action="store_true", help="do not delete the voice at the end")
    args = ap.parse_args()
    key = os.environ.get("SAWTI_API_KEY", "")
    if not key:
        print("SAWTI_API_KEY is not set", file=sys.stderr)
        return 2
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    report: dict = {"url": args.url, "steps": [], "files": []}
    base = args.url.rstrip("/")
    t_start = time.time()

    try:
        with httpx.Client(base_url=base, timeout=httpx.Timeout(120, connect=30)) as anon:
            print("1. health")
            t = time.time()
            end = t + args.engine_wait
            while True:
                try:
                    r = anon.get("/health")
                    if r.status_code == 200 and r.json().get("engine_state") == "ready":
                        break
                    state = r.json().get("engine_state") if r.status_code == 200 else r.status_code
                except (httpx.HTTPError, ValueError) as e:
                    state = type(e).__name__
                if time.time() > end:
                    raise Fail(f"engine not ready after {args.engine_wait}s (state={state})")
                print(f"    waiting for engine: {state}", flush=True)
                time.sleep(10)
            report["engine_ready_wait_s"] = round(time.time() - t, 1)
            check(True, f"server healthy, engine ready (waited {report['engine_ready_wait_s']}s)")
            print("2. auth")
            check(anon.get("/api/status").status_code == 401, "status without key -> 401")
            check(anon.get("/api/status", headers={"Authorization": "Bearer wrong-key"}).status_code == 401,
                  "wrong key -> 401")

        with httpx.Client(base_url=base, headers={"Authorization": f"Bearer {key}"},
                          timeout=httpx.Timeout(300, connect=30)) as c:
            st = c.get("/api/status").json()
            report["engine"] = st["engine"]
            check(st["engine_state"] == "ready", f"engine {st['engine'].get('name')} ready")

            print("3. validation")
            r = c.post("/api/voice/upload", files={"file": ("x.txt", b"not audio", "text/plain")})
            check(r.status_code == 415, "non-audio file rejected (415)")
            r = c.post("/api/voice/upload", files={"file": ("x.mp3", b"\x00" * 4096, "audio/mpeg")})
            check(r.status_code in (415, 422), f"fake mp3 rejected ({r.status_code})")
            r = c.post("/api/tts/generate", json={"voice_id": "voice_nonexistent", "text": "مرحبا"})
            check(r.status_code == 404, "unknown voice -> 404")

            print("4. upload sample")
            sample = Path(args.sample)
            with sample.open("rb") as f:
                r = c.post("/api/voice/upload", files={"file": (sample.name, f, "application/octet-stream")},
                           data={"name": "smoke", "transcript": args.transcript})
            check(r.status_code == 201, f"upload accepted ({r.status_code}) {r.text[:200] if r.status_code != 201 else ''}")
            voice = r.json()
            report["quality"] = voice["quality"]
            vid = voice["voice_id"]
            print(f"    quality: {voice['quality']['label']} score={voice['quality']['score']}")

            print("5. prepare voice")
            r = c.post("/api/voice/prepare", json={"voice_id": vid})
            check(r.status_code == 202, "prepare accepted")
            t = time.time()
            j = wait_job(c, r.json()["job_id"], args.job_timeout)
            check(j["status"] == "done", f"voice prepared in {time.time()-t:.1f}s ({j.get('error_message') or 'ok'})")
            check(c.get("/api/voice/status", params={"voice_id": vid}).json()["status"] == "ready", "voice status = ready")

            print("6. generate")
            for i, text in enumerate(TEXTS, 1):
                t = time.time()
                r = c.post("/api/tts/generate", json={"voice_id": vid, "text": text, "request_id": f"smoke-{t}-{i}"})
                check(r.status_code == 202, f"[{i}] generate accepted")
                j = wait_job(c, r.json()["job_id"], args.job_timeout)
                check(j["status"] == "done", f"[{i}] generated ({j.get('error_message') or 'ok'})")
                gen_s = time.time() - t
                aid = j["result"]["audio_id"]
                r = c.get(f"/api/audio/{aid}")
                check(r.status_code == 200 and r.content[:4] == b"RIFF", f"[{i}] WAV downloaded ({len(r.content)} bytes)")
                with wave.open(io.BytesIO(r.content)) as w:
                    dur = w.getnframes() / w.getframerate()
                check(dur > 0.8, f"[{i}] audio duration {dur:.2f}s")
                p = out / f"smoke_{i}.wav"
                p.write_bytes(r.content)
                report["files"].append({"text": text, "file": p.name, "duration_s": round(dur, 2),
                                        "wall_seconds": round(gen_s, 1), "rtf": round(gen_s / dur, 2)})
                check(anon_status(base, aid) == 401, f"[{i}] audio not reachable without key")
                check(c.delete(f"/api/audio/{aid}").status_code == 200, f"[{i}] audio deleted on server")
                check(c.get(f"/api/audio/{aid}").status_code == 404, f"[{i}] deleted audio -> 404")

            print("7. cleanup")
            if not args.keep:
                check(c.delete(f"/api/voice/{vid}").status_code == 200, "voice deleted")
                check(c.get("/api/voice/status", params={"voice_id": vid}).status_code == 404, "deleted voice -> 404")
        report["ok"] = True
    except (Fail, httpx.HTTPError) as e:
        report["ok"] = False
        report["error"] = f"{type(e).__name__}: {e}"
        print(f"  ✘ {report['error']}", flush=True)
    report["total_seconds"] = round(time.time() - t_start, 1)
    (out / "smoke_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1


def anon_status(base: str, aid: str) -> int:
    return httpx.get(f"{base}/api/audio/{aid}", timeout=60).status_code


if __name__ == "__main__":
    sys.exit(main())
