"""Battle rules, power-ups, teams and end of match (GAME_RULES §5, §6.2, §6.3)."""

import pytest

from app.engine import core
from app.engine.armies import Army
from app.engine.models import (
    Answer,
    ChooseTarget,
    Phase,
    PowerUp,
    ProvideQuestion,
    StartMatch,
    Timeout,
    UsePowerUp,
)
from tests.helpers import grid_map, line_map, mcq, new_match, numeric, step, to_battle, types

R = Army.PHARAOH  # perks that do not touch battle values
M = Army.MONGOL


def duel(s, target, att_ms=None, def_ms=None, att_ok=True, def_ok=False, correct=0):
    """Attacker chooses ``target``; both answer the MCQ (``None`` ms = no answer)."""
    attacker = s.attacker
    defender = s.territories[target].owner
    step(s, ChooseTarget(seat=attacker, territory=target))
    step(s, ProvideQuestion(question=mcq(correct=correct)))
    ev = []
    pid = s.phase_id
    for seat, ms, ok in ((attacker, att_ms, att_ok), (defender, def_ms, def_ok)):
        if ms is not None and s.phase_id == pid:
            ev += step(
                s, Answer(seat=seat, choice=correct if ok else (correct + 1) % 4, elapsed_ms=ms)
            )
    if s.phase_id == pid:
        ev += step(s, Timeout(phase_id=pid))
    return ev


def two_player_line(armies=(R, R), **kw):
    """0(base A) 1A 2A 3B 4B 5(base B); seat 0 attacks first (equal scores)."""
    s = new_match(line_map(6, [0, 5]), list(armies), **kw)
    to_battle(s, {1: 0, 2: 0, 3: 1, 4: 1})
    return s


def test_battle_starts_with_lowest_score_and_adjacent_targets():
    s = two_player_line()
    assert s.phase is Phase.BATTLE_TARGET
    assert s.attacker == 0
    assert core.legal_targets(s, 0) == [3]


def test_capture_changes_owner_and_adds_100():
    s = two_player_line()
    ev = duel(s, 3, att_ms=3000, def_ms=1000, def_ok=False)
    assert s.territories[3].owner == 0 and s.territories[3].value == 300
    assert "territory_captured" in types(ev)
    assert s.attacker == 1  # next turn


def test_defender_holds_and_gains_100_when_attacker_is_wrong():
    s = two_player_line()
    duel(s, 3, att_ms=500, att_ok=False, def_ms=None)
    assert s.territories[3].owner == 1 and s.territories[3].value == 300


def test_attacker_must_be_correct_even_against_silence():
    s = two_player_line()
    duel(s, 3, att_ms=300, att_ok=False, def_ms=None)
    assert s.territories[3].owner == 1


def test_both_correct_faster_wins_outside_tie_window():
    s = two_player_line()
    duel(s, 3, att_ms=4000, def_ms=3000, att_ok=True, def_ok=True)
    assert s.territories[3].owner == 1  # defender was 1 s faster


def test_close_correct_answers_go_to_numeric_tiebreak():
    s = two_player_line()
    duel(s, 3, att_ms=3000, def_ms=3300, att_ok=True, def_ok=True)
    assert s.phase is Phase.BATTLE_TIEBREAK
    step(s, ProvideQuestion(question=numeric(100)))
    step(s, Answer(seat=0, value=98, elapsed_ms=4000))
    ev = step(s, Answer(seat=1, value=90, elapsed_ms=2000))
    assert s.territories[3].owner == 0
    assert next(e for e in ev if e.type == "battle_result").data["tiebreak"] is True


def test_identical_tiebreak_favours_defender():
    s = two_player_line()
    duel(s, 3, att_ms=3000, def_ms=3000, att_ok=True, def_ok=True)
    step(s, ProvideQuestion(question=numeric(100)))
    step(s, Answer(seat=0, value=90, elapsed_ms=2000))
    step(s, Answer(seat=1, value=110, elapsed_ms=2000))
    assert s.territories[3].owner == 1


def test_target_timeout_picks_a_legal_target():
    s = two_player_line()
    ev = step(s, Timeout(phase_id=s.phase_id))
    chosen = next(e for e in ev if e.type == "target_chosen")
    assert chosen.data["territory"] == 3 and chosen.data["auto"] is True


