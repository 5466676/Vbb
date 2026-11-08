from app.bots.simple import Difficulty
from app.ranks import BOT_XP, level_of, match_xp, rank_of, total_xp


def test_match_xp_counts_play_answers_and_win():
    assert match_xp(0, False) == 10
    assert match_xp(8, True) == 10 + 40 + 30


def test_total_is_the_sum_of_matches():
    games = [(3, False), (10, True), (0, False)]
    assert total_xp(3, 13, 1) == sum(match_xp(c, w) for c, w in games)


def test_rank_thresholds():
    assert [rank_of(x) for x in (0, 199, 200, 600, 1500, 3499, 3500, 7000, 99999)] == [
        "E",
        "E",
        "D",
        "C",
        "B",
        "B",
        "A",
        "S",
        "S",
    ]


def test_level():
    assert level_of(0) == 1
    assert level_of(99) == 1
    assert level_of(250) == 3


def test_bots_rank_by_difficulty():
    assert rank_of(BOT_XP[Difficulty.EASY]) == "D"
    assert rank_of(BOT_XP[Difficulty.MEDIUM]) == "C"
    assert rank_of(BOT_XP[Difficulty.HARD]) == "A"
