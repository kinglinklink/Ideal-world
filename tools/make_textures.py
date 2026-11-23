"""Makes the building materials' textures from scratch, so nothing has to be
downloaded and every texture is free to share.

    python tools/make_textures.py

Writes textures/materials/<id>.png (the pattern, grey, multiplied by the
part's colour in the game) and, where bumps help, <id>_n.png (a normal map:
red and green hold the surface's tilt along the picture's x and y; blue is
rebuilt in the shader). Every picture tiles: the noise is shaped in the
frequency domain (which wraps round), and drawn lines wrap at the edges.

Also writes scripts/material_textures.gd, the table the game reads: how many
metres one copy of each picture covers, how strong its bumps are, the gain
that keeps the average colour equal to the colour picked, and how much the
pattern changes the roughness.
"""

import os

import numpy as np
from PIL import Image, ImageDraw

SIZE = 256
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "textures", "materials")
TABLE = os.path.join(HERE, "..", "scripts", "material_textures.gd")
rng = np.random.default_rng(11)

U, V = np.meshgrid(np.arange(SIZE) / SIZE, np.arange(SIZE) / SIZE)   # u across, v down


# --- Building blocks -----------------------------------------------------------------

def noise(sigma_u, sigma_v=None, seed=None):
    """Tiling noise, 0 to 1: white noise blurred by a Gaussian of `sigma`
    pixels (longer along v when sigma_v is larger: streaks)."""
    if sigma_v is None:
        sigma_v = sigma_u
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((SIZE, SIZE))
    fu = np.fft.fftfreq(SIZE)[None, :]
    fv = np.fft.fftfreq(SIZE)[:, None]
    shape = np.exp(-2.0 * (np.pi ** 2) * ((fu * sigma_u) ** 2 + (fv * sigma_v) ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * shape))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def fbm(base, octaves=4, seed=None):
    total = np.zeros((SIZE, SIZE))
    amp = 1.0
    norm = 0.0
    sigma = base
    for i in range(octaves):
        total += noise(sigma, seed=None if seed is None else seed + i) * amp
        norm += amp
        amp *= 0.5
        sigma = max(sigma / 2.0, 0.6)
    return total / norm


def cells(count, seed=0):
    """Tiling Voronoi: distance to the nearest point (0 to 1), and which cell."""
    r = np.random.default_rng(seed)
    points = r.random((count, 2))
    best = np.full((SIZE, SIZE), 9.0)
    second = np.full((SIZE, SIZE), 9.0)
    owner = np.zeros((SIZE, SIZE), dtype=int)
    for index, (pu, pv) in enumerate(points):
        du = np.abs(U - pu)
        dv = np.abs(V - pv)
        du = np.minimum(du, 1.0 - du)
        dv = np.minimum(dv, 1.0 - dv)
        d = np.sqrt(du * du + dv * dv)
        closer = d < best
        second = np.where(closer, best, np.minimum(second, d))
        owner = np.where(closer, index, owner)
        best = np.where(closer, d, best)
    return best * np.sqrt(count), second * np.sqrt(count), owner


def lines(count, length, width, shade, seed=0, angle=None, spread=np.pi):
    """Short straight strokes drawn on a picture that wraps (scratches,
    strands). Returns 0 to 1 where 1 is a stroke."""
    r = np.random.default_rng(seed)
    big = Image.new("L", (SIZE * 3, SIZE * 3), 0)
    draw = ImageDraw.Draw(big)
    for _ in range(count):
        cu, cv = r.random(2) * SIZE
        a = r.random() * spread if angle is None else angle + (r.random() - 0.5) * spread
        half = length * (0.5 + r.random()) * SIZE * 0.5
        du, dv = np.cos(a) * half, np.sin(a) * half
        value = int(255 * shade * (0.5 + 0.5 * r.random()))
        for ou in (0, SIZE, 2 * SIZE):
            for ov in (0, SIZE, 2 * SIZE):
                draw.line([(cu + ou - du, cv + ov - dv), (cu + ou + du, cv + ov + dv)], fill=value, width=width)
    folded = np.asarray(big, dtype=float) / 255.0
    tile = np.zeros((SIZE, SIZE))
    for i in range(3):
        for j in range(3):
            tile = np.maximum(tile, folded[i * SIZE:(i + 1) * SIZE, j * SIZE:(j + 1) * SIZE])
    return tile


