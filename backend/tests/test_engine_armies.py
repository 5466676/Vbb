"""Every army perk and ability (GAME_RULES §2.1)."""

import pytest

from app.engine import armies as A
from app.engine import core
from app.engine.armies import Army
from app.engine.models import (
    Answer,
    ChooseTarget,
    Phase,
    PickTerritories,
    ProvideQuestion,
    StartMatch,
    Timeout,
    UseAbility,
)
from tests.helpers import line_map, mcq, new_match, numeric, step, to_battle, types
from tests.test_engine_battle import duel

N = Army.PHARAOH  # neutral in battle


def line2(a0, a1, **kw):
    s = new_match(line_map(6, [0, 5]), [a0, a1], **kw)
    to_battle(s, {1: 0, 2: 0, 3: 1, 4: 1})
    return s


def base2(a0, a1, **kw):
    s = new_match(line_map(4, [0, 3]), [a0, a1], battle_rounds=10, **kw)
    to_battle(s, {1: 0, 2: 0})
    if s.attacker == 1:  # seat 1 (lower score) opens: let it fail
        duel(s, 2, att_ms=None, def_ms=None)
    return s


# --- passive perks --------------------------------------------------------------------------


def test_ayyubid_base_starts_at_1100():
    s = new_match(line_map(4, [0, 3]), [Army.AYYUBID, N])
    assert s.territories[0].value == A.AYYUBID_BASE_VALUE
    assert s.territories[3].value == 1000


def test_roman_gains_25_on_every_territory_at_battle_start():
    s = line2(Army.ROMAN, N)
    assert [s.territories[t].value for t in (0, 1, 2)] == [1025, 225, 225]
    assert s.territories[3].value == 200


def test_crusader_defence_adds_150():
    s = line2(N, Army.CRUSADER)
    duel(s, 3, att_ms=1000, att_ok=False, def_ms=None)
    assert s.territories[3].value == 350


def test_ottoman_capture_adds_150():
    s = line2(Army.OTTOMAN, N)
    duel(s, 3, att_ms=1000, def_ms=None)
    assert s.territories[3].value == 350


def test_islamic_gets_50_bonus_per_capture():
    s = line2(Army.ISLAMIC, N)
    duel(s, 3, att_ms=1000, def_ms=None)
    assert s.players[0].bonus == 50
    assert core.score(s, 0) == 1000 + 200 + 200 + 300 + 50


def test_pharaoh_gets_two_extra_seconds_on_numeric():
    s = new_match(line_map(6, [0, 5]), [Army.PHARAOH, Army.ROMAN])
    step(s, StartMatch())
    step(s, ProvideQuestion(question=numeric()))
    assert s.active.limits_ms == {0: 17_000, 1: 15_000}
    step(s, Answer(seat=0, value=1, elapsed_ms=16_500))  # accepted
    with pytest.raises(core.RuleError):
        step(s, Answer(seat=1, value=1, elapsed_ms=16_500))


def test_mongol_attack_time_bonus_turns_a_loss_into_a_tie():
    s = line2(Army.MONGOL, N)
    duel(s, 3, att_ms=3600, def_ms=3000, att_ok=True, def_ok=True)
    assert s.phase is Phase.BATTLE_TIEBREAK  # 3600 - 200 = 3400, gap 400 < 500
    s2 = line2(N, N)
    duel(s2, 3, att_ms=3600, def_ms=3000, att_ok=True, def_ok=True)
    assert s2.territories[3].owner == 1  # without the bonus the defender wins outright


def test_ww2_first_expansion_pick_may_be_anywhere():
    s = new_match(line_map(8, [0, 7]), [Army.WW2, N])
    step(s, StartMatch())
    step(s, ProvideQuestion(question=numeric(100)))
    step(s, Answer(seat=0, value=100, elapsed_ms=1000))
    step(s, Answer(seat=1, value=0, elapsed_ms=1000))
    ev = step(s, PickTerritories(seat=0, territories=[4, 5]))
    claims = {e.data["territory"]: e.data["auto"] for e in ev if e.type == "territory_claimed"}
    assert claims[4] is False  # first pick anywhere
    assert 5 in claims and claims[5] is False  # second pick touches 4
    assert core.legal_picks(s, 0) != core.free_territories(s) or not core.free_territories(s)


# --- active abilities -----------------------------------------------------------------------


