"""Shared helpers for engine tests: simple maps, questions and a bot-driven match runner."""

from __future__ import annotations

import math
import random
from collections import deque
from dataclasses import dataclass, field

from app.bots import simple as bots
from app.engine import core
from app.engine.armies import Army
from app.engine.models import (
    Answer,
    Event,
    MapDef,
    MatchSettings,
    MatchState,
    Mode,
    Phase,
    PlaceBase,
    PlayerSetup,
    ProvideQuestion,
    Question,
    QuestionKind,
    StartMatch,
    TerritoryDef,
    Timeout,
)
from app.engine.rng import Rng

ARMIES = list(Army)

# ------------------------------------------------------------------------------------------
# Maps
# ------------------------------------------------------------------------------------------


def grid_map(players: int, per_player: int = 5) -> MapDef:
    """A roughly 2:1 grid with 4-neighbour links plus one diagonal, bases far apart."""
    n = players * per_player
    cols = math.ceil(math.sqrt(2 * n))
    rows = math.ceil(n / cols)
    ids = list(range(n))
    pos = {i: (i // cols, i % cols) for i in ids}
    at = {v: k for k, v in pos.items()}
    terrs = []
    for i in ids:
        r, c = pos[i]
        nb = [
            at[p]
            for p in (
                (r - 1, c),
                (r + 1, c),
                (r, c - 1),
                (r, c + 1),
                (r + 1, c + 1),
                (r - 1, c - 1),
            )
            if p in at
        ]
        terrs.append(TerritoryDef(id=i, neighbors=nb))
    graph = {t.id: t.neighbors for t in terrs}
    bases = farthest_points(graph, players)
    _ = rows
    return MapDef(id=f"grid-{players}", territories=terrs, bases=bases)


def bfs(graph: dict[int, list[int]], start: int) -> dict[int, int]:
    dist = {start: 0}
    q = deque([start])
    while q:
        u = q.popleft()
        for v in graph[u]:
            if v not in dist:
                dist[v] = dist[u] + 1
                q.append(v)
    return dist


def farthest_points(graph: dict[int, list[int]], k: int) -> list[int]:
    chosen = [0]
    dists = [bfs(graph, 0)]
    while len(chosen) < k:
        best = max(
            (t for t in graph if t not in chosen), key=lambda t: (min(d[t] for d in dists), -t)
        )
        chosen.append(best)
        dists.append(bfs(graph, best))
    return chosen


def line_map(n: int, bases: list[int]) -> MapDef:
    """0 - 1 - 2 - ... - n-1 (handy for hand-written tests)."""
    terrs = [
        TerritoryDef(id=i, neighbors=[j for j in (i - 1, i + 1) if 0 <= j < n]) for i in range(n)
    ]
    return MapDef(id=f"line-{n}", territories=terrs, bases=bases)


# ------------------------------------------------------------------------------------------
# Questions
# ------------------------------------------------------------------------------------------


class QuestionFactory:
    def __init__(self, seed: int = 0) -> None:
        self.rnd = random.Random(seed)
        self.n = 0

    def make(self, kind: QuestionKind) -> Question:
        self.n += 1
        if kind is QuestionKind.MCQ:
            return Question(
                id=f"q{self.n}",
                kind=kind,
                text="?",
                options=["a", "b", "c", "d"],
                correct_index=self.rnd.randrange(4),
            )
        return Question(
            id=f"q{self.n}", kind=kind, text="?", answer=float(self.rnd.randint(10, 5000))
        )


def mcq(correct: int = 0, qid: str = "m") -> Question:
    return Question(
        id=qid, kind=QuestionKind.MCQ, options=["a", "b", "c", "d"], correct_index=correct
    )


def numeric(answer: float = 100, qid: str = "n") -> Question:
    return Question(id=qid, kind=QuestionKind.NUMERIC, answer=answer)


# ------------------------------------------------------------------------------------------
# Building states for hand-written tests
# ------------------------------------------------------------------------------------------


def setups(armies: list[Army], teams: list[int] | None = None) -> list[PlayerSetup]:
    return [
        PlayerSetup(seat=i, name=f"p{i}", army=a, team=None if teams is None else teams[i])
        for i, a in enumerate(armies)
    ]


def new_match(map_def: MapDef, armies: list[Army], seed: int = 1, **settings) -> MatchState:
    teams = settings.pop("teams", None)
    s = MatchSettings(mode=Mode.TEAMS if teams else Mode.FFA, **settings)
    return core.create_match("m", map_def, setups(armies, teams), seed=seed, settings=s)


def to_battle(state: MatchState, owners: dict[int, int]) -> list[Event]:
    """Assign free territories directly and enter the battle phase (skips expansion)."""
    for tid, seat in owners.items():
        state.territories[tid].owner = seat
    for t in state.territories.values():
        assert t.owner is not None, f"territory {t.id} still free"
    ev: list[Event] = []
    rng = Rng(state.rng_state)
    state.phase = Phase.EXP_PICKS  # pretend expansion just ended
    core._start_battle(state, ev, rng)
    state.rng_state = rng.state
    return ev


def step(state: MatchState, action) -> list[Event]:
    return core.apply_inplace(state, action)


def types(events: list[Event]) -> list[str]:
    return [e.type for e in events]


# ------------------------------------------------------------------------------------------
# Full bot match with a wall-clock model
# ------------------------------------------------------------------------------------------

REVEAL_MS = 4000  # show the correct answer and ranking
NUMERIC_REVEAL_MS = 6500  # arrows fly into the target
CLAIM_ANIM_MS = 2500  # territories appear after picks
DUEL_ANIM_MS = 4500  # army marches, battle scene
START_MS = 4500
BASE_ANIM_MS = 1800  # a castle lands
MARCH_MS = 3500  # troops march to the target


@dataclass
class SimResult:
    state: MatchState
    duration_ms: int
    actions: int
    events: list[str] = field(default_factory=list)


def check_invariants(state: MatchState) -> None:
    seats = {p.seat for p in state.players}
    for t in state.territories.values():
        assert t.owner is None or t.owner in seats
        assert t.value > 0
        if t.is_base:
            assert t.owner is not None and 0 < t.towers <= state.base_towers
        if t.owner is not None:
            assert not state.players[t.owner].eliminated, "eliminated players own nothing"
    if state.phase in core.BATTLE_PHASES or state.phase is Phase.RESULTS:
        assert all(t.owner is not None for t in state.territories.values())
    placing = state.phase in (Phase.STARTING, Phase.BASE_PLACEMENT)
    for p in state.players:
        if not p.eliminated and not placing:
            assert any(t.owner == p.seat and t.is_base for t in state.territories.values())


def play_match(
    n_players: int,
    seed: int,
    mode: Mode = Mode.FFA,
    difficulty: bots.Difficulty | None = None,
    check: bool = True,
    copy_every: int = 0,
    rounds: int | None = None,
    per_player: int = 5,
    towers: int | None = None,
    map_def: MapDef | None = None,
    open_ended: bool = True,
    choose_bases: bool = True,
    battle_extras: bool = True,
) -> SimResult:
    rnd = random.Random(seed)
    team_size = n_players // 2 if mode is Mode.TEAMS else 0
    armies = [rnd.choice(ARMIES) for _ in range(n_players)]
    teams = [i // team_size for i in range(n_players)] if team_size else None
    diffs = [difficulty or rnd.choice(list(bots.Difficulty)[:3]) for _ in range(n_players)]
    state = core.create_match(
        f"sim-{seed}",
        map_def or grid_map(n_players, per_player),
        setups(armies, teams),
        seed=seed,
        settings=MatchSettings(
            mode=mode,
            battle_rounds=rounds,
            base_towers=towers,
            open_ended=open_ended,
            choose_bases=choose_bases,
            battle_extras=battle_extras,
        ),
    )
    qf = QuestionFactory(seed)
    clock = START_MS
    n_actions = 0
    seen: list[str] = []

    def do(action) -> None:
        nonlocal state, n_actions
        n_actions += 1
        if copy_every and n_actions % copy_every == 0:
            state, ev = core.apply(state, action)
        else:
            ev = core.apply_inplace(state, action)
        seen.extend(e.type for e in ev)
        if check:
            check_invariants(state)

    def try_extras(seat: int) -> None:
        for a in bots.extras(state, seat, diffs[seat], rnd):
            do(a)

    do(StartMatch())
    timers = state.settings.timers
    for _ in range(20_000):
        if state.phase is Phase.RESULTS:
            break
        if state.pending_question is not None:
            if state.phase is Phase.BATTLE_DUEL:
                clock += MARCH_MS + DUEL_ANIM_MS  # each duel: troops march, then the result
            do(ProvideQuestion(question=qf.make(state.pending_question)))
            continue
        if state.active is not None:
            aq = state.active
            phase_id = state.phase_id
            answers: list[Answer] = []
            silent = False
            for seat in aq.participants:
                try_extras(seat)
                if state.phase_id != phase_id:
                    break
                if rnd.random() < 0.04:  # sometimes a player does not answer
                    silent = True
                    continue
                answers.append(bots.answer(aq.question, seat, aq.limits_ms[seat], diffs[seat], rnd))
            if state.phase_id != phase_id:
                continue
            longest = max((a.elapsed_ms for a in answers), default=0)
            for a in answers:
                do(a)
            if silent and state.phase_id == phase_id:
                do(Timeout(phase_id=phase_id))
                longest = max(aq.limits_ms.values())
            numeric = aq.question.kind is QuestionKind.NUMERIC
            clock += longest + (NUMERIC_REVEAL_MS if numeric else REVEAL_MS)
            continue
        if state.phase is Phase.BASE_PLACEMENT:
            seat = state.placer
            assert seat is not None
            if rnd.random() < 0.1:
                do(Timeout(phase_id=state.phase_id))
                clock += timers.base_ms
            else:
                do(PlaceBase(seat=seat, territory=core.auto_base(state, seat)))
                clock += rnd.randint(2500, 5000)
            clock += BASE_ANIM_MS
            continue
        if state.phase is Phase.EXP_PICKS:
            phase_id = state.phase_id
            think = 0
            for seat, count in list(state.pick_quota.items()):
                try_extras(seat)
                if state.phase_id != phase_id:
                    break
                if rnd.random() < 0.05:
                    think = timers.pick_ms
                    continue
                think = max(think, rnd.randint(2500, 6000))
                do(bots.picks(state, seat, state.pick_quota.get(seat, count), rnd))
                if state.phase_id != phase_id:
                    break
            if state.phase_id == phase_id:
                do(Timeout(phase_id=phase_id))
            clock += think + CLAIM_ANIM_MS
            continue
        if state.phase is Phase.BATTLE_TARGET:
            # everyone in `planners` picks at once; the duels then play one after another
            phase_id = state.phase_id
            think = 0
            timed_out = False
            for seat in list(state.planners):
                try_extras(seat)
                if state.phase_id != phase_id:
                    break
                choice = bots.target(state, seat, diffs[seat], rnd) if rnd.random() > 0.05 else None
                if choice is None:
                    timed_out = True
                    continue
                think = max(think, rnd.randint(3000, 8000))
                do(choice)
                if state.phase_id != phase_id:
                    break
            if state.phase_id == phase_id:
                do(Timeout(phase_id=phase_id))
            clock += timers.target_ms if timed_out else think
            continue
        raise AssertionError(f"stuck in phase {state.phase}")
    else:
        raise AssertionError("match did not finish")
    return SimResult(state=state, duration_ms=clock, actions=n_actions, events=seen)
