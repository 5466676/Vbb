"""Map templates produced by ``maps/generate.py`` (phase 3).

Templates live in ``backend/maps/templates/<id>.json``. Coordinates are normalised to the
painted image (x, y in [0, 1]); the engine only needs the territory graph and the bases.
"""

from __future__ import annotations

import json
from collections import deque
from enum import StrEnum
from functools import lru_cache
from pathlib import Path

from app.engine.models import MapDef, TerritoryDef

PER_PLAYER = 5
TEMPLATES = Path(__file__).resolve().parents[1] / "maps" / "templates"


class MapKind(StrEnum):
    FANTASY = "fantasy"
    WORLD = "world"


def template_id(kind: MapKind, players: int) -> str:
    return f"{kind.value}-{players}p"


@lru_cache
def load_template(map_id: str) -> dict:
    path = TEMPLATES / f"{map_id}.json"
    if not path.is_file():
        raise KeyError(f"unknown map {map_id}")
    return json.loads(path.read_text())


def to_map_def(template: dict) -> MapDef:
    return MapDef(
        id=template["id"],
        territories=[
            TerritoryDef(id=t["id"], neighbors=t["neighbors"]) for t in template["territories"]
        ],
        bases=template["bases"],
    )


def map_for(kind: MapKind, players: int) -> MapDef:
    """The engine map for a match of ``players`` on a ``kind`` map."""
    return to_map_def(load_template(template_id(kind, players)))


def available() -> list[str]:
    return sorted(p.stem for p in TEMPLATES.glob("*.json"))


def hops(graph: dict[int, list[int]], start: int) -> dict[int, int]:
    """Breadth-first hop distance from ``start``."""
    dist = {start: 0}
    q = deque([start])
    while q:
        u = q.popleft()
        for v in graph[u]:
            if v not in dist:
                dist[v] = dist[u] + 1
                q.append(v)
    return dist


def validate(t: dict) -> list[str]:
    """Return a list of problems (empty = valid). Also used by the test-suite."""
    errs = []
    n = t["players"] * PER_PLAYER
    terrs = t["territories"]
    if len(terrs) != n:
        errs.append(f"{len(terrs)} territories, expected {n}")
    ids = {x["id"] for x in terrs}
    if ids != set(range(len(terrs))):
        errs.append("territory ids must be 0..N-1")
    graph = {x["id"]: x["neighbors"] for x in terrs}
    for link in t["sea_links"]:
        if link["b"] not in graph.get(link["a"], []):
            errs.append(f"sea link {link['a']}-{link['b']} missing from neighbours")
    for a, nbs in graph.items():
        if not nbs:
            errs.append(f"territory {a} has no neighbours")
        for b in nbs:
            if a not in graph.get(b, []):
                errs.append(f"neighbour link {a}-{b} is not symmetric")
    if graph and len(hops(graph, 0)) != len(graph):
        errs.append("map is not connected")
    bases = t["bases"]
    if len(bases) != t["players"] or len(set(bases)) != len(bases):
        errs.append("need one distinct base per player")
    elif graph:
        d = min(hops(graph, a)[b] for i, a in enumerate(bases) for b in bases[i + 1 :])
        if d < 2:
            errs.append("two bases are adjacent")
    areas = [x["area"] for x in terrs]
    max_spread = 4 if t["kind"] == "fantasy" else 8  # real continents differ a lot in size
    if areas and max(areas) / min(areas) > max_spread:
        errs.append(f"territory sizes too uneven ({max(areas) / min(areas):.1f}x)")
    for x in terrs:
        if len(x["polygon"]) < 3:
            errs.append(f"territory {x['id']} has a degenerate polygon")
        if not all(0 <= v <= 1 for p in x["polygon"] for v in p):
            errs.append(f"territory {x['id']} polygon outside [0,1]")
    return errs
