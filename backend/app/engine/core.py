"""Pure game engine: ``apply(state, action) -> (new_state, events)``.

No I/O, no clocks, no global randomness. The room layer owns timers and feeds a
``Timeout`` action (carrying the current ``phase_id``) when a phase deadline passes, and
answers ``question_needed`` events with a ``ProvideQuestion`` action.

All rules follow docs/GAME_RULES.md; section numbers are referenced in comments.
"""

from __future__ import annotations

import math

from app.engine import armies as A
from app.engine.armies import Army
from app.engine.models import (
    DEFAULT_BATTLE_ROUNDS,
    DOMINATION,
    MAX_BATTLE_ROUNDS,
    Action,
    ActiveQuestion,
    Answer,
    AnswerRecord,
    ChooseTarget,
    Duel,
    Event,
    MapDef,
    MatchSettings,
    MatchState,
    Mode,
    Phase,
    PickTerritories,
    PlaceBase,
    PlayerSetup,
    PlayerState,
    PowerUp,
    ProvideQuestion,
    QuestionKind,
    SetConnected,
    StartMatch,
    TerritoryState,
    Timeout,
    UseAbility,
    UsePowerUp,
)
from app.engine.ranking import is_correct, rank, sort_key
from app.engine.rng import Rng


class RuleError(ValueError):
    """An action that is not allowed right now. The state is left unchanged."""


SPECTATOR_POINTS = 50  # a right answer to someone else's duel question (§6.2.2)
BATTLE_PHASES = (Phase.BATTLE_TARGET, Phase.BATTLE_DUEL, Phase.BATTLE_TIEBREAK)

# ==========================================================================================
# Creation
# ==========================================================================================


def create_match(
    match_id: str,
    map_def: MapDef,
    players: list[PlayerSetup],
    seed: int,
    settings: MatchSettings | None = None,
) -> MatchState:
    settings = settings or MatchSettings()
    n = len(players)
    if not 2 <= n <= 8:
        raise RuleError("a match needs 2-8 players")
    if len(map_def.bases) < n:
        raise RuleError("map has fewer bases than players")
    seats = sorted(p.seat for p in players)
    if seats != list(range(n)):
        raise RuleError("seats must be 0..n-1")
    if settings.mode is Mode.TEAMS and any(p.team is None for p in players):
        raise RuleError("team mode needs a team for every player")

    neighbors = {t.id: sorted(set(t.neighbors)) for t in map_def.territories}
    territories = {
        t.id: TerritoryState(id=t.id, value=settings.normal_value) for t in map_def.territories
    }
    towers = settings.base_towers or (5 if n <= 4 else 3)
    player_states: list[PlayerState] = []
    for p in sorted(players, key=lambda p: p.seat):
        team = p.team if settings.mode is Mode.TEAMS and p.team is not None else p.seat
        player_states.append(
            PlayerState(seat=p.seat, name=p.name, army=p.army, team=team, is_bot=p.is_bot)
        )
        if not settings.choose_bases:
            _make_base(territories[map_def.bases[p.seat]], p.seat, p.army, towers, settings)

    rounds = settings.battle_rounds or (
        MAX_BATTLE_ROUNDS if settings.open_ended else DEFAULT_BATTLE_ROUNDS[n]
    )
    return MatchState(
        default_bases={p.seat: map_def.bases[p.seat] for p in players}
        if settings.choose_bases
        else {},
        match_id=match_id,
        settings=settings,
        map_id=map_def.id,
        neighbors=neighbors,
        territories=territories,
        players=player_states,
        rng_state=seed,
        battle_rounds=rounds,
        base_towers=towers,
    )


def _make_base(
    t: TerritoryState, seat: int, army: Army, towers: int, settings: MatchSettings
) -> None:
    t.owner = seat
    t.is_base = True
    t.towers = towers
    t.value = A.AYYUBID_BASE_VALUE if army is Army.AYYUBID else settings.base_value


# ==========================================================================================
# Entry points
# ==========================================================================================


def apply(state: MatchState, action: Action) -> tuple[MatchState, list[Event]]:
    """Return a new state and the events produced. ``state`` is not modified.

    Raises ``RuleError`` for illegal actions (the caller sends an ``error`` to the client).
    """
    new = state.model_copy(deep=True)
    events = apply_inplace(new, action)
    return new, events


def apply_inplace(state: MatchState, action: Action) -> list[Event]:
    """Same as ``apply`` but mutates ``state``. Use only on a state you own."""
    rng = Rng(state.rng_state)
    ev: list[Event] = []
    handler = _HANDLERS.get(type(action))
    if handler is None:
        raise RuleError(f"unknown action {type(action).__name__}")
    handler(state, action, rng, ev)
    state.rng_state = rng.state
    return ev


