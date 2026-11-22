"""Engine registry. Only real engines are registered here."""

from __future__ import annotations

from typing import Callable

from .base import Engine

_REGISTRY: dict[str, Callable[[], Engine]] = {}


def register(name: str, factory: Callable[[], Engine]) -> None:
    _REGISTRY[name] = factory


def create(name: str) -> Engine:
    if name not in _REGISTRY:
        raise ValueError(f"unknown engine '{name}'. available: {sorted(_REGISTRY)}")
    return _REGISTRY[name]()


def _silma() -> Engine:
    from .silma import SilmaEngine
    return SilmaEngine()


def _chatterbox() -> Engine:
    from .chatterbox import ChatterboxEngine
    return ChatterboxEngine()


register("silma", _silma)
register("chatterbox", _chatterbox)
