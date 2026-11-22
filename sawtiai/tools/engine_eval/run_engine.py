"""Generate the Arabic evaluation set with one real TTS engine.

Usage:
  python run_engine.py --engine silma|chatterbox|xtts --ref REF.wav \
      --ref-text "..." --out OUTDIR

Writes OUTDIR/<variant>__<text_id>.wav and OUTDIR/metrics_<engine>.json.
Nothing here is simulated: if an engine fails, the error is recorded and the
job fails.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import resource
import sys
import time
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "backend"))
from app.text.arabic import normalize_arabic  # noqa: E402


def rss_mb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0


def audio_seconds(path: Path) -> float:
    import soundfile as sf
    info = sf.info(str(path))
    return info.frames / float(info.samplerate)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", required=True, choices=["silma", "chatterbox", "xtts"])
    ap.add_argument("--ref", required=True)
    ap.add_argument("--ref-text", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    texts = json.loads((HERE / "texts.json").read_text(encoding="utf-8"))
    import torch
    torch.set_num_threads(os.cpu_count() or 2)

    results: dict = {
        "engine": args.engine,
        "python": platform.python_version(),
        "torch": torch.__version__,
        "cpu_count": os.cpu_count(),
        "device": "cpu",
        "items": [],
    }

    t0 = time.time()
    if args.engine == "silma":
        from silma_tts.api import SilmaTTS
        model = SilmaTTS(device="cpu")

        def synth(text: str, path: Path, variant: str) -> None:
            model.infer(
                ref_file=args.ref, ref_text=args.ref_text, gen_text=text,
                file_wave=str(path), seed=1234,
                normalize_numbers=(variant == "silma_nemo_numbers"),
                force_tashkeel=(variant != "silma_no_tashkeel"),
            )

        variants = ["silma", "silma_no_tashkeel", "silma_nemo_numbers"]
    elif args.engine == "chatterbox":
        import torchaudio as ta
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        model = ChatterboxMultilingualTTS.from_pretrained(device="cpu")

        def synth(text: str, path: Path, variant: str) -> None:
            kw = {} if variant == "chatterbox_default_voice" else {"audio_prompt_path": args.ref}
            wav = model.generate(text, language_id="ar", **kw)
            ta.save(str(path), wav, model.sr)

        variants = ["chatterbox", "chatterbox_default_voice"]
    else:
        os.environ["COQUI_TOS_AGREED"] = "1"
        from TTS.api import TTS
        model = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to("cpu")

        def synth(text: str, path: Path, variant: str) -> None:
            model.tts_to_file(text=text, speaker_wav=args.ref, language="ar", file_path=str(path))

        variants = ["xtts"]
    results["load_seconds"] = round(time.time() - t0, 2)
    results["rss_after_load_mb"] = round(rss_mb(), 1)
    print(f"[{args.engine}] model loaded in {results['load_seconds']}s, RSS {results['rss_after_load_mb']} MB", flush=True)

    failures = 0
    for variant in variants:
        for item in texts:
            # Secondary variants only run on the texts where they tell us something.
            if variant == "silma_nemo_numbers" and item["id"] != "t4_numbers":
                continue
            if variant == "silma_no_tashkeel" and item["id"] not in ("t1_msa", "t2_iraqi", "t5_iraqi2"):
                continue
            if variant == "chatterbox_default_voice" and item["id"] != "t1_msa":
                continue
            text = item["text"] if variant == "silma_nemo_numbers" else normalize_arabic(item["text"])
            path = out / f"{variant}__{item['id']}.wav"
            rec = {"variant": variant, "id": item["id"], "input_text": text}
            try:
                t = time.time()
                synth(text, path, variant)
                rec["gen_seconds"] = round(time.time() - t, 2)
                rec["audio_seconds"] = round(audio_seconds(path), 2)
                rec["rtf"] = round(rec["gen_seconds"] / max(rec["audio_seconds"], 1e-6), 2)
                rec["bytes"] = path.stat().st_size
                print(f"[{variant}] {item['id']}: {rec['audio_seconds']}s audio in {rec['gen_seconds']}s (RTF {rec['rtf']})", flush=True)
            except Exception as e:  # recorded, and the job fails below
                failures += 1
                rec["error"] = f"{type(e).__name__}: {e}"
                traceback.print_exc()
            results["items"].append(rec)
    results["peak_rss_mb"] = round(rss_mb(), 1)
    (out / f"metrics_{args.engine}.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