# ==========================================================================================
# Queries (also used by bots, rooms and tests)
# ==========================================================================================


def player(state: MatchState, seat: int) -> PlayerState:
    if not 0 <= seat < len(state.players):
        raise RuleError("no such seat")
    return state.players[seat]


def alive_seats(state: MatchState) -> list[int]:
    return [p.seat for p in state.players if not p.eliminated]


def owned(state: MatchState, seat: int) -> list[int]:
    return [t.id for t in state.territories.values() if t.owner == seat]


def free_territories(state: MatchState) -> list[int]:
    return sorted(t.id for t in state.territories.values() if t.owner is None)


def are_allies(state: MatchState, a: int, b: int) -> bool:
    return state.players[a].team == state.players[b].team


def score(state: MatchState, seat: int) -> int:
    land = sum(t.value for t in state.territories.values() if t.owner == seat)
    return land + state.players[seat].bonus


def team_scores(state: MatchState) -> dict[int, int]:
    out: dict[int, int] = {}
    for p in state.players:
        out[p.team] = out.get(p.team, 0) + score(state, p.seat)
    return out


def _touches(state: MatchState, seat: int, tid: int) -> bool:
    return any(state.territories[n].owner == seat for n in state.neighbors[tid])


def legal_picks(state: MatchState, seat: int) -> list[int]:
    """GAME_RULES §6.1.5 (+ WW2 passive for the first pick)."""
    free = free_territories(state)
    p = state.players[seat]
    if p.army is Army.WW2 and not p.first_pick_done:
        return free
    adjacent = [t for t in free if _touches(state, seat, t)]
    return adjacent or _nearest_free(state, seat, free)


def _nearest_free(state: MatchState, seat: int, free: list[int]) -> list[int]:
    """The free territories the fewest steps away from the seat's land (BFS over the map)."""
    frontier = owned(state, seat)
    if not frontier:
        return free
    seen = set(frontier)
    wanted = set(free)
    while frontier:
        hit = sorted(t for t in frontier if t in wanted)
        if hit:
            return hit
        nxt = []
        for t in frontier:
            for n in state.neighbors[t]:
                if n not in seen:
                    seen.add(n)
                    nxt.append(n)
        frontier = nxt
    return free


def legal_targets(state: MatchState, seat: int) -> list[int]:
    """Enemy territories the seat may attack (§6.2.1, WW2 airdrop)."""
    p = state.players[seat]
    enemy = [
        t.id
        for t in state.territories.values()
        if t.owner is not None
        and not are_allies(state, t.owner, seat)
        and not state.players[t.owner].eliminated
    ]
    if p.airdrop_armed:
        return sorted(enemy)
    return sorted(t for t in enemy if _touches(state, seat, t))


# ==========================================================================================
# Phase plumbing
# ==========================================================================================


def _set_phase(state: MatchState, phase: Phase, ev: list[Event], **data) -> None:
    state.phase = phase
    state.phase_id += 1
    ev.append(
        Event(type="phase_changed", data={"phase": phase.value, "phase_id": state.phase_id, **data})
    )


def _request_question(
    state: MatchState, kind: QuestionKind, seats: list[int], ev: list[Event]
) -> None:
    state.pending_question = kind
    state.pending_participants = list(seats)
    state.active = None
    ev.append(
        Event(
            type="question_needed",
            data={"kind": kind.value, "participants": list(seats), "phase_id": state.phase_id},
        )
    )


def _limit_ms(state: MatchState, kind: QuestionKind, seat: int) -> int:
    t = state.settings.timers
    if kind is QuestionKind.MCQ:
        return t.mcq_ms
    extra = A.PHARAOH_NUMERIC_EXTRA_MS if state.players[seat].army is Army.PHARAOH else 0
    return t.numeric_ms + extra


# ==========================================================================================
# Handlers
# ==========================================================================================


def _on_start(state: MatchState, action: StartMatch, rng: Rng, ev: list[Event]) -> None:
    if state.phase is not Phase.STARTING:
        raise RuleError("match already started")
    ev.append(
        Event(
            type="match_started",
            data={"players": len(state.players), "rounds": state.battle_rounds},
        )
    )
    if state.settings.choose_bases:
        # §6.0: in a random order, each player places their castle
        order = [p.seat for p in state.players]
        rng.shuffle(order)
        state.place_order = order
        _next_placement(state, ev)
        return
    _start_expansion_round(state, ev)


# ==========================================================================================
# Castle placement (§6.0)
# ==========================================================================================


