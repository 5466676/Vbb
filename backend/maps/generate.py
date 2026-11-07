"""Offline map-template generator (phase 3).

For every painted map it reads the land mask, splits the playable land into
``players * 5`` territories, finds neighbours and sea links, places bases far apart,
validates the result and writes ``templates/<id>.json`` (+ a preview PNG with ``--preview``).

Coordinates in the JSON are normalised: x and y in [0, 1] over the painted image, so the
client draws the painting over the whole map rectangle and the polygons on top.

Usage (from backend/):  python -m maps.generate [--preview DIR] [--only fantasy-4p]
Needs the ``maps`` extra: numpy, scipy, scikit-image, pillow.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import deque
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage.measure import approximate_polygon, find_contours

from app.maps import PER_PLAYER, hops, validate

HERE = Path(__file__).resolve().parent
SHAPES = HERE / "shapes"
OUT = HERE / "templates"
WORK_W, WORK_H = 1024, 512  # partition resolution
LLOYD_ITERS = 12
BALANCE_ITERS = 12
MIN_ISLAND_SHARE = 0.35  # an island needs this fraction of an average territory to be playable
SEA_LINK_NEAR = 0.06  # extra sea links between land masses closer than this (fraction of width)

# The 4-player continent comes from the first mockup (844x390 space), not from a mask file.
FANTASY_4P_COAST = (
    "764,200 763,206 755,212 746,217 741,223 740,229 738,235 734,240 732,246 737,253 743,261 "
    "741,268 728,272 708,275 690,277 677,280 665,284 652,287 641,290 634,296 630,303 623,309 "
    "609,311 591,311 574,311 560,312 547,315 533,315 517,313 502,311 488,311 475,309 461,306 "
    "448,301 436,298 425,300 413,307 399,314 384,320 369,324 352,327 335,330 319,331 305,328 "
    "292,324 277,323 259,324 240,324 224,322 212,317 201,312 188,309 174,305 164,300 156,294 "
    "145,289 131,286 118,281 115,274 123,265 136,256 146,248 151,241 155,235 158,229 157,224 "
    "147,220 132,216 122,211 121,205 124,200 124,195 118,189 112,183 112,177 117,172 121,166 "
    "125,161 133,156 149,153 166,150 178,147 178,141 174,134 173,127 177,121 183,115 190,110 "
    "199,105 213,103 231,103 247,102 256,98 263,91 271,85 283,82 296,79 308,75 319,70 332,65 "
    "346,61 360,57 375,52 390,46 407,42 425,44 442,51 457,59 470,66 483,72 495,78 505,84 517,87 "
    "530,88 544,89 555,92 562,98 568,104 577,108 588,110 600,112 609,116 617,120 627,123 638,126 "
    "646,130 648,135 652,140 664,143 687,144 712,145 734,147 750,151 764,156 775,161 781,168 "
    "776,174 766,182 759,188 760,194"
)


@dataclass(frozen=True)
class Source:
    id: str
    kind: str  # "fantasy" | "world"
    players: int
    image: str  # path of the painting, relative to app/
    aspect: float  # width / height of the painting


def sources() -> list[Source]:
    out = []
    for n in range(2, 9):
        aspect = 1688 / 780 if n == 4 else 2048 / (1024 if n == 7 else 1013)
        out.append(Source(f"fantasy-{n}p", "fantasy", n, f"assets/maps/fantasy-{n}p.jpg", aspect))
    for n in range(2, 9):
        out.append(Source(f"world-{n}p", "world", n, "assets/maps/real-world.jpg", 2048 / 1013))
    return out


# ------------------------------------------------------------------------------------------
# Land mask
# ------------------------------------------------------------------------------------------


def load_mask(src: Source) -> np.ndarray:
    if src.id == "fantasy-4p":
        img = Image.new("L", (WORK_W, WORK_H), 0)
        pts = [tuple(map(float, p.split(","))) for p in FANTASY_4P_COAST.split()]
        ImageDraw.Draw(img).polygon(
            [(x / 844 * WORK_W, y / 390 * WORK_H) for x, y in pts], fill=255
        )
        return np.array(img) > 0
    name = f"fantasy-{src.players}p" if src.kind == "fantasy" else "real-world"
    img = (
        Image.open(SHAPES / f"{name}-mask.png").convert("L").resize((WORK_W, WORK_H), Image.NEAREST)
    )
    return np.array(img) > 127


def playable_components(mask: np.ndarray, n_regions: int) -> tuple[np.ndarray, list[int]]:
    """Label land masses and keep those big enough to hold part of a territory."""
    lab, n = ndimage.label(mask)
    areas = ndimage.sum(mask, lab, range(1, n + 1))
    avg = mask.sum() / n_regions
    keep = [i + 1 for i, a in enumerate(areas) if a >= MIN_ISLAND_SHARE * avg]
    return lab, keep


def allocate(areas: list[float], total: int) -> list[int]:
    """Largest-remainder allocation of ``total`` regions by area, at least 1 each."""
    s = sum(areas)
    raw = [a / s * total for a in areas]
    out = [max(1, math.floor(r)) for r in raw]
    while sum(out) > total:
        i = max(range(len(out)), key=lambda k: (out[k] - raw[k], out[k]))
        out[i] -= 1
    while sum(out) < total:
        i = max(range(len(out)), key=lambda k: raw[k] - out[k])
        out[i] += 1
    return out


# ------------------------------------------------------------------------------------------
# Geodesic k-means: regions are always connected and follow the land shape
# ------------------------------------------------------------------------------------------


def grow(region: np.ndarray, seeds: list[tuple[int, int]], first_label: int) -> np.ndarray:
    """Multi-source BFS over the pixels of ``region`` (4-neighbour). Returns labels (0 = none)."""
    h, w = region.shape
    labels = np.zeros((h, w), dtype=np.int32)
    q: deque[tuple[int, int]] = deque()
    for k, (r, c) in enumerate(seeds):
        labels[r, c] = first_label + k
        q.append((r, c))
    while q:
        r, c = q.popleft()
        lab = labels[r, c]
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rr, cc = r + dr, c + dc
            if 0 <= rr < h and 0 <= cc < w and region[rr, cc] and labels[rr, cc] == 0:
                labels[rr, cc] = lab
                q.append((rr, cc))
    return labels


def weighted_grow(
    region: np.ndarray, seeds: list[tuple[int, int]], weights: list[float], first_label: int
) -> np.ndarray:
    """Dijkstra from all seeds; region k spreads at speed ``weights[k]``. Regions stay connected."""
    import heapq

    h, w = region.shape
    labels = np.zeros((h, w), dtype=np.int32)
    heap = [(0.0, r, c, k) for k, (r, c) in enumerate(seeds)]
    heapq.heapify(heap)
    steps = (
        (1, 0, 1.0),
        (-1, 0, 1.0),
        (0, 1, 1.0),
        (0, -1, 1.0),
        (1, 1, 1.4142),
        (1, -1, 1.4142),
        (-1, 1, 1.4142),
        (-1, -1, 1.4142),
    )
    while heap:
        d, r, c, k = heapq.heappop(heap)
        if labels[r, c]:
            continue
        labels[r, c] = first_label + k
        for dr, dc, cost in steps:
            rr, cc = r + dr, c + dc
            if 0 <= rr < h and 0 <= cc < w and region[rr, cc] and not labels[rr, cc]:
                heapq.heappush(heap, (d + cost / weights[k], rr, cc, k))
    return labels


def balance(region: np.ndarray, seeds: list[tuple[int, int]], first_label: int) -> np.ndarray:
    """Adjust per-region speeds until sizes are close to equal (power-diagram style)."""
    k = len(seeds)
    weights = [1.0] * k
    target = region.sum() / k
    best, best_spread = None, float("inf")
    for _ in range(BALANCE_ITERS):
        labels = weighted_grow(region, seeds, weights, first_label)
        sizes = np.bincount(labels.ravel(), minlength=first_label + k)[first_label:]
        spread = sizes.max() / max(1, sizes.min())
        if spread < best_spread:
            best, best_spread = labels, spread
        if spread < 1.3:
            break
        weights = [w * (target / max(1, s)) ** 0.5 for w, s in zip(weights, sizes, strict=True)]
    assert best is not None
    return best


def partition(
    component: np.ndarray, k: int, first_label: int, rng: np.random.Generator
) -> np.ndarray:
    ys, xs = np.nonzero(component)
    pts = np.stack([ys, xs], axis=1)
    # k-means++ style spread of the initial seeds
    seeds = [tuple(pts[rng.integers(len(pts))])]
    for _ in range(1, k):
        d = np.min([((pts - np.array(s)) ** 2).sum(1) for s in seeds], axis=0)
        seeds.append(tuple(pts[int(np.argmax(d))]))
    labels = grow(component, seeds, first_label)
    for _ in range(LLOYD_ITERS):
        new = []
        for j in range(k):
            ry, rx = np.nonzero(labels == first_label + j)
            if len(ry) == 0:
                new.append(seeds[j])
                continue
            cy, cx = ry.mean(), rx.mean()
            i = int(np.argmin((ry - cy) ** 2 + (rx - cx) ** 2))
            new.append((int(ry[i]), int(rx[i])))
        if new == seeds:
            break
        seeds = new
        labels = grow(component, seeds, first_label)
    return balance(component, seeds, first_label)


# ------------------------------------------------------------------------------------------
# Graph, polygons, bases
# ------------------------------------------------------------------------------------------


def land_neighbors(labels: np.ndarray, min_shared: int = 3) -> dict[int, set[int]]:
    pairs: dict[tuple[int, int], int] = {}
    for a, b in ((labels[:, :-1], labels[:, 1:]), (labels[:-1, :], labels[1:, :])):
        m = (a != b) & (a > 0) & (b > 0)
        for x, y in zip(a[m].tolist(), b[m].tolist(), strict=True):
            key = (min(x, y), max(x, y))
            pairs[key] = pairs.get(key, 0) + 1
    nb: dict[int, set[int]] = {}
    for (x, y), count in pairs.items():
        if count >= min_shared:
            nb.setdefault(x, set()).add(y)
            nb.setdefault(y, set()).add(x)
    return nb


def sea_links(labels: np.ndarray, comp_of: dict[int, int]) -> list[tuple[int, int, list, list]]:
    """Connect separate land masses: a minimum spanning tree plus any very close pairs."""
    comps = sorted(set(comp_of.values()))
    if len(comps) < 2:
        return []
    edge_px: dict[int, np.ndarray] = {}
    for t in comp_of:
        m = labels == t
        border = m & ~ndimage.binary_erosion(m)
        ys, xs = np.nonzero(border)
        edge_px[t] = np.stack([ys, xs], 1)[:: max(1, len(ys) // 400)]
    best: dict[tuple[int, int], tuple[float, int, int, list, list]] = {}
    for a in comp_of:
        for b in comp_of:
            ca, cb = comp_of[a], comp_of[b]
            if ca >= cb:
                continue
            dm = np.sqrt(((edge_px[a][:, None, :] - edge_px[b][None, :, :]) ** 2).sum(-1))
            i, j = np.unravel_index(int(np.argmin(dm)), dm.shape)
            d = float(dm[i, j])
            key = (ca, cb)
            if key not in best or d < best[key][0]:
                best[key] = (d, a, b, edge_px[a][i].tolist(), edge_px[b][j].tolist())
    # Kruskal over land masses
    parent = {c: c for c in comps}

    def find(c: int) -> int:
        while parent[c] != c:
            parent[c] = parent[parent[c]]
            c = parent[c]
        return c

    links = []
    for (ca, cb), (d, a, b, pa, pb) in sorted(best.items(), key=lambda kv: kv[1][0]):
        joined = find(ca) != find(cb)
        if joined:
            parent[find(ca)] = find(cb)
        if joined or d < SEA_LINK_NEAR * labels.shape[1]:
            links.append((a, b, pa, pb))
    return links


def polygon(mask: np.ndarray) -> list[list[float]]:
    padded = np.pad(mask, 1).astype(float)
    contours = find_contours(padded, 0.5)
    ring = max(contours, key=len)
    ring = approximate_polygon(ring, tolerance=1.0)
    h, w = mask.shape
    return [[round((c - 1) / w, 4), round((r - 1) / h, 4)] for r, c in ring[:-1]]


def label_point(mask: np.ndarray) -> list[float]:
    """The most interior pixel (for the shield / castle)."""
    dist = ndimage.distance_transform_edt(np.pad(mask, 1))[1:-1, 1:-1]
    r, c = np.unravel_index(int(np.argmax(dist)), dist.shape)
    h, w = mask.shape
    return [round(c / w, 4), round(r / h, 4)]


def place_bases(graph: dict[int, list[int]], k: int, pos: dict[int, list[float]]) -> list[int]:
    """Maximise the minimum hop distance between bases, then balance the land each base 'owns'."""
    nodes = sorted(graph)
    dist = {n: hops(graph, n) for n in nodes}

    def quality(bases: list[int]) -> tuple:
        min_d = min(dist[a][b] for i, a in enumerate(bases) for b in bases[i + 1 :])
        # territories closest to each base (ties shared) -> spread of these counts
        share = [0.0] * len(bases)
        for n in nodes:
            ds = [dist[b][n] for b in bases]
            best = min(ds)
            win = [i for i, d in enumerate(ds) if d == best]
            for i in win:
                share[i] += 1 / len(win)
        return (min_d, -(max(share) - min(share)), sum(dist[a][b] for a in bases for b in bases))

    best_bases: list[int] | None = None
    best_q: tuple | None = None
    for start in nodes:
        bases = [start]
        while len(bases) < k:
            bases.append(
                max(
                    (n for n in nodes if n not in bases),
                    key=lambda n: min(dist[b][n] for b in bases),
                )
            )
        improved = True
        while improved:  # swap search
            improved = False
            q = quality(bases)
            for i in range(k):
                for n in nodes:
                    if n in bases:
                        continue
                    trial = bases[:i] + [n] + bases[i + 1 :]
                    tq = quality(trial)
                    if tq > q:
                        bases, q, improved = trial, tq, True
        q = quality(bases)
        if best_q is None or q > best_q:
            best_bases, best_q = bases, q
    assert best_bases is not None
    # left-to-right order: in team modes seats 0..k/2-1 (team 0) get the western bases
    return sorted(best_bases, key=lambda t: (pos[t][0], pos[t][1]))


# ------------------------------------------------------------------------------------------
# Template
# ------------------------------------------------------------------------------------------


def build(src: Source, seed: int = 7) -> tuple[dict, np.ndarray]:
    n_regions = src.players * PER_PLAYER
    mask = load_mask(src)
    lab, keep = playable_components(mask, n_regions)
    areas = [float((lab == c).sum()) for c in keep]
    counts = allocate(areas, n_regions)
    rng = np.random.default_rng(seed)
    labels = np.zeros(mask.shape, dtype=np.int32)
    comp_of: dict[int, int] = {}
    next_label = 1
    for comp, k in zip(keep, counts, strict=True):
        part = partition(lab == comp, k, next_label, rng)
        labels[part > 0] = part[part > 0]
        for j in range(k):
            comp_of[next_label + j] = comp
        next_label += k
    nb = land_neighbors(labels)
    links = sea_links(labels, comp_of)
    for a, b, _, _ in links:
        nb.setdefault(a, set()).add(b)
        nb.setdefault(b, set()).add(a)
    ids = sorted(comp_of)
    remap = {old: i for i, old in enumerate(ids)}  # territory ids 0..N-1
    graph = {remap[t]: sorted(remap[x] for x in nb.get(t, ())) for t in ids}
    pos = {remap[t]: label_point(labels == t) for t in ids}
    bases = place_bases(graph, src.players, pos)
    territories = []
    for t in ids:
        m = labels == t
        territories.append(
            {
                "id": remap[t],
                "polygon": polygon(m),
                "label": pos[remap[t]],
                "area": round(float(m.sum()) / mask.size, 5),
                "neighbors": graph[remap[t]],
            }
        )
    template = {
        "id": src.id,
        "kind": src.kind,
        "players": src.players,
        "image": src.image,
        "aspect": round(src.aspect, 4),
        "territories": territories,
        "sea_links": sorted(
            (
                {
                    "a": remap[a],
                    "b": remap[b],
                    "from": [round(pa[1] / WORK_W, 4), round(pa[0] / WORK_H, 4)],
                    "to": [round(pb[1] / WORK_W, 4), round(pb[0] / WORK_H, 4)],
                }
                for a, b, pa, pb in links
            ),
            key=lambda x: (x["a"], x["b"]),
        ),
        "bases": bases,
    }
    remapped = np.zeros_like(labels)
    for t in ids:
        remapped[labels == t] = remap[t] + 1
    return template, remapped


def preview(t: dict, labels: np.ndarray, out: Path) -> None:
    """Draw territories, links and bases over the painting for a visual check."""
    app = HERE.parent.parent / "app"
    img = Image.open(app / t["image"]).convert("RGB").resize((1200, 600))
    d = ImageDraw.Draw(img, "RGBA")
    w, h = img.size
    palette = [
        (46, 158, 58),
        (198, 40, 40),
        (31, 111, 184),
        (126, 87, 194),
        (230, 126, 34),
        (212, 160, 23),
        (214, 63, 140),
        (19, 141, 144),
    ]
    for x in t["territories"]:
        pts = [(px * w, py * h) for px, py in x["polygon"]]
        d.polygon(pts, fill=palette[x["id"] % 8] + (70,), outline=(59, 36, 20, 255))
    for link in t["sea_links"]:
        pa, pb = link["from"], link["to"]
        d.line([(pa[0] * w, pa[1] * h), (pb[0] * w, pb[1] * h)], fill=(255, 255, 255, 220), width=3)
    for i, b in enumerate(t["bases"]):
        x, y = t["territories"][b]["label"]
        d.ellipse([x * w - 10, y * h - 10, x * w + 10, y * h + 10], fill=(0, 0, 0, 230))
        d.text((x * w - 4, y * h - 7), str(i), fill=(255, 255, 255, 255))
    img.save(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", type=Path)
    ap.add_argument("--only")
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)
    for src in sources():
        if args.only and src.id != args.only:
            continue
        template, labels = build(src)
        problems = validate(template)
        if problems:
            raise SystemExit(f"{src.id}: " + "; ".join(problems))
        (OUT / f"{src.id}.json").write_text(json.dumps(template, separators=(",", ":")))
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            preview(template, labels, args.preview / f"{src.id}.png")
        sizes = [x["area"] for x in template["territories"]]
        print(
            f"{src.id}: {len(template['territories'])} territories, "
            f"{len(template['sea_links'])} sea links, "
            f"size spread {max(sizes) / min(sizes):.2f}x, bases {template['bases']}"
        )


if __name__ == "__main__":
    main()
