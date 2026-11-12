#!/usr/bin/env python3
"""Convert a painted map image into a game map JSON.

Colours: green = ground, light grey = low walkable hills (large areas become flat
plateaus), dark grey = impassable mountains, blue = water, red dots = start markers.

Usage:
    python3 tools/png_to_map.py source_art/maps/map_1.png Valleys --width 3200 --height 3136

The terrain is rebuilt with the same formulas as game_assets/MapConfig.gd and checked on
the game's 20-unit walkability grid before the JSON is written.
"""

import argparse
import heapq
import itertools
import json
import math
import random
import sys
from collections import deque
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
MAPS_DIR = REPO / "game_assets" / "maps"

GROUND, LIGHT, DARK, WATER, RED = 0, 1, 2, 3, 4
PALETTE = np.array([
    (99, 151, 62),
    (146, 146, 144),
    (122, 122, 121),
    (45, 132, 227),
    (151, 64, 60),
], dtype=np.float32)

# Must match game_assets/MapConfig.gd, World.gd, WalkabilityGrid.gd, WaterBuilder.gd.
GROUND_HEIGHT = 5.0
STEP = 20.0
MAX_SLOPE_DEG = 45.0
SURFACE_CLIP_EPSILON = 0.05
EDGE_STOP = 80.0
SPAWN_SPREAD = 40.0

FRAME_PX = 14
MIN_REGION_PX = 120

DARK_HEIGHT = (62.0, 82.0)
DARK_FALLOFF = 24.0
LIGHT_FLAT_HEIGHT = 30.0
LIGHT_SMALL_HEIGHT = (14.0, 20.0)
LIGHT_LARGE_AREA_PX = 6000
LIGHT_FALLOFF = 160.0
WATER_DEPTH = 40.0
WATER_SURFACE = 3.0

# Capture-point placement (walking distances in world units).
VILLAGE_DIST = 350.0
VILLAGE_EDGE_MARGIN = 150.0
CP_MIN_START_DIST = 700.0
CP_SPACING = 450.0
PAIR_SPACING = 500.0
# (type, target walking distance from each start to its nearest one)
PAIR_TYPES = [("Stables", 1900.0), ("Blacksmith", 1600.0), ("Archery", 2300.0)]
BALANCE_TOLERANCE = 0.05


def classify(path):
    rgb = np.array(Image.open(path).convert("RGB"), dtype=np.float32)
    rgb = rgb[FRAME_PX:-FRAME_PX, FRAME_PX:-FRAME_PX]
    d = ((rgb[:, :, None, :] - PALETTE[None, None, :, :]) ** 2).sum(axis=3)
    # Blur between two colours averages to something near dark grey in RGB, so only
    # near-neutral pixels may be grey; everything else picks among the hues.
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    neutral = sat < 14.0
    d[neutral] = np.where(np.isin(np.arange(5), [LIGHT, DARK]), d[neutral], np.inf)
    d[~neutral] = np.where(np.isin(np.arange(5), [LIGHT, DARK]), np.inf, d[~neutral])
    labels = d.argmin(axis=2).astype(np.uint8)
    red = labels == RED
    # Majority filter: blur fringes between colours snap to the dominant neighbour.
    # Start dots take whatever terrain surrounds them.
    votes = np.stack([
        cv2.blur((labels == c).astype(np.float32), (9, 9)) for c in range(4)
    ], axis=2)
    wide = np.stack([
        cv2.blur((labels == c).astype(np.float32), (41, 41)) for c in range(4)
    ], axis=2)
    near_red = cv2.dilate(red.astype(np.uint8), np.ones((9, 9), np.uint8)).astype(bool)
    votes[near_red] = wide[near_red]
    labels = votes.argmax(axis=2).astype(np.uint8)
    return labels, red


def components(mask, min_px=MIN_REGION_PX):
    n, cc, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8), connectivity=4)
    out = []
    for k in range(1, n):
        if stats[k, cv2.CC_STAT_AREA] >= min_px:
            out.append(cc == k)
    return out