def legal_bases(state: MatchState) -> list[int]:
    """Free territories that do not touch a castle (castles keep a gap between them)."""
    bases = {t.id for t in state.territories.values() if t.is_base}
    return sorted(
        t.id
        for t in state.territories.values()
        if t.owner is None and not any(n in bases for n in state.neighbors[t.id])
    )


def auto_base(state: MatchState, seat: int) -> int:
    """The map's suggested spot if still legal, else the legal spot farthest from other castles."""
    legal = legal_bases(state) or free_territories(state)
    want = state.default_bases.get(seat)
    if want in legal:
        return want  # type: ignore[return-value]
    bases = [t.id for t in state.territories.values() if t.is_base]
    if not bases:
        return legal[0]
    dist = {b: _distances(state, b) for b in bases}
    return max(legal, key=lambda t: (min(dist[b].get(t, 99) for b in bases), -t))


def _distances(state: MatchState, start: int) -> dict[int, int]:
    out = {start: 0}
    frontier = [start]
    while frontier:
        nxt = []
        for t in frontier:
            for n in state.neighbors[t]:
                if n not in out:
                    out[n] = out[t] + 1
                    nxt.append(n)
        frontier = nxt
    return out


def _next_placement(state: MatchState, ev: list[Event]) -> None:
    if not state.place_order:
        state.placer = None
        _start_expansion_round(state, ev)
        return
    state.placer = state.place_order.pop(0)
    _set_phase(
        state,
        Phase.BASE_PLACEMENT,
        ev,
        placer=state.placer,
        options=legal_bases(state),
        deadline_ms=state.settings.timers.base_ms,
    )


def _place_base(state: MatchState, seat: int, tid: int, auto: bool, ev: list[Event]) -> None:
    p = state.players[seat]
    t = state.territories[tid]
    _make_base(t, seat, p.army, state.base_towers, state.settings)
    ev.append(
        Event(
            type="base_placed",
            data={
                "seat": seat,
                "territory": tid,
                "auto": auto,
                "towers": t.towers,
                "value": t.value,
            },
        )
    )
    _next_placement(state, ev)


def _on_place_base(state: MatchState, action: PlaceBase, rng: Rng, ev: list[Event]) -> None:
    if state.phase is not Phase.BASE_PLACEMENT or action.seat != state.placer:
        raise RuleError("it is not your turn to place a castle")
    if action.territory not in legal_bases(state):
        raise RuleError("a castle needs a free spot that does not touch another castle")
    _place_base(state, action.seat, action.territory, False, ev)


def _on_provide_question(
    state: MatchState, action: ProvideQuestion, rng: Rng, ev: list[Event]
) -> None:
    kind = state.pending_question
    if kind is None:
        raise RuleError("no question is needed now")
    q = action.question
    if q.kind is not kind:
        raise RuleError(f"expected a {kind.value} question")
    if q.kind is QuestionKind.MCQ and (len(q.options) != 4 or q.correct_index not in range(4)):
        raise RuleError("an MCQ needs 4 options and a correct index")
    if q.kind is QuestionKind.NUMERIC and (q.answer is None or not math.isfinite(q.answer)):
        raise RuleError("a numeric question needs a finite answer")
    seats = state.pending_participants
    limits = {s: _limit_ms(state, kind, s) for s in seats}
    state.active = ActiveQuestion(question=q, participants=list(seats), limits_ms=limits)
    state.pending_question = None
    state.pending_participants = []
    state.asked_question_ids.append(q.id)
    public = {
        "id": q.id,
        "kind": q.kind.value,
        "text": q.text,
        "options": list(q.options),
        "unit": q.unit,
        "participants": list(seats),
        "limits_ms": {str(k): v for k, v in limits.items()},
        "phase_id": state.phase_id,
    }
    ev.append(Event(type="question", data=public))  # never contains the answer


def _on_answer(state: MatchState, action: Answer, rng: Rng, ev: list[Event]) -> None:
    aq = state.active
    if aq is None or state.phase not in (
        Phase.EXP_QUESTION,
        Phase.BATTLE_DUEL,
        Phase.BATTLE_TIEBREAK,
    ):
        raise RuleError("no question is open")
    seat = action.seat
    if seat not in aq.participants:
        raise RuleError("you are not answering this question")
    if seat in aq.answers:
        raise RuleError("duplicate answer")
    grace = state.settings.timers.latency_grace_ms
    if action.elapsed_ms < 0 or action.elapsed_ms > aq.limits_ms[seat] + grace:
        raise RuleError("late answer")
    if aq.question.kind is QuestionKind.MCQ:
        if action.choice not in range(4):
            raise RuleError("choice must be 0-3")
        rec = AnswerRecord(seat=seat, choice=action.choice, elapsed_ms=action.elapsed_ms)
    else:
        if action.value is None or not math.isfinite(action.value):
            raise RuleError("a numeric answer is required")
        rec = AnswerRecord(seat=seat, value=float(action.value), elapsed_ms=action.elapsed_ms)
    aq.answers[seat] = rec
    ev.append(Event(type="answer_locked", data={"seat": seat}))
    if len(aq.answers) == len(aq.participants):
        _resolve_question(state, rng, ev)


