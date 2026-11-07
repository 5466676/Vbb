"""Map templates (phase 3): structure, fairness and full bot matches on every template."""

import statistics

import pytest

from app.engine.models import Mode, Phase
from app.maps import MapKind, available, hops, load_template, map_for, template_id, validate
from tests.helpers import play_match

ALL = [(k, n) for k in MapKind for n in range(2, 9)]


def point_in_polygon(x: float, y: float, poly: list[list[float]]) -> bool:
    inside = False
    for i in range(len(poly)):
        x1, y1 = poly[i - 1]
        x2, y2 = poly[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def test_a_template_exists_for_every_kind_and_player_count():
    assert sorted(available()) == sorted(template_id(k, n) for k, n in ALL)


@pytest.mark.parametrize(("kind", "players"), ALL, ids=[template_id(k, n) for k, n in ALL])
def test_template_is_valid_and_fair(kind: MapKind, players: int):
    t = load_template(template_id(kind, players))
    assert validate(t) == []
    assert t["players"] == players and t["kind"] == kind.value
    assert 1.5 < t["aspect"] < 2.5
    for terr in t["territories"]:
        x, y = terr["label"]
        assert point_in_polygon(x, y, terr["polygon"]), f"label of {terr['id']} outside its polygon"
    graph = {x["id"]: x["neighbors"] for x in t["territories"]}
    bases = t["bases"]
    pair = [hops(graph, a)[b] for i, a in enumerate(bases) for b in bases[i + 1 :]]
    assert min(pair) >= 2
    # bases are listed west to east (team 0 gets the western half in team modes)
    xs = [t["territories"][b]["label"][0] for b in bases]
    assert xs == sorted(xs)


@pytest.mark.parametrize(("kind", "players"), ALL, ids=[template_id(k, n) for k, n in ALL])
def test_bot_matches_on_template(kind: MapKind, players: int):
    m = map_for(kind, players)
    lengths = []
    for seed in range(40):
        r = play_match(players, seed, map_def=m)
        assert r.state.phase is Phase.RESULTS
        assert r.state.map_id == m.id
        lengths.append(r.duration_ms / 60_000)
    if players in (4, 6, 8):
        for seed in range(15):
            r = play_match(players, 1000 + seed, mode=Mode.TEAMS, map_def=m)
            assert r.state.phase is Phase.RESULTS
    mean = statistics.mean(lengths)
    low = 6.0 if players == 2 else 7.5
    assert low <= mean <= 12.5, f"{m.id}: mean length {mean:.1f} min"