def contour_of(mask, max_points=40):
    m = mask.astype(np.uint8)
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cs:
        return None
    c = max(cs, key=cv2.contourArea)
    eps = 1.0
    approx = cv2.approxPolyDP(c, eps, True)
    while len(approx) > max_points:
        eps *= 1.25
        approx = cv2.approxPolyDP(c, eps, True)
    if len(approx) < 3:
        return None
    return approx[:, 0, :].astype(np.float64)


class Scale:
    def __init__(self, img_w, img_h, map_w, map_h):
        self.sx = map_w / img_w
        self.sy = map_h / img_h

    def pt(self, px, py):
        return ((px + 0.5) * self.sx, (py + 0.5) * self.sy)

    def poly(self, pts):
        return [{"x": round(self.pt(p[0], p[1])[0], 1), "y": round(self.pt(p[0], p[1])[1], 1)} for p in pts]

    def to_px(self, x, z):
        return (x / self.sx - 0.5, z / self.sy - 0.5)


def dark_features(labels, scale, rng):
    feats = []
    for mask in components(labels == DARK):
        pts = contour_of(mask)
        if pts is None:
            continue
        feats.append({
            "type": "plateau_polygon",
            "points": scale.poly(pts),
            "height": round(rng.uniform(*DARK_HEIGHT), 1),
            "falloff": DARK_FALLOFF,
        })
        # Crags at distance-transform peaks, sized to stay well inside the region.
        dist = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
        avail = dist.copy()
        for _ in range(14):
            j, i = np.unravel_index(np.argmax(avail), avail.shape)
            r_px = float(dist[j, i])
            if r_px < 6.0:
                break
            x, z = scale.pt(i, j)
            r_world = r_px * min(scale.sx, scale.sy)
            feats.append({
                "type": "hill",
                "x": round(x, 1),
                "y": round(z, 1),
                "base_width": round(1.8 * r_world, 1),
                "height": round(rng.uniform(95.0, 155.0) * min(1.0, 0.55 + r_px / 60.0), 1),
            })
            yy, xx = np.ogrid[:avail.shape[0], :avail.shape[1]]
            avail[(xx - i) ** 2 + (yy - j) ** 2 <= (1.3 * r_px) ** 2] = 0
    return feats


def light_features(labels, scale, rng):
    feats = []
    for mask in components(labels == LIGHT):
        area = int(mask.sum())
        dist = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
        thick = float(dist.max())
        # The exterior falloff spreads outward; pull the edge in so the slope sits
        # inside the painted shape.
        erode_px = int(min(7.0, thick * 0.4))
        m = mask.astype(np.uint8)
        if erode_px >= 1:
            k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * erode_px + 1, 2 * erode_px + 1))
            eroded = cv2.erode(m, k)
            if eroded.sum() > area * 0.3:
                m = eroded
        pts = contour_of(m)
        if pts is None:
            continue
        if area >= LIGHT_LARGE_AREA_PX:
            height = LIGHT_FLAT_HEIGHT
        else:
            t = min(1.0, thick / 25.0)
            height = LIGHT_SMALL_HEIGHT[0] + (LIGHT_SMALL_HEIGHT[1] - LIGHT_SMALL_HEIGHT[0]) * t
            height += rng.uniform(-1.5, 1.5)
        feats.append({
            "type": "plateau_polygon",
            "points": scale.poly(pts),
            "height": round(height, 1),
            "falloff": LIGHT_FALLOFF,
        })
    return feats


def water_features(labels, scale):
    feats = []
    regions = []
    for mask in components(labels == WATER):
        pts = contour_of(mask, max_points=48)
        if pts is None:
            continue
        dist = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
        # Rim from the typical channel half-width so narrow river parts still carve deep.
        inner = dist[dist > 0]
        half_w = float(np.percentile(inner, 75)) * min(scale.sx, scale.sy)
        rim = max(25.0, min(60.0, half_w * 0.7))
        feats.append({
            "type": "valley_polygon",
            "points": scale.poly(pts),
            "depth": WATER_DEPTH,
            "falloff": round(rim, 1),
        })
        regions.append(mask)
    return feats, regions


