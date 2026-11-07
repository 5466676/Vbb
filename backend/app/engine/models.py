"""Serialisable match state, actions and events.

Everything here is plain data (Pydantic v2). Game logic lives in ``core.py``.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Annotated, Any, Literal

from pydantic import BaseModel, Field

from app.engine.armies import Army

# ------------------------------------------------------------------------------------------
# Settings and map input
# ------------------------------------------------------------------------------------------

DEFAULT_BATTLE_ROUNDS = {2: 19, 3: 13, 4: 9, 5: 8, 6: 6, 7: 5, 8: 4}  # calibrated by simulation


class Mode(StrEnum):
    FFA = "ffa"
    TEAMS = "teams"


class Timers(BaseModel):
    """Phase durations in milliseconds. The room enforces them; the engine validates answers."""

    mcq_ms: int = 10_000
    numeric_ms: int = 15_000
    pick_ms: int = 5_000
    target_ms: int = 8_000
    latency_grace_ms: int = 150


class MatchSettings(BaseModel):
    mode: Mode = Mode.FFA
    battle_rounds: int | None = None  # None = DEFAULT_BATTLE_ROUNDS[player count]
    tie_window_ms: int = 500
    normal_value: int = 200
    base_value: int = 1000
    base_towers: int | None = None  # None = 5 for 2-4 players, 3 for 5-8 (GAME_RULES §3)
    capture_gain: int = 100
    hold_gain: int = 100
    double_gain: int = 200
    timers: Timers = Field(default_factory=Timers)


class TerritoryDef(BaseModel):
    id: int
    neighbors: list[int]


class MapDef(BaseModel):
    """Territory graph. ``bases[i]`` is the base territory of seat ``i``."""

    id: str
    territories: list[TerritoryDef]
    bases: list[int]


class PlayerSetup(BaseModel):
    seat: int
    name: str
    army: Army
    team: int | None = None  # None in FFA (team = seat)
    is_bot: bool = False


# ------------------------------------------------------------------------------------------
# Questions
# ------------------------------------------------------------------------------------------


class QuestionKind(StrEnum):
    MCQ = "mcq"
    NUMERIC = "numeric"


class Question(BaseModel):
    """A question as known to the server (includes the answer)."""

    id: str
    kind: QuestionKind
    text: str = ""
    options: list[str] = Field(default_factory=list)  # MCQ only, canonical order
    correct_index: int | None = None  # MCQ only
    answer: float | None = None  # numeric only


class AnswerRecord(BaseModel):
    seat: int
    choice: int | None = None  # MCQ: canonical option index
    value: float | None = None  # numeric
    elapsed_ms: int


# ------------------------------------------------------------------------------------------
# State
# ------------------------------------------------------------------------------------------


class Phase(StrEnum):
    STARTING = "starting"
    EXP_QUESTION = "expansion_question"
    EXP_PICKS = "expansion_picks"
    BATTLE_TARGET = "battle_target"
    BATTLE_DUEL = "battle_duel"
    BATTLE_TIEBREAK = "battle_tiebreak"
    RESULTS = "results"


class PowerUp(StrEnum):
    REMOVE_TWO = "remove_two"
    HINT = "hint"
    SHIELD = "shield"
    DOUBLE = "double"


class TerritoryState(BaseModel):
    id: int
    owner: int | None = None
    value: int = 200
    is_base: bool = False
    towers: int = 0
    shielded: bool = False


class PlayerState(BaseModel):
    seat: int
    name: str
    army: Army
    team: int
    is_bot: bool = False
    connected: bool = True
    eliminated: bool = False
    bonus: int = 0
    powerups: list[PowerUp] = Field(default_factory=lambda: list(PowerUp))
    ability_used: bool = False
    # pending one-shot effects
    double_armed: bool = False
    fath_armed: bool = False  # islamic: +1 pick in the current expansion round
    sumud_armed: bool = False  # ayyubid
    siege_armed: bool = False  # crusader
    turtle_armed: bool = False  # roman
    raid_armed: bool = False  # mongol
    janissary_armed: bool = False  # ottoman
    airdrop_armed: bool = False  # ww2
    first_pick_done: bool = False  # ww2 passive
    # stats
    answered: int = 0
    correct: int = 0
    total_answer_ms: int = 0


class ActiveQuestion(BaseModel):
    question: Question
    participants: list[int]
    limits_ms: dict[int, int]  # per-seat time limit (pharaoh numeric bonus)
    answers: dict[int, AnswerRecord] = Field(default_factory=dict)


class Duel(BaseModel):
    attacker: int
    defender: int
    territory: int


class MatchState(BaseModel):
    match_id: str
    settings: MatchSettings
    map_id: str
    neighbors: dict[int, list[int]]
    territories: dict[int, TerritoryState]
    players: list[PlayerState]
    phase: Phase = Phase.STARTING
    phase_id: int = 0  # increments on every phase change; Timeout must match it
    rng_state: int
    battle_rounds: int
    base_towers: int
    # expansion
    expansion_round: int = 0
    ranking: list[int] = Field(default_factory=list)
    pick_quota: dict[int, int] = Field(default_factory=dict)
    picks: dict[int, list[int]] = Field(default_factory=dict)
    # battle
    battle_round: int = 0
    turn_queue: list[int] = Field(default_factory=list)
    attacker: int | None = None
    duel: Duel | None = None
    extra_turn: bool = False
    first_seat: int = 0
    # questions
    pending_question: QuestionKind | None = None
    pending_participants: list[int] = Field(default_factory=list)
    active: ActiveQuestion | None = None
    asked_question_ids: list[str] = Field(default_factory=list)
    winner_team: int | None = None


# ------------------------------------------------------------------------------------------
# Actions (input) and events (output)
# ------------------------------------------------------------------------------------------


class StartMatch(BaseModel):
    type: Literal["start_match"] = "start_match"


class ProvideQuestion(BaseModel):
    type: Literal["provide_question"] = "provide_question"
    question: Question


class Answer(BaseModel):
    type: Literal["answer"] = "answer"
    seat: int
    choice: int | None = None
    value: float | None = None
    elapsed_ms: int


class PickTerritories(BaseModel):
    type: Literal["pick_territories"] = "pick_territories"
    seat: int
    territories: list[int]


class ChooseTarget(BaseModel):
    type: Literal["choose_target"] = "choose_target"
    seat: int
    territory: int


class UsePowerUp(BaseModel):
    type: Literal["use_powerup"] = "use_powerup"
    seat: int
    powerup: PowerUp
    territory: int | None = None


class UseAbility(BaseModel):
    type: Literal["use_ability"] = "use_ability"
    seat: int
    territory: int | None = None


class SetConnected(BaseModel):
    type: Literal["set_connected"] = "set_connected"
    seat: int
    connected: bool


class Timeout(BaseModel):
    type: Literal["timeout"] = "timeout"
    phase_id: int


Action = Annotated[
    StartMatch
    | ProvideQuestion
    | Answer
    | PickTerritories
    | ChooseTarget
    | UsePowerUp
    | UseAbility
    | SetConnected
    | Timeout,
    Field(discriminator="type"),
]


class Event(BaseModel):
    """Something that happened. ``to`` is None for public events, else the seats that may see it."""

    type: str
    data: dict[str, Any] = Field(default_factory=dict)
    to: list[int] | None = None
