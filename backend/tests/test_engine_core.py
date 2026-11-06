"""Core flow: questions, ranking, expansion, timeouts and validation (GAME_RULES §4, §6.1, §8)."""

import pytest

from app.engine import core
from app.engine.armies import Army
from app.engine.models import (
    Answer,
    AnswerRecord,
    Phase,
    PickTerritories,
    ProvideQuestion,
    QuestionKind,
    StartMatch,
    Timeout,
)
from app.engine.ranking import rank
from tests.helpers import grid_map, line_map, mcq, new_match, numeric, step, types

A2 = [Army.ROMAN, Army.MONGOL]


def started(map_def, armies, **kw):
    s = new_match(map_def, armies, **kw)
    step(s, StartMatch())
    return s


# --- ranking -------------------------------------------------------------------------------


def test_mcq_ranking_correct_first_then_faster_no_answer_last():
    q = mcq(correct=2)
    answers = {
        0: AnswerRecord(seat=0, choice=1, elapsed_ms=500),  # wrong, fast
        1: AnswerRecord(seat=1, choice=2, elapsed_ms=4000),  # correct, slow
        2: AnswerRecord(seat=2, choice=2, elapsed_ms=2000),  # correct, fast
    }
    assert rank(q, [0, 1, 2, 3], answers) == [2, 1, 0, 3]


def test_numeric_ranking_closer_first_then_faster():
    q = numeric(answer=100)
    answers = {
        0: AnswerRecord(seat=0, value=90, elapsed_ms=1000),
        1: AnswerRecord(seat=1, value=110, elapsed_ms=500),  # same distance, faster
        2: AnswerRecord(seat=2, value=99, elapsed_ms=9000),  # closest
    }
    assert rank(q, [0, 1, 2, 3], answers) == [2, 1, 0, 3]


def test_time_bonus_is_subtracted():
    q = mcq(correct=0)
    answers = {
        0: AnswerRecord(seat=0, choice=0, elapsed_ms=2100),
        1: AnswerRecord(seat=1, choice=0, elapsed_ms=2000),
    }
    assert rank(q, [0, 1], answers) == [1, 0]
    assert rank(q, [0, 1], answers, {0: 200}) == [0, 1]


# --- questions and validation -----------------------------------------------------------


def test_start_requests_numeric_question_for_everyone():
    s = new_match(grid_map(3), [Army.ROMAN] * 3)
    ev = step(s, StartMatch())
    assert s.phase is Phase.EXP_QUESTION
    assert s.pending_question is QuestionKind.NUMERIC
    need = next(e for e in ev if e.type == "question_needed")
    assert need.data["participants"] == [0, 1, 2]


def test_question_event_never_contains_the_answer():
    s = started(grid_map(2), A2)
    ev = step(s, ProvideQuestion(question=numeric(answer=1234)))
    q = next(e for e in ev if e.type == "question")
    assert "answer" not in q.data and "correct_index" not in q.data
    assert 1234 not in q.data.values()


def test_wrong_question_kind_is_rejected():
    s = started(grid_map(2), A2)
    with pytest.raises(core.RuleError):
        step(s, ProvideQuestion(question=mcq()))


def test_late_duplicate_and_foreign_answers_are_rejected():
    s = started(grid_map(3), [Army.ROMAN] * 3)
    step(s, ProvideQuestion(question=numeric()))
    limit = s.settings.timers.numeric_ms + s.settings.timers.latency_grace_ms
    with pytest.raises(core.RuleError, match="late"):
        step(s, Answer(seat=0, value=1, elapsed_ms=limit + 1))
    step(s, Answer(seat=0, value=1, elapsed_ms=limit))  # exactly at the grace edge is fine
    with pytest.raises(core.RuleError, match="duplicate"):
        step(s, Answer(seat=0, value=2, elapsed_ms=100))
    with pytest.raises(core.RuleError):
        step(s, Answer(seat=7, value=2, elapsed_ms=100))


def test_rejected_action_leaves_state_unchanged_with_apply():
    s = started(grid_map(2), A2)
    before = s.model_dump()
    with pytest.raises(core.RuleError):
        core.apply(s, Answer(seat=0, value=1, elapsed_ms=10))  # no question yet
    assert s.model_dump() == before


def test_apply_does_not_mutate_input():
    s = started(grid_map(2), A2)
    before = s.model_dump()
    new, _ = core.apply(s, ProvideQuestion(question=numeric()))
    assert s.model_dump() == before
    assert new.active is not None


