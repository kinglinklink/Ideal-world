"""Writes the B-2 Spirit build: a full-size flying-wing bomber in dark grey.

    python3 tools/make_b2.py <out.json>

The nose points along +Z, up is +Y, and the pilot's left is +X. Full size:
four cells (0.25 m) to the metre, 52 m across. Ground is y 0.

What it carries: 43 small bombs (100 m blast) in a grid of bays filling the
centre body, one huge bomb (500 m blast) in the middle, and four missiles
under the wings that fly straight ahead. Every bay is a reload gate, so it
hangs a fresh bomb a moment after it lets one go.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from build_kit import Build, X0, side_box, holes_cut, IDENT  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/b2.json"
THRUST = float(os.environ.get("B2_THRUST", "250000"))   # each of four engines

SMALL_RADIUS = 100.0       # m, small bombs' blast
BIG_RADIUS = 500.0         # m, the big one's
MISSILE_RADIUS = 25.0
SMALL_RELOAD = float(os.environ.get("B2_SMALL_RELOAD", "2.0"))   # s, each small bay
BIG_RELOAD = 3.0
MISSILE_RELOAD = 0.5
SMALL_FLOOR = 160.0        # m above the ground: no small bombs below this (the blast hurts out to 150 m)
BIG_FLOOR = 800.0          # m: nor the big one below this (its blast reaches 500 m)
MISSILE_FLOOR = 30.0
# Stability system: yaw from the sideslip, and the thrusters' share.
SLIP_GAIN = 2.0            # degrees a second of turn into the airflow, for each degree of slip
YAW_KP, YAW_KI = 4.0, 1.0
DIFF_THRUST = 0.5          # the most each side's throttle moves for yaw
VEC_PITCH = 0.8            # engine swivel, degrees per degree of pitch command
VEC_ROLL = 0.5             # and of roll command, each side opposite
PITCH_KP, PITCH_KI = 4.0, 3.0
INNER_ROLL = 1.0           # the inner elevons' share of the roll command
ROLL_KI = 1.5
GEAR_UP_AT = 50.0          # m above the ground: the gear goes up
GEAR_DOWN_AT = 35.0        # and comes down again below this

SKIN = "#34373d"
DARK = "#26282d"
EDGE = "#2c2f35"
GLASS = "#1d2a38"
BAY = "#1a1b1f"
METAL = "#55585f"
BOMB = "#4b5233"           # olive drab
BOMB_NOSE = "#3c3f2a"
CASING = "plastic"         # the bombs' casings: about 750 kg a small bomb with its steel nose
BIG_BOMB = "#5c5f62"
WHITE = "#e9e9e6"
RED = "#a1111b"

b = Build("B-2 Spirit")
SIDES = (1, -1)          # +1 the pilot's left (+X), -1 the right (-X)

# ---------------------------------------------------------------------------
# The shape. z falls going aft; dx is the distance out from the centreline.
NZ = 172.0               # the nose
K = 0.65                 # leading edges swept 33 degrees: tan 33 = 0.65
BELLY = 8.0              # the flat underside, 2 m up
SLAB = 10.0              # top of the wing over the inner and middle wing
OUTER_TOP = 9.0          # and over the outer wing (thinner)
TIP = 104.0              # half span, cells
TIP_LE = 104.5
CENTRE_TE = 90.5         # the trailing edge's points: the middle of the tail
NOTCH_TE = 110.0         # the notches at dx 30
W_TE = 90.5              # the points at dx 60
HINGE = 98.0             # hinge line of the outer wing's surfaces
SURF_TE = 90.0           # their trailing edge: long surfaces, for a heavy wing

# The bay box: the centre body between the walls, full of bomb bays.
BOX_DX = 22.25
BOX_Z0, BOX_Z1 = 106.0, 146.0
BOX_TOP = 14.5
DECK = 11.0              # bay ceiling (the small bays' gates hang from it)
BIG_DECK = 13.0          # the big bay's ceiling, higher (under the top skin)
ROWS = [107.0, 120.0, 133.0]          # tail end of each row's small bombs (12 cells long)
COLS = [4.25 + 2.75 * k for k in range(7)]   # small columns' dx, each side
MID_TOP = 10.0           # the middle wing's top: flush with the inner wing
MID_BOT = 8.75           # and its underside, a little higher than the belly
OUT_BOT = 9.25           # the outer wing's underside: thinner still

# Humps: one each side, over the engines and the main gear.
HUMP_DX0, HUMP_DX1 = 28.25, 38.25
ROOT_DX = 38.25          # the wing's root, full depth, reaches out under the humps
ROOF = SLAB + 2.0        # the root, round the wells, is twice as deep: 1 m
HUMP_Z0, HUMP_Z1 = 110.0, 144.0
HUMP_TOP = 19.0
GEAR_Z = float(os.environ.get("B2_GEAR_Z", "122.0"))
GEAR_DX = 33.25
NOSE_GEAR_Z = 163.0

# Cockpit hump over the nose.
CP_DX = 6.0
CP_Z0, CP_Z1 = 146.0, 168.0
HATCH = (X0 - 2.5, X0 + 2.5, 154.5, 158.0)
BIG_END = ROWS[1] + 12.5     # the big bay's front wall
NOSE_WELL = (X0 - 2.25, X0 + 2.25, 161.0, 165.0)

# ---------------------------------------------------------------------------
# Logic parts: weightless and hidden once spawned, in rows on the floor in a
# corner of the grid, clear of the plane.
_logic_slot = [0]


def logic(ptype, settings, links=None):
    n = _logic_slot[0]
    _logic_slot[0] += 1
    col, row = n % 14, n // 14
    x, z = 4 + col * 1.5, 4 + row * 1.5
    d = {}
    if links:
        d = {port: {"part": src, "output": out} for port, (src, out) in links.items()}
    return b.add(ptype, (x, x + 1, 0, 0.5, z, z + 1), IDENT, "#2a2c33", material="plastic",
                 settings=settings, links=d)


def pad(control, scale=1.0, mode="Hold", curve=1.0, deadzone=0.12, second=None):
    s = {"control": control, "mode": mode, "curve": curve, "deadzone": deadzone, "scale": scale,
         "output": "Number from two controls" if second else "One control"}
    if second:
        s["second_control"] = second
    return logic("gamepad_input", s)


def key(k, mode="Hold", second=None):
    s = {"key": k, "mode": mode, "output": "Number from two keys" if second else "Boolean",
         "second_key": second or ""}
    return logic("input_block", s)


def gate(op, a=None, b_=None, c=None, value=0.0):
    links = {}
    if a is not None:
        links["a"] = a
    if b_ is not None:
        links["b"] = b_
    if c is not None:
        links["c"] = c
    return logic("number_gate", {"operation": op, "value": value}, links)


def bgate(op, a=None, b_=None, seconds=1.0):
    links = {}
    if a is not None:
        links["a"] = a
    if b_ is not None:
        links["b"] = b_
    return logic("boolean_gate", {"operation": op, "seconds": seconds}, links)


def sym_clamp(src, limit):
    """Between -limit and limit (the Clamp gate keeps between 0 and its value)."""
    low = gate("Max", R(src), value=-limit)
    return gate("Min", R(low), value=limit)


def V(i):
    return (i, "value")


def P(i):
    return (i, "pressed")


def R(i):
    return (i, "result")


def T(i):
    return (i, "is_true")


def O(i):
    return (i, "output")


def le(dx):
    return NZ - K * dx


# ---------------------------------------------------------------------------
# The wing: one slab of aero panels over the whole planform, 0.5 m thick
# inboard and 0.25 m outboard, cut round the bay box, the wells and the
# hatch. It is what lifts the plane (the bay ceilings lift too).
NOSE_RECT = (X0 - CP_DX, X0 + CP_DX, BOX_Z1, 168.0)
NOSE_BOT = 9.0           # the wing ahead of the bay box is thinner: the nose is light
for (x0, x1, z0, z1) in holes_cut(NOSE_RECT, [HATCH, NOSE_WELL]):
    b.box((x0, x1, NOSE_BOT, SLAB, z0, z1), SKIN, ptype="aero_panel")
WELLS = {}
for s in SIDES:
    # Apex: a small triangle in front of the nose rectangle.
    b.tri_panel(side_box(s, 0.0, CP_DX, NOSE_BOT, SLAB, 168.0, NZ), (s, 0, 0), (0, 0, 1), SKIN)
    # Inner wing, in front of the bay box.
    b.box(side_box(s, CP_DX, 30.0, NOSE_BOT, SLAB, BOX_Z1, 152.5), SKIN, ptype="aero_panel")
    b.tri_panel(side_box(s, CP_DX, 30.0, NOSE_BOT, SLAB, 152.5, le(CP_DX)), (s, 0, 0), (0, 0, 1), SKIN)
    # Beside the bay box and under the hump: the wing's root, full depth,
    # with the main gear's well cut out. The engines and the gear push on
    # it, and it is welded along the box's whole side.
    gx = X0 + s * GEAR_DX
    well = (gx - 2.75, gx + 2.75, GEAR_Z - 2.5, GEAR_Z + 2.5)
    WELLS[s] = well
    r_a, r_b = sorted((X0 + s * BOX_DX, X0 + s * ROOT_DX))
    # (Twice as deep as the rest: the pieces round the well are joined by
    # their sides, and deep sides make wide joints for the wing's bending.)
    for (x0, x1, z0, z1) in holes_cut((r_a, r_b, NOTCH_TE, 133.0), [well]):
        b.box((x0, x1, BELLY, ROOF, z0, z1), SKIN, ptype="aero_panel")
    b.box(side_box(s, BOX_DX, 30.0, BELLY, SLAB, 133.0, BOX_Z1), SKIN, ptype="aero_panel")
    # The tail: a triangle behind the bay box back to the middle point, and
    # the bits of trailing edge beside the box's back corners.
    tail_dx = (BOX_Z0 - CENTRE_TE) / K
    b.tri_panel(side_box(s, 0.0, tail_dx, BELLY, SLAB, CENTRE_TE, BOX_Z0), (s, 0, 0), (0, 0, -1), SKIN)
    b.box(side_box(s, BOX_DX, tail_dx, BELLY, SLAB, BOX_Z0, NOTCH_TE), SKIN, ptype="aero_panel")
    b.tri_panel(side_box(s, tail_dx, 30.0, BELLY, SLAB, BOX_Z0, NOTCH_TE), (s, 0, 0), (0, 0, -1), SKIN)
    # Middle wing.
    b.box(side_box(s, ROOT_DX, 60.0, MID_BOT, MID_TOP, NOTCH_TE, 133.0), SKIN, ptype="aero_panel")
    b.tri_panel(side_box(s, 30.0, 60.0, MID_BOT, MID_TOP, 133.0, le(30.0)), (s, 0, 0), (0, 0, 1), SKIN)
    b.tri_panel(side_box(s, 30.0, 60.0, MID_BOT, MID_TOP, W_TE, NOTCH_TE), (-s, 0, 0), (0, 0, -1), SKIN)
    # Outer wing, thinner.
    b.box(side_box(s, 60.0, TIP, OUT_BOT, SLAB, HINGE, TIP_LE), SKIN, ptype="aero_panel")
    b.tri_panel(side_box(s, 60.0, TIP, OUT_BOT, SLAB, TIP_LE, 133.0), (s, 0, 0), (0, 0, 1), SKIN)

# Trailing-edge surfaces on the outer wing: split, like the real B-2's.
# The inner pair are elevons; the outer pair are elevons that also split
# open, one side at a time, to steer (drag rudders), or both as air brakes.
SURFACES = {}      # (side, "inner"/"outer", "top"/"bottom") -> servo
TOP_AXES = ([-1, 0, 0], [0, 0, -1], [0, -1, 0])
BOTTOM_AXES = ([1, 0, 0], [0, 0, -1], [0, 1, 0])


def split_surface(s, dx0, dx1, y0, y1, hinge_z, chord, name):
    """Two door hinge servos (top and bottom) just behind hinge_z, each with
    a thin panel behind it."""
    mid = (y0 + y1) / 2
    settings = {"default_angle": 0.0, "positive_angle": 60.0, "negative_angle": -60.0,
                "speed": 250.0, "easing": 1500.0, "max_torque": 400000.0,
                "when_idle": "Return to default angle"}
    top = b.add("door_hinge_servo", side_box(s, dx0, dx1, mid, y1, hinge_z - 1.0, hinge_z), TOP_AXES, DARK,
                settings=dict(settings))
    bottom = b.add("door_hinge_servo", side_box(s, dx0, dx1, y0, mid, hinge_z - 1.0, hinge_z), BOTTOM_AXES, DARK,
                   settings=dict(settings))
    t = 0.15
    b.box(side_box(s, dx0, dx1, y1 - t, y1, hinge_z - 1.0 - chord, hinge_z - 1.0), SKIN, ptype="aero_panel")
    b.box(side_box(s, dx0, dx1, y0, y0 + t, hinge_z - 1.0 - chord, hinge_z - 1.0), SKIN, ptype="aero_panel")
    SURFACES[(s, name, "top")] = top
    SURFACES[(s, name, "bottom")] = bottom


TIPS = {}
for s in SIDES:
    split_surface(s, 61.0, 80.5, OUT_BOT, SLAB, HINGE, HINGE - 1.0 - SURF_TE, "inner")
    split_surface(s, 81.5, 101.0, OUT_BOT, SLAB, HINGE, HINGE - 1.0 - SURF_TE, "outer")
    # Fixed trailing edge either side of the surfaces, clear of them.
    for (d0, d1) in [(60.0, 60.9), (80.6, 81.4), (101.1, TIP)]:
        b.box(side_box(s, d0, d1, OUT_BOT, SLAB, SURF_TE, HINGE), SKIN)
    # Wing tip: navigation light, red on the left, green on the right.
    TIPS[s] = b.add("light_panel", side_box(s, TIP, TIP + 0.125, OUT_BOT + 0.1, SLAB - 0.1, 99.0, 103.0),
                    ([0, 0, 1], [s, 0, 0], [0, s, 0]), "#ff2222" if s > 0 else "#22ff44",
                    settings={"color": "#ff2222" if s > 0 else "#22ff44", "brightness": 2.0})

# ---------------------------------------------------------------------------
# The bay box: open underneath, walls between the columns of bays, a
# ceiling (the decks) the bombs hang from, and the top skin.
bx0, bx1 = X0 - BOX_DX, X0 + BOX_DX
b.box((bx0, bx1, BELLY, BOX_TOP, BOX_Z0, BOX_Z0 + 0.5), DARK)            # rear wall
b.box((bx0, bx1, BELLY, BOX_TOP, BOX_Z1 - 0.5, BOX_Z1), DARK)            # front wall
for s in SIDES:
    b.box(side_box(s, BOX_DX - 0.25, BOX_DX, BELLY, BOX_TOP, BOX_Z0 + 0.5, BOX_Z1 - 0.5), DARK)
    # The big bay's walls reach up to its higher ceiling.
    b.box(side_box(s, 2.75, 3.0, BELLY, BIG_DECK, BOX_Z0 + 0.5, BIG_END), BAY)
    b.box(side_box(s, 2.75, 3.0, BELLY, DECK, BIG_END, BOX_Z1 - 0.5), BAY)
    for k in range(1, 7):
        d0 = 2.75 + 2.75 * k
        b.box(side_box(s, d0, d0 + 0.25, BELLY, DECK, BOX_Z0 + 0.5, BOX_Z1 - 0.5), BAY)
    # Ceiling over the small bays: aero panels, so the box lifts its share.
    b.box(side_box(s, 3.0, BOX_DX - 0.25, DECK, DECK + 0.5, BOX_Z0 + 0.5, BOX_Z1 - 0.5), BAY, ptype="aero_panel")
# The centre column: the big bay at the back (high ceiling), one small bay in front.
b.box((X0 - 2.75, X0 + 2.75, BIG_DECK, BIG_DECK + 0.5, BOX_Z0 + 0.5, BIG_END), BAY, ptype="aero_panel")
b.box((X0 - 2.75, X0 + 2.75, DECK, BIG_DECK, BIG_END, BIG_END + 0.5), BAY)
b.box((X0 - 2.75, X0 + 2.75, DECK, DECK + 0.5, BIG_END + 0.5, BOX_Z1 - 0.5), BAY, ptype="aero_panel")
# Top skin: it lifts too (each panel lifts at its own middle, so lift up
# here, ahead of the thin outer wings, keeps the wing's lift balanced on
# the heavy middle).
b.box((bx0, bx1, BOX_TOP - 1.0, BOX_TOP, BOX_Z0 + 0.5, BOX_Z1 - 0.5), SKIN, ptype="aero_panel")
# Ballast in the tail: a tungsten slab that brings the weight back over the
# lift. (Half what it was before the engines moved back onto their swivels.)
BALLAST = b.box((X0 - 2.0, X0 + 2.0, SLAB, SLAB + 1.0, 96.0, 98.0), DARK, material="tungsten")
# Slopes down to the wing all round (the cockpit hump fills the front middle).
for s in SIDES:
    b.wedge(side_box(s, BOX_DX, BOX_DX + 4.0, ROOF, BOX_TOP, BOX_Z0, BOX_Z1), (-s, 0, 0), (0, -1, 0), SKIN)
    for (z0, z1) in ((BOX_Z0, NOTCH_TE), (133.0, BOX_Z1)):
        b.box(side_box(s, BOX_DX, BOX_DX + 4.0, SLAB, ROOF, z0, z1), SKIN)
    b.wedge(side_box(s, CP_DX, BOX_DX, SLAB, BOX_TOP, BOX_Z1, BOX_Z1 + 4.0), (0, 0, -1), (0, -1, 0), SKIN)
    b.corner(side_box(s, BOX_DX, BOX_DX + 3.5, SLAB, BOX_TOP, BOX_Z1, BOX_Z1 + 3.5), (-s, 0, 0), (0, 0, -1), (0, -1, 0), SKIN)
b.wedge((X0 - 19.0, X0 + 19.0, SLAB, BOX_TOP, BOX_Z0 - 2.5, BOX_Z0), (0, 0, 1), (0, -1, 0), SKIN)

# ---------------------------------------------------------------------------
# Bombs. Each hangs nose forward on a reload gate under the ceiling, clear
# of the walls and its neighbours, so the gate's payload is the bomb alone.
# A heavy steel nose keeps it falling nose first.
BAYS = []        # (gate, explosive, detector, row, column) for the small bombs


def bomb(cx, z0, ceiling, dia, nose, body, tail, radius, reload_time, safe_time, colour):
    """A bomb hanging from a gate under `ceiling`, its tail end at z0.
    Returns (gate, explosive, detector)."""
    top = ceiling - 0.25
    r = dia / 2
    y0, y1 = top - dia, top
    yc = (y0 + y1) / 2
    zb0, zb1 = z0 + tail, z0 + tail + body
    # Inside the casing, in the same fibreglass: the charge, and the
    # detector that sets it off on impact. Listed first so they keep their
    # own weight where they share space with the casing.
    q = dia * 0.34
    exp = b.add("explosive_block", (cx - q, cx + q, yc - q, yc + q, zb0 + 1.0, zb1 - 1.5), IDENT, colour,
                material=CASING, settings={"blast_radius": radius})
    d = 0.5
    det = b.add("impact_detector", (cx - d, cx + d, yc - d, yc + d, zb1 - 1.25, zb1 - 0.25), IDENT, colour,
                material=CASING, settings={"threshold": 30.0, "pulse": 0.2})
    b.along("cylinder", (cx - r, cx + r, y0, y1, zb0, zb1), (0, 0, 1), colour, material=CASING)
    b.along("cone", (cx - r, cx + r, y0, y1, zb1, zb1 + nose), (0, 0, 1), BOMB_NOSE, material="steel")
    b.along("cone", (cx - r, cx + r, y0, y1, z0, zb0), (0, 0, -1), colour, material=CASING)
    # Tail fins: a cross of thin plates, no wider than the bomb.
    t = 0.05
    b.box((cx - r, cx + r, yc - t, yc + t, z0, zb0), colour, material=CASING)
    b.box((cx - t, cx + t, y0, y1, z0, zb0), colour, material=CASING)
    # The gate over the casing, rail down: short and thin, it weighs little.
    w = 0.5 if dia < 3.0 else 1.0
    zm = (zb0 + zb1) / 2
    half = 2.0 if dia < 3.0 else 4.0
    rack = b.add("reload_gate", (cx - w, cx + w, top, ceiling, zm - half, zm + half),
                 ([1, 0, 0], [0, -1, 0], [0, 0, -1]), METAL, material="aluminum",
                 settings={"reload_time": reload_time, "reloads": 0.0, "safe_time": safe_time,
                           "push_speed": 3.0})
    return rack, exp, det


for r_i, z0 in enumerate(ROWS):
    for s in SIDES:
        for c_i, dx in enumerate(COLS):
            rack, exp, det = bomb(X0 + s * dx, z0, DECK, 2.0, 2.5, 7.5, 2.0, SMALL_RADIUS,
                                  SMALL_RELOAD, 1.0, BOMB)
            BAYS.append((rack, exp, det, r_i, s * (c_i + 1)))
    if r_i == 2:
        # The centre column's one small bay, in front of the big bomb.
        rack, exp, det = bomb(X0, z0, DECK, 2.0, 2.5, 7.5, 2.0, SMALL_RADIUS, SMALL_RELOAD, 1.0, BOMB)
        BAYS.append((rack, exp, det, r_i, 0))
# The big one: a metre thick and six long, in the middle of the box.
BIG = bomb(X0, ROWS[0], BIG_DECK, 4.0, 6.0, 15.0, 4.0, BIG_RADIUS, BIG_RELOAD, 1.5, BIG_BOMB)

# ---------------------------------------------------------------------------
# Humps over the engines and main gear.
THRUSTERS = {1: [], -1: []}       # by side: each side's pair gets its own throttle
VECTOR_SERVOS = {1: [], -1: []}
VECTOR_MAX = 20.0                 # degrees each way the engines swivel
EXHAUST = []
for s in SIDES:
    hx0, hx1 = sorted((X0 + s * HUMP_DX0, X0 + s * HUMP_DX1))
    for wx in ((hx0, hx0 + 0.5), (hx1 - 0.5, hx1)):
        b.box((wx[0], wx[1], ROOF, HUMP_TOP, HUMP_Z0 + 2.0, 133.0), SKIN)
        b.box((wx[0], wx[1], SLAB, HUMP_TOP, 133.0, HUMP_Z1 - 6.0), SKIN)
    b.box((hx0, hx1, HUMP_TOP - 0.5, HUMP_TOP, HUMP_Z0 + 2.0, HUMP_Z1 - 6.0), SKIN, ptype="aero_panel")
    b.wedge((hx0, hx1, SLAB, HUMP_TOP, HUMP_Z1 - 6.0, HUMP_Z1), (0, 0, -1), (0, -1, 0), EDGE)    # intake front
    b.wedge((hx0, hx1, ROOF, HUMP_TOP, HUMP_Z0, HUMP_Z0 + 2.0), (0, 0, 1), (0, -1, 0), SKIN)     # exhaust deck
    # Engines: a hidden thruster each, pushing on an aluminium bulkhead
    # that spreads the push into the hump and the wing.
    # Engines: low, just behind the wing's deep root, so the push goes
    # through the middle of the plane (high up, it would hold the nose down
    # on the runway). Steel: their weight, back here, balances the bombs.
    # Each swivels up and down on a servo for thrust vectoring: a mount on
    # the root's back face holds the servo's base half; its top (+X) carries
    # a hub, and the engine hangs off the hub behind the servo, its push
    # passing through the servo's axis. The glow is on its back.
    for ex in (33.0, 37.0):
        cx = X0 + s * ex
        y0, y1 = SLAB + 0.25, ROOF + 0.25            # clear of the wing's top
        b.box((cx - 2.0, cx - 0.1, y0, y1, NOTCH_TE - 0.5, NOTCH_TE), METAL, material="aluminum")
        servo = b.add("servo", (cx - 1.0, cx + 1.0, y0, y1, NOTCH_TE - 2.5, NOTCH_TE - 0.5),
                      ([0, 0, 1], [1, 0, 0], [0, 1, 0]), DARK,
                      settings={"default_angle": 0.0, "positive_angle": VECTOR_MAX, "negative_angle": -VECTOR_MAX,
                                "speed": 120.0, "easing": 600.0, "max_torque": 5000000.0,
                                "when_idle": "Return to default angle"})
        VECTOR_SERVOS[s].append(servo)
        b.box((cx + 1.0, cx + 1.5, y0, y1, NOTCH_TE - 5.5, NOTCH_TE - 0.5), METAL, material="aluminum")
        THRUSTERS[s].append(b.add("thruster", (cx - 1.0, cx + 1.0, y0, y1, NOTCH_TE - 5.5, NOTCH_TE - 2.75),
                                  ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), "#0d0d0f", material="steel",
                                  settings={"thrust": THRUST, "ideal": True}))
        EXHAUST.append(b.add("light_panel", (cx - 1.0, cx + 1.0, y0 + 0.2, y1 - 0.2,
                                             NOTCH_TE - 5.62, NOTCH_TE - 5.5),
                             ([1, 0, 0], [0, 0, -1], [0, 1, 0]), "#ff6a1a",
                             settings={"color": "#ff6a1a", "brightness": 3.0}))

# ---------------------------------------------------------------------------
# Landing gear: each leg on a piston that pulls it up into its well, under
# the humps (main) and the cockpit (nose). The barrel sits on top of the
# wing, held by aluminium plates fore and aft that rest on the wing beside
# the well; the wheels rise past them, either side.
GEAR_TRAVEL = 8.5
MAIN_LIFT = 2.75         # cells the main wheels sit higher than the nose wheel: about 3.5 degrees nose up
GEAR_PISTONS = []


def gear_leg(cx, cz, wheel_d, wheel_w, wheel_dx, steer=False, plates=(3.7, 3.7), lift=0.0, barrel_y=None,
             travel=GEAR_TRAVEL):
    """A leg at (cx, cz). `lift` raises its wheels: the main wheels sit
    higher than the nose wheel, so the plane stands a little nose up and
    its wing lifts as it rolls. The barrel sits on top of the wing, held by
    plates fore and aft, or (barrel_y) hangs from a roof that high up, with
    the strut long enough that nothing on the leg rises into it. A steered
    leg turns on a servo just above its axle."""
    top = ROOF if barrel_y is None else barrel_y
    p = b.add("piston", (cx - 0.9, cx + 0.9, top, top + 1.5, cz - 0.9, cz + 0.9),
              ([1, 0, 0], [0, -1, 0], [0, 0, -1]), METAL, material="steel",
              settings={"current_length": travel, "target_length": 0.0, "max_length": travel,
                        "speed": 1.2, "easing": 2.0, "max_force": 1500000.0,
                        "when_idle": "Return to starting length"})
    GEAR_PISTONS.append(p)
    if barrel_y is None:
        for (z0, z1) in ((cz + 0.9, cz + 0.9 + plates[0]), (cz - 0.9 - plates[1], cz - 0.9)):
            b.box((cx - 0.9, cx + 0.9, ROOF, ROOF + 1.5, z0, z1), DARK)
    axle_y = lift + wheel_d / 2
    strut_bottom = axle_y + 0.6
    steer_servo = None
    if steer:
        steer_servo = b.add("servo", (cx - 0.9, cx + 0.9, strut_bottom, strut_bottom + 1.5, cz - 0.9, cz + 0.9),
                            ([1, 0, 0], [0, -1, 0], [0, 0, -1]), METAL, material="steel",
                            settings={"default_angle": 0.0, "positive_angle": 35.0, "negative_angle": -35.0,
                                      "speed": 60.0, "easing": 400.0, "max_torque": 200000.0,
                                      "when_idle": "Return to default angle"})
        strut_bottom += 1.5
    b.box((cx - 0.4, cx + 0.4, strut_bottom, top, cz - 0.4, cz + 0.4), METAL, material="steel")
    inner = wheel_dx - wheel_w / 2
    b.box((cx - inner, cx + inner, axle_y - 0.6, axle_y + 0.6, cz - 0.5, cz + 0.5), METAL, material="steel")
    for o in (-wheel_dx, wheel_dx):
        x = cx + o
        b.add("wheel", (x - wheel_w / 2, x + wheel_w / 2, lift, lift + wheel_d, cz - wheel_d / 2, cz + wheel_d / 2),
              IDENT, "#151515", material="aluminum", settings={"free_spinning": True, "friction": 20.0})
    return p, steer_servo


for s in SIDES:
    gear_leg(X0 + s * GEAR_DX, GEAR_Z, 4.0, 1.5, 1.75, lift=MAIN_LIFT, travel=7.0)
_, NOSE_STEER = gear_leg(X0, NOSE_GEAR_Z, 3.0, 1.0, 1.5, steer=True, barrel_y=HUMP_TOP - 2.0)

# ---------------------------------------------------------------------------
# Cockpit hump over the nose: hollow, glazed at the front, the seat behind
# the hatch the ladder comes up through.
cx0, cx1 = X0 - CP_DX, X0 + CP_DX
for s in SIDES:
    b.box(side_box(s, CP_DX - 0.5, CP_DX, SLAB, HUMP_TOP, CP_Z0, 164.0), SKIN)
b.box((cx0, cx1, HUMP_TOP - 0.5, HUMP_TOP, CP_Z0, 164.0), SKIN, ptype="aero_panel")
b.box((cx0 + 0.5, cx1 - 0.5, BOX_TOP, HUMP_TOP - 0.5, CP_Z0, CP_Z0 + 0.5), SKIN)   # back wall, over the bay box
b.wedge((cx0, cx1, 14.0, HUMP_TOP, 164.0, CP_Z1), (0, 0, -1), (0, -1, 0), GLASS)
b.box((cx0, cx1, SLAB, 14.0, CP_Z1 - 0.5, CP_Z1), SKIN)                             # under the windscreen
SEAT = b.add("seat", (X0 - 1.5, X0 + 1.5, SLAB, SLAB + 3.0, 150.5, 153.5), ([-1, 0, 0], [0, 1, 0], [0, 0, -1]),
             METAL, settings={})
b.box((X0 - 3.0, X0 + 3.0, SLAB, SLAB + 3.0, 158.0, 159.0), DARK)    # instrument panel
# Ladder: up through the hatch from the ground, folded away in flight.
LADDER = b.add("ladder", (X0 - 2.0, X0 + 2.0, 1.0, SLAB + 0.5, HATCH[2], HATCH[2] + 0.25), IDENT, METAL)

# ---------------------------------------------------------------------------
# Missiles: two under each wing on reload gates, flying straight ahead.
MISSILES = []


def missile(cx, z):
    d = 1.2
    rail = MID_BOT - 0.25              # the gate's rail: the missile's top
    y0, y1 = rail - d, rail
    yc = (y0 + y1) / 2
    rocket = b.add("solid_rocket", (cx - d / 2, cx + d / 2, y0, y1, z, z + 7.0),
                   ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), WHITE, material="aluminum",
                   settings={"thrust": 85000.0, "burn_time": 6.0, "ideal": False})
    b.along("cylinder", (cx - d / 2, cx + d / 2, y0, y1, z + 7.0, z + 12.0), (0, 0, 1), WHITE, material="aluminum")
    det = b.add("impact_detector", (cx - 0.45, cx + 0.45, yc - 0.45, yc + 0.45, z + 12.0, z + 12.9),
                IDENT, RED, material="aluminum", settings={"threshold": 40.0, "pulse": 0.2})
    b.along("cylinder", (cx - d / 2, cx + d / 2, y0, y1, z + 12.0, z + 13.4), (0, 0, 1), RED, material="aluminum")
    exp = b.add("explosive_block", (cx - d / 2, cx + d / 2, y0, y1, z + 13.4, z + 16.0), IDENT, WHITE,
                material="aluminum", settings={"blast_radius": MISSILE_RADIUS})
    b.along("cone", (cx - d / 2, cx + d / 2, y0, y1, z + 16.0, z + 19.0), (0, 0, 1), WHITE, material="aluminum")
    for (zf, span, chord) in [(z, 0.7, 2.2), (z + 13.6, 0.5, 1.5)]:
        for (ux, uy) in [(1, 0), (-1, 0), (0, -1)]:
            if ux:
                xa = cx + ux * d / 2
                fb = (min(xa, xa + ux * span), max(xa, xa + ux * span), yc - 0.05, yc + 0.05, zf, zf + chord)
            else:
                ya = yc + uy * d / 2
                fb = (cx - 0.05, cx + 0.05, min(ya, ya + uy * span), max(ya, ya + uy * span), zf, zf + chord)
            b.tri_panel(fb, (ux, uy, 0), (0, 0, 1), WHITE, material="aluminum")
    rack = b.add("reload_gate", (cx - 0.3, cx + 0.3, rail, MID_BOT, z + 5.0, z + 13.0),
                 ([1, 0, 0], [0, -1, 0], [0, 0, -1]), METAL, material="aluminum",
                 settings={"reload_time": MISSILE_RELOAD, "reloads": 0.0, "safe_time": 0.5})
    MISSILES.append((rack, rocket, det, exp))


for s in SIDES:
    missile(X0 + s * 43.0, 102.0)
    missile(X0 + s * 51.0, 97.0)

# ---------------------------------------------------------------------------
# Sensors: in the cockpit, and the height finder far out under the left
# wing, where nothing the plane drops falls past it.
ATT = b.add("attitude_sensor", (X0 + 3.5, X0 + 4.5, SLAB, SLAB + 1.0, 155.0, 156.0),
            ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), DARK)
# (Facing forward, as the attitude sensor: its sideways speed is the slip.)
SPEED = b.add("speed_sensor", (X0 - 4.5, X0 - 3.5, SLAB, SLAB + 1.0, 155.0, 156.0),
              ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), DARK)
DIST = b.add("distance_sensor", side_box(1, 70.0, 71.0, OUT_BOT - 0.5, OUT_BOT, 110.0, 111.0),
             ([1, 0, 0], [0, 0, -1], [0, 1, 0]), DARK, settings={"range": 3000.0})
BEACON = b.add("light_panel", (X0 - 0.5, X0 + 0.5, HUMP_TOP, HUMP_TOP + 0.125, 152.0, 153.0), IDENT, "#ff1010",
               settings={"color": "#ff1010", "brightness": 3.0})

# ---------------------------------------------------------------------------
# Controls. Each reads the controller and its keyboard twin together.
pad_pitch = pad("Left stick Y (up +)", curve=1.6, deadzone=0.1)
key_pitch = key("W", second="S")
pitch_in = gate("Add", V(pad_pitch), V(key_pitch))
pad_roll = pad("Left stick X (right +)", curve=1.6, deadzone=0.1)
key_roll = key("D", second="A")
roll_in = gate("Add", V(pad_roll), V(key_roll))
key_yaw = key("X", second="Z")          # every button is a bomb: yaw is on the keyboard
yaw_in = gate("Add", V(key_yaw))

# Throttle: the right trigger, M for cruise, K for full power.
pad_rt = pad("RT / R2 trigger", deadzone=0.05)
key_k = key("K")
key_m = key("M", mode="Toggle")
cruise = gate("Multiply", V(key_m), value=0.55)
t1 = gate("Max", V(pad_rt), R(cruise))
throttle = gate("Max", R(t1), V(key_k))
engines_on = gate("Compare", R(throttle), value=0.02)

# Gain schedule: the faster it goes, the less surface a turn rate takes:
# 100 m/s over the speed (up to 1.3), and past 250 m/s, 25000 over the
# speed squared. Below 25 m/s the sticks move the surfaces straight, and the
# stability system takes over by 55 m/s.
v2 = gate("Multiply", (SPEED, "speed"), (SPEED, "speed"))
v_sched = gate("Max", (SPEED, "speed"), value=77.0)
k_const = gate("Constant", value=100.0)
sched_slow = gate("Divide", R(k_const), R(v_sched))
v2_sched = gate("Max", R(v2), value=1.0)
k2_const = gate("Constant", value=25000.0)
sched_fast = gate("Divide", R(k2_const), R(v2_sched))
sched = gate("Min", R(sched_slow), R(sched_fast))
v_over = gate("Subtract", (SPEED, "speed"), value=25.0)
v_share = gate("Multiply", R(v_over), value=1.0 / 30.0)
v_fade = gate("Clamp", R(v_share), value=1.0)
# On the ground, too, the sticks move the surfaces straight (rotating for
# takeoff, say), and nothing winds up; in the air by 10 m, it's all the
# stability system's.
h_over = gate("Subtract", (DIST, "distance"), value=4.0)
h_share = gate("Multiply", R(h_over), value=1.0 / 6.0)
h_fade = gate("Clamp", R(h_share), value=1.0)
fade = gate("Min", R(v_fade), R(h_fade))
one = gate("Constant", value=1.0)
unfade = gate("Subtract", R(one), R(fade))


def stability_axis(stick, rate_per_unit, measured, pid_settings, direct_gain, extra=None):
    """Rate command, attitude hold for one axis; the stick moves the
    surfaces straight at low speed. `extra` adds to the rate asked for.
    Returns the command in degrees."""
    if isinstance(rate_per_unit, int):
        cmd = gate("Multiply", R(stick), R(rate_per_unit))
    else:
        cmd = gate("Multiply", R(stick), value=rate_per_unit)
    if extra is not None:
        cmd = gate("Add", R(cmd), R(extra))
    err = gate("Subtract", R(cmd), measured)
    err_f = gate("Multiply", R(err), R(fade))
    setpoint = gate("Add", measured, R(err_f))
    pid = logic("pid_controller", pid_settings, {"setpoint": R(setpoint), "measurement": measured})
    flying = gate("Multiply", O(pid), R(sched))
    direct = gate("Multiply", R(stick), value=direct_gain)
    direct_f = gate("Multiply", R(direct), R(unfade))
    return gate("Add", R(flying), R(direct_f))


# A big, heavy wing: gentle rates. Pitch: up to 10 degrees a second, and no
# more than about 2.5 g. Roll: 45 degrees a second (less when fast). Yaw: a
# few degrees a second, and the drag rudders damp any wagging.
v_floor = gate("Max", (SPEED, "speed"), value=60.0)
g_cap = gate("Constant", value=1.5 * 9.81 * 57.2958)     # 1.5 g on top of the 1 g of level flight
g_rate = gate("Divide", R(g_cap), R(v_floor))
pitch_rate = gate("Min", R(g_rate), value=10.0)
# In a level turn the nose has to come round as well as across: banked, the
# pitch rate a turn takes (the yaw rate times the tangent of the bank) is
# added to what the stick asks, so let go in a bank it holds its height.
# (No tangent gate: x(1 + x^2/3), within 5% to 45 degrees, and no more than
# 60 degrees' worth.)
bank = gate("Multiply", (ATT, "roll"), value=1.0 / 57.2958)
bank_sq = gate("Multiply", R(bank), R(bank))
bank_f = gate("Multiply", R(bank_sq), value=1.0 / 3.0)
bank_f1 = gate("Add", R(bank_f), value=1.0)
bank_tan = gate("Multiply", R(bank), R(bank_f1))
bank_tan = sym_clamp(bank_tan, 1.73)
turn_pitch = gate("Multiply", R(bank_tan), (ATT, "yaw_rate"))
P_ = stability_axis(pitch_in, pitch_rate, (ATT, "pitch_rate"),
                    {"kp": PITCH_KP, "ki": PITCH_KI, "kd": 0.0, "output_min": -30.0, "output_max": 30.0}, 35.0,
                    extra=turn_pitch)
roll_cap = gate("Constant", value=12000.0)
roll_fast = gate("Divide", R(roll_cap), R(v_floor))
roll_rate = gate("Min", R(roll_fast), value=45.0)
R_ = stability_axis(roll_in, roll_rate, (ATT, "roll_rate"),
                    {"kp": 2.0, "ki": ROLL_KI, "kd": 0.0, "output_min": -60.0, "output_max": 60.0}, 30.0)
side_cap = gate("Constant", value=1.5 * 9.81 * 57.2958)
side_rate = gate("Divide", R(side_cap), R(v_floor))
yaw_rate = gate("Min", R(side_rate), value=6.0)
# A flying wing has no fin to swing its nose into the airflow, so the
# stability system does it: the sideslip (sideways over forward speed, in
# degrees) asks for a turn toward it, SLIP_GAIN degrees a second for each
# degree. That also coordinates turns: banked, the plane slips toward the low
# wing, and the nose follows. Yaw itself is mostly differential thrust (see
# the engines), with the drag rudders helping.
fwd_floor = gate("Max", (SPEED, "forward"), value=30.0)
slip = gate("Divide", (SPEED, "sideways"), R(fwd_floor))
slip_deg = gate("Multiply", R(slip), value=57.2958 * SLIP_GAIN)
slip_cmd = sym_clamp(slip_deg, 12.0)
Y_ = stability_axis(yaw_in, yaw_rate, (ATT, "yaw_rate"),
                    {"kp": YAW_KP, "ki": YAW_KI, "kd": 0.0, "output_min": -40.0, "output_max": 40.0}, 30.0,
                    extra=slip_cmd)

# Air brake: Q opens both outer surfaces both ways (less when fast).
key_brake = key("Q")
brake_full = gate("Multiply", V(key_brake), value=50.0)
brake_v2 = gate("Max", R(v2), value=22500.0)
brake_k = gate("Constant", value=22500.0)
brake_share = gate("Divide", R(brake_k), R(brake_v2))
brake = gate("Multiply", R(brake_full), R(brake_share))
# Steering by drag: the yaw command opens the outer surface on the side to
# turn toward.
yaw_right = gate("Max", R(Y_), value=0.0)
neg_y = gate("Multiply", R(Y_), value=-1.0)
yaw_left = gate("Max", R(neg_y), value=0.0)
drag = {-1: gate("Add", R(yaw_right), R(brake)), 1: gate("Add", R(yaw_left), R(brake))}

# Mixing. A positive deflection lifts the trailing edge (the top panel
# opens); a negative one drops it. Stick back lifts every trailing edge;
# stick right lifts the right side and drops the left.
r07 = gate("Multiply", R(R_), value=INNER_ROLL)
deflection = {
    # (The surfaces' travel is shared: pitch first, roll on top, so a full
    # roll still rolls while the stability system is trimming.)
    (-1, "inner"): gate("Add", R(P_), R(r07)),
    (1, "inner"): gate("Subtract", R(P_), R(r07)),
    (-1, "outer"): gate("Add", R(P_), R(R_)),
    (1, "outer"): gate("Subtract", R(P_), R(R_)),
}
for (s, name), dsrc in deflection.items():
    neg_d = gate("Multiply", R(dsrc), value=-1.0)
    up_only = gate("Max", R(dsrc), value=0.0)
    down_only = gate("Max", R(neg_d), value=0.0)
    if name == "outer":
        up_only = gate("Add", R(up_only), R(drag[s]))
        down_only = gate("Add", R(down_only), R(drag[s]))
    top_g = gate("Multiply", R(up_only), value=-1.0)       # positive turns both leaves inward
    bottom_g = gate("Multiply", R(down_only), value=-1.0)
    b.link(SURFACES[(s, name, "top")], "angle", top_g, "result")
    b.link(SURFACES[(s, name, "bottom")], "angle", bottom_g, "result")
# Nose wheel: steered by the roll stick and the yaw keys.
steer_in = gate("Add", R(roll_in), R(yaw_in))
# Full steering up to 15 m/s, none by 40: fast on the runway, a nose wheel
# turned would swing the plane round.
v_left = gate("Subtract", (SPEED, "speed"), value=40.0)
v_left_neg = gate("Multiply", R(v_left), value=-1.0 / 25.0)
steer_share = gate("Clamp", R(v_left_neg), value=1.0)
steer_scaled = gate("Multiply", R(steer_in), R(steer_share))
steer = gate("Multiply", R(steer_scaled), value=-30.0)
b.link(NOSE_STEER, "angle", steer, "result")
# Engines: each side's pair has its own throttle, for yaw. A turn to the
# right opens the left pair up and the right pair down, by up to half the
# throttle's travel (the yaw command's 40 degrees), within 0 and full.
diff = gate("Multiply", R(Y_), value=DIFF_THRUST / 40.0)
for s in SIDES:
    side_thr = gate("Add" if s > 0 else "Subtract", R(throttle), R(diff))
    side_thr = gate("Clamp", R(side_thr), value=1.0)
    side_on = gate("Compare", R(side_thr), value=0.02)
    for t in THRUSTERS[s]:
        b.link(t, "throttle", side_thr, "result")
        b.link(t, "on", side_on, "is_true")
# Thrust vectoring: the engines swivel with the stability system's pitch
# command (all four the same way) and roll command (each side opposite),
# within 20 degrees.
# A positive angle pushes the tail down: nose up.
# (Flying only: on the runway the sticks move the elevons straight, and
# swivelled engines on top of them snatch the nose up on rotation, far
# enough to drag the missiles on the runway.)
vec_pf = gate("Multiply", R(P_), R(fade))
vec_p = gate("Multiply", R(vec_pf), value=VEC_PITCH)
vec_rf = gate("Multiply", R(R_), R(fade))
vec_r = gate("Multiply", R(vec_rf), value=VEC_ROLL)
for s in SIDES:
    # Rolling right lifts the left side: its engines swing to push up.
    side_vec = gate("Subtract" if s > 0 else "Add", R(vec_p), R(vec_r))
    side_vec = sym_clamp(side_vec, VECTOR_MAX)
    for v in VECTOR_SERVOS[s]:
        b.link(v, "angle", side_vec, "result")
# Their glow.
glow_r = gate("Multiply", R(throttle), value=255.0)
glow_g = gate("Multiply", R(throttle), value=110.0)
for l in EXHAUST:
    b.link(l, "on", engines_on, "is_true")
    b.link(l, "red", glow_r, "result")
    b.link(l, "green", glow_g, "result")
beacon = logic("pwm_generator", {"frequency": 1.0, "duty": 12.0})
b.link(BEACON, "on", beacon, "output")

# Height above the ground, from the sensor under the left wing.
def above(metres):
    return gate("Compare", (DIST, "distance"), value=metres)


# Landing gear: up by itself once GEAR_UP_AT m above the ground, down again
# below GEAR_DOWN_AT.
high = above(GEAR_UP_AT)
low_limit = above(GEAR_DOWN_AT)
coming_down = bgate("NOT", T(low_limit))
gear_up = bgate("Latch", T(high), (coming_down, "result"))
for p in GEAR_PISTONS:
    b.link(p, "extend", gear_up, "result")
# The ladder folds away while the engines run or the gear is up.
ladder_away = bgate("OR", T(engines_on), (gear_up, "result"))
b.link(LADDER, "stowed", ladder_away, "result")

# ---------------------------------------------------------------------------
# Weapons. Every button on the controller drops bombs (and a number key on
# the keyboard), each its own part of the array; hold it and those bays
# keep dropping as fast as they reload. Bombs drop only high enough that
# their blast can't reach the plane.
small_ok = above(SMALL_FLOOR)
big_ok = above(BIG_FLOOR)
missile_ok = above(MISSILE_FLOOR)


def button(control, k, ok):
    either = bgate("OR", P(pad(control)), P(key(k)))
    return bgate("AND", (either, "result"), T(ok))


ALL = button("A / Cross", "1", small_ok)              # every small bay: the carpet
BIG_GO = button("Y / Triangle", "2", big_ok)         # the 500 m bomb
ROW_MID = button("X / Square", "3", small_ok)        # middle row
CENTRE = button("B / Circle", "4", small_ok)         # the three middle columns
HALF = {1: button("LB / L1", "5", small_ok), -1: button("RB / R1", "6", small_ok)}
ROW_FRONT = button("D-pad up", "7", small_ok)
ROW_REAR = button("D-pad down", "8", small_ok)
OUTER = {1: button("D-pad left", "9", small_ok), -1: button("D-pad right", "0", small_ok)}
ROW_BUTTON = {0: ROW_REAR, 1: ROW_MID, 2: ROW_FRONT}
row_sig = {r: bgate("OR", (ALL, "result"), (ROW_BUTTON[r], "result")) for r in range(3)}
_class = {}


def bay_signal(r, c):
    side = 1 if c > 0 else -1 if c < 0 else 0
    kind = "outer" if abs(c) >= 6 else "centre" if abs(c) <= 1 else "plain"
    k_ = (r, side, kind)
    if k_ in _class:
        return _class[k_]
    base = row_sig[r] if side == 0 else bgate("OR", (row_sig[r], "result"), (HALF[side], "result"))
    if kind == "outer":
        sig = bgate("OR", (base, "result"), (OUTER[side], "result"))
    elif kind == "centre":
        sig = bgate("OR", (base, "result"), (CENTRE, "result"))
    else:
        sig = base
    _class[k_] = sig
    return sig


for (rack, exp, det, r_i, c) in BAYS:
    b.link(rack, "release", bay_signal(r_i, c), "result")
    b.link(exp, "detonate", det, "triggered")
b.link(BIG[0], "release", BIG_GO, "result")
b.link(BIG[1], "detonate", BIG[2], "triggered")

# Missiles: the left trigger (or R). Held, every loaded rail fires, and
# fires again as soon as it reloads.
fire = button("LT / L2 trigger", "R", missile_ok)
for (rack, rocket, det, exp) in MISSILES:
    b.link(rack, "release", fire, "result")
    b.link(rocket, "ignite", fire, "result")
    b.link(exp, "detonate", det, "triggered")

b.write(OUT)

# Names of the parts the tests look at, by index in the file.
names = {"seat": SEAT, "att": ATT, "speed": SPEED, "dist": DIST, "ladder": LADDER, "steer": NOSE_STEER,
         "big_rack": BIG[0], "big_bomb": BIG[1], "tip_L": TIPS[1], "tip_R": TIPS[-1]}
for (s_, name, half), idx in SURFACES.items():
    names["%s_%s_%s" % (name, "L" if s_ > 0 else "R", half)] = idx
for i, p_ in enumerate(GEAR_PISTONS):
    names["gear_%d" % i] = p_
for i, t_ in enumerate(THRUSTERS[1] + THRUSTERS[-1]):
    names["thrust_%d" % i] = t_
for i, v_ in enumerate(VECTOR_SERVOS[1] + VECTOR_SERVOS[-1]):
    names["vector_%d" % i] = v_
for i, (rack, exp, det, r_i, c) in enumerate(BAYS):
    names["bay_%d_%d" % (r_i, c)] = rack
for i, (rack, rocket, det, exp) in enumerate(MISSILES):
    names["rail_%d" % i] = rack
    names["missile_%d" % i] = rocket
with open(OUT + ".names.json", "w") as f:
    json.dump(names, f)

# ---------------------------------------------------------------------------
# A rough weigh-in (overlaps counted twice), for tuning: the weight, where
# its centre is, and where the wing's lift centres.
DENSITY = {"kevlar": 1440.0, "balsa": 150.0, "aluminum": 2700.0, "steel": 7850.0, "fiberglass": 1900.0, "plastic": 1050.0,
           "glass": 2500.0, "tungsten": 19250.0}
FILL = {"wedge": 0.5, "corner_wedge": 1 / 6, "cylinder": 0.785, "cone": 0.262, "aero_panel_triangle": 0.5,
        "servo": 0.5, "door_hinge_servo": 0.5, "piston": 0.5, "wheel": 0.5, "light_panel": 0.5,
        "impact_detector": 0.4, "explosive_block": 0.8, "reload_gate": 0.8, "ladder": 0.3, "seat": 0.4,
        "attitude_sensor": 0.3, "speed_sensor": 0.3, "distance_sensor": 0.3}
LOGIC = {"gamepad_input", "input_block", "number_gate", "boolean_gate", "pid_controller", "pwm_generator"}
mass = 0.0
mz = 0.0
bombs = 0.0
area = 0.0
az = 0.0
payload = set()
for (rack, exp, det, r_i, c) in BAYS + [(BIG[0], BIG[1], BIG[2], 0, 0)]:
    payload.update([exp, det])
for i, p_ in enumerate(b.parts):
    if p_["type"] in LOGIC:
        continue
    sx, sy, sz = p_["size"]
    vol = sx * sy * sz / 64.0 * FILL.get(p_["type"], 1.0)
    m = vol * DENSITY[p_["material"]]
    mass += m
    mz += m * p_["pos"][2]
    if p_["material"] in ("fiberglass",) or (p_["material"] == "steel" and p_["type"] == "cone" and p_["color"] == BOMB_NOSE):
        bombs += m
    if p_["type"].startswith("aero_panel") and abs(p_["y_axis"][1]) > 0.5:
        a = sx * sz / 16.0 * (0.5 if "triangle" in p_["type"] else 1.0)
        z = p_["pos"][2]
        if "triangle" in p_["type"]:
            # The centroid is a third of the way along each leg from the right angle.
            z += p_["z_axis"][2] * sz / 6.0 * -1.0
        area += a
        az += a * z
print("parts %d logic %d | ~%.0f t (bombs ~%.0f t) | centre of mass z %.1f, of lift z %.1f, area %.0f m2" % (
    len(b.parts), _logic_slot[0], mass / 1000.0, bombs / 1000.0, mz / mass, az / area, area))
