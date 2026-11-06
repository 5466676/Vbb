"""Deterministic, serialisable random number generator (SplitMix64).

The generator state is a plain ``int`` stored inside ``MatchState`` so a match can be
saved, restored and replayed exactly. Never use the ``random`` module in the engine.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import TypeVar

T = TypeVar("T")
_MASK = (1 << 64) - 1


class Rng:
    """Small wrapper that reads and writes the RNG state held by a ``MatchState``."""

    def __init__(self, state: int) -> None:
        self.state = state & _MASK

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & _MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & _MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & _MASK
        return z ^ (z >> 31)

    def randbelow(self, n: int) -> int:
        """Uniform integer in ``[0, n)``."""
        if n <= 0:
            raise ValueError("n must be positive")
        return self.next_u64() % n

    def random(self) -> float:
        """Uniform float in ``[0, 1)``."""
        return (self.next_u64() >> 11) / float(1 << 53)

    def choice(self, items: Sequence[T]) -> T:
        if not items:
            raise ValueError("cannot choose from an empty sequence")
        return items[self.randbelow(len(items))]

    def shuffle(self, items: list[T]) -> None:
        for i in range(len(items) - 1, 0, -1):
            j = self.randbelow(i + 1)
            items[i], items[j] = items[j], items[i]