def _on_timeout(state: MatchState, action: Timeout, rng: Rng, ev: list[Event]) -> None:
    if action.phase_id != state.phase_id:
        return  # stale timer, ignore
    if state.phase in (Phase.EXP_QUESTION, Phase.BATTLE_DUEL, Phase.BATTLE_TIEBREAK):
        if state.active is None:
            return  # the question has not been delivered yet; the room retries
        _resolve_question(state, rng, ev)
    elif state.phase is Phase.BASE_PLACEMENT:
        seat = state.placer
        assert seat is not None
        _place_base(state, seat, auto_base(state, seat), True, ev)
    elif state.phase is Phase.EXP_PICKS:
        _resolve_picks(state, rng, ev)
    elif state.phase is Phase.BATTLE_TARGET:
        targets = legal_targets(state, state.attacker)  # type: ignore[arg-type]
        if not targets:
            ev.append(Event(type="turn_skipped", data={"seat": state.attacker}))
            _next_turn(state, ev, rng)
            return
        _start_duel(state, rng.choice(targets), ev, rng, auto=True)


def _on_pick(state: MatchState, action: PickTerritories, rng: Rng, ev: list[Event]) -> None:
    if state.phase is not Phase.EXP_PICKS:
        raise RuleError("picks are not open")
    quota = state.pick_quota.get(action.seat, 0)
    if quota == 0:
        raise RuleError("you have no picks this round")
    if action.seat in state.picks:
        raise RuleError("picks already submitted")
    chosen = list(dict.fromkeys(action.territories))[:quota]
    if any(t not in state.territories for t in chosen):
        raise RuleError("unknown territory")
    state.picks[action.seat] = chosen  # legality is checked at resolution (§6.1.4)
    ev.append(Event(type="pick_locked", data={"seat": action.seat}))
    if all(s in state.picks for s in state.pick_quota):
        _resolve_picks(state, rng, ev)


def _on_choose_target(state: MatchState, action: ChooseTarget, rng: Rng, ev: list[Event]) -> None:
    if state.phase is not Phase.BATTLE_TARGET or action.seat != state.attacker:
        raise RuleError("it is not your turn to attack")
    if action.territory not in legal_targets(state, action.seat):
        raise RuleError("illegal target")
    _start_duel(state, action.territory, ev, rng, auto=False)


def _on_powerup(state: MatchState, action: UsePowerUp, rng: Rng, ev: list[Event]) -> None:
    p = player(state, action.seat)
    if p.eliminated or state.phase in (Phase.STARTING, Phase.RESULTS):
        raise RuleError("power-ups are not available now")
    if action.powerup not in p.powerups:
        raise RuleError("power-up already used")
    aq = state.active
    private: dict = {}
    if action.powerup in (PowerUp.REMOVE_TWO, PowerUp.HINT):
        want = QuestionKind.MCQ if action.powerup is PowerUp.REMOVE_TWO else QuestionKind.NUMERIC
        if aq is None or aq.question.kind is not want or p.seat not in aq.participants:
            raise RuleError("no matching question is open for you")
        if p.seat in aq.answers:
            raise RuleError("you already answered")
        q = aq.question
        if action.powerup is PowerUp.REMOVE_TWO:
            wrong = [i for i in range(4) if i != q.correct_index]
            rng.shuffle(wrong)
            private = {"removed": sorted(wrong[:2])}
        else:
            ans = float(q.answer or 0.0)
            width = max(abs(ans) * 0.25, 2.0)
            low = ans - rng.random() * width
            private = {"low": math.floor(low), "high": math.ceil(low + width)}
    elif action.powerup is PowerUp.SHIELD:
        if state.phase not in BATTLE_PHASES:
            raise RuleError("shields are used during the battle")
        t = state.territories.get(-1 if action.territory is None else action.territory)
        if t is None or t.owner != p.seat:
            raise RuleError("shield one of your own territories")
        if state.duel is not None and state.duel.territory == t.id:
            raise RuleError("this territory is already under attack")
        t.shielded = True
        private = {"territory": t.id}
    elif action.powerup is PowerUp.DOUBLE:
        p.double_armed = True
    p.powerups.remove(action.powerup)
    ev.append(Event(type="powerup_used", data={"seat": p.seat, "powerup": action.powerup.value}))
    if private:
        ev.append(
            Event(
                type="powerup_result",
                data={"powerup": action.powerup.value, **private},
                to=[p.seat],
            )
        )


