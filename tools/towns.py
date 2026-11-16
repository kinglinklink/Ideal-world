"""The towns: real roads and buildings from OpenStreetMap (map/osm.json, from
tools/fetch_osm.py), laid onto the baked terrain. Called by bake_map.py.

Writes:
    map_data/roads.bin       every road, sampled every 10 m: float32 x, y, z per
                             sample, x and z measured from the middle of the
                             road's 1 km drawing square
    map_data/road_runs.bin   int32 [square x, square z, first sample, count, kind]
                             per stretch of road, sorted by square
and returns, for world.json, the buildings (outline, base and roof heights,
colour, solid or not) and the bridges, grouped by 1 km square.

Road kinds: 0 trunk, 1 primary, 2 secondary, 3 tertiary, 4 unclassified,
5 residential, 6 service, 7 track; +8 when the road is unpaved.

Map data (c) OpenStreetMap contributors, ODbL.
"""

import json
import os

import numpy as np
from scipy.spatial import cKDTree

import map_common

CELL = 1024.0
ROAD_STEP = 10.0          # metres between road samples
ROAD_LIFT = 0.18          # roads sit this far above the ground, so it does not show through
BRIDGE_LIFT = 1.5         # bridge decks sit this far above the water
KINDS = {
    "motorway": 0, "trunk": 0, "motorway_link": 0, "trunk_link": 0,
    "primary": 1, "primary_link": 1,
    "secondary": 2, "secondary_link": 2,
    "tertiary": 3, "tertiary_link": 3,
    "unclassified": 4,
    "residential": 5, "living_street": 5,
    "service": 6,
    "track": 7,
}
WIDTHS = [11.0, 9.0, 8.0, 7.0, 6.0, 6.0, 4.0, 3.5]
UNPAVED = {"unpaved", "gravel", "dirt", "ground", "compacted", "fine_gravel", "earth", "grass", "sand", "mud"}

# Building heights, metres, when the data gives none.
KIND_HEIGHTS = {
    "house": 6.0, "residential": 6.5, "detached": 6.0, "cabin": 4.5, "bungalow": 4.5, "garage": 3.5,
    "garages": 3.5, "shed": 3.0, "roof": 4.0, "carport": 3.0, "boathouse": 4.5, "barn": 8.0,
    "warehouse": 8.0, "industrial": 8.0, "commercial": 7.5, "retail": 6.0, "school": 9.0,
    "church": 12.0, "hotel": 12.0, "apartments": 12.0, "hospital": 14.0, "farm_auxiliary": 6.0,
}


def _game(lon_lat, offset):
    pts = np.asarray(lon_lat, dtype=float)
    x, z = map_common.to_local(pts[:, 0], pts[:, 1])
    return np.stack([x - offset[0], z - offset[1]], axis=1)