def test_islamic_fath_adds_a_pick():
    s = new_match(line_map(8, [0, 7]), [Army.ISLAMIC, N])
    step(s, StartMatch())
    step(s, UseAbility(seat=0))
    step(s, ProvideQuestion(question=numeric(100)))
    step(s, Answer(seat=0, value=100, elapsed_ms=1000))
    step(s, Answer(seat=1, value=0, elapsed_ms=1000))
    assert s.pick_quota[0] == 3
    with pytest.raises(core.RuleError):
        step(s, UseAbility(seat=0))  # once per match


def test_islamic_fath_lets_a_non_picker_pick():
    s = new_match(line_map(8, [0, 7]), [N, Army.ISLAMIC])
    step(s, StartMatch())
    step(s, ProvideQuestion(question=numeric(100)))
    step(s, Answer(seat=0, value=100, elapsed_ms=1000))
    step(s, Answer(seat=1, value=0, elapsed_ms=1000))
    assert 1 not in s.pick_quota
    step(s, UseAbility(seat=1))
    assert s.pick_quota[1] == 1


def test_battle_abilities_are_rejected_during_expansion():
    s = new_match(line_map(8, [0, 7]), [Army.AYYUBID, N])
    step(s, StartMatch())
    with pytest.raises(core.RuleError):
        step(s, UseAbility(seat=0))


def test_pharaoh_pyramid_adds_300_to_own_territory_only():
    s = line2(Army.PHARAOH, N)
    with pytest.raises(core.RuleError):
        step(s, UseAbility(seat=0, territory=3))
    step(s, UseAbility(seat=0, territory=1))
    assert s.territories[1].value == 500


def test_ayyubid_sumud_blocks_one_tower_hit():
    s = base2(N, Army.AYYUBID)
    step(s, UseAbility(seat=1))
    ev = duel(s, 3, att_ms=1000, def_ms=None)
    assert "base_guarded" in types(ev)
    assert s.territories[3].towers == 3


def test_crusader_siege_removes_two_towers():
    s = base2(Army.CRUSADER, N)
    step(s, UseAbility(seat=0))
    duel(s, 3, att_ms=1000, def_ms=None)
    assert s.territories[3].towers == 1


def test_mongol_raid_gives_an_extra_attack_after_success():
    s = line2(Army.MONGOL, N)
    step(s, UseAbility(seat=0))
    ev = duel(s, 3, att_ms=1000, def_ms=None)
    assert "extra_turn" in types(ev)
    assert s.attacker == 0 and s.phase is Phase.BATTLE_TARGET
    assert core.legal_targets(s, 0) == [4]


def test_mongol_raid_does_nothing_after_failure():
    s = line2(Army.MONGOL, N)
    step(s, UseAbility(seat=0))
    duel(s, 3, att_ms=1000, att_ok=False, def_ms=None)
    assert s.attacker == 1
    assert s.players[0].raid_armed  # still waiting for a success


def test_ottoman_janissary_wins_a_tie_as_attacker():
    s = line2(Army.OTTOMAN, N)
    step(s, UseAbility(seat=0))
    ev = duel(s, 3, att_ms=3000, def_ms=3100, att_ok=True, def_ok=True)
    assert "tie_won_by_ability" in types(ev)
    assert s.territories[3].owner == 0


def test_roman_turtle_wins_a_tie_as_defender():
    s = line2(N, Army.ROMAN)
    step(s, UseAbility(seat=1))
    duel(s, 3, att_ms=3000, def_ms=3100, att_ok=True, def_ok=True)
    assert s.territories[3].owner == 1
    assert s.phase is Phase.BATTLE_TARGET


def test_opposing_tie_abilities_cancel_into_a_tiebreak():
    s = line2(Army.OTTOMAN, Army.ROMAN)
    step(s, UseAbility(seat=0))
    step(s, UseAbility(seat=1))
    duel(s, 3, att_ms=3000, def_ms=3100, att_ok=True, def_ok=True)
    assert s.phase is Phase.BATTLE_TIEBREAK
    assert not s.players[0].janissary_armed and not s.players[1].turtle_armed


def test_ww2_airdrop_allows_any_enemy_territory_once():
    s = line2(Army.WW2, N)
    assert core.legal_targets(s, 0) == [3]
    step(s, UseAbility(seat=0))
    assert core.legal_targets(s, 0) == [3, 4, 5]
    step(s, ChooseTarget(seat=0, territory=5))
    assert s.duel.territory == 5
    assert not s.players[0].airdrop_armed
    step(s, ProvideQuestion(question=mcq()))
    step(s, Timeout(phase_id=s.phase_id))