def green_hills(labels, scale, starts_world, rng, count=38):
    green = (labels == GROUND).astype(np.uint8)
    clear = cv2.distanceTransform(green, cv2.DIST_L2, 5) * min(scale.sx, scale.sy)
    ys, xs = np.nonzero(clear > 150.0)
    feats = []
    placed = []
    order = rng.sample(range(len(xs)), len(xs))
    for idx in order:
        if len(feats) >= count:
            break
        x, z = scale.pt(xs[idx], ys[idx])
        if any((x - sx) ** 2 + (z - sz) ** 2 < 260.0 ** 2 for sx, sz in starts_world):
            continue
        if any((x - px) ** 2 + (z - pz) ** 2 < 280.0 ** 2 for px, pz in placed):
            continue
        c = float(clear[ys[idx], xs[idx]])
        bw = min(rng.uniform(250.0, 500.0), c * 2.6)
        placed.append((x, z))
        feats.append({
            "type": "hill",
            "x": round(x, 1),
            "y": round(z, 1),
            "base_width": round(bw, 1),
            "height": round(rng.uniform(8.0, 16.0), 1),
        })
    return feats


def start_markers(red, scale):
    n, _, stats, cents = cv2.connectedComponentsWithStats(red.astype(np.uint8))
    pts = [cents[k] for k in range(1, n) if stats[k, cv2.CC_STAT_AREA] >= 6]
    world = [scale.pt(p[0], p[1]) for p in pts]
    if len(world) != 4:
        sys.exit("expected 4 red start markers, found %d" % len(world))
    cx = sum(p[0] for p in world) / 4.0
    cz = sum(p[1] for p in world) / 4.0

    def corner(p):
        return ("N" if p[1] < cz else "S") + ("W" if p[0] < cx else "E")

    by = {corner(p): p for p in world}
    order = ["NW", "SE", "NE", "SW"]
    if set(by) != set(order):
        sys.exit("start markers are not one per corner: %s" % sorted(by))
    return [(c, by[c]) for c in order]


# ---- Height model (mirrors MapConfig.sample_height) ----

def _point_in_poly(px, pz, poly):
    inside = np.zeros(px.shape, dtype=bool)
    n = len(poly)
    for k in range(n):
        ax, az = poly[k]
        bx, bz = poly[(k + 1) % n]
        cond = (az > pz) != (bz > pz)
        with np.errstate(divide="ignore", invalid="ignore"):
            xint = (bx - ax) * (pz - az) / (bz - az) + ax
        inside ^= cond & (px < xint)
    return inside


def _edge_dist(px, pz, poly):
    best = np.full(px.shape, np.inf)
    n = len(poly)
    for k in range(n):
        ax, az = poly[k]
        bx, bz = poly[(k + 1) % n]
        dx, dz = bx - ax, bz - az
        ll = dx * dx + dz * dz
        if ll < 1e-9:
            t = np.zeros(px.shape)
        else:
            t = np.clip(((px - ax) * dx + (pz - az) * dz) / ll, 0.0, 1.0)
        cx, cz = ax + dx * t, az + dz * t
        best = np.minimum(best, (px - cx) ** 2 + (pz - cz) ** 2)
    return np.sqrt(best)