def _on_ability(state: MatchState, action: UseAbility, rng: Rng, ev: list[Event]) -> None:
    p = player(state, action.seat)
    if p.eliminated or p.ability_used:
        raise RuleError("ability not available")
    data: dict = {"seat": p.seat, "army": p.army.value}
    if p.army is Army.ISLAMIC:
        if state.phase is Phase.EXP_QUESTION:
            p.fath_armed = True
        elif state.phase is Phase.EXP_PICKS:
            state.pick_quota[p.seat] = state.pick_quota.get(p.seat, 0) + 1
            state.picks.pop(p.seat, None)  # allow a new, larger submission
        else:
            raise RuleError("فتح is used during expansion")
    elif p.army is Army.PHARAOH:
        if state.phase in (Phase.STARTING, Phase.RESULTS):
            raise RuleError("not now")
        t = state.territories.get(action.territory if action.territory is not None else -1)
        if t is None or t.owner != p.seat:
            raise RuleError("choose one of your territories")
        t.value += A.PHARAOH_PYRAMID_GAIN
        data["territory"] = t.id
    else:
        if state.phase not in BATTLE_PHASES:
            raise RuleError("this ability is used during the battle")
        flag = {
            Army.AYYUBID: "sumud_armed",
            Army.CRUSADER: "siege_armed",
            Army.ROMAN: "turtle_armed",
            Army.MONGOL: "raid_armed",
            Army.OTTOMAN: "janissary_armed",
            Army.WW2: "airdrop_armed",
        }[p.army]
        setattr(p, flag, True)
    p.ability_used = True
    ev.append(Event(type="ability_used", data=data))


def _on_connected(state: MatchState, action: SetConnected, rng: Rng, ev: list[Event]) -> None:
    p = player(state, action.seat)
    p.connected = action.connected
    ev.append(Event(type="player_connection", data={"seat": p.seat, "connected": p.connected}))


_HANDLERS = {
    StartMatch: _on_start,
    ProvideQuestion: _on_provide_question,
    Answer: _on_answer,
    Timeout: _on_timeout,
    PickTerritories: _on_pick,
    PlaceBase: _on_place_base,
    ChooseTarget: _on_choose_target,
    UsePowerUp: _on_powerup,
    UseAbility: _on_ability,
    SetConnected: _on_connected,
}

# ==========================================================================================
# Questions: resolution
# ==========================================================================================


def _record_stats(state: MatchState, aq: ActiveQuestion) -> None:
    for seat, rec in aq.answers.items():
        p = state.players[seat]
        p.answered += 1
        p.total_answer_ms += rec.elapsed_ms
        if is_correct(aq.question, rec):
            p.correct += 1


def _resolve_question(state: MatchState, rng: Rng, ev: list[Event]) -> None:
    aq = state.active
    assert aq is not None
    state.active = None
    _record_stats(state, aq)
    bonus: dict[int, int] = {}
    if state.duel is not None and state.players[state.duel.attacker].army is Army.MONGOL:
        bonus[state.duel.attacker] = A.MONGOL_ATTACK_TIME_BONUS_MS
    order = rank(aq.question, aq.participants, aq.answers, bonus)
    q = aq.question
    ev.append(
        Event(
            type="question_result",
            data={
                "id": q.id,
                "correct_index": q.correct_index,
                "answer": q.answer,
                "ranking": order,
                "answers": {str(s): r.model_dump(exclude={"seat"}) for s, r in aq.answers.items()},
            },
        )
    )
    if state.phase is Phase.EXP_QUESTION:
        _open_picks(state, order, ev)
    elif state.phase is Phase.BATTLE_DUEL:
        _resolve_duel(state, aq, bonus, rng, ev)
    elif state.phase is Phase.BATTLE_TIEBREAK:
        duel = state.duel
        assert duel is not None
        both_silent = not aq.answers
        attacker_first = order[0] == duel.attacker and not both_silent
        if attacker_first and len(order) == 2:
            # identical keys favour the defender
            if sort_key(q, aq.answers.get(duel.attacker), bonus.get(duel.attacker, 0)) == sort_key(
                q, aq.answers.get(duel.defender)
            ):
                attacker_first = False
        _apply_duel_outcome(state, attacker_first, rng, ev, tiebreak=True)


# ==========================================================================================
# Expansion (§6.1)
# ==========================================================================================


def _start_expansion_round(state: MatchState, ev: list[Event]) -> None:
    state.expansion_round += 1
    state.ranking = []
    state.pick_quota = {}
    state.picks = {}
    _set_phase(state, Phase.EXP_QUESTION, ev, expansion_round=state.expansion_round)
    _request_question(state, QuestionKind.NUMERIC, alive_seats(state), ev)