def test_illegal_target_and_wrong_attacker_are_rejected():
    s = two_player_line()
    with pytest.raises(core.RuleError):
        step(s, ChooseTarget(seat=0, territory=4))  # not adjacent
    with pytest.raises(core.RuleError):
        step(s, ChooseTarget(seat=1, territory=2))  # not seat 1's turn


def base_line(armies=(R, R), **kw):
    """0(base A) 1A 2A 3(base B): seat 1 owns only its base."""
    s = new_match(line_map(4, [0, 3]), list(armies), **kw)
    to_battle(s, {1: 0, 2: 0})
    return s


def test_base_hits_remove_towers_and_fall_eliminates_and_transfers():
    s = base_line(battle_rounds=10, base_towers=3)
    towers_seen = []
    ev = []
    while s.phase is not Phase.RESULTS:
        if s.attacker == 1:
            duel(s, 2, att_ms=None, def_ms=None)  # nobody answers: seat 0 holds
        else:
            ev = duel(s, 3, att_ms=1000, def_ms=None)
            towers_seen.append(s.territories[3].towers)
    assert towers_seen == [2, 1, 0]
    assert s.players[1].eliminated
    assert all(t.owner == 0 for t in s.territories.values())
    assert not s.territories[3].is_base
    assert "player_eliminated" in types(ev)
    assert s.phase is Phase.RESULTS  # only one team left
    end = next(e for e in ev if e.type == "match_ended")
    assert end.data["winner_team"] == 0


def test_shield_blocks_next_attack_without_a_question():
    s = two_player_line()
    step(s, UsePowerUp(seat=1, powerup=PowerUp.SHIELD, territory=3))
    ev = step(s, ChooseTarget(seat=0, territory=3))
    assert "shield_blocked" in types(ev)
    assert "question_needed" not in types(ev)
    assert s.territories[3].owner == 1 and not s.territories[3].shielded
    assert s.attacker == 1
    with pytest.raises(core.RuleError):
        step(s, UsePowerUp(seat=1, powerup=PowerUp.SHIELD, territory=4))  # used once


def test_shield_only_on_own_territory():
    s = two_player_line()
    with pytest.raises(core.RuleError):
        step(s, UsePowerUp(seat=1, powerup=PowerUp.SHIELD, territory=0))


def test_double_gain_on_capture():
    s = two_player_line()
    step(s, UsePowerUp(seat=0, powerup=PowerUp.DOUBLE))
    duel(s, 3, att_ms=1000, def_ms=None)
    assert s.territories[3].value == 400


def test_remove_two_is_private_and_keeps_the_correct_option():
    s = two_player_line()
    step(s, ChooseTarget(seat=0, territory=3))
    step(s, ProvideQuestion(question=mcq(correct=2)))
    ev = step(s, UsePowerUp(seat=0, powerup=PowerUp.REMOVE_TWO))
    res = next(e for e in ev if e.type == "powerup_result")
    assert res.to == [0]
    assert len(res.data["removed"]) == 2 and 2 not in res.data["removed"]
    with pytest.raises(core.RuleError):
        step(s, UsePowerUp(seat=0, powerup=PowerUp.HINT))  # not a numeric question


def test_hint_range_contains_the_answer():
    for seed in range(20):
        s = new_match(grid_map(2), [R, R], seed=seed)
        step(s, StartMatch())
        step(s, ProvideQuestion(question=numeric(1234)))
        ev = step(s, UsePowerUp(seat=0, powerup=PowerUp.HINT))
        res = next(e for e in ev if e.type == "powerup_result").data
        assert res["low"] <= 1234 <= res["high"]


def test_turn_order_rotates_each_round():
    s = new_match(line_map(9, [0, 4, 8]), [R, R, R], battle_rounds=3)
    s.territories[7].value = 100  # seat 2 has the lowest score -> starts round 1
    to_battle(s, {1: 0, 2: 0, 3: 1, 5: 1, 6: 2, 7: 2})
    order = []
    while s.phase is not Phase.RESULTS:
        order.append(s.attacker)
        step(s, Timeout(phase_id=s.phase_id))  # auto target
        if s.phase is Phase.BATTLE_DUEL:
            step(s, ProvideQuestion(question=mcq()))
            step(s, Timeout(phase_id=s.phase_id))  # nobody answers: defender holds
    assert order == [2, 0, 1, 0, 1, 2, 1, 2, 0]


