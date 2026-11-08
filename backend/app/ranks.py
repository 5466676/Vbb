"""Ranks and levels: a cosmetic progression (GAME_RULES §9). Pure functions, no I/O.

Experience comes from finished online matches: 10 for playing, 5 per right answer, 30 for a win.
The rank letter (E → S) and the level (1 + xp // 100) are derived from the total.
"""

from __future__ import annotations

from app.bots.simple import Difficulty

XP_PLAYED = 10
XP_PER_CORRECT = 5
XP_WIN = 30

# lowest total experience for each rank, from the lowest rank up
RANKS: tuple[tuple[str, int], ...] = (
    ("E", 0),
    ("D", 200),
    ("C", 600),
    ("B", 1500),
    ("A", 3500),
    ("S", 7000),
)

# bots show a rank that matches how well they play
BOT_XP = {
    Difficulty.EASY: 250,
    Difficulty.MEDIUM: 900,
    Difficulty.HARD: 3800,
    Difficulty.SEAT_KEEPER: 0,
}


def match_xp(correct: int, won: bool) -> int:
    return XP_PLAYED + XP_PER_CORRECT * max(0, correct) + (XP_WIN if won else 0)


def total_xp(matches: int, correct: int, wins: int) -> int:
    """The sum of match_xp over many matches (it is linear, so totals are enough)."""
    return XP_PLAYED * matches + XP_PER_CORRECT * correct + XP_WIN * wins


def rank_of(xp: int) -> str:
    letter = RANKS[0][0]
    for name, low in RANKS:
        if xp >= low:
            letter = name
    return letter


def level_of(xp: int) -> int:
    return 1 + max(0, xp) // 100
