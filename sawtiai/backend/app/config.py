"""Runtime configuration, read from environment variables only.

No secret has a default value. If SAWTI_API_KEY is not set, every /api route
refuses to work (fail closed) - see security.py.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

APP_VERSION = "1.0.0"


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


def _float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


@dataclass
class Settings:
    api_key: str = field(default_factory=lambda: os.environ.get("SAWTI_API_KEY", "").strip())
    engine: str = field(default_factory=lambda: os.environ.get("SAWTI_ENGINE", "silma").strip().lower())
    data_dir: Path = field(default_factory=lambda: Path(os.environ.get("SAWTI_DATA_DIR", "/tmp/sawti")))
    max_upload_mb: int = field(default_factory=lambda: _int("SAWTI_MAX_UPLOAD_MB", 25))
    max_sample_seconds: float = field(default_factory=lambda: _float("SAWTI_MAX_SAMPLE_SECONDS", 120))
    max_text_chars: int = field(default_factory=lambda: _int("SAWTI_MAX_TEXT_CHARS", 2000))
    audio_ttl_minutes: int = field(default_factory=lambda: _int("SAWTI_AUDIO_TTL_MINUTES", 60))
    upload_ttl_minutes: int = field(default_factory=lambda: _int("SAWTI_UPLOAD_TTL_MINUTES", 30))
    job_timeout_seconds: int = field(default_factory=lambda: _int("SAWTI_JOB_TIMEOUT_SECONDS", 1800))
    max_queue: int = field(default_factory=lambda: _int("SAWTI_MAX_QUEUE", 4))
    rate_limit_per_minute: int = field(default_factory=lambda: _int("SAWTI_RATE_LIMIT_PER_MINUTE", 60))
    preload_model: bool = field(default_factory=lambda: os.environ.get("SAWTI_PRELOAD", "1") != "0")
    threads: int = field(default_factory=lambda: _int("SAWTI_THREADS", os.cpu_count() or 2))

    @property
    def voices_dir(self) -> Path:
        return self.data_dir / "voices"

    @property
    def audio_dir(self) -> Path:
        return self.data_dir / "audio"

    @property
    def uploads_dir(self) -> Path:
        return self.data_dir / "uploads"

    def ensure_dirs(self) -> None:
        for d in (self.voices_dir, self.audio_dir, self.uploads_dir):
            d.mkdir(parents=True, exist_ok=True)
            try:
                os.chmod(d, 0o700)
            except OSError:
                pass


settings = Settings()
