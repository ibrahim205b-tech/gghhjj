"""Common interface every voice-cloning engine implements."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np


@dataclass
class EngineInfo:
    id: str
    name: str
    version: str
    license: str
    source_url: str
    model_url: str
    languages: list[str]
    sample_rate: int
    # Reference-sample requirements of *this* engine (shown in the app)
    min_sample_seconds: float
    recommended_sample_seconds: float
    max_useful_sample_seconds: float
    needs_transcript: bool
    supports_speed: bool
    speed_range: tuple[float, float] = (1.0, 1.0)
    styles: list[dict] = field(default_factory=list)
    qualities: list[dict] = field(default_factory=list)
    max_chunk_chars: int = 200
    notes: str = ""

    def to_dict(self) -> dict:
        d = self.__dict__.copy()
        d["speed_range"] = list(self.speed_range)
        return d


@dataclass
class VoiceProfile:
    voice_id: str
    reference_wav: Path
    transcript: str
    extra: dict = field(default_factory=dict)


class Engine(ABC):
    info: EngineInfo

    @abstractmethod
    def load(self) -> None:
        """Load weights. May take minutes on a cold CPU host."""

    @abstractmethod
    def prepare_voice(self, voice_id: str, sample_wav: Path, transcript: str, workdir: Path) -> VoiceProfile:
        """Turn an uploaded sample into what synthesis needs. Must not fake."""

    def purge_cache(self) -> None:
        """Forget any cached voice data (called when voices are deleted)."""

    @abstractmethod
    def synthesize(self, text: str, profile: VoiceProfile, *, language: str, speed: float,
                   style: str | None, quality: str | None) -> np.ndarray:
        """Return a mono float32 waveform at info.sample_rate for ONE chunk."""
