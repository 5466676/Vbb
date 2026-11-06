"""500 full bot matches per player count and mode (brief §5.1).

Every action is followed by an invariant check (see ``helpers.check_invariants``). The
wall-clock model in ``helpers.play_match`` estimates match length from the timers.
"""

import statistics
from collections import Counter

import pytest

from app.engine.models import Mode, Phase
from tests.helpers import play_match

MATCHES = 500
CONFIGS = [(n, Mode.FFA) for n in range(2, 9)] + [(n, Mode.TEAMS) for n in (4, 6, 8)]

# Accepted mean length in minutes. 2-3 player matches often end early by elimination
# (see DECISIONS.md, phase 2); the brief's 8-12 minute target is enforced from 4 players up.
MEAN_BOUNDS = {2: (3.5, 12.0), 3: (5.5, 12.0)}
DEFAULT_BOUNDS = (8.0, 12.0)
HARD_MAX_MIN = 15.0


@pytest.mark.parametrize(("players", "mode"), CONFIGS, ids=[f"{m.value}{n}" for n, m in CONFIGS])
def test_many_full_matches(players: int, mode: Mode) -> None:
    durations = []
    for seed in range(MATCHES):
        r = play_match(players, seed, mode=mode, copy_every=7)
        s = r.state
        assert s.phase is Phase.RESULTS
        assert all(t.owner is not None for t in s.territories.values())
        assert "match_ended" in r.events
        durations.append(r.duration_ms / 60_000)
    mean = statistics.mean(durations)
    low, high = MEAN_BOUNDS.get(players, DEFAULT_BOUNDS) if mode is Mode.FFA else DEFAULT_BOUNDS
    assert low <= mean <= high, f"mean length {mean:.1f} min outside {low}-{high}"
    assert max(durations) <= HARD_MAX_MIN, f"longest match {max(durations):.1f} min"


def test_same_seed_same_match() -> None:
    a = play_match(5, 123)
    b = play_match(5, 123)
    assert a.state.model_dump() == b.state.model_dump()
    assert a.events == b.events


def test_no_army_dominates() -> None:
    """Win share per army stays near fair (armies are assigned at random)."""
    wins: Counter[str] = Counter()
    games: Counter[str] = Counter()
    for seed in range(1500):
        s = play_match(4, 10_000 + seed, check=False).state
        winner = s.winner_team
        for p in s.players:
            games[p.army.value] += 1
            if p.team == winner:
                wins[p.army.value] += 1
    rates = {a: wins[a] / games[a] for a in games}
    fair = 1 / 4
    for army, rate in rates.items():
        assert 0.6 * fair <= rate <= 1.5 * fair, (
            f"{army} wins {rate:.0%} (fair {fair:.0%}): {rates}"
        )
