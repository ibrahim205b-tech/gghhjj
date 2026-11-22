"""Transcribe smoke-test outputs with Whisper and compare to the requested text.

  python tools/asr_check.py --dir smoke_out --ref reference.wav [--max-cer 0.35]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent / "engine_eval"))
from score import audio_stats, cer  # noqa: E402

SPOKEN = {"الرقم 07700240001، والتاريخ 22 نوفمبر 2026.":
          "الرقم صفر سبعة سبعة صفر صفر اثنين أربعة صفر صفر صفر واحد والتاريخ اثنين وعشرين نوفمبر ألفين وستة وعشرين"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--max-cer", type=float, default=0.35)
    args = ap.parse_args()
    from faster_whisper import WhisperModel
    from resemblyzer import VoiceEncoder, preprocess_wav

    rep = json.loads((Path(args.dir) / "smoke_report.json").read_text(encoding="utf-8"))
    asr = WhisperModel("large-v3-turbo", device="cpu", compute_type="int8")
    enc = VoiceEncoder("cpu")
    ref = enc.embed_utterance(preprocess_wav(args.ref))
    worst = 0.0
    lines = ["| # | text | ASR | CER | speaker sim | dur s | RTF |", "|---|---|---|---|---|---|---|"]
    for i, f in enumerate(rep["files"], 1):
        p = Path(args.dir) / f["file"]
        segs, _ = asr.transcribe(str(p), language="ar", beam_size=5)
        hyp = " ".join(s.text.strip() for s in segs)
        c = cer(SPOKEN.get(f["text"], f["text"]), hyp)
        e = enc.embed_utterance(preprocess_wav(str(p)))
        sim = float(np.dot(ref, e) / (np.linalg.norm(ref) * np.linalg.norm(e)))
        st = audio_stats(p)
        worst = max(worst, c)
        lines.append(f"| {i} | {f['text']} | {hyp} | {c:.3f} | {sim:.3f} | {st['duration']} | {f['rtf']} |")
    print("\n".join(lines))
    Path(args.dir, "asr_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if worst > args.max_cer:
        print(f"worst CER {worst:.3f} > {args.max_cer}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
