"""Chatterbox Multilingual (Resemble AI) - backup engine.

Code and weights: MIT (https://github.com/resemble-ai/chatterbox,
https://huggingface.co/ResembleAI/chatterbox). 23 languages including Arabic.
Outputs carry Resemble's inaudible PerTh watermark.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import numpy as np

from .base import Engine, EngineInfo, VoiceProfile

STYLE_EXAGGERATION = {"calm": 0.3, "natural": 0.5, "expressive": 0.8}


class ChatterboxEngine(Engine):
    info = EngineInfo(
        id="chatterbox",
        name="Chatterbox Multilingual",
        version="chatterbox-tts 0.1.7",
        license="MIT (الكود والأوزان) — يضيف علامة مائية غير مسموعة PerTh",
        source_url="https://github.com/resemble-ai/chatterbox",
        model_url="https://huggingface.co/ResembleAI/chatterbox",
        languages=["ar", "en", "fr", "de", "es", "tr"],
        sample_rate=24000,
        min_sample_seconds=5.0,
        recommended_sample_seconds=10.0,
        max_useful_sample_seconds=15.0,
        needs_transcript=False,
        supports_speed=False,
        styles=[{"id": "calm", "label": "هادئ"}, {"id": "natural", "label": "طبيعي"},
                {"id": "expressive", "label": "معبّر"}],
        qualities=[],
        max_chunk_chars=250,
        notes="لا يحتاج نص العينة. أبطأ على المعالج من SILMA.",
    )

    def __init__(self) -> None:
        self._m = None

    def load(self) -> None:
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        self._m = ChatterboxMultilingualTTS.from_pretrained(device="cpu")
        self.info.sample_rate = int(self._m.sr)

    def prepare_voice(self, voice_id: str, sample_wav: Path, transcript: str, workdir: Path) -> VoiceProfile:
        if self._m is None:
            raise RuntimeError("engine_not_loaded")
        dst = workdir / "reference.wav"
        shutil.copyfile(sample_wav, dst)
        self._m.prepare_conditionals(str(dst))  # validates that conditioning works
        return VoiceProfile(voice_id=voice_id, reference_wav=dst, transcript=transcript or "")

    def synthesize(self, text: str, profile: VoiceProfile, *, language: str, speed: float,
                   style: str | None, quality: str | None) -> np.ndarray:
        if self._m is None:
            raise RuntimeError("engine_not_loaded")
        wav = self._m.generate(text, language_id=language or "ar", audio_prompt_path=str(profile.reference_wav),
                               exaggeration=STYLE_EXAGGERATION.get(style or "natural", 0.5))
        return wav.squeeze(0).detach().cpu().numpy().astype(np.float32)