def normals(height, strength):
    """A normal map from a height field (wrapping), as red-green tilt."""
    du = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * SIZE / 64.0
    dv = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * SIZE / 64.0
    nu, nv, nz = -du * strength, -dv * strength, np.ones_like(height)
    length = np.sqrt(nu * nu + nv * nv + nz * nz)
    rgb = np.stack([nu / length, nv / length, nz / length], axis=-1) * 0.5 + 0.5
    return (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def blend(a, b, t):
    return a + (b - a) * t


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --- The materials ---------------------------------------------------------------------
# Each returns (shade 0..1, height 0..1 or None). The shade multiplies the
# part's colour, so it is grey; the gain in the table puts the average back.

def wood_grain(rings, warp, contrast, pores=0.0, seed=1):
    # The rings wander gently along the board, and a little from fibre to fibre.
    bend = noise(60, 110, seed=seed) - 0.5 + 0.04 * (noise(4, 30, seed=seed + 1) - 0.5)
    phase = rings * U + warp * bend + 0.12 * np.sin(2 * np.pi * V)
    ring = 0.5 + 0.5 * np.sin(2 * np.pi * phase)
    late = smooth(0.55, 0.95, ring)                      # the dark late wood of each ring
    streaks = noise(0.8, 30, seed=seed + 5)              # fibres along the grain
    shade = 1.0 - contrast * late - 0.12 * (streaks - 0.5)
    if pores:
        dash = lines(260, 0.05, 1, 1.0, seed=seed + 9, angle=np.pi / 2, spread=0.1)
        shade -= pores * dash
    height = 0.6 * (1.0 - late) + 0.4 * streaks
    return shade, height


def brushed(streak_len, contrast, scratches=0.0, seed=1):
    streaks = noise(0.7, streak_len, seed=seed)            # along v, the part's length
    fine = noise(0.6, seed=seed + 1)
    shade = 1.0 - contrast * (0.7 * streaks + 0.3 * fine)
    if scratches:
        shade -= scratches * lines(14, 0.35, 1, 1.0, seed=seed + 2)
    return shade, streaks * 0.6 + fine * 0.4


def polished(scratches, mottle, seed=1):
    swirl = fbm(50, 3, seed=seed)
    marks = lines(18, 0.2, 1, 1.0, seed=seed + 3)
    shade = 1.0 - mottle * swirl - scratches * marks
    return shade, marks * 0.5 + swirl * 0.2


def weave(tows, twill, light, dark, seed=1):
    """Woven cloth: tows over and under each other. Warp along v, weft along u."""
    i = np.floor(U * tows).astype(int)
    j = np.floor(V * tows).astype(int)
    fu = U * tows - i
    fv = V * tows - j
    if twill:
        warp_up = ((i - j) % 4) < 2
    else:
        warp_up = ((i + j) % 2) == 0
    # Across a tow it is rounded; along it, the fibres shine.
    across = np.where(warp_up, fu, fv)
    along = np.where(warp_up, fv, fu)
    bulge = np.sin(np.pi * across) ** 0.6 * (0.7 + 0.3 * np.sin(np.pi * along) ** 0.5)
    fibres = noise(0.6, 6, seed=seed)
    fibres = np.where(warp_up, fibres, fibres.T)
    shade = np.where(warp_up, light, dark) * (0.75 + 0.25 * bulge) + 0.08 * (fibres - 0.5)
    return shade, bulge


def bricks(rows, per_row, mortar, seed=1):
    r = np.random.default_rng(seed)
    row = np.floor(V * rows).astype(int)
    shifted = U * per_row + 0.5 * (row % 2)
    col = np.floor(shifted).astype(int) % per_row
    fu = shifted - np.floor(shifted)
    fv = V * rows - row
    gap_u = mortar * per_row
    gap_v = mortar * rows * 1.0
    in_mortar = (fu < gap_u) | (fv < gap_v)
    tone = r.uniform(0.72, 0.95, size=(rows, per_row))[row % rows, col]
    grit = fbm(3, 3, seed=seed + 1)
    shade = np.where(in_mortar, 0.98 - 0.15 * grit, tone * (0.88 + 0.24 * grit))
    edge = np.minimum(smooth(0.0, gap_u * 1.8, fu), smooth(0.0, gap_v * 1.8, fv))
    height = edge * (0.85 + 0.15 * grit)
    return shade, height


def concrete(seed=1):
    mottle = fbm(28, 4, seed=seed)
    grains = noise(1.2, seed=seed + 1)
    pits = smooth(0.82, 0.9, noise(1.4, seed=seed + 2))
    stones = smooth(0.72, 0.78, noise(3.0, seed=seed + 3))
    shade = 0.9 - 0.18 * (mottle - 0.5) - 0.12 * (grains - 0.5) - 0.35 * pits + 0.06 * stones
    return shade, 1.0 - pits * 0.8 + grains * 0.2


def granite(seed=1):
    dark = smooth(0.7, 0.74, noise(1.6, seed=seed))
    light = smooth(0.66, 0.7, noise(2.2, seed=seed + 1))
    pink = smooth(0.68, 0.72, noise(2.8, seed=seed + 2))
    base = 0.75 + 0.1 * (fbm(20, 3, seed=seed + 3) - 0.5)
    shade = base - 0.55 * dark + 0.2 * light + 0.08 * pink
    return shade, None


def foam(seed=1):
    near, second, _ = cells(900, seed=seed)
    rim = smooth(0.0, 0.25, second - near)
    pore = 1.0 - smooth(0.0, 0.55, near)
    shade = 0.95 - 0.18 * pore + 0.03 * (1.0 - rim)
    return shade, 1.0 - pore


def cork(seed=1):
    near, _, owner = cells(1400, seed=seed)
    tone = np.random.default_rng(seed).uniform(0.7, 1.0, size=owner.max() + 1)[owner]
    specks = smooth(0.8, 0.86, noise(0.9, seed=seed + 4))
    shade = tone * (0.92 + 0.08 * smooth(0.0, 0.5, near)) - 0.35 * specks
    return shade, tone * 0.6 + 0.4 * smooth(0.0, 0.5, near)


def rubber(seed=1):
    grain = noise(0.8, seed=seed)
    mottle = fbm(18, 3, seed=seed + 1)
    shade = 0.92 - 0.1 * (grain - 0.5) - 0.08 * (mottle - 0.5)
    return shade, grain


def plain(grain, size=1.0, seed=1):
    fine = noise(size, seed=seed)
    return 1.0 - grain * fine, fine


def orange_peel(seed=1):
    peel = noise(2.5, seed=seed)
    return 0.98 - 0.03 * peel, peel


def fiberglass(seed=1):
    strands = lines(500, 0.12, 1, 1.0, seed=seed)
    resin = fbm(16, 3, seed=seed + 1)
    shade = 0.88 + 0.1 * strands - 0.06 * (resin - 0.5)
    return shade, strands * 0.7 + resin * 0.3


def ice(seed=1):
    cloud = fbm(30, 4, seed=seed)
    cracks = lines(25, 0.5, 1, 1.0, seed=seed + 1)
    bubbles = smooth(0.86, 0.9, noise(1.3, seed=seed + 2))
    shade = 0.82 + 0.16 * cloud + 0.15 * cracks + 0.1 * bubbles
    return shade, cloud * 0.5 + cracks * 0.5


def cast(seed=1):
    sand = noise(0.9, seed=seed)
    mottle = fbm(22, 4, seed=seed + 1)
    pits = smooth(0.85, 0.92, noise(1.1, seed=seed + 2))
    shade = 0.9 - 0.16 * (sand - 0.5) - 0.18 * (mottle - 0.5) - 0.3 * pits
    return shade, sand * 0.6 + mottle * 0.2 - pits * 0.5


def facets(seed=1):
    near, second, owner = cells(60, seed=seed)
    tone = np.random.default_rng(seed).uniform(0.85, 1.0, size=owner.max() + 1)[owner]
    tilt = np.random.default_rng(seed + 1).uniform(0.0, 1.0, size=owner.max() + 1)[owner]
    edge = smooth(0.0, 0.06, second - near)
    return tone * (0.9 + 0.1 * edge), tilt * 0.5 + 0.5 * U * tilt


def lab_grid(seed=1):
    g = 8
    fu = (U * g) % 1.0
    fv = (V * g) % 1.0
    line = 1.0 - np.minimum(smooth(0.0, 0.03, fu) * smooth(0.0, 0.03, 1.0 - fu), smooth(0.0, 0.03, fv) * smooth(0.0, 0.03, 1.0 - fv))
    return 1.0 - 0.18 * line, None


# id: (pattern, metres per copy, bump strength, roughness variation)
PLAN = {
    "foam":         (lambda: foam(1), 0.2, 0.8, 0.0),
    "balsa":        (lambda: wood_grain(9, 1.0, 0.12, 0.0, seed=2), 0.6, 0.25, 0.1),
    "cork":         (lambda: cork(3), 0.25, 0.6, 0.0),
    "wood":         (lambda: wood_grain(7, 1.2, 0.32, 0.0, seed=4), 0.7, 0.35, 0.15),
    "oak":          (lambda: wood_grain(11, 1.4, 0.4, 0.25, seed=5), 0.7, 0.45, 0.15),
    "ice":          (lambda: ice(6), 1.0, 0.3, 0.2),
    "plastic":      (lambda: orange_peel(7), 0.3, 0.15, 0.0),
    "rubber":       (lambda: rubber(8), 0.15, 0.5, 0.1),
    "nylon":        (lambda: plain(0.06, 0.7, seed=9), 0.15, 0.1, 0.05),
    "acrylic":      (lambda: plain(0.0, seed=10), 1.0, 0.0, 0.0),
    "kevlar":       (lambda: weave(8, False, 0.98, 0.82, seed=11), 0.06, 0.7, 0.15),
    "carbon_fiber": (lambda: weave(8, True, 1.0, 0.55, seed=12), 0.05, 0.5, 0.25),
    "magnesium":    (lambda: brushed(40, 0.14, 0.1, seed=13), 0.4, 0.1, 0.2),
    "fiberglass":   (lambda: fiberglass(14), 0.4, 0.3, 0.1),
    "brick":        (lambda: bricks(8, 3, 0.022, seed=15), 0.6, 1.2, 0.1),
    "concrete":     (lambda: concrete(16), 0.8, 0.7, 0.1),
    "glass":        (lambda: plain(0.0, seed=17), 1.0, 0.0, 0.0),
    "aluminum":     (lambda: brushed(50, 0.12, 0.12, seed=18), 0.4, 0.12, 0.25),
    "granite":      (lambda: granite(19), 0.5, 0.0, 0.1),
    "diamond":      (lambda: facets(20), 0.3, 1.5, 0.0),
    "titanium":     (lambda: brushed(30, 0.16, 0.08, seed=21), 0.35, 0.12, 0.2),
    "cast_iron":    (lambda: cast(22), 0.4, 0.6, 0.25),
    "steel":        (lambda: brushed(45, 0.15, 0.18, seed=23), 0.4, 0.12, 0.25),
    "brass":        (lambda: polished(0.12, 0.12, seed=24), 0.5, 0.08, 0.2),
    "copper":       (lambda: polished(0.12, 0.18, seed=25), 0.5, 0.08, 0.2),
    "silver":       (lambda: polished(0.1, 0.08, seed=26), 0.5, 0.06, 0.15),
    "lead":         (lambda: cast(27), 0.5, 0.25, 0.2),
    "depleted_uranium": (lambda: cast(31), 0.3, 0.3, 0.25),
    "tungsten":     (lambda: plain(0.12, 0.8, seed=28), 0.2, 0.2, 0.2),
    "gold":         (lambda: polished(0.08, 0.1, seed=29), 0.5, 0.05, 0.15),
    "frictionless": (lambda: lab_grid(30), 1.0, 0.0, 0.0),
}


def to_linear(shade):
    return np.clip(shade, 0.0, 1.0) ** 2.2


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for name, (make, metres, bump, rough_var) in PLAN.items():
        shade, height = make()
        shade = np.clip(shade, 0.0, 1.0)
        Image.fromarray((shade * 255.0 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, name + ".png"), optimize=True)
        has_bumps = height is not None and bump > 0.0
        if has_bumps:
            Image.fromarray(normals(height, 1.0), "RGB").save(os.path.join(OUT, name + "_n.png"), optimize=True)
        gain = 1.0 / max(float(to_linear(shade).mean()), 0.05)
        rows.append('\t"%s": {"tile": %.3f, "bump": %.2f, "gain": %.3f, "rough_var": %.2f, "normals": %s},'
                    % (name, metres, bump if has_bumps else 0.0, gain, rough_var, "true" if has_bumps else "false"))
        print("%-13s gain %.2f%s" % (name, gain, "  + normals" if has_bumps else ""))
    with open(TABLE, "w") as f:
        f.write('extends RefCounted\n')
        f.write('## Written by tools/make_textures.py: do not edit by hand.\n')
        f.write('## For each material, how many metres one copy of its picture covers,\n')
        f.write('## how strong its bumps are (0: no normal map), the gain that keeps the\n')
        f.write('## average colour equal to the colour picked, and how much the pattern\n')
        f.write('## changes the roughness.\n\n')
        f.write('const TEXTURES := {\n')
        f.write("\n".join(rows) + "\n}\n")


if __name__ == "__main__":
    main()