def _open_picks(state: MatchState, order: list[int], ev: list[Event]) -> None:
    state.ranking = order
    top = math.ceil(len(order) / 2)
    quota = {s: (2 if i == 0 else 1) for i, s in enumerate(order[:top])}
    for p in state.players:
        if p.fath_armed and not p.eliminated:
            quota[p.seat] = quota.get(p.seat, 0) + 1
            p.fath_armed = False
    state.pick_quota = quota
    state.picks = {}
    _set_phase(
        state,
        Phase.EXP_PICKS,
        ev,
        deadline_ms=state.settings.timers.pick_ms,
        quota={str(k): v for k, v in quota.items()},
        ranking=order,
    )


def _resolve_picks(state: MatchState, rng: Rng, ev: list[Event]) -> None:
    order = [s for s in state.ranking if s in state.pick_quota]
    order += [s for s in state.pick_quota if s not in order]  # fath users outside the top half
    for seat in order:
        requested = state.picks.get(seat, [])
        for i in range(state.pick_quota[seat]):
            if not free_territories(state):
                break
            legal = legal_picks(state, seat)
            want = requested[i] if i < len(requested) else None
            auto = want not in legal
            tid = rng.choice(legal) if auto else want
            t = state.territories[tid]  # type: ignore[index]
            t.owner = seat
            state.players[seat].first_pick_done = True
            ev.append(
                Event(
                    type="territory_claimed",
                    data={"seat": seat, "territory": tid, "auto": auto, "value": t.value},
                )
            )
    state.pick_quota = {}
    state.picks = {}
    if free_territories(state):
        _start_expansion_round(state, ev)
    else:
        _start_battle(state, ev, rng)


# ==========================================================================================
# Battle (§6.2)
# ==========================================================================================


def _start_battle(state: MatchState, ev: list[Event], rng: Rng) -> None:
    for p in state.players:
        if p.army is Army.ROMAN and not p.eliminated:
            for t in state.territories.values():
                if t.owner == p.seat:
                    t.value += A.ROMAN_BATTLE_START_GAIN
    alive = alive_seats(state)
    state.first_seat = min(alive, key=lambda s: (score(state, s), s))
    state.battle_round = 0
    state.turn_queue = []
    data = {"rounds": state.battle_rounds, "open_ended": state.settings.open_ended}
    ev.append(Event(type="battle_started", data=data))
    _next_turn(state, ev, rng)


def _alive_teams(state: MatchState) -> set[int]:
    return {p.team for p in state.players if not p.eliminated}


def _build_queue(state: MatchState) -> None:
    seats = [p.seat for p in state.players]
    start = (seats.index(state.first_seat) + state.battle_round - 1) % len(seats)
    order = seats[start:] + seats[:start]
    state.turn_queue = [s for s in order if not state.players[s].eliminated]
    state.round_order = list(state.turn_queue)


def _next_turn(state: MatchState, ev: list[Event], rng: Rng) -> None:
    state.duel = None
    while True:
        dominant = dominant_team(state)
        if len(_alive_teams(state)) <= 1 or dominant is not None:
            _finish(state, ev, first_team=dominant)
            return
        seat: int | None = None
        if state.extra_turn and state.attacker is not None:
            state.extra_turn = False
            if not state.players[state.attacker].eliminated:
                seat = state.attacker
        if seat is None:
            if not state.turn_queue:
                state.battle_round += 1
                if state.battle_round > state.battle_rounds:
                    _finish(state, ev)
                    return
                _build_queue(state)
                order = list(state.round_order)
                win = round(domination_share(state), 2) if state.settings.open_ended else None
                data = {"round": state.battle_round, "order": order, "win_share": win}
                ev.append(Event(type="round_started", data=data))
                continue
            seat = state.turn_queue.pop(0)
            if state.players[seat].eliminated:
                continue
        targets = legal_targets(state, seat)
        if not targets:
            ev.append(Event(type="turn_skipped", data={"seat": seat}))
            continue
        state.attacker = seat
        _set_phase(
            state,
            Phase.BATTLE_TARGET,
            ev,
            attacker=seat,
            round=state.battle_round,
            targets=targets,
            deadline_ms=state.settings.timers.target_ms,
        )
        return