def test_teammates_are_not_targets_and_team_wins_together():
    s = new_match(line_map(4, [0, 1, 2, 3]), [R, R, R, R], teams=[0, 0, 1, 1])
    to_battle(s, {})
    assert core.legal_targets(s, 0) == []  # only neighbour is teammate 1
    assert core.legal_targets(s, 1) == [2]
    scores = core.team_scores(s)
    assert scores == {0: 2000, 1: 2000}


def test_match_ends_after_last_round_with_standings():
    s = two_player_line(battle_rounds=1)
    duel(s, 3, att_ms=1000, def_ms=None)  # seat 0 captures 3
    ev = duel(s, 3, att_ms=None, def_ms=None)  # seat 1 fails to take it back
    assert s.phase is Phase.RESULTS
    end = next(e for e in ev if e.type == "match_ended").data
    assert end["standings"][0]["seat"] == 0
    assert end["winner_team"] == 0


def test_score_ties_break_on_correct_answers():
    s = two_player_line(battle_rounds=1)
    s.players[1].correct = 5
    rows = core.standings(s)
    assert rows[0]["seat"] == 1  # equal scores, more correct answers


def test_default_towers_depend_on_player_count():
    assert new_match(grid_map(2), [R, R]).base_towers == 5
    assert new_match(grid_map(4), [R] * 4).territories[0].towers == 5
    assert new_match(grid_map(5), [R] * 5).base_towers == 3
    assert new_match(grid_map(8), [R] * 8, base_towers=4).base_towers == 4


def test_round_started_carries_the_turn_order():
    s = new_match(line_map(6, [0, 5]), [R, R])
    ev = to_battle(s, {1: 0, 2: 0, 3: 1, 4: 1})
    started = [e for e in ev if e.type == "round_started"]
    assert started and started[0].data["order"] == [0, 1]
    assert s.round_order == [0, 1]
    duel(s, 3, att_ms=3000, def_ms=1000)  # seat 0's turn
    ev = duel(s, core.legal_targets(s, 1)[0], att_ms=3000, def_ms=1000)  # seat 1 ends round 1
    nxt = [e for e in ev if e.type == "round_started"]
    assert nxt and nxt[0].data == {"round": 2, "order": [1, 0]}  # rotates one seat


def test_both_right_goes_to_the_tiebreak_even_with_a_big_time_gap():
    s = two_player_line()
    step(s, ChooseTarget(seat=0, territory=3))
    step(s, ProvideQuestion(question=mcq(correct=0)))
    step(s, Answer(seat=0, choice=0, elapsed_ms=1000))
    step(s, Answer(seat=1, choice=0, elapsed_ms=6000))
    assert s.phase is Phase.BATTLE_TIEBREAK  # speed no longer decides between two right answers


def test_everyone_answers_the_duel_and_right_watchers_score_points():
    s = new_match(line_map(7, [0, 3, 6]), [R, R, R])
    to_battle(s, {1: 0, 2: 0, 4: 1, 5: 2})
    attacker = s.attacker
    target = core.legal_targets(s, attacker)[0]
    defender = s.territories[target].owner
    watcher = ({0, 1, 2} - {attacker, defender}).pop()
    step(s, ChooseTarget(seat=attacker, territory=target))
    ev = step(s, ProvideQuestion(question=mcq(correct=1)))
    assert s.active is not None and sorted(s.active.participants) == [0, 1, 2]
    before = s.players[watcher].bonus
    ev = step(s, Answer(seat=watcher, choice=1, elapsed_ms=900))
    ev += step(s, Answer(seat=attacker, choice=0, elapsed_ms=1000))  # wrong: the defender holds
    ev += step(s, Answer(seat=defender, choice=2, elapsed_ms=1200))
    assert s.players[watcher].bonus == before + core.SPECTATOR_POINTS
    assert "bonus_points" in types(ev) and "territory_held" in types(ev)
