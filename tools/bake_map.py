"""Builds Ideal World's map from the downloaded terrain in map/.

    pip install pillow numpy scipy scikit-image
    python tools/bake_map.py

Writes:
    map_data/terrain_coarse.png   the whole map, one sample every 16 m
    map_data/terrain_detail.png   Wild Horse, Cromwell, Melita and Dream Islands, every 4 m
    map_data/trees.bin            every tree, ready to hand to the graphics card
    map_data/tree_tiles.bin       which trees stand in each 128 m square, for collision
    map_data/world.json           runways, buildings, the boundary wall, carrier spots
    map_data/minimap.png          the picture behind the mini map
    scripts/map_info.gd           the numbers the game needs to read all of the above

Heights in the two terrain pictures: red is the high byte and green the low
byte of a 16-bit number; blue holds the surface kind (low 3 bits) and how
wooded the spot is (high 5 bits). Game height = number / scale - offset, in
metres above the build pad. See map_info.gd for each picture's scale and offset.

Game coordinates: the origin is the corner of the build pad, east is +X,
north is -Z, and Y = 0 is the level of the pad. The lake surface is LAKE_Y.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from map_common import ROOT, load_layer, layer_extent, resample, to_local  # noqa: E402

OUT = os.path.join(ROOT, "map_data")
INFO_SCRIPT = os.path.join(ROOT, "scripts", "map_info.gd")

COARSE = 16.0
DETAIL = 4.0
TILE = 128.0      # collision squares
CELL = 1024.0     # tree drawing squares
PAD_REF = np.array([-477.0, -781.0])   # the pad's corner in the reference frame of map_common
HOME = (-15.0, -43.0, 47.0, 79.0)      # pad, gap and garage, with a margin: x0, z0, x1, z1
BORDER_MARGIN = 2000.0                 # metres of land between the lake's furthest reach and the wall
NEAR_SHORE = 600.0                     # woods are thicker this close to the water
MAX_DEPTH = 113.0
LAKE_LONLAT = (-114.10, 47.90)

COARSE_OFFSET, COARSE_SCALE = 300.0, 20.0
DETAIL_OFFSET, DETAIL_SCALE = 200.0, 100.0

NATURAL, ASPHALT, GRAVEL, SITE, OUTSIDE, WATER = 0, 1, 2, 3, 4, 5

RNG = np.random.default_rng(20261116)


# --- Grids -------------------------------------------------------------------

class Grid:
    """Heights on an even grid in game coordinates (metres above sea level
    until encoding). Sample [row, col] is at (x0 + col * sp, z0 + row * sp)."""

    def __init__(self, layer_name, spacing):
        heights, layer = load_layer(layer_name)
        ex0, ez0, ex1, ez1 = layer_extent(layer)
        ex0, ex1 = ex0 - PAD_REF[0], ex1 - PAD_REF[0]
        ez0, ez1 = ez0 - PAD_REF[1], ez1 - PAD_REF[1]
        self.sp = spacing
        self.x0 = math.ceil(ex0 / spacing) * spacing
        self.z0 = math.ceil(ez0 / spacing) * spacing
        self.cols = int(math.floor((ex1 - self.x0) / spacing))
        self.rows = int(math.floor((ez1 - self.z0) / spacing))
        self.h = resample(heights, layer, self.x0 + PAD_REF[0], self.z0 + PAD_REF[1],
                          spacing, self.cols, self.rows)
        self.kind = np.zeros(self.h.shape, dtype=np.uint8)
        xs = self.x0 + np.arange(self.cols) * spacing
        zs = self.z0 + np.arange(self.rows) * spacing
        self.X, self.Z = np.meshgrid(xs, zs)

    def cell(self, x, z):
        return int(round((z - self.z0) / self.sp)), int(round((x - self.x0) / self.sp))

    def sample(self, array, x, z, order=1):
        return ndimage.map_coordinates(array, [(np.asarray(z) - self.z0) / self.sp,
                                               (np.asarray(x) - self.x0) / self.sp], order=order, mode="nearest")

    def inside(self, x, z, margin=0.0):
        return ((x >= self.x0 + margin) & (x <= self.x0 + (self.cols - 1) * self.sp - margin)
                & (z >= self.z0 + margin) & (z <= self.z0 + (self.rows - 1) * self.sp - margin))


def game_point(lon, lat):
    x, z = to_local(lon, lat)
    return float(x) - PAD_REF[0], float(z) - PAD_REF[1]


def ref_point(x, z):
    return x - PAD_REF[0], z - PAD_REF[1]


def direction(heading):
    """Unit vectors for a heading in degrees clockwise from north: along, and
    across (90 degrees to the right)."""
    a = math.radians(heading)
    return np.array([math.sin(a), -math.cos(a)]), np.array([math.cos(a), math.sin(a)])


def local(grid, centre, heading):
    along, across = direction(heading)
    dx, dz = grid.X - centre[0], grid.Z - centre[1]
    return dx * along[0] + dz * along[1], dx * across[0] + dz * across[1]


def smooth01(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grade(grid, centre, heading, half_len, half_wid, profile, skirt, kind=None, kind_half=None):
    """Levels a rectangle to `profile(t)` (t measured along the heading from
    the centre) and blends it into the ground over `skirt` metres. The middle
    part, `kind_half` = (half length, half width), gets surface `kind`."""
    t, s = local(grid, centre, heading)
    reach = max(half_len, half_wid) + skirt + grid.sp
    near = (np.abs(t) <= reach) & (np.abs(s) <= reach)
    if not near.any():
        return
    tt, ss = t[near], s[near]
    out_t = np.maximum(np.abs(tt) - half_len - grid.sp, 0.0)
    out_s = np.maximum(np.abs(ss) - half_wid - grid.sp, 0.0)
    outside = np.hypot(out_t, out_s)
    target = profile(np.clip(tt, -half_len, half_len))
    keep = smooth01(outside / skirt)
    grid.h[near] = target * (1.0 - keep) + grid.h[near] * keep
    if kind is not None:
        kl, kw = kind_half
        mark = (np.abs(tt) <= kl) & (np.abs(ss) <= kw)
        sub = grid.kind[near]
        sub[mark] = kind
        grid.kind[near] = sub


# --- Build --------------------------------------------------------------------

def main():
    os.makedirs(OUT, exist_ok=True)
    print("Resampling the terrain ...")
    coarse = Grid("lake", COARSE)
    detail = Grid("islands", DETAIL)
    raw_detail = detail.h.copy()

    # The lake: flat water in the elevation data.
    band = coarse.h[(coarse.h > 880.0) & (coarse.h < 881.0)]
    lake = float(np.round(np.median(band), 2))
    print("Lake surface %.2f m" % lake)

    def water_mask(grid, x, z):
        candidate = (grid.h > lake - 0.6) & (grid.h < lake + 0.3)
        labels, _ = ndimage.label(candidate)
        r, c = grid.cell(x, z)
        # Start from the nearest water to the given point.
        _, (near_r, near_c) = ndimage.distance_transform_edt(~candidate, return_indices=True)
        r, c = near_r[r, c], near_c[r, c]
        return labels == labels[r, c]

    lx, lz = game_point(*LAKE_LONLAT)
    coarse_water = water_mask(coarse, lx, lz)
    detail_water = water_mask(detail, *ref_point(-1000.0, 2100.0))

    # In bounds: a rectangle round the lake's furthest reach, with a margin of
    # land all round, and its sides square to north. The land beyond it is
    # still drawn.
    land_to_water = ndimage.distance_transform_edt(~coarse_water) * COARSE
    rows, cols = np.nonzero(coarse_water)
    keep_in = 1000.0   # at least this much drawn land beyond the wall
    bounds = [
        max(math.floor((coarse.x0 + cols.min() * COARSE - BORDER_MARGIN) / 64.0) * 64.0, coarse.x0 + keep_in),
        max(math.floor((coarse.z0 + rows.min() * COARSE - BORDER_MARGIN) / 64.0) * 64.0, coarse.z0 + keep_in),
        min(math.ceil((coarse.x0 + cols.max() * COARSE + BORDER_MARGIN) / 64.0) * 64.0,
            coarse.x0 + (coarse.cols - 1) * COARSE - keep_in),
        min(math.ceil((coarse.z0 + rows.max() * COARSE + BORDER_MARGIN) / 64.0) * 64.0,
            coarse.z0 + (coarse.rows - 1) * COARSE - keep_in),
    ]
    print("World bounds x %.0f to %.0f, z %.0f to %.0f (%.1f x %.1f km)" % (
        bounds[0], bounds[2], bounds[1], bounds[3], (bounds[2] - bounds[0]) / 1000.0, (bounds[3] - bounds[1]) / 1000.0))
    inbounds = ((coarse.X >= bounds[0]) & (coarse.X <= bounds[2])
                & (coarse.Z >= bounds[1]) & (coarse.Z <= bounds[3]))

    # The lake bed: deepening away from shore to the real 113 m.
    water_to_land = ndimage.distance_transform_edt(coarse_water) * COARSE

    def depth(distance):
        return 1.5 + (MAX_DEPTH - 1.5) * np.tanh(distance / 6000.0)

    near_lake = land_to_water < 300.0
    coarse.h = np.where(coarse_water, lake - depth(water_to_land),
                        np.where(near_lake, np.maximum(coarse.h, lake + 0.5), coarse.h))

    detail_to_land = ndimage.distance_transform_edt(detail_water) * DETAIL
    detail_to_land = np.minimum(detail_to_land, coarse.sample(water_to_land, detail.X, detail.Z))
    detail_land_to_water = ndimage.distance_transform_edt(~detail_water) * DETAIL
    detail.h = np.where(detail_water, lake - depth(detail_to_land),
                        np.where(detail_land_to_water < 300.0, np.maximum(detail.h, lake + 0.5), detail.h))

    # Islands in the detailed area.
    detail_land = ~detail_water
    island_labels, _ = ndimage.label(detail_land)

    def island_at(x, z):
        r, c = detail.cell(x, z)
        return island_labels == island_labels[r, c]

    wild_horse = island_at(*ref_point(0.0, 0.0))
    melita = island_at(*ref_point(-1560.0, 2680.0))


    # --- The build pad ---
    hx0, hz0, hx1, hz1 = HOME
    home_mask = (detail.X >= hx0) & (detail.X <= hx1) & (detail.Z >= hz0) & (detail.Z <= hz1)
    base = float(np.round(np.median(raw_detail[home_mask]), 1))
    print("Build pad level %.1f m above sea level" % base)
    home_centre = ((hx0 + hx1) * 0.5, (hz0 + hz1) * 0.5)
    home_half = ((hz1 - hz0) * 0.5, (hx1 - hx0) * 0.5)
    for grid in (detail, coarse):
        grade(grid, home_centre, 0.0, home_half[0], home_half[1], lambda t: np.full_like(t, base), 30.0,
              SITE, home_half)

    features = {"runways": [], "buildings": [], "docks": [], "helipads": []}
    # Where trees must not grow: ("rect", centre, heading, half length, half width) or ("circle", centre, radius).
    clearings = [("rect", home_centre, 0.0, home_half[0] + 50.0, home_half[1] + 50.0)]

    # --- Wild Horse runway: 1,200 m, at 90 degrees to Melita's ---
    melita_a = np.array(ref_point(-1948.0, 2588.0))
    melita_b = np.array(ref_point(-1148.0, 2658.0))
    melita_vec = melita_b - melita_a
    melita_heading = math.degrees(math.atan2(melita_vec[0], -melita_vec[1])) % 360.0
    wh_heading = (melita_heading + 90.0) % 360.0
    wh_centre = np.array(ref_point(-780.0, 0.0))
    wh_half = 600.0
    # Fit a straight grade along it, no steeper than 2 %.
    along, across = direction(wh_heading)
    t = np.linspace(-wh_half, wh_half, 241)
    pts = wh_centre[None, :] + t[:, None] * along[None, :]
    h_line = detail.sample(raw_detail, pts[:, 0], pts[:, 1])
    slope, mid = np.polyfit(t, h_line, 1)
    slope = float(np.clip(slope, -0.02, 0.02))
    mid = float(np.mean(h_line - slope * t))

    def wh_profile(tt):
        return mid + slope * tt

    for grid in (detail, coarse):
        grade(grid, wh_centre, wh_heading, wh_half + 30.0, 30.0, wh_profile, 50.0, ASPHALT, (wh_half, 15.0))
    # The apron, beside the middle of the runway on the side toward the pad.
    side = 1.0 if np.dot(np.array([home_centre[0], home_centre[1]]) - wh_centre, across) > 0 else -1.0
    apron_centre = wh_centre + across * side * (15.0 + 25.0 + 45.0)
    for grid in (detail, coarse):
        grade(grid, apron_centre, wh_heading, 90.0, 45.0, lambda tt: np.full_like(tt, mid), 40.0,
              ASPHALT, (90.0, 45.0))
    clearings.append(("rect", wh_centre, wh_heading, wh_half + 120.0, 60.0))
    clearings.append(("rect", apron_centre, wh_heading, 120.0, 75.0))
    features["runways"].append({
        "name": "Wild Horse Island", "surface": "asphalt",
        "centre": [float(wh_centre[0]), float(wh_centre[1])], "heading": wh_heading,
        "length": wh_half * 2.0, "width": 30.0,
        "height_mid": mid - base, "slope": slope,
        "apron": {"centre": [float(apron_centre[0]), float(apron_centre[1])], "length": 180.0, "width": 90.0,
                  "side": side},
    })

    # --- Melita bush strip, from the dock at its west end ---
    m_half = float(np.linalg.norm(melita_vec)) * 0.5
    m_centre = (melita_a + melita_b) * 0.5
    m_along, m_across = direction(melita_heading)
    steps = int(m_half * 2.0 / 4.0) + 1
    tm = np.linspace(-m_half, m_half, steps)
    pts = m_centre[None, :] + tm[:, None] * m_along[None, :]
    prof = detail.sample(raw_detail, pts[:, 0], pts[:, 1])
    prof = ndimage.gaussian_filter1d(prof, 15.0, mode="nearest")
    prof = np.maximum(prof, lake + 1.0)

    def melita_profile(tt):
        return np.interp(tt, tm, prof)

    for grid in (detail, coarse):
        grade(grid, m_centre, melita_heading, m_half, 13.5, melita_profile, 20.0, GRAVEL, (m_half, 7.5))
    clearings.append(("rect", m_centre, melita_heading, m_half + 15.0, 7.5 + 14.0))
    features["runways"].append({
        "name": "Melita Island", "surface": "gravel",
        "centre": [float(m_centre[0]), float(m_centre[1])], "heading": melita_heading,
        "length": m_half * 2.0, "width": 15.0,
        "profile": [float(v - base) for v in prof], "profile_step": float(tm[1] - tm[0]),
    })
    dock_start = m_centre - m_along * m_half
    features["docks"].append({
        "name": "Camp Melita dock", "start": [float(dock_start[0]), float(dock_start[1])],
        "heading": (melita_heading + 180.0) % 360.0, "length": 50.0, "width": 4.0,
        "deck": float(max(prof[0] + 0.05, lake + 1.2)) - base,   # flush with the end of the strip
    })

    # The camp lodge, as the terminal: in the open middle of the island.
    rows, cols = np.nonzero(melita)
    centroid = np.array([detail.x0 + cols.mean() * DETAIL, detail.z0 + rows.mean() * DETAIL])
    offset = float(np.dot(centroid - m_centre, m_across))
    lodge_side = 1.0 if offset >= 0 else -1.0
    along_pos = float(np.clip(np.dot(centroid - m_centre, m_along), -m_half * 0.5, m_half * 0.5))
    lodge_centre = m_centre + m_along * along_pos + m_across * lodge_side * 42.0
    lodge_height = float(np.median(detail.sample(raw_detail, lodge_centre[0] + np.array([-10, 0, 10]),
                                                 lodge_centre[1] + np.array([-6, 0, 6]))))
    for grid in (detail, coarse):
        grade(grid, lodge_centre, melita_heading, 22.0, 15.0, lambda tt: np.full_like(tt, lodge_height), 15.0,
              SITE, (16.0, 10.0))
    clearing_centre = m_centre + m_along * along_pos + m_across * lodge_side * 30.0
    clearings.append(("rect", lodge_centre, melita_heading, 32.0, 24.0))
    clearings.append(("circle", clearing_centre, 90.0))
    features["buildings"].append({
        "kind": "melita_lodge", "name": "Camp Melita lodge (terminal)",
        "centre": [float(lodge_centre[0]), float(lodge_centre[1])], "heading": melita_heading,
        "facing": -lodge_side, "ground": lodge_height - base,
    })

    # --- Cromwell Island mansion ---
    cx, cz = game_point(-114.267201, 47.850731)
    mansion_height = float(np.median(detail.sample(raw_detail, cx + np.array([-20, 0, 20, 0]),
                                                   cz + np.array([0, -15, 0, 15]))))
    for grid in (detail, coarse):
        grade(grid, (cx, cz), 90.0, 60.0, 45.0, lambda tt: np.full_like(tt, mansion_height), 30.0,
              SITE, (55.0, 40.0))
    clearings.append(("rect", (cx, cz), 90.0, 85.0, 70.0))
    features["buildings"].append({
        "kind": "cromwell_mansion", "name": "Cromwell Island villa",
        "centre": [cx, cz], "heading": 90.0, "ground": mansion_height - base,
    })

    # --- Airstrips, helipads and the Shelter Island mansion on the other islands ---
    island_features(coarse, detail, coarse_water, detail_water, lake, base, features, clearings, (cx, cz))

    # --- Join the detailed area smoothly onto the rest ---
    from_coarse = coarse.sample(coarse.h, detail.X, detail.Z)
    ramp = 25
    rr = np.minimum(np.arange(detail.rows), np.arange(detail.rows)[::-1])[:, None]
    cc = np.minimum(np.arange(detail.cols), np.arange(detail.cols)[::-1])[None, :]
    blend = smooth01(np.minimum(rr, cc) / ramp)
    detail.h = from_coarse * (1.0 - blend) + detail.h * blend

    # Outside the wall, for the shading, and the lake itself, so the water
    # surface is only drawn on the lake.
    coarse.kind[~inbounds & (coarse.kind == NATURAL)] = OUTSIDE
    coarse.kind[coarse_water] = WATER
    detail.kind[detail_water] = WATER

    # --- Trees ---
    print("Placing trees ...")
    trees = place_trees(coarse, detail, coarse_water, detail_water, inbounds, land_to_water, wild_horse, melita,
                        island_labels, clearings, base)
    print("  %d trees" % len(trees))

    # --- The wall: the four sides of the rectangle ---
    walls = [[[bounds[0], bounds[1]], [bounds[2], bounds[1]], [bounds[2], bounds[3]], [bounds[0], bounds[3]]]]

    # --- Carrier spots: deep open water, far from land ---
    open_water = coarse_water & (water_to_land >= 1500.0) & inbounds
    rr, cc = np.nonzero(open_water)
    pick = RNG.choice(len(rr), size=min(300, len(rr)), replace=False)
    carrier_spots = [[float(coarse.x0 + cc[i] * COARSE), float(coarse.z0 + rr[i] * COARSE)] for i in pick]

    # --- Islands to label on the mini map ---
    labels_list = []
    for name, lon, lat in ISLANDS:
        x, z = game_point(lon, lat)
        labels_list.append({"name": name, "at": [x, z]})

    # --- Write it all ---
    write_terrain(coarse, "terrain_coarse.png", base, COARSE_OFFSET, COARSE_SCALE)
    write_terrain(detail, "terrain_detail.png", base, DETAIL_OFFSET, DETAIL_SCALE)
    tree_cells = write_trees(trees, coarse)
    write_minimap(coarse, coarse_water, inbounds, base, lake)

    world = {
        "base_elevation": base, "lake_surface": lake, "lake_y": lake - base,
        "runways": features["runways"], "buildings": features["buildings"], "docks": features["docks"],
        "helipads": features["helipads"], "bounds": bounds, "walls": walls, "carrier_spots": carrier_spots, "islands": labels_list, "tree_cells": tree_cells,
        "minimap": {"x0": coarse.x0, "z0": coarse.z0,
                    "width": coarse.cols * COARSE, "depth": coarse.rows * COARSE},
    }
    with open(os.path.join(OUT, "world.json"), "w") as handle:
        json.dump(world, handle)
    open(os.path.join(OUT, ".gdignore"), "w").close()
    write_info_script(coarse, detail, base, lake)
    print("Done.")


ISLANDS = [
    ("Wild Horse", -114.215, 47.845), ("Cromwell", -114.2636, 47.8503), ("Melita", -114.2356, 47.8214),
    ("Dream", -114.2306, 47.8119), ("Shelter", -114.1742, 47.8956), ("Cedar", -114.1661, 47.8958),
    ("Rock", -114.1714, 47.8947), ("Mary B", -114.1689, 47.9253), ("Douglas", -114.1683, 47.9336),
    ("Goose", -114.1778, 47.9486), ("Bird", -114.0792, 47.7997), ("Bull", -114.1161, 47.7706),
    ("Little Bull", -114.125, 47.7681), ("Invitation", -114.2169, 48.0708),
]


# --- Trees -------------------------------------------------------------------

def smooth_noise(shape, size):
    noise = ndimage.gaussian_filter(RNG.random(shape), size)
    noise -= noise.min()
    return noise / max(noise.max(), 1e-9)


def in_clearing(x, z, clearings):
    """True where trees must not grow."""
    blocked = np.zeros(np.shape(x), dtype=bool)
    for clearing in clearings:
        if clearing[0] == "rect":
            _, centre, heading, half_len, half_wid = clearing
            along, across = direction(heading)
            dx, dz = x - centre[0], z - centre[1]
            t = dx * along[0] + dz * along[1]
            s = dx * across[0] + dz * across[1]
            blocked |= (np.abs(t) <= half_len) & (np.abs(s) <= half_wid)
        else:
            _, centre, radius = clearing
            blocked |= np.hypot(x - centre[0], z - centre[1]) < radius
    return blocked


def place_trees(coarse, detail, coarse_water, detail_water, inbounds, land_to_water, wild_horse, melita,
                island_labels, clearings, base):
    found = []

    def scatter(grid, density, land, shore_gap, use):
        """One chance per grid cell, with `density` trees per square metre."""
        gy, gx = np.gradient(grid.h, grid.sp)
        steep = np.hypot(gx, gy) > math.tan(math.radians(38.0))
        shore = ndimage.distance_transform_edt(land) * grid.sp < shore_gap
        chance = density * grid.sp * grid.sp
        chance[~land | steep | shore | ~use] = 0.0
        hit = RNG.random(grid.h.shape) < chance
        rows, cols = np.nonzero(hit)
        x = grid.x0 + (cols + RNG.uniform(-0.5, 0.5, len(cols))) * grid.sp
        z = grid.z0 + (rows + RNG.uniform(-0.5, 0.5, len(rows))) * grid.sp
        ok = ~in_clearing(x, z, clearings)
        x, z = x[ok], z[ok]
        y = grid.sample(grid.h, x, z) - base
        return np.stack([x, y, z], axis=1)

    # The detailed area.
    d_land = ~detail_water
    gy, gx = np.gradient(detail.h, DETAIL)
    slope = np.hypot(gx, gy)
    north_facing = np.clip(gy / np.maximum(slope, 1e-6), -1.0, 1.0) * np.clip(slope / 0.25, 0.0, 1.0)
    patches = smooth_noise(detail.h.shape, 18.0)
    density = np.zeros(detail.h.shape)
    # Wild Horse: Palouse grassland, with pine on north-facing slopes and in patches.
    wh_forest = np.clip(0.05 + 0.75 * north_facing + 0.9 * (patches - 0.55), 0.0, 1.0)
    density[wild_horse] = (wh_forest / 55.0)[wild_horse]
    # Melita: dense forest.
    density[melita] = 1.0 / 26.0
    # Cromwell and the small islands: thick forest.
    others = d_land & ~wild_horse & ~melita
    island_sizes = ndimage.sum(np.ones_like(island_labels), island_labels, index=np.arange(island_labels.max() + 1))
    small_island = others & (island_sizes[island_labels] * DETAIL * DETAIL < 3.0e6)
    density[small_island] = 1.0 / 40.0
    # The mainland: woods in patches, thicker near the water.
    in_d = coarse.sample(inbounds.astype(float), detail.X, detail.Z, order=0) > 0.5
    near_d = coarse.sample(land_to_water, detail.X, detail.Z) < NEAR_SHORE
    mainland = others & ~small_island
    woods = np.clip(patches * 1.4 - 0.3, 0.0, 1.0)
    density[mainland] = np.where(near_d, woods / 160.0, woods / 700.0)[mainland]
    found.append(scatter(detail, density, d_land, 6.0, in_d))

    # Everywhere else inside the wall, at the coarse spacing. The islands out
    # here are wooded too.
    c_land = ~coarse_water
    cpatch = smooth_noise(coarse.h.shape, 6.0)
    cwoods = np.clip(cpatch * 1.4 - 0.3, 0.0, 1.0)
    c_labels, _ = ndimage.label(c_land)
    c_sizes = np.bincount(c_labels.ravel())
    c_island = c_land & (c_sizes[c_labels] * COARSE * COARSE < 3.0e6)
    cdensity = np.where(land_to_water < NEAR_SHORE, cwoods / 260.0, cwoods / 1100.0)
    cdensity = np.where(c_island, 1.0 / 45.0, cdensity)
    outside_detail = ~detail.inside(coarse.X, coarse.Z, 4.0)
    found.append(scatter(coarse, cdensity, c_land, 16.0, inbounds & outside_detail))
    trees = np.concatenate(found, axis=0)

    # Record how wooded each spot is, for shading the ground from far away.
    # Each grid counts only the trees that stand on it, blurred over the same
    # distance on both, so the two agree where they meet.
    for grid in (detail, coarse):
        counts = np.zeros(grid.h.shape)
        r = np.round((trees[:, 2] - grid.z0) / grid.sp).astype(int)
        c = np.round((trees[:, 0] - grid.x0) / grid.sp).astype(int)
        on = (r >= 0) & (r < grid.rows) & (c >= 0) & (c < grid.cols)
        np.add.at(counts, (r[on], c[on]), 1.0)
        per_area = ndimage.gaussian_filter(counts, 24.0 / grid.sp) / (grid.sp * grid.sp)
        wooded = np.clip(per_area * 40.0 * 31.0, 0, 31).astype(np.uint8)
        grid.kind = (grid.kind & 7) | (wooded << 3)
    return trees


def write_trees(trees, coarse):
    """Writes every tree as four floats: x and z measured from the middle of
    its 1,024 m drawing square, its height y, and its size. The game turns and
    colours each tree from its place in the file. Trees are sorted by drawing
    square and then by 128 m collision square, so that both are runs of the
    file."""
    count = len(trees)
    x, y, z = trees[:, 0], trees[:, 1], trees[:, 2]
    size = RNG.uniform(1.0, 2.2, count)
    tile_i = np.floor(x / TILE).astype(np.int64)
    tile_k = np.floor(z / TILE).astype(np.int64)
    per = int(CELL / TILE)
    cell_i = np.floor_divide(tile_i, per)
    cell_k = np.floor_divide(tile_k, per)
    order = np.lexsort((tile_i, tile_k, cell_i, cell_k))
    x, y, z, size = x[order], y[order], z[order], size[order]
    tile_i, tile_k, cell_i, cell_k = tile_i[order], tile_k[order], cell_i[order], cell_k[order]

    packed = np.zeros((count, 4), dtype=np.float32)
    packed[:, 0] = x - (cell_i + 0.5) * CELL
    packed[:, 1] = y
    packed[:, 2] = z - (cell_k + 0.5) * CELL
    packed[:, 3] = size
    packed.tofile(os.path.join(OUT, "trees.bin"))

    # Runs of the same collision square: [tile x, tile z, first tree, count].
    key = tile_k * 100000 + tile_i
    change = np.r_[True, key[1:] != key[:-1]]
    starts = np.nonzero(change)[0]
    counts = np.diff(np.r_[starts, count])
    table = np.stack([tile_i[starts], tile_k[starts], starts, counts], axis=1).astype(np.int32)
    table.tofile(os.path.join(OUT, "tree_tiles.bin"))

    # Runs of the same drawing square.
    ckey = cell_k * 100000 + cell_i
    change = np.r_[True, ckey[1:] != ckey[:-1]]
    cstarts = np.nonzero(change)[0]
    ccounts = np.diff(np.r_[cstarts, count])
    return [[int(cell_i[s]), int(cell_k[s]), int(s), int(n)] for s, n in zip(cstarts, ccounts)]


# --- The other islands ---------------------------------------------------------

STRIP_ISLANDS = {"Cromwell", "Shelter", "Cedar", "Bird", "Bull", "Little Bull", "Dream", "Rock", "Mary B",
                 "Douglas", "Goose", "Invitation"}
MIN_STRIP = 250.0     # metres; shorter than this and an island gets a helipad instead
STRIP_WIDTH = 12.0
STRIP_INSET = 6.0     # metres between a strip's ends and the shore
MAX_GROUND_SLOPE = 0.15   # strips are laid only across ground gentler than this
MAX_STRIP_GRADE = 0.06    # and graded no steeper than this


def limit_grade(profile, step, grade):
    """Pulls a height profile in until no stretch is steeper than `grade`,
    keeping it as close to the ground as it can: the middle of the cut and
    fill, from both ends."""
    prof = np.array(profile, dtype=float)
    rise = grade * step
    for _ in range(4):
        up = prof.copy()
        for i in range(1, len(up)):
            up[i] = min(up[i], up[i - 1] + rise)
            up[i] = max(up[i], up[i - 1] - rise)
        down = prof.copy()
        for i in range(len(down) - 2, -1, -1):
            down[i] = min(down[i], down[i + 1] + rise)
            down[i] = max(down[i], down[i + 1] - rise)
        prof = (up + down) * 0.5
    return prof


def island_features(coarse, detail, coarse_water, detail_water, lake, base, features, clearings, villa):
    """Gives each small island an airstrip as long as fits on it, or a helipad
    if no strip fits, and Shelter Island its mansion."""
    c_land = ~coarse_water
    c_labels, _ = ndimage.label(c_land)
    c_sizes = np.bincount(c_labels.ravel())
    mainland = int(np.argmax(c_sizes[1:]) + 1)
    for name, lon, lat in ISLANDS:
        if name not in STRIP_ISLANDS:
            continue
        x, z = game_point(lon, lat)
        # The island's piece of land in the coarse data, nearest the point.
        r0, k0 = coarse.cell(x, z)
        best = None
        for dr in range(-8, 9):
            for dc in range(-8, 9):
                label = c_labels[r0 + dr, k0 + dc]
                if label > 0 and label != mainland:
                    d = math.hypot(dr, dc)
                    if best is None or d < best[0]:
                        best = (d, label)
        if best is None:
            print("  %s: not found" % name)
            continue
        rows, cols = np.nonzero(c_labels == best[1])
        bx0 = coarse.x0 + cols.min() * COARSE - 80.0
        bx1 = coarse.x0 + cols.max() * COARSE + 80.0
        bz0 = coarse.z0 + rows.min() * COARSE - 80.0
        bz1 = coarse.z0 + rows.max() * COARSE + 80.0
        # A 4 m local grid over the island, from the finest data there is.
        xs = np.arange(bx0, bx1, 4.0)
        zs = np.arange(bz0, bz1, 4.0)
        gx, gz = np.meshgrid(xs, zs)
        use_detail = bool(detail.inside(np.array([bx0, bx1]), np.array([bz0, bz1]), 8.0).all())
        source = detail if use_detail else coarse
        h = source.sample(source.h, gx, gz)
        land = h > lake + 0.3
        labels, _ = ndimage.label(land)
        rr, cc = np.unravel_index(np.argmin(np.hypot(gx - x, gz - z) + np.where(land, 0.0, 1e9)), land.shape)
        island = labels == labels[rr, cc]
        inner = ndimage.distance_transform_edt(island) * 4.0
        usable = inner >= STRIP_INSET
        # Only gentle ground, so a strip does not carve a trench through a hill.
        sy, sx = np.gradient(ndimage.gaussian_filter(h, 2.0), 4.0)
        usable &= np.hypot(sx, sy) < MAX_GROUND_SLOPE
        if name == "Cromwell":
            usable &= np.hypot(gx - villa[0], gz - villa[1]) > 110.0
        strip = longest_line(gx[usable], gz[usable])
        if strip is not None and strip[0] >= MIN_STRIP:
            length, heading, a, b = strip
            centre = (a + b) * 0.5
            along, across = direction(heading)
            half = length * 0.5
            steps = int(length / 4.0) + 1
            t = np.linspace(-half, half, steps)
            pts = centre[None, :] + t[:, None] * along[None, :]
            prof = ndimage.map_coordinates(h, [(pts[:, 1] - bz0) / 4.0, (pts[:, 0] - bx0) / 4.0], order=1)
            prof = ndimage.gaussian_filter1d(prof, 10.0, mode="nearest")
            prof = limit_grade(prof, t[1] - t[0], MAX_STRIP_GRADE)
            prof = np.maximum(prof, lake + 1.0)

            def profile(tt, t=t, prof=prof):
                return np.interp(tt, t, prof)

            for grid in (coarse, detail):
                grade(grid, centre, heading, half, STRIP_WIDTH * 0.5 + 6.0, profile, 20.0, GRAVEL,
                      (half, STRIP_WIDTH * 0.5))
            clearings.append(("rect", centre, heading, half + 15.0, STRIP_WIDTH * 0.5 + 14.0))
            features["runways"].append({
                "name": "%s Island" % name, "surface": "gravel",
                "centre": [float(centre[0]), float(centre[1])], "heading": float(heading),
                "length": float(length), "width": STRIP_WIDTH,
                "profile": [float(v - base) for v in prof], "profile_step": float(t[1] - t[0]),
            })
            print("  %s: %.0f m airstrip, heading %.0f" % (name, length, heading))
        else:
            # A helipad on the island's most inland spot.
            rr, cc = np.unravel_index(np.argmax(inner), inner.shape)
            centre = np.array([gx[rr, cc], gz[rr, cc]])
            ground = float(max(h[rr, cc], lake + 1.0))
            for grid in (coarse, detail):
                grade(grid, centre, 0.0, 12.0, 12.0, lambda tt, g=ground: np.full_like(tt, g), 10.0, SITE, (11.0, 11.0))
            clearings.append(("circle", centre, 25.0))
            features["helipads"].append({"name": "%s Island" % name, "centre": [float(centre[0]), float(centre[1])],
                                         "ground": ground - base})
            print("  %s: helipad" % name)
        if name == "Shelter":
            # The mansion: on the most inland spot well clear of the strip.
            room = inner.copy()
            if strip is not None and strip[0] >= MIN_STRIP:
                along, across = direction(strip[1])
                centre_line = (strip[2] + strip[3]) * 0.5
                off = np.abs((gx - centre_line[0]) * across[0] + (gz - centre_line[1]) * across[1])
                room[off < 45.0] = 0.0
            rr, cc = np.unravel_index(np.argmax(room), room.shape)
            spot = np.array([gx[rr, cc], gz[rr, cc]])
            heading = strip[1] if strip is not None else 0.0
            ground = float(np.median(h[max(rr - 3, 0):rr + 4, max(cc - 3, 0):cc + 4]))
            for grid in (coarse, detail):
                grade(grid, spot, heading, 35.0, 28.0, lambda tt, g=ground: np.full_like(tt, g), 15.0, SITE, (30.0, 24.0))
            clearings.append(("rect", spot, heading, 45.0, 38.0))
            features["buildings"].append({"kind": "shelter_mansion", "name": "Shelter Island mansion",
                                          "centre": [float(spot[0]), float(spot[1])], "heading": float(heading),
                                          "ground": ground - base})
            print("  Shelter mansion at %.0f, %.0f (%.1f m from the inner edge)" % (spot[0], spot[1], room[rr, cc]))


def longest_line(px, pz, step=4.0):
    """The longest straight run through a set of points on a 4 m grid:
    (length, heading, start, end), or None."""
    if len(px) < 2:
        return None
    best = None
    for heading in np.arange(0.0, 180.0, 2.0):
        along, across = direction(heading)
        t = px * along[0] + pz * along[1]
        s = px * across[0] + pz * across[1]
        key = np.round(s / step).astype(int)
        order = np.lexsort((t, key))
        tk, kk = t[order], key[order]
        breaks = np.nonzero((np.diff(kk) != 0) | (np.diff(tk) > step * 1.5))[0]
        starts = np.r_[0, breaks + 1]
        ends = np.r_[breaks, len(tk) - 1]
        lengths = tk[ends] - tk[starts]
        i = int(np.argmax(lengths))
        if best is None or lengths[i] > best[0]:
            offset = kk[starts[i]] * step
            a = tk[starts[i]] * along + offset * across
            b = tk[ends[i]] * along + offset * across
            best = (float(lengths[i]), float(heading), a, b)
    return best


# --- Writing -----------------------------------------------------------------

def write_terrain(grid, file_name, base, offset, scale):
    value = np.clip(np.round((grid.h - base + offset) * scale), 0, 65535).astype(np.uint16)
    rgb = np.stack([(value >> 8).astype(np.uint8), (value & 255).astype(np.uint8), grid.kind], axis=-1)
    Image.fromarray(rgb, "RGB").save(os.path.join(OUT, file_name), optimize=True)
    print("  %s: %d x %d" % (file_name, grid.cols, grid.rows))


def write_minimap(coarse, water, inbounds, base, lake):
    step = 4
    h = coarse.h[::step, ::step]
    wet = water[::step, ::step]
    inside = inbounds[::step, ::step]
    gy, gx = np.gradient(h, COARSE * step)
    light = np.clip(0.75 + (-gx * 0.6 - gy * 0.6) / np.sqrt(1 + gx * gx + gy * gy) * 0.8, 0.35, 1.15)
    high = np.clip((h - lake) / 900.0, 0.0, 1.0)
    rgb = np.stack([(0.30 + 0.45 * high) * light, (0.52 + 0.18 * high) * light, (0.26 + 0.30 * high) * light], -1)
    deep = np.clip((lake - h) / MAX_DEPTH, 0.0, 1.0)
    rgb[wet] = np.stack([0.20 - 0.10 * deep, 0.45 - 0.20 * deep, 0.78 - 0.20 * deep], -1)[wet]
    rgb[~inside] *= 0.45
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "minimap.png"))


def write_info_script(coarse, detail, base, lake):
    text = '''extends RefCounted
## Written by tools/bake_map.py. Do not edit by hand: run the script again.
##
## Where the map's data sits in game coordinates. The origin is the corner of
## the build pad on Wild Horse Island, east is +X, north is -Z, and Y = 0 is
## the level of the pad.

const BASE_ELEVATION := %.2f   ## metres above sea level of Y = 0
const LAKE_Y := %.2f           ## the lake surface

const COARSE_FILE := "res://map_data/terrain_coarse.png"
const COARSE_ORIGIN := Vector2(%.1f, %.1f)   ## X and Z of the first sample
const COARSE_SPACING := %.1f
const COARSE_SIZE := Vector2i(%d, %d)
const COARSE_SCALE := %.1f    ## height = value / scale - offset
const COARSE_OFFSET := %.1f

const DETAIL_FILE := "res://map_data/terrain_detail.png"
const DETAIL_ORIGIN := Vector2(%.1f, %.1f)
const DETAIL_SPACING := %.1f
const DETAIL_SIZE := Vector2i(%d, %d)
const DETAIL_SCALE := %.1f
const DETAIL_OFFSET := %.1f

const TILE := %.1f    ## collision squares, metres
const CELL := %.1f    ## tree drawing squares, metres
const WORLD_FILE := "res://map_data/world.json"
const TREES_FILE := "res://map_data/trees.bin"
const TREE_TILES_FILE := "res://map_data/tree_tiles.bin"
const MINIMAP_FILE := "res://map_data/minimap.png"
''' % (base, lake - base,
       coarse.x0, coarse.z0, COARSE, coarse.cols, coarse.rows, COARSE_SCALE, COARSE_OFFSET,
       detail.x0, detail.z0, DETAIL, detail.cols, detail.rows, DETAIL_SCALE, DETAIL_OFFSET,
       TILE, CELL)
    with open(INFO_SCRIPT, "w") as handle:
        handle.write(text)


if __name__ == "__main__":
    main()