def _start_duel(state: MatchState, tid: int, ev: list[Event], rng: Rng, auto: bool) -> None:
    attacker = state.attacker
    assert attacker is not None
    a = state.players[attacker]
    t = state.territories[tid]
    defender = t.owner
    assert defender is not None
    if a.airdrop_armed:
        a.airdrop_armed = False
    state.duel = Duel(attacker=attacker, defender=defender, territory=tid)
    ev.append(
        Event(
            type="target_chosen",
            data={"attacker": attacker, "defender": defender, "territory": tid, "auto": auto},
        )
    )
    if t.shielded:
        t.shielded = False
        ev.append(Event(type="shield_blocked", data={"territory": tid, "defender": defender}))
        _finish_turn(state, attacker_won=False, ev=ev, rng=rng)
        return
    _set_phase(state, Phase.BATTLE_DUEL, ev, attacker=attacker, defender=defender, territory=tid)
    # everyone still in the match answers; only the attacker and the defender decide the land,
    # the others play for spectator points (§6.2.2)
    watchers = [
        p.seat for p in state.players if not p.eliminated and p.seat not in (attacker, defender)
    ]
    _request_question(state, QuestionKind.MCQ, [attacker, defender, *watchers], ev)


def _resolve_duel(
    state: MatchState, aq: ActiveQuestion, bonus: dict[int, int], rng: Rng, ev: list[Event]
) -> None:
    duel = state.duel
    assert duel is not None
    q = aq.question
    att, dfd = duel.attacker, duel.defender
    ra, rd = aq.answers.get(att), aq.answers.get(dfd)
    a_ok, d_ok = is_correct(q, ra), is_correct(q, rd)
    points = {
        s: SPECTATOR_POINTS
        for s in aq.participants
        if s not in (att, dfd) and is_correct(q, aq.answers.get(s))
    }
    for s, n in points.items():
        state.players[s].bonus += n
    if points:
        ev.append(
            Event(type="bonus_points", data={"points": {str(s): n for s, n in points.items()}})
        )
    if a_ok and d_ok:
        # both right: no race on speed, a numeric tiebreak decides (closest wins) — §6.2.3
        pa, pd = state.players[att], state.players[dfd]
        if pa.janissary_armed and not pd.turtle_armed:
            pa.janissary_armed = False
            ev.append(Event(type="tie_won_by_ability", data={"seat": att}))
            _apply_duel_outcome(state, True, rng, ev)
            return
        if pd.turtle_armed and not pa.janissary_armed:
            pd.turtle_armed = False
            ev.append(Event(type="tie_won_by_ability", data={"seat": dfd}))
            _apply_duel_outcome(state, False, rng, ev)
            return
        pa.janissary_armed = pd.turtle_armed = False
        _set_phase(
            state,
            Phase.BATTLE_TIEBREAK,
            ev,
            attacker=att,
            defender=dfd,
            territory=duel.territory,
        )
        _request_question(state, QuestionKind.NUMERIC, [att, dfd], ev)
        return
    # The attacker must answer correctly to win (DECISIONS: phase 2).
    _apply_duel_outcome(state, a_ok, rng, ev)


def _apply_duel_outcome(
    state: MatchState, attacker_won: bool, rng: Rng, ev: list[Event], tiebreak: bool = False
) -> None:
    duel = state.duel
    assert duel is not None
    s = state.settings
    t = state.territories[duel.territory]
    att, dfd = state.players[duel.attacker], state.players[duel.defender]
    if attacker_won:
        if t.is_base:
            if dfd.sumud_armed:
                dfd.sumud_armed = False
                ev.append(
                    Event(type="base_guarded", data={"territory": t.id, "defender": dfd.seat})
                )
            else:
                dmg = 1
                if att.siege_armed:
                    att.siege_armed = False
                    dmg = A.CRUSADER_SIEGE_TOWERS
                t.towers = max(0, t.towers - dmg)
                ev.append(
                    Event(
                        type="tower_hit",
                        data={"territory": t.id, "towers": t.towers, "attacker": att.seat},
                    )
                )
                if t.towers == 0:
                    _base_falls(state, att.seat, dfd.seat, t.id, ev)
        else:
            gain = A.OTTOMAN_CAPTURE_GAIN if att.army is Army.OTTOMAN else s.capture_gain
            if att.double_armed:
                att.double_armed = False
                gain = s.double_gain
            t.owner = att.seat
            t.shielded = False
            t.value += gain
            if att.army is Army.ISLAMIC:
                att.bonus += A.ISLAMIC_CAPTURE_BONUS
            ev.append(
                Event(
                    type="territory_captured",
                    data={
                        "territory": t.id,
                        "attacker": att.seat,
                        "defender": dfd.seat,
                        "value": t.value,
                    },
                )
            )
    else:
        gain = A.CRUSADER_HOLD_GAIN if dfd.army is Army.CRUSADER else s.hold_gain
        if dfd.double_armed:
            dfd.double_armed = False
            gain = s.double_gain
        t.value += gain
        ev.append(
            Event(
                type="territory_held",
                data={"territory": t.id, "defender": dfd.seat, "value": t.value},
            )
        )
    ev.append(
        Event(
            type="battle_result",
            data={"attacker_won": attacker_won, "tiebreak": tiebreak, "territory": t.id},
        )
    )
    _finish_turn(state, attacker_won, ev, rng)


