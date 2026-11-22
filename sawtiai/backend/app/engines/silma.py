"""SILMA TTS v1 (F5-TTS architecture, 150M params, Arabic + English).

Code: MIT (https://github.com/SILMA-AI/silma-tts)
Weights: Apache-2.0 (https://huggingface.co/silma-ai/silma-tts)
Zero-shot cloning from a short reference clip + its transcript.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np

from .base import Engine, EngineInfo, VoiceProfile

QUALITY_STEPS = {"fast": 12, "balanced": 16, "high": 32}


class SilmaEngine(Engine):
    info = EngineInfo(
        id="silma",
        name="SILMA TTS v1",
        version="silma-tts 1.0.5",
        license="الكود: MIT — الأوزان: Apache-2.0 (يسمح بالاستخدام الشخصي والتجاري)",
        source_url="https://github.com/SILMA-AI/silma-tts",
        model_url="https://huggingface.co/silma-ai/silma-tts",
        languages=["ar", "en"],
        sample_rate=24000,
        min_sample_seconds=3.0,
        recommended_sample_seconds=7.0,
        max_useful_sample_seconds=8.0,
        needs_transcript=True,
        supports_speed=True,
        speed_range=(0.7, 1.3),
        styles=[],
        qualities=[
            {"id": "fast", "label": "سريع"},
            {"id": "balanced", "label": "متوازن"},
            {"id": "high", "label": "جودة عالية (أبطأ)"},
        ],
        max_chunk_chars=200,
        notes="يستنسخ الصوت من عينة قصيرة (حتى 8 ثوانٍ) مع نصها. يضيف التشكيل تلقائياً بنموذج CATT لتحسين النطق.",
    )

    def __init__(self, force_tashkeel: bool = True) -> None:
        self._tts = None
        self.force_tashkeel = force_tashkeel

    def load(self) -> None:
        from silma_tts.api import SilmaTTS
        # Numbers/dates are normalized by app.text.arabic, so the (slow to
        # compile) NeMo grammars are not loaded.
        self._tts = SilmaTTS(device="cpu", enable_normalizer=False, force_tashkeel=self.force_tashkeel)

    def _model(self):
        if self._tts is None:
            raise RuntimeError("engine_not_loaded")
        return self._tts

    def prepare_voice(self, voice_id: str, sample_wav: Path, transcript: str, workdir: Path) -> VoiceProfile:
        from silma_tts.infer.utils_infer import preprocess_ref_audio_text
        self._model()
        # SILMA clips the reference to <= 8 s on silence and re-transcribes with
        # Whisper if it had to cut, or if no transcript was given.
        ref_path, ref_text = preprocess_ref_audio_text(str(sample_wav), transcript or "", show_info=lambda *_: None)
        ref_text = (ref_text or "").strip()
        if not ref_text:
            raise RuntimeError("transcript_failed")
        dst = workdir / "reference.wav"
        shutil.copyfile(ref_path, dst)
        self.purge_cache()
        return VoiceProfile(voice_id=voice_id, reference_wav=dst, transcript=ref_text)

    def purge_cache(self) -> None:
        """SILMA keeps preprocessed copies of reference clips in temp files;
        remove them so no voice data lingers after a voice is deleted."""
        try:
            from silma_tts.infer import utils_infer as u
        except ImportError:
            return
        for p in list(getattr(u, "_ref_audio_cache", {}).values()):
            try:
                Path(p).unlink(missing_ok=True)
            except OSError:
                pass
        getattr(u, "_ref_audio_cache", {}).clear()
        getattr(u, "_ref_text_cache", {}).clear()

    def synthesize(self, text: str, profile: VoiceProfile, *, language: str, speed: float,
                   style: str | None, quality: str | None) -> np.ndarray:
        wav, sr, _ = self._model().infer(
            ref_file=str(profile.reference_wav),
            ref_text=profile.transcript,
            gen_text=text,
            speed=float(speed),
            nfe_step=QUALITY_STEPS.get(quality or "balanced", 16),
            normalize_numbers=False,  # done by app.text.arabic (phone/date aware)
            force_tashkeel=self.force_tashkeel,
            seed=None,
            show_info=lambda *_: None,
        )
        return np.asarray(wav, dtype=np.float32).reshape(-1)
