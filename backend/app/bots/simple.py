"""Bot players.

Bots run on the server and see the question's answer, so their skill is simulated with
probabilities. They use their own ``random.Random`` (never the match RNG) so the engine
stays deterministic for a given sequence of actions.

``Difficulty.SEAT_KEEPER`` is the stand-in for a disconnected human (GAME_RULES §7):
random answers, auto picks, no power-ups or abilities.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from enum import StrEnum

from app.engine import core
from app.engine.armies import Army
from app.engine.models import (
    Answer,
    ChooseTarget,
    MatchState,
    Phase,
    PickTerritories,
    PowerUp,
    Question,
    QuestionKind,
    UseAbility,
    UsePowerUp,
)


class Difficulty(StrEnum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"
    SEAT_KEEPER = "seat_keeper"


@dataclass(frozen=True)
class Profile:
    p_correct: float  # MCQ
    numeric_sigma: float  # relative error of numeric guesses
    min_ms: int
    max_ms: int
    extras: bool  # uses power-ups and abilities


PROFILES = {
    Difficulty.EASY: Profile(0.45, 0.45, 3500, 9000, True),
    Difficulty.MEDIUM: Profile(0.65, 0.25, 2500, 7500, True),
    Difficulty.HARD: Profile(0.85, 0.10, 1500, 5500, True),
    Difficulty.SEAT_KEEPER: Profile(0.25, 1.00, 4000, 9500, False),
}


def answer(
    question: Question, seat: int, limit_ms: int, difficulty: Difficulty, rnd: random.Random
) -> Answer:
    prof = PROFILES[difficulty]
    elapsed = min(limit_ms, rnd.randint(prof.min_ms, prof.max_ms))
    if question.kind is QuestionKind.MCQ:
        if rnd.random() < prof.p_correct:
            choice = question.correct_index
        else:
            choice = rnd.choice([i for i in range(4) if i != question.correct_index])
        return Answer(seat=seat, choice=choice, elapsed_ms=elapsed)
    true = float(question.answer or 0.0)
    spread = max(abs(true) * prof.numeric_sigma, 1.0)
    guess = round(true + rnd.gauss(0, spread))
    return Answer(seat=seat, value=float(guess), elapsed_ms=elapsed)


def picks(state: MatchState, seat: int, count: int, rnd: random.Random) -> PickTerritories:
    legal = core.legal_picks(state, seat)
    chosen = rnd.sample(legal, min(count, len(legal)))
    return PickTerritories(seat=seat, territories=chosen)


def target(
    state: MatchState, seat: int, difficulty: Difficulty, rnd: random.Random
) -> ChooseTarget | None:
    options = core.legal_targets(state, seat)
    if not options:
        return None
    if difficulty is Difficulty.HARD:
        # prefer a base that is nearly down, otherwise the most valuable target
        def value(tid: int) -> tuple:
            t = state.territories[tid]
            return (t.is_base and t.towers == 1, t.value)

        return ChooseTarget(seat=seat, territory=max(options, key=value))
    return ChooseTarget(seat=seat, territory=rnd.choice(options))


def extras(
    state: MatchState, seat: int, difficulty: Difficulty, rnd: random.Random
) -> list[UsePowerUp | UseAbility]:
    """Occasionally use a power-up or the army ability when it is legal right now."""
    if not PROFILES[difficulty].extras or rnd.random() > 0.25:
        return []
    p = state.players[seat]
    out: list[UsePowerUp | UseAbility] = []
    aq = state.active
    if aq is not None and seat in aq.participants and seat not in aq.answers:
        if aq.question.kind is QuestionKind.MCQ and PowerUp.REMOVE_TWO in p.powerups:
            out.append(UsePowerUp(seat=seat, powerup=PowerUp.REMOVE_TWO))
        if aq.question.kind is QuestionKind.NUMERIC and PowerUp.HINT in p.powerups:
            out.append(UsePowerUp(seat=seat, powerup=PowerUp.HINT))
    mine = core.owned(state, seat)
    if state.phase in core.BATTLE_PHASES and mine:
        if PowerUp.DOUBLE in p.powerups:
            out.append(UsePowerUp(seat=seat, powerup=PowerUp.DOUBLE))
        busy = state.duel.territory if state.duel else None
        safe = [t for t in mine if t != busy]
        if PowerUp.SHIELD in p.powerups and safe:
            out.append(UsePowerUp(seat=seat, powerup=PowerUp.SHIELD, territory=rnd.choice(safe)))
    if not p.ability_used:
        if p.army is Army.ISLAMIC and state.phase in (Phase.EXP_QUESTION, Phase.EXP_PICKS):
            out.append(UseAbility(seat=seat))
        elif p.army is Army.PHARAOH and mine and state.phase is not Phase.RESULTS:
            out.append(UseAbility(seat=seat, territory=rnd.choice(mine)))
        elif p.army not in (Army.ISLAMIC, Army.PHARAOH) and state.phase in core.BATTLE_PHASES:
            out.append(UseAbility(seat=seat))
    return out