def _smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def heights_grid(features, map_w, map_h):
    cols = int(math.ceil(map_w / STEP)) + 1
    rows = int(math.ceil(map_h / STEP)) + 1
    pz, px = np.meshgrid(np.arange(rows) * STEP, np.arange(cols) * STEP, indexing="ij")
    positive = np.zeros(px.shape)
    carve = np.zeros(px.shape)
    for f in features:
        t = f["type"]
        if t == "hill":
            s = f["base_width"] / 6.0
            d2 = (px - f["x"]) ** 2 + (pz - f["y"]) ** 2
            positive = np.maximum(positive, f["height"] * np.exp(-d2 / (2 * s * s)))
        elif t == "plateau_polygon":
            poly = [(p["x"], p["y"]) for p in f["points"]]
            s = f["falloff"] / 6.0
            inside = _point_in_poly(px, pz, poly)
            ed = _edge_dist(px, pz, poly)
            h = np.where(inside, f["height"], f["height"] * np.exp(-(ed * ed) / (2 * s * s)))
            positive = np.maximum(positive, h)
        elif t == "valley_polygon":
            poly = [(p["x"], p["y"]) for p in f["points"]]
            inside = _point_in_poly(px, pz, poly)
            ed = _edge_dist(px, pz, poly)
            c = np.where(inside, f["depth"] * _smoothstep(0.0, f["falloff"], ed), 0.0)
            carve = np.maximum(carve, c)
    return np.maximum(positive, GROUND_HEIGHT) - carve


def slope_blocked(h):
    rows, cols = h.shape
    pad = np.pad(h, 1, mode="edge")
    worst = np.zeros(h.shape)
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            if di == 0 and dj == 0:
                continue
            nb = pad[1 + dj:1 + dj + rows, 1 + di:1 + di + cols]
            dist = STEP * (math.sqrt(2.0) if di and dj else 1.0)
            worst = np.maximum(worst, np.degrees(np.arctan(np.abs(nb - h) / dist)))
    return worst > MAX_SLOPE_DEG


def flood(h, si, sj, surface):
    rows, cols = h.shape
    mask = np.zeros(h.shape, dtype=bool)
    seen = np.zeros(h.shape, dtype=bool)
    q = deque([(si, sj)])
    seen[sj, si] = True
    while q:
        i, j = q.popleft()
        if h[j, i] >= surface - SURFACE_CLIP_EPSILON:
            continue
        mask[j, i] = True
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ni, nj = i + di, j + dj
            if 0 <= ni < cols and 0 <= nj < rows and not seen[nj, ni]:
                seen[nj, ni] = True
                q.append((ni, nj))
    return mask


def region_cells(region_mask, scale, shape):
    rows, cols = shape
    out = np.zeros(shape, dtype=bool)
    ih, iw = region_mask.shape
    for j in range(rows):
        for i in range(cols):
            x, y = scale.to_px(i * STEP, j * STEP)
            xi, yi = int(round(x)), int(round(y))
            if 0 <= xi < iw and 0 <= yi < ih and region_mask[yi, xi]:
                out[j, i] = True
    return out


def lake_seeds(h, water_regions, scale):
    seeds = []
    water = np.zeros(h.shape, dtype=bool)
    coverage = []
    for k, region in enumerate(water_regions):
        cells = region_cells(region, scale, h.shape)
        covered = np.zeros(h.shape, dtype=bool)
        for _ in range(8):
            todo = cells & ~covered & ~water & (h < WATER_SURFACE - 1.0)
            if not todo.any():
                break
            hv = np.where(todo, h, np.inf)
            sj, si = np.unravel_index(np.argmin(hv), h.shape)
            rise = WATER_SURFACE - float(h[sj, si])
            m = flood(h, si, sj, WATER_SURFACE)
            if m.sum() < 3:
                covered[sj, si] = True
                continue
            seeds.append({"x": round(si * STEP, 1), "y": round(sj * STEP, 1), "rise": round(rise, 2)})
            covered |= m
            water |= m
        frac = float((covered & cells).sum()) / max(1, int(cells.sum()))
        coverage.append((k, int(cells.sum()), frac))
    return seeds, water, coverage