def _base_falls(
    state: MatchState, attacker: int, defender: int, base_id: int, ev: list[Event]
) -> None:
    """§6.2.3: the defender is eliminated; the base and all their land go to the attacker."""
    taken = []
    for t in state.territories.values():
        if t.owner == defender:
            t.owner = attacker
            t.shielded = False
            taken.append(t.id)
    base = state.territories[base_id]
    base.is_base = False
    base.towers = 0
    d = state.players[defender]
    d.eliminated = True
    a = state.players[attacker]
    if a.army is Army.ISLAMIC:
        a.bonus += A.ISLAMIC_CAPTURE_BONUS
    ev.append(
        Event(
            type="player_eliminated", data={"seat": defender, "by": attacker, "territories": taken}
        )
    )


def _finish_turn(state: MatchState, attacker_won: bool, ev: list[Event], rng: Rng) -> None:
    att = state.players[state.attacker]  # type: ignore[index]
    if attacker_won and att.raid_armed:
        att.raid_armed = False
        state.extra_turn = True
        ev.append(Event(type="extra_turn", data={"seat": att.seat}))
    _next_turn(state, ev, rng)


# ==========================================================================================
# End of match (§6.3)
# ==========================================================================================


def domination_share(state: MatchState) -> float:
    """Share of the map that wins (§6.3): 2/3 (4/5 head to head), easing by 1.5 points every
    attack after the first 16 attacks, down to a fair-share floor — a clear leader wins sooner,
    a close match goes on."""
    alive = len(_alive_teams(state))
    start = DOMINATION if alive > 2 else 0.8
    floor = 1 / max(alive, 1) + 0.08
    players = sum(1 for p in state.players if not p.eliminated)
    attacks = max(0, state.battle_round - 1) * players  # roughly: full rounds played so far
    return max(floor, start - 0.015 * max(0, attacks - 16))


def dominant_team(state: MatchState) -> int | None:
    """The team owning at least DOMINATION of the map, if any (§6.3)."""
    if not state.settings.open_ended:
        return None
    count: dict[int, int] = {}
    for t in state.territories.values():
        if t.owner is not None:
            team = state.players[t.owner].team
            count[team] = count.get(team, 0) + 1
    if state.battle_round <= (3 if len(_alive_teams(state)) <= 2 else 1):
        return None  # everyone gets some attacks first (head to head: three rounds)
    need = domination_share(state) * len(state.territories)
    return next((team for team, n in count.items() if n >= need), None)


def standings(state: MatchState, first_team: int | None = None) -> list[dict]:
    rows = []
    for p in state.players:
        avg = p.total_answer_ms / p.answered if p.answered else float("inf")
        rows.append(
            {
                "seat": p.seat,
                "team": p.team,
                "score": score(state, p.seat),
                "correct": p.correct,
                "avg_answer_ms": None if p.answered == 0 else round(avg),
                "eliminated": p.eliminated,
                "_avg": avg,
            }
        )
    teams: dict[int, dict] = {}
    for r in rows:
        t = teams.setdefault(
            r["team"], {"team": r["team"], "score": 0, "correct": 0, "ms": 0, "answered": 0}
        )
        t["score"] += r["score"]
        t["correct"] += r["correct"]
        p = state.players[r["seat"]]
        t["ms"] += p.total_answer_ms
        t["answered"] += p.answered
    for t in teams.values():
        t["_avg"] = t["ms"] / t["answered"] if t["answered"] else float("inf")
    team_order = sorted(
        teams.values(),
        key=lambda t: (t["team"] != first_team, -t["score"], -t["correct"], t["_avg"], t["team"]),
    )
    rank_of = {t["team"]: i for i, t in enumerate(team_order)}
    rows.sort(key=lambda r: (rank_of[r["team"]], -r["score"], -r["correct"], r["_avg"], r["seat"]))
    for r in rows:
        r.pop("_avg")
    return rows


def _finish(state: MatchState, ev: list[Event], first_team: int | None = None) -> None:
    rows = standings(state, first_team)
    state.winner_team = rows[0]["team"]
    state.attacker = None
    state.duel = None
    _set_phase(state, Phase.RESULTS, ev)
    ev.append(
        Event(
            type="match_ended",
            data={
                "winner_team": state.winner_team,
                "standings": rows,
                "team_scores": team_scores(state),
            },
        )
    )
