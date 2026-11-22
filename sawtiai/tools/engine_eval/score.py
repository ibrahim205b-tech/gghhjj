"""Score generated audio objectively.

For every wav produced by run_engine.py:
  * ASR round-trip with Whisper large-v3-turbo (faster-whisper, CPU int8):
    character error rate (CER) against what was asked for.
  * Speaker similarity: cosine similarity of Resemblyzer d-vectors between the
    reference voice and the output (same speaker typically > ~0.80; a different
    speaker typically < ~0.75). A different-voice baseline is included.
  * Audio sanity: duration, peak level, clipping, longest internal silence.

Writes report.md and scores.json. This is an objective proxy - a human still
has to listen to judge naturalness.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "backend"))
from app.text.arabic import normalize_arabic  # noqa: E402

_PUNCT = re.compile(r"[^ء-ي\s]")


def canon(text: str) -> str:
    t = normalize_arabic(text, keep_tashkeel=False)
    t = re.sub(r"[إأآٱ]", "ا", t).replace("ة", "ه").replace("ى", "ي").replace("ؤ", "و").replace("ئ", "ي")
    t = _PUNCT.sub(" ", t)
    return " ".join(t.split())


def edit_distance(a, b) -> int:
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def cer(ref: str, hyp: str) -> float:
    r, h = canon(ref).replace(" ", ""), canon(hyp).replace(" ", "")
    return edit_distance(r, h) / max(len(r), 1)


def wer(ref: str, hyp: str) -> float:
    r, h = canon(ref).split(), canon(hyp).split()
    return edit_distance(r, h) / max(len(r), 1)


def audio_stats(path: Path) -> dict:
    y, sr = sf.read(str(path), always_2d=False)
    if y.ndim > 1:
        y = y.mean(axis=1)
    peak = float(np.max(np.abs(y))) if y.size else 0.0
    clip = float(np.mean(np.abs(y) > 0.999)) if y.size else 0.0
    frame = int(sr * 0.02)
    n = len(y) // frame
    longest = 0.0
    if n:
        e = np.sqrt(np.mean(y[: n * frame].reshape(n, frame) ** 2, axis=1))
        thr = max(1e-4, 0.02 * float(np.max(e)))
        silent = e < thr
        # ignore leading/trailing silence
        idx = np.where(~silent)[0]
        if idx.size:
            inner = silent[idx[0]: idx[-1] + 1]
            run = best = 0
            for s in inner:
                run = run + 1 if s else 0
                best = max(best, run)
            longest = best * 0.02
    return {"duration": round(len(y) / sr, 2), "sr": sr, "peak": round(peak, 3),
            "clipped_ratio": round(clip, 5), "longest_inner_silence_s": round(longest, 2)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio-dir", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    from faster_whisper import WhisperModel
    from resemblyzer import VoiceEncoder, preprocess_wav

    texts = {t["id"]: t for t in json.loads((HERE / "texts.json").read_text(encoding="utf-8"))}
    asr = WhisperModel("large-v3-turbo", device="cpu", compute_type="int8")
    enc = VoiceEncoder("cpu")
    ref_emb = enc.embed_utterance(preprocess_wav(args.ref))

    metrics = {}
    for mf in Path(args.audio_dir).rglob("metrics_*.json"):
        m = json.loads(mf.read_text(encoding="utf-8"))
        metrics[m["engine"]] = m

    rows = []
    for wav in sorted(Path(args.audio_dir).rglob("*.wav")):
        variant, tid = wav.stem.split("__", 1)
        item = texts[tid]
        segs, _ = asr.transcribe(str(wav), language="ar", beam_size=5, vad_filter=False)
        hyp = " ".join(s.text.strip() for s in segs)
        target = item.get("spoken", item["text"])
        emb = enc.embed_utterance(preprocess_wav(str(wav)))
        sim = float(np.dot(ref_emb, emb) / (np.linalg.norm(ref_emb) * np.linalg.norm(emb)))
        row = {"variant": variant, "id": tid, "kind": item["kind"], "asr": hyp,
               "cer": round(cer(target, hyp), 3), "wer": round(wer(target, hyp), 3),
               "speaker_sim": round(sim, 3), **audio_stats(wav)}
        for m in metrics.values():
            for it in m["items"]:
                if it["variant"] == variant and it["id"] == tid:
                    row["gen_seconds"] = it.get("gen_seconds")
                    row["rtf"] = it.get("rtf")
        rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)

    # Aggregate per variant
    agg = {}
    for r in rows:
        a = agg.setdefault(r["variant"], {"n": 0, "cer": 0.0, "wer": 0.0, "sim": 0.0, "rtf": 0.0, "rtf_n": 0})
        a["n"] += 1
        a["cer"] += r["cer"]
        a["wer"] += r["wer"]
        a["sim"] += r["speaker_sim"]
        if r.get("rtf") is not None:
            a["rtf"] += r["rtf"]
            a["rtf_n"] += 1

    lines = ["# Sawti AI — engine evaluation (real CPU runs)", ""]
    lines.append("| engine/variant | files | mean CER ↓ | mean WER ↓ | speaker sim ↑ | mean RTF (CPU) ↓ | load s | peak RAM MB |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for v, a in agg.items():
        eng = next((m for k, m in metrics.items() if v.startswith(k)), {})
        lines.append(
            f"| {v} | {a['n']} | {a['cer']/a['n']:.3f} | {a['wer']/a['n']:.3f} | {a['sim']/a['n']:.3f} | "
            f"{(a['rtf']/a['rtf_n']) if a['rtf_n'] else float('nan'):.2f} | {eng.get('load_seconds','')} | {eng.get('peak_rss_mb','')} |")
    lines += ["", "## Per file", "",
              "| variant | text | kind | CER | sim | dur s | RTF | longest gap s | ASR transcript |",
              "|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['variant']} | {r['id']} | {r['kind']} | {r['cer']} | {r['speaker_sim']} | {r['duration']} | "
                     f"{r.get('rtf','')} | {r['longest_inner_silence_s']} | {r['asr']} |")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out / "scores.json").write_text(json.dumps({"rows": rows, "metrics": metrics}, ensure_ascii=False, indent=2), encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