def reach(walk, si, sj):
    rows, cols = walk.shape
    seen = np.zeros(walk.shape, dtype=bool)
    if not walk[sj, si]:
        return seen
    q = deque([(si, sj)])
    seen[sj, si] = True
    while q:
        i, j = q.popleft()
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ni, nj = i + di, j + dj
            if 0 <= ni < cols and 0 <= nj < rows and walk[nj, ni] and not seen[nj, ni]:
                seen[nj, ni] = True
                q.append((ni, nj))
    return seen


def reach8(walk, si, sj):
    rows, cols = walk.shape
    seen = np.zeros(walk.shape, dtype=bool)
    if not walk[sj, si]:
        return seen
    q = deque([(si, sj)])
    seen[sj, si] = True
    while q:
        i, j = q.popleft()
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                ni, nj = i + di, j + dj
                if 0 <= ni < cols and 0 <= nj < rows and walk[nj, ni] and not seen[nj, ni]:
                    seen[nj, ni] = True
                    q.append((ni, nj))
    return seen


def walk_distance(walk, si, sj):
    """Walking distance (world units) from cell (si, sj) over 8-connected walkable cells."""
    rows, cols = walk.shape
    dist = np.full(walk.shape, np.inf)
    if not walk[sj, si]:
        return dist
    dist[sj, si] = 0.0
    pq = [(0.0, si, sj)]
    diag = STEP * math.sqrt(2.0)
    while pq:
        d, i, j = heapq.heappop(pq)
        if d > dist[j, i]:
            continue
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                if di == 0 and dj == 0:
                    continue
                ni, nj = i + di, j + dj
                if not (0 <= ni < cols and 0 <= nj < rows) or not walk[nj, ni]:
                    continue
                if di and dj and not (walk[j, ni] and walk[nj, i]):
                    continue
                nd = d + (diag if di and dj else STEP)
                if nd < dist[nj, ni]:
                    dist[nj, ni] = nd
                    heapq.heappush(pq, (nd, ni, nj))
    return dist


def place_villages(dist, candidates):
    """One village per start, the same walking distance from its own start, far from the
    others, on the side of the start that faces the map centre."""
    rows, cols = candidates.shape
    jj, ii = np.mgrid[:rows, :cols]
    margin = int(round(VILLAGE_EDGE_MARGIN / STEP))
    inside = (ii >= margin) & (ii < cols - margin) & (jj >= margin) & (jj < rows - margin)
    to_centre = np.hypot(ii - (cols - 1) / 2.0, jj - (rows - 1) / 2.0) * STEP
    out = []
    for k in range(len(dist)):
        own = dist[k]
        others = np.min(np.delete(dist, k, axis=0), axis=0)
        ok = candidates & inside & (np.abs(own - VILLAGE_DIST) <= 3 * STEP) & (others >= 2.0 * own) & np.isfinite(others)
        if not ok.any():
            return None
        score = np.full(own.shape, np.inf)
        score[ok] = np.abs(own[ok] - VILLAGE_DIST) + 0.1 * to_centre[ok]
        j, i = np.unravel_index(np.argmin(score), score.shape)
        out.append((float(i * STEP), float(j * STEP)))
    return out


def place_balanced_pair(dist, candidates, placed, target):
    """Two spots of one type so every start has the same walking distance to its nearest one.

    Scored by the spread of the nearest distance across starts, then the spread of the
    second-nearest, then closeness to `target`."""
    sub = np.zeros(candidates.shape, dtype=bool)
    sub[::2, ::2] = True
    ys, xs = np.nonzero(candidates & sub)
    pos = np.stack([xs * STEP, ys * STEP], axis=1).astype(np.float64)
    d = dist[:, ys, xs]
    ok = np.ones(len(xs), dtype=bool)
    for p in placed:
        ok &= ((pos - np.array(p)) ** 2).sum(axis=1) >= CP_SPACING ** 2
    idx = np.nonzero(ok)[0]
    best = None
    for a in idx:
        b = idx[idx > a]
        b = b[((pos[b] - pos[a]) ** 2).sum(axis=1) >= PAIR_SPACING ** 2]
        if len(b) == 0:
            continue
        near = np.minimum(d[:, a][:, None], d[:, b])
        far = np.maximum(d[:, a][:, None], d[:, b])
        sn = (near.max(axis=0) - near.min(axis=0)) / near.max(axis=0)
        sf = (far.max(axis=0) - far.min(axis=0)) / far.max(axis=0)
        score = sn + 0.3 * sf + 0.05 * np.abs(near.mean(axis=0) - target) / target
        k = int(np.argmin(score))
        if best is None or score[k] < best[0]:
            best = (score[k], tuple(pos[a]), tuple(pos[b[k]]))
    if best is None:
        return None
    return [best[1], best[2]]


