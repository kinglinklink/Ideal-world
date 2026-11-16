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
from skimage import measure

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
SHORE_STRIP = 500.0                    # metres of mainland inside the wall
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

    # In bounds: the lake, every island, and a strip of the mainland.
    land_to_water = ndimage.distance_transform_edt(~coarse_water) * COARSE
    inbounds = coarse_water | (land_to_water <= SHORE_STRIP)
    inbounds = ndimage.binary_fill_holes(inbounds)
    edge = int(200.0 / COARSE)
    inbounds[:edge, :] = False
    inbounds[-edge:, :] = False
    inbounds[:, :edge] = False
    inbounds[:, -edge:] = False
    inbounds = ndimage.binary_fill_holes(inbounds)
    labels, _ = ndimage.label(inbounds)
    r, c = coarse.cell(lx, lz)
    inbounds = labels == labels[r, c]

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
    cromwell = island_at(*ref_point(-3895.0, -637.0))

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

    features = {"runways": [], "buildings": [], "docks": []}

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
    features["buildings"].append({
        "kind": "cromwell_mansion", "name": "Cromwell Island villa",
        "centre": [cx, cz], "heading": 90.0, "ground": mansion_height - base,
    })

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
    trees = place_trees(coarse, detail, coarse_water, detail_water, inbounds, wild_horse, melita, cromwell,
                        island_labels, features, home_centre, home_half, wh_centre, wh_heading, wh_half,
                        apron_centre, m_centre, melita_heading, m_half, lodge_centre, clearing_centre,
                        (cx, cz), base)
    print("  %d trees" % len(trees))

    # --- The wall ---
    walls = wall_lines(coarse, inbounds)

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
        "walls": walls, "carrier_spots": carrier_spots, "islands": labels_list, "tree_cells": tree_cells,
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


def place_trees(coarse, detail, coarse_water, detail_water, inbounds, wild_horse, melita, cromwell,
                island_labels, features, home_centre, home_half, wh_centre, wh_heading, wh_half,
                apron_centre, m_centre, m_heading, m_half, lodge_centre, clearing_centre, mansion, base):
    found = []

    def keep_out(grid, x, z):
        """True where trees must not grow."""
        blocked = np.zeros(x.shape, dtype=bool)

        def rect(centre, heading, half_len, half_wid):
            along, across = direction(heading)
            dx, dz = x - centre[0], z - centre[1]
            t = dx * along[0] + dz * along[1]
            s = dx * across[0] + dz * across[1]
            return (np.abs(t) <= half_len) & (np.abs(s) <= half_wid)

        blocked |= rect(home_centre, 0.0, home_half[0] + 50.0, home_half[1] + 50.0)
        blocked |= rect(wh_centre, wh_heading, wh_half + 120.0, 60.0)
        blocked |= rect(apron_centre, wh_heading, 120.0, 75.0)
        blocked |= rect(m_centre, m_heading, m_half + 15.0, 7.5 + 14.0)
        blocked |= rect(lodge_centre, m_heading, 32.0, 24.0)
        blocked |= np.hypot(x - clearing_centre[0], z - clearing_centre[1]) < 90.0
        blocked |= rect(mansion, 90.0, 85.0, 70.0)
        return blocked

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
        ok = ~keep_out(grid, x, z)
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
    # The mainland inside the wall: woods in patches.
    in_d = coarse.sample(inbounds.astype(float), detail.X, detail.Z, order=0) > 0.5
    mainland = others & ~small_island
    density[mainland] = (np.clip(patches * 1.4 - 0.3, 0.0, 1.0) / 160.0)[mainland]
    found.append(scatter(detail, density, d_land, 6.0, in_d))

    # Everywhere else inside the wall, at the coarse spacing.
    c_land = ~coarse_water
    cpatch = smooth_noise(coarse.h.shape, 6.0)
    cdensity = np.clip(cpatch * 1.4 - 0.3, 0.0, 1.0) / 260.0
    outside_detail = ~detail.inside(coarse.X, coarse.Z, 4.0)
    found.append(scatter(coarse, cdensity, c_land, 16.0, inbounds & outside_detail))
    trees = np.concatenate(found, axis=0)

    # Record how wooded each spot is, for shading the ground from far away.
    for grid in (detail, coarse):
        counts = np.zeros(grid.h.shape)
        r = np.clip(np.round((trees[:, 2] - grid.z0) / grid.sp).astype(int), 0, grid.rows - 1)
        c = np.clip(np.round((trees[:, 0] - grid.x0) / grid.sp).astype(int), 0, grid.cols - 1)
        np.add.at(counts, (r, c), 1.0)
        per_area = ndimage.gaussian_filter(counts, 1.5) / (grid.sp * grid.sp)
        wooded = np.clip(per_area * 40.0 * 31.0, 0, 31).astype(np.uint8)
        grid.kind = (grid.kind & 7) | (wooded << 3)
    return trees


def write_trees(trees, coarse):
    """Writes every tree as a MultiMesh instance (a 3 x 4 transform and a
    colour, 16 floats), sorted by 1,024 m drawing square and then by 128 m
    collision square, so that both are runs of the file. X and Z are measured
    from the middle of the tree's drawing square, where the game puts the
    square's MultiMesh, so that its draw distance is judged from there."""
    count = len(trees)
    x, y, z = trees[:, 0], trees[:, 1], trees[:, 2]
    size = RNG.uniform(1.0, 2.2, count)
    turn = RNG.uniform(0.0, 2.0 * math.pi, count)
    tile_i = np.floor(x / TILE).astype(np.int64)
    tile_k = np.floor(z / TILE).astype(np.int64)
    per = int(CELL / TILE)
    cell_i = np.floor_divide(tile_i, per)
    cell_k = np.floor_divide(tile_k, per)
    order = np.lexsort((tile_i, tile_k, cell_i, cell_k))
    x, y, z, size, turn = x[order], y[order], z[order], size[order], turn[order]
    tile_i, tile_k, cell_i, cell_k = tile_i[order], tile_k[order], cell_i[order], cell_k[order]

    buffer = np.zeros((count, 16), dtype=np.float32)
    cos, sin = np.cos(turn) * size, np.sin(turn) * size
    buffer[:, 0] = cos
    buffer[:, 2] = sin
    buffer[:, 3] = x - (cell_i + 0.5) * CELL
    buffer[:, 5] = size
    buffer[:, 7] = y
    buffer[:, 8] = -sin
    buffer[:, 10] = cos
    buffer[:, 11] = z - (cell_k + 0.5) * CELL
    buffer[:, 12] = RNG.uniform(0.10, 0.20, count)
    buffer[:, 13] = RNG.uniform(0.32, 0.48, count)
    buffer[:, 14] = RNG.uniform(0.14, 0.24, count)
    buffer[:, 15] = 1.0
    buffer.tofile(os.path.join(OUT, "trees.bin"))

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


# --- Wall --------------------------------------------------------------------

def wall_lines(coarse, inbounds):
    padded = np.pad(inbounds.astype(float), 1)
    padded = ndimage.gaussian_filter(padded, 1.0)
    lines = measure.find_contours(padded, 0.5)
    lines.sort(key=len, reverse=True)
    outer = measure.approximate_polygon(lines[0], tolerance=0.6)
    points = []
    for row, col in outer:
        points.append([float(coarse.x0 + (col - 1) * COARSE), float(coarse.z0 + (row - 1) * COARSE)])
    length = sum(math.dist(points[i], points[i + 1]) for i in range(len(points) - 1))
    print("Wall: %d corners, %.1f km long" % (len(points), length / 1000.0))
    return [points]


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
