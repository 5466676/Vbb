"""Pure game logic.

Rules for this package:
- No I/O, no network, no clocks, no global randomness.
- Everything goes through ``apply(state, action) -> (new_state, events)``.
- All randomness comes from the seeded RNG stored inside ``MatchState``.
"""

from app.engine.armies import Army
from app.engine.core import (
    RuleError,
    alive_seats,
    apply,
    apply_inplace,
    create_match,
    legal_picks,
    legal_targets,
    owned,
    score,
    standings,
    team_scores,
)
from app.engine.models import (
    Answer,
    ChooseTarget,
    Event,
    MapDef,
    MatchSettings,
    MatchState,
    Mode,
    Phase,
    PickTerritories,
    PlayerSetup,
    PowerUp,
    ProvideQuestion,
    Question,
    QuestionKind,
    SetConnected,
    StartMatch,
    TerritoryDef,
    Timeout,
    UseAbility,
    UsePowerUp,
)

__all__ = [
    "Answer",
    "Army",
    "ChooseTarget",
    "Event",
    "MapDef",
    "MatchSettings",
    "MatchState",
    "Mode",
    "Phase",
    "PickTerritories",
    "PlayerSetup",
    "PowerUp",
    "ProvideQuestion",
    "Question",
    "QuestionKind",
    "RuleError",
    "SetConnected",
    "StartMatch",
    "TerritoryDef",
    "Timeout",
    "UseAbility",
    "UsePowerUp",
    "alive_seats",
    "apply",
    "apply_inplace",
    "create_match",
    "legal_picks",
    "legal_targets",
    "owned",
    "score",
    "standings",
    "team_scores",
]