def nearest_dists(dist, spots, shape):
    """Per start: walking distance to the nearest of `spots`."""
    return [
        min(float(dist[k][cell_of(x, z, shape)[::-1]]) for x, z in spots)
        for k in range(len(dist))
    ]


def nearest_spread(dist, spots, shape):
    nearest = nearest_dists(dist, spots, shape)
    return (max(nearest) - min(nearest)) / max(nearest)


def cell_of(x, z, shape):
    rows, cols = shape
    return (min(cols - 1, max(0, int(round(x / STEP)))), min(rows - 1, max(0, int(round(z / STEP)))))


CHEST_MIN_SEP = 150.0
CHEST_LAKE_CLEAR = 80.0
CHEST_COUNT = 8


def place_chests(width, height, avoid, lakes, count=CHEST_COUNT, min_sep=CHEST_MIN_SEP, lake_clear=CHEST_LAKE_CLEAR):
    """Eight chest points, each at least min_sep from starts, capture points, and other chests."""
    width = float(width)
    height = float(height)
    obstacles = [(float(p[0]), float(p[1])) for p in avoid]
    lake_pts = [(float(p[0]), float(p[1])) for p in lakes]
    placed = []
    for margin, step in ((100.0, 50.0), (60.0, 25.0), (40.0, 20.0)):
        candidates = []
        y = margin
        while y <= height - margin:
            x = margin
            while x <= width - margin:
                if _chest_clear(x, y, obstacles, lake_pts, min_sep, lake_clear):
                    candidates.append((x, y))
                x += step
            y += step
        placed = _pick_separated(candidates, obstacles, count, min_sep)
        if len(placed) >= count:
            break
    if len(placed) < count:
        raise RuntimeError(
            "could only place %d/%d chests on %.0fx%.0f with separation %.0f" % (
                len(placed), count, width, height, min_sep))
    return [{"id": "chest_%d" % (i + 1), "x": round(x, 1), "y": round(y, 1)} for i, (x, y) in enumerate(placed)]


def _chest_clear(x, y, obstacles, lakes, min_sep, lake_clear):
    for ox, oy in obstacles:
        if (x - ox) * (x - ox) + (y - oy) * (y - oy) < min_sep * min_sep:
            return False
    for lx, ly in lakes:
        if (x - lx) * (x - lx) + (y - ly) * (y - ly) < lake_clear * lake_clear:
            return False
    return True