def test_stale_timeout_is_ignored():
    s = started(grid_map(2), A2)
    step(s, ProvideQuestion(question=numeric()))
    old = s.phase_id
    assert step(s, Timeout(phase_id=old - 1)) == []
    assert s.active is not None


def test_timeout_before_question_delivery_does_nothing():
    s = started(grid_map(2), A2)
    assert step(s, Timeout(phase_id=s.phase_id)) == []
    assert s.pending_question is QuestionKind.NUMERIC


def test_all_answers_resolve_without_waiting_for_timeout():
    s = started(grid_map(2), A2)
    step(s, ProvideQuestion(question=numeric(100)))
    step(s, Answer(seat=0, value=100, elapsed_ms=3000))
    ev = step(s, Answer(seat=1, value=50, elapsed_ms=1000))
    assert "question_result" in types(ev)
    assert s.phase is Phase.EXP_PICKS
    assert s.ranking == [0, 1]


# --- expansion ------------------------------------------------------------------------------


def answer_numeric(s, values: dict[int, float], answer=100):
    step(s, ProvideQuestion(question=numeric(answer)))
    for seat, v in values.items():
        step(s, Answer(seat=seat, value=v, elapsed_ms=1000 + seat))
    if s.phase is Phase.EXP_QUESTION:
        step(s, Timeout(phase_id=s.phase_id))


def test_top_half_picks_first_gets_two():
    s = started(grid_map(5), [Army.ROMAN] * 5)
    answer_numeric(s, {0: 50, 1: 99, 2: 80, 3: 10, 4: 70})
    assert s.ranking == [1, 2, 4, 0, 3]
    assert s.pick_quota == {1: 2, 2: 1, 4: 1}  # ceil(5/2) = 3 pickers


def test_conflict_goes_to_better_rank():
    # 0 - 1 - 2 - 3 - 4 with bases 0, 2, 4: territory 1 touches seats 0 and 1
    s = started(line_map(5, [0, 2, 4]), [Army.ROMAN] * 3)
    answer_numeric(s, {0: 90, 1: 100, 2: 0})  # rank: 1, 0, 2
    step(s, PickTerritories(seat=0, territories=[1]))
    ev = step(s, PickTerritories(seat=1, territories=[1, 3]))
    assert s.territories[1].owner == 1 and s.territories[3].owner == 1
    claimed = [e.data for e in ev if e.type == "territory_claimed"]
    assert [c["seat"] for c in claimed] == [1, 1]  # seat 0 got nothing: no free land left


def test_illegal_pick_is_replaced_by_a_legal_auto_pick():
    s = started(line_map(6, [0, 5]), A2)
    answer_numeric(s, {0: 100, 1: 0})
    ev = step(s, PickTerritories(seat=0, territories=[4, 3]))  # not adjacent to seat 0
    assert s.territories[1].owner == 0 and s.territories[2].owner == 0
    assert all(e.data["auto"] for e in ev if e.type == "territory_claimed" and e.data["seat"] == 0)


def test_pick_anywhere_when_no_adjacent_free_land():
    s = started(line_map(6, [0, 5]), A2)
    s.territories[1].owner = 1  # seat 0 is boxed in
    answer_numeric(s, {0: 100, 1: 0})
    step(s, PickTerritories(seat=0, territories=[3]))
    assert s.territories[3].owner == 0


def test_pick_timeout_auto_picks_and_expansion_repeats_until_full():
    s = started(line_map(8, [0, 7]), A2)
    rounds = 0
    while s.phase in (Phase.EXP_QUESTION, Phase.EXP_PICKS):
        answer_numeric(s, {0: 100, 1: 0})
        step(s, Timeout(phase_id=s.phase_id))
        rounds += 1
    assert all(t.owner is not None for t in s.territories.values())
    assert s.phase is Phase.BATTLE_TARGET
    assert rounds == 3  # 6 free, 2 picks per round (only the winner picks with 2 players)


def test_fewer_free_than_picks_stops_in_rank_order():
    s = started(line_map(3, [0, 2]), A2)
    answer_numeric(s, {0: 0, 1: 100})
    ev = step(s, PickTerritories(seat=1, territories=[1]))
    assert [e.type for e in ev].count("territory_claimed") == 1
    assert s.phase is Phase.BATTLE_TARGET


def test_no_answer_ranks_last_in_expansion():
    s = started(grid_map(3), [Army.ROMAN] * 3)
    answer_numeric(s, {1: 0, 2: 5})
    assert s.ranking[-1] == 0