def bake_towns(path, out_dir, ground, is_water, lake_y, bounds, offset):
    """`ground(x, z)` gives game heights for arrays of points, `is_water(x, z)`
    true over the lake, `offset` turns map_common's local metres into game
    positions. Returns (world.json section, function that tells which of a set
    of tree positions stand clear of roads and buildings)."""
    if not os.path.exists(path):
        print("  no map/osm.json: no towns (run tools/fetch_osm.py)")
        return {"buildings": [], "bridges": [], "road_count": 0}, None
    data = json.load(open(path))

    samples_out = []
    runs_out = []
    bridges = []
    road_points = []
    road_halves = []
    for road in data.get("roads", []):
        kind = KINDS.get(road.get("kind"))
        if kind is None:
            continue
        line = _game(road["line"], offset)
        lengths = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(line, axis=0), axis=1))]
        total = lengths[-1]
        if total < 1.0:
            continue
        # Resample, keeping every original corner.
        t = np.unique(np.r_[np.arange(0.0, total, ROAD_STEP), lengths, total])
        x = np.interp(t, lengths, line[:, 0])
        z = np.interp(t, lengths, line[:, 1])
        y = ground(x, z) + ROAD_LIFT
        wet = is_water(x, z)
        width = WIDTHS[kind]
        if wet.any():
            y = _bridge(y, wet, lake_y + BRIDGE_LIFT)
            _note_bridges(bridges, x, y, z, wet, width)
        code = kind + (8 if (kind == 7 or str(road.get("surface")) in UNPAVED) else 0)
        road_points.append(np.stack([x, z], axis=1))
        road_halves.append(np.full(len(x), width * 0.5))
        # Split into runs by 1 km square; each run ends on the first sample of
        # the next, so the ribbons join up.
        cells = np.floor(np.stack([x, z], axis=1) / CELL).astype(int)
        start = 0
        for i in range(1, len(x) + 1):
            if i == len(x) or (cells[i] != cells[start]).any():
                end = min(i, len(x) - 1)
                if end > start:
                    ci, ck = cells[start]
                    centre_x = (ci + 0.5) * CELL
                    centre_z = (ck + 0.5) * CELL
                    first = sum(len(s) for s in samples_out)
                    block = np.stack([x[start:end + 1] - centre_x, y[start:end + 1], z[start:end + 1] - centre_z], axis=1)
                    samples_out.append(block.astype(np.float32))
                    runs_out.append([ci, ck, first, len(block), code])
                start = i

    if samples_out:
        samples = np.concatenate(samples_out)
        runs = np.array(runs_out, dtype=np.int64)
        order = np.lexsort((runs[:, 0], runs[:, 1]))
        # Keep the sample blocks where they are; only the run table is sorted.
        runs = runs[order].astype(np.int32)
    else:
        samples = np.zeros((0, 3), dtype=np.float32)
        runs = np.zeros((0, 5), dtype=np.int32)
    samples.astype(np.float32).tofile(os.path.join(out_dir, "roads.bin"))
    runs.tofile(os.path.join(out_dir, "road_runs.bin"))
    print("  %d stretches of road, %d samples, %d bridges" % (len(runs), len(samples), len(bridges)))

    # Buildings.
    buildings = []
    centres = []
    reaches = []
    rng = np.random.default_rng(7)
    for item in data.get("buildings", []):
        outline = _game(item["outline"], offset)
        if np.allclose(outline[0], outline[-1]):
            outline = outline[:-1]
        if len(outline) < 3:
            continue
        area = 0.5 * float(np.sum(outline[:, 0] * np.roll(outline[:, 1], -1) - np.roll(outline[:, 0], -1) * outline[:, 1]))
        if abs(area) < 4.0:
            continue
        if area < 0:
            outline = outline[::-1]   # always the same way round
        middle = outline.mean(axis=0)
        under = ground(np.r_[outline[:, 0], middle[0]], np.r_[outline[:, 1], middle[1]])
        if is_water(np.array([middle[0]]), np.array([middle[1]]))[0]:
            continue   # a boathouse over the water: leave it out
        height = item.get("height")
        if not height and item.get("levels"):
            height = float(item["levels"]) * 3.2 + 1.0
        if not height:
            height = KIND_HEIGHTS.get(item.get("kind"))
        if not height:
            size = abs(area)
            height = 5.0 if size < 150 else (6.5 if size < 600 else 8.5)
        base = float(under.min()) - 0.6
        top = float(under.max()) + float(height)
        cell = np.floor(middle / CELL).astype(int)
        inside = bounds[0] <= middle[0] <= bounds[2] and bounds[1] <= middle[1] <= bounds[3]
        rel = outline - (cell + 0.5) * CELL
        buildings.append([int(cell[0]), int(cell[1]), [[round(float(a), 2), round(float(b), 2)] for a, b in rel],
                          round(base, 2), round(top, 2), int(rng.integers(0, 8)), 1 if inside else 0,
                          str(item.get("kind") or "yes")])
        centres.append(middle)
        reaches.append(float(np.max(np.linalg.norm(outline - middle, axis=1))))
    print("  %d buildings" % len(buildings))

    # What stands in the way of trees.
    if road_points:
        all_road = np.concatenate(road_points)
        all_half = np.concatenate(road_halves)
        road_tree = cKDTree(all_road)
    else:
        road_tree = None
    if centres:
        centre_array = np.array(centres)
        reach_array = np.array(reaches)
        building_tree = cKDTree(centre_array)

    def clear_of_towns(xz):
        keep = np.ones(len(xz), dtype=bool)
        if road_tree is not None:
            distance, index = road_tree.query(xz, distance_upper_bound=12.0)
            near = np.isfinite(distance)
            keep[near] = distance[near] > all_half[index[near]] + 2.5
        if centres:
            distance, index = building_tree.query(xz, distance_upper_bound=60.0)
            near = np.isfinite(distance)
            keep[near] &= distance[near] > reach_array[index[near]] + 2.0
        return keep

    return {"buildings": buildings, "bridges": bridges, "road_count": len(runs)}, clear_of_towns


def _bridge(y, wet, deck):
    """Carries a road straight across water: each wet stretch is bridged from
    the last dry sample before it to the first dry one after it."""
    y = y.copy()
    n = len(y)
    i = 0
    while i < n:
        if not wet[i]:
            i += 1
            continue
        j = i
        while j < n and wet[j]:
            j += 1
        before = y[i - 1] if i > 0 else deck
        after = y[j] if j < n else deck
        for k in range(i, j):
            share = (k - i + 1) / (j - i + 1)
            y[k] = max(before + (after - before) * share, deck)
        i = j
    return y


def _note_bridges(bridges, x, y, z, wet, width):
    """Notes each span over water, from the dry sample before to the dry one
    after, for the game to make solid."""
    n = len(x)
    i = 0
    while i < n:
        if not wet[i]:
            i += 1
            continue
        j = i
        while j < n and wet[j]:
            j += 1
        a = max(i - 1, 0)
        b = min(j, n - 1)
        for k in range(a, b):
            bridges.append([round(float(x[k]), 2), round(float(y[k]), 2), round(float(z[k]), 2),
                            round(float(x[k + 1]), 2), round(float(y[k + 1]), 2), round(float(z[k + 1]), 2),
                            width])
        i = j