def _pick_separated(candidates, obstacles, count, min_sep):
    placed = []
    unused = list(candidates)
    need = min_sep * min_sep
    for _ in range(count):
        best_i = -1
        best_score = -1.0
        for i, (x, y) in enumerate(unused):
            ok = True
            score = 1e9
            for px, py in placed:
                d2 = (x - px) * (x - px) + (y - py) * (y - py)
                if d2 < need:
                    ok = False
                    break
                score = min(score, d2)
            if not ok:
                continue
            if not placed:
                score = 0.0
                for ox, oy in obstacles:
                    score = max(score, (x - ox) * (x - ox) + (y - oy) * (y - oy))
                if not obstacles:
                    score = (x - 0.0) * (x - 0.0)
            if score > best_score:
                best_score = score
                best_i = i
        if best_i < 0:
            break
        placed.append(unused.pop(best_i))
    return placed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("name")
    ap.add_argument("--width", type=float, default=3200.0)
    ap.add_argument("--height", type=float, default=3136.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--debug", help="write a walkability preview PNG here")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    labels, red = classify(args.image)
    ih, iw = labels.shape
    scale = Scale(iw, ih, args.width, args.height)

    starts = start_markers(red, scale)
    starts_world = [p for _, p in starts]

    features = []
    features += green_hills(labels, scale, starts_world, rng)
    features += light_features(labels, scale, rng)
    features += dark_features(labels, scale, rng)
    water_feats, water_regions = water_features(labels, scale)
    features += water_feats

    h = heights_grid(features, args.width, args.height)
    seeds, water, coverage = lake_seeds(h, water_regions, scale)
    walk = ~slope_blocked(h) & ~water

    fails = []
    for k, n, frac in coverage:
        print("water region %d: %d cells, %.0f%% flooded" % (k, n, frac * 100))
        if n >= 6 and frac < 0.6:
            fails.append("water region %d is only %.0f%% flooded" % (k, frac * 100))

    base = starts_world[0]
    bi, bj = cell_of(base[0], base[1], h.shape)
    main_area = reach(walk, bi, bj)
    if not walk[bj, bi]:
        fails.append("start NW is not walkable")
    for corner, (x, z) in starts:
        i, j = cell_of(x, z, h.shape)
        if not main_area[j, i]:
            fails.append("start %s is not connected to NW" % corner)
        edge_x = EDGE_STOP if x <= args.width - x else args.width - EDGE_STOP
        for dz in (-SPAWN_SPREAD, 0.0, SPAWN_SPREAD):
            ei, ej = cell_of(edge_x, z + dz, h.shape)
            if not main_area[ej, ei]:
                fails.append("start %s: edge entry at z=%.0f cannot reach the start" % (corner, z + dz))

    dark_cells = region_cells(labels == DARK, scale, h.shape)
    dark_core = cv2.erode(dark_cells.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
    leak = reach8(walk, bi, bj) & dark_core
    if leak.any():
        ys, xs = np.nonzero(leak)
        fails.append("%d dark grey cells are reachable, e.g. (%.0f, %.0f)" % (len(xs), xs[0] * STEP, ys[0] * STEP))

    # Capture points on reachable green ground with some clearance: a Village in every
    # start valley, then two of each other type placed so every start has the same
    # walking distance to its nearest one.
    green_cells = region_cells(labels == GROUND, scale, h.shape)
    clearance = cv2.erode((main_area & green_cells).astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
    dist = np.stack([walk_distance(walk, *cell_of(x, z, h.shape)) for _, (x, z) in starts])
    capture_points = []
    placed = []
    walk_clearance = cv2.erode(main_area.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
    villages = place_villages(dist, walk_clearance)
    if villages is None:
        fails.append("no village spot at %.0f walking units from every start" % VILLAGE_DIST)
        villages = []
    for k, p in enumerate(villages):
        capture_points.append({"id": "Village" if k == 0 else "Village_%d" % (k + 1), "type": "Village", "x": p[0], "y": p[1]})
        placed.append(p)
    pair_clearance = cv2.erode(main_area.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
    pair_area = pair_clearance & np.isfinite(dist).all(axis=0) & (dist.min(axis=0) >= CP_MIN_START_DIST)
    # Placement is greedy (earlier types take the best spots), so try every type order.
    best_layout = None
    for order in itertools.permutations(PAIR_TYPES):
        layout = {}
        taken = list(placed)
        for ctype, target in order:
            pair = place_balanced_pair(dist, pair_area, taken, target)
            if pair is None:
                break
            layout[ctype] = pair
            taken += pair
        if len(layout) < len(PAIR_TYPES):
            continue
        worst = max(nearest_spread(dist, pair, h.shape) for pair in layout.values())
        if best_layout is None or worst < best_layout[0]:
            best_layout = (worst, layout)
    if best_layout is None:
        fails.append("no balanced spots for %s" % ", ".join(t for t, _ in PAIR_TYPES))
    else:
        for ctype, _ in PAIR_TYPES:
            for k, p in enumerate(best_layout[1][ctype]):
                capture_points.append({"id": ctype if k == 0 else "%s_2" % ctype, "type": ctype, "x": p[0], "y": p[1]})

    print("walking distance from each start to its nearest capture point of each type:")
    for ctype in ["Village"] + [t for t, _ in PAIR_TYPES]:
        spots = [(cp["x"], cp["y"]) for cp in capture_points if cp["type"] == ctype]
        if not spots:
            continue
        nearest = nearest_dists(dist, spots, h.shape)
        spread = nearest_spread(dist, spots, h.shape)
        print("  %-10s %s  spread %.1f%%" % (
            ctype, "  ".join("%s=%.0f" % (c, d) for (c, _), d in zip(starts, nearest)), spread * 100))
        if spread > BALANCE_TOLERANCE:
            fails.append("%s is unbalanced: nearest walking distances differ by %.0f%%" % (ctype, spread * 100))
    for k, cp in enumerate(capture_points[:len(villages)]):
        own = float(dist[k][cell_of(cp["x"], cp["y"], h.shape)[::-1]])
        for m in range(len(starts)):
            if m != k and float(dist[m][cell_of(cp["x"], cp["y"], h.shape)[::-1]]) <= own:
                fails.append("%s is not closest to start %s" % (cp["id"], starts[k][0]))

    if args.debug:
        dbg = np.zeros(h.shape + (3,), dtype=np.uint8)
        dbg[walk] = (90, 160, 70)
        dbg[~walk] = (60, 60, 60)
        dbg[water] = (40, 110, 220)
        dbg[main_area] = (140, 210, 110)
        for _, (x, z) in starts:
            i, j = cell_of(x, z, h.shape)
            dbg[max(0, j - 1):j + 2, max(0, i - 1):i + 2] = (230, 40, 40)
        Image.fromarray(dbg).resize((h.shape[1] * 4, h.shape[0] * 4), Image.Resampling.NEAREST).save(args.debug)
        print("debug image:", args.debug)

    walk_frac = walk.mean()
    print("features: %d (%s)" % (len(features), ", ".join(
        "%s=%d" % (t, sum(1 for f in features if f["type"] == t))
        for t in ("hill", "plateau_polygon", "valley_polygon"))))
    print("lake seeds: %d, walkable cells: %.0f%%, height range %.1f..%.1f" % (
        len(seeds), walk_frac * 100, h.min(), h.max()))

    if fails:
        for f in fails:
            print("FAIL:", f)
        sys.exit(1)

    out = {
        "name": args.name,
        "size": {"width": args.width, "height": args.height},
        "terrain": {"type": "hills", "features": features},
        "lakes": seeds,
        "lighting": {
            "sun_azimuth_deg": 275.0,
            "sun_elevation_deg": 0.0,
            "energy": 0.12,
            "color": [1.0, 0.98, 0.95],
            "shadow_max_distance": None,
        },
        "vegetation": {"count": 0, "forest_clusters": 0},
        "capture_points": capture_points,
        "chests": place_chests(
            args.width,
            args.height,
            [(float(p["x"]), float(p["y"])) for p in capture_points]
            + [(float(p[0]), float(p[1])) for _, p in starts],
            [(float(s["x"]), float(s["y"])) for s in seeds],
        ),
        "start_positions": [{"x": round(p[0], 1), "y": round(p[1], 1)} for _, p in starts],
        "player_starts": [
            {"slot": k, "corner": c, "armies": []} for k, (c, _) in enumerate(starts)
        ],
        "props": [],
    }
    path = MAPS_DIR / ("map_%s.json" % args.name)
    path.write_text(json.dumps(out, indent=1) + "\n")
    print("wrote", path)


if __name__ == "__main__":
    main()
