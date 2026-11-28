"""Writes the SR-71 build: a 1.5x scale Blackbird in black balsa.

    python3 tools/make_sr71.py <out.json> [thrust_newtons_per_engine] [afterburner_newtons]

The nose points along +Z, up is +Y, and the pilot's left is +X. One metre of
the real aeroplane is 6 cells here (1.5x scale, 0.25 m cells). Ground is y 0.

The shape follows the published drawings: 32.74 m long with the probe, 16.94 m
across, the chines running from the nose out into the wing, the nacelles 4 m
out with their spikes, a 52.6 degree leading edge, and fins 4.51 m at the root
and 2.39 m at the tip, canted 15 degrees in. Everything above the chine line
is smooth (half cones, tapered half cylinders, rounded wedges); everything
under it is a flat-bottomed pan with the wheel wells and the missile bays.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from build_kit import Build, X0, side_box, holes_cut, IDENT, cross  # noqa: E402

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
OUT = ARGS[0] if len(ARGS) > 0 else "/tmp/sr71.json"
THRUST = float(ARGS[1]) if len(ARGS) > 1 else 700000.0          # each engine, right trigger
AFTERBURNER = float(ARGS[2]) if len(ARGS) > 2 else 9000000.0    # each engine, left trigger on top

BLAST = 40.0               # m, each missile's blast
MISSILE_RELOAD = 3.0       # s
MISSILE_SAFE = 1.5         # s after leaving the rail before a warhead is armed
MISSILE_FLOOR = 20.0       # m above the ground: the bay doors would hit it lower down
GEAR_UP_AT = 50.0          # m above the ground: the gear goes up by itself
GEAR_DOWN_AT = 35.0        # and comes down by itself below this
REVERSE = 0.025            # reverse thrust on the ground, a share of full
VECTOR_MAX = 8.0           # degrees each way the nozzles swivel
VEC_PITCH = 0.5            # nozzle swivel per degree of pitch command
VEC_ROLL = 0.3             # and of roll command, each side opposite
SLIP_GAIN = 2.0            # degrees a second of turn into the airflow per degree of slip
DIFF_THRUST = 0.35         # the most each side's throttle moves for yaw
TOP_SPEED = 750.0          # m/s, the game's limit: the afterburners ease off just short of it

BLACK = "#121317"          # the Blackbird's blue-black
DARK = "#1b1c21"
GREY = "#3b3d44"
GLASS = "#0f1824"
ENGINE = "#0b0b0d"
METAL = "#55585f"
WHITE = "#e9e9e6"
RED = "#a1111b"

b = Build("SR-71 Blackbird")
SIDES = (1, -1)          # +1 the pilot's left (+X), -1 the right (-X)

# Heights (y) and stations (z), in cells.
YC = 14.0                # the chine line: the wing, the body's axis, the nacelles' axis
PAN_Y = 10.0             # the flat underside
NOSE = 226.0             # nose tip (the probe goes on to 235)
CORE_R = 5.0             # the fuselage's radius
CORE_NOSE = 172.0        # where the nose cone reaches the fuselage's full size
TAIL = 39.0              # the tail cone's point
CHINE_Z = 178.0          # the chines' cone meets their taper here
INLET = 135.4            # the inlet lips
LENS_W, LENS_H = 18.5, 4.0   # the body between the nacelles: half-width and height over the chine line
BODY_END = 85.0          # where it starts sloping down to the trailing edge
TE_BODY = 55.0
NAC_DX, NAC_R = 24.0, 5.5
NAC_END = 52.0           # the nacelles' tail, where the swivelling nozzles start
SPIKE_TIP = 149.2


def r1(v):
    return round(v * 200.0) / 200.0


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
    """Clamps a signal to within +-limit (the Clamp gate only goes 0 to value)."""
    hi = gate("Min", R(src), value=limit)
    return gate("Max", R(hi), value=-limit)


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


# ---------------------------------------------------------------------------
# Shape helpers.
def half(ptype, box, along, up, color, **kw):
    """A half cylinder, half cone or tapered half cylinder: its length runs
    along `along` (toward the point or the narrow end), its round side looks
    along `up` and its flat face the other way."""
    z = list(along)
    y = list(up)
    x = cross(y, z)
    return b.add(ptype, box, (x, y, z), color, **kw)


def rounded(box, thin, up, color, ptype="rounded_wedge", **kw):
    """A rounded (or curved) wedge: its thin edge toward `thin`, its curved
    top looking along `up`."""
    x = list(thin)
    y = list(up)
    z = cross(x, y)
    return b.add(ptype, box, (x, y, z), color, **kw)


def quarter(box, out1, out2, color, **kw):
    """A convex curve (a quarter round, extruded) bulging along out1 and out2."""
    x = list(out1)
    y = list(out2)
    z = cross(x, y)
    return b.add("convex_curve", box, (x, y, z), color, **kw)


# ---------------------------------------------------------------------------
# The fuselage above the chine line: a long cone to its full size behind the
# cockpit, and a cone to a point at the tail.
UP, DOWN, FWD, AFT = (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)
half("half_cone", (X0 - CORE_R, X0 + CORE_R, YC, YC + CORE_R, CORE_NOSE, NOSE), FWD, UP, BLACK)
half("half_cylinder", (X0 - CORE_R, X0 + CORE_R, YC, YC + CORE_R, 108.0, CORE_NOSE), FWD, UP, BLACK)
half("half_cylinder", (X0 - CORE_R, X0 + CORE_R, YC, YC + CORE_R, BODY_END, 108.0), FWD, UP, BLACK)
half("half_cone", (X0 - CORE_R, X0 + CORE_R, YC, YC + CORE_R, TAIL, BODY_END), AFT, UP, BLACK)
# Under the chine line at the nose: a flatter cone, down to the flat underside.
half("half_cone", (X0 - 5.5, X0 + 5.5, PAN_Y, YC, CHINE_Z, NOSE), FWD, DOWN, BLACK)
# The pitot probe, from inside the nose tip.
b.along("cylinder", (X0 - 0.35, X0 + 0.35, YC - 0.35, YC + 0.35, 220.0, 233.5), FWD, BLACK)
b.along("cone", (X0 - 0.35, X0 + 0.35, YC - 0.35, YC + 0.35, 233.5, 235.0), FWD, BLACK)

# The chines: a flat cone from the nose to behind the cockpit, then a taper
# doubling its width and height out to the nacelles at the inlets. Behind
# the inlets the body between the nacelles keeps that section, then curves
# down to a thin trailing edge.
half("half_cone", (X0 - LENS_W / 2, X0 + LENS_W / 2, YC, YC + LENS_H / 2, CHINE_Z, NOSE), FWD, UP, BLACK)
half("half_frustum", (X0 - LENS_W, X0 + LENS_W, YC, YC + LENS_H, INLET, CHINE_Z), FWD, UP, BLACK)
half("half_cylinder", (X0 - LENS_W, X0 + LENS_W, YC, YC + LENS_H, BODY_END, INLET), FWD, UP, BLACK)
rounded((X0 - LENS_W, X0 + LENS_W, YC, YC + LENS_H, TE_BODY, BODY_END), AFT, UP, BLACK)

# ---------------------------------------------------------------------------
# The pan under the chine line. Under the forebody it is narrow, rounded at
# its edges, with the nose wheel well in the middle; behind the inlets it
# spans the nacelles, hollow, with the missile bays and the main wheel wells.
FORE_KEEL, FORE_PAN = 2.0, 5.5
NOSE_WELL = (168.5, 173.5)          # z of the nose wheel well
AFT_PAN0, AFT_PAN1 = 62.0, 132.0    # z of the wide pan
AFT_BOX = 15.0                      # its flat bottom's half-width; rounded out to LENS_W
SKIN = 0.5
for (z0, z1) in [(AFT_PAN1, NOSE_WELL[0]), (NOSE_WELL[1], CHINE_Z)]:
    b.box((X0 - FORE_KEEL, X0 + FORE_KEEL, PAN_Y, YC, z0, z1), BLACK)
for s in SIDES:
    quarter(side_box(s, FORE_KEEL, FORE_PAN, PAN_Y, YC, AFT_PAN1, CHINE_Z), (s, 0, 0), DOWN, BLACK)

# The wide pan: a bottom skin with the openings cut, rounded edges, ribs.
BAY_Z = (104.0, 130.0)              # missile bays
BAY_DX = (1.0, 8.5)                 # each side's bay, out from the centreline
MAIN_Z = 108.0                      # main wheels' axle, just behind the centre of mass
MAIN_SLOT = (11.0, 13.8, 106.0, 121.5)  # dx0, dx1, z0, z1 of each main wheel well's opening
holes = []
for s in SIDES:
    a, c = sorted((X0 + s * BAY_DX[0], X0 + s * BAY_DX[1]))
    holes.append((a, c, BAY_Z[0], BAY_Z[1]))
    a, c = sorted((X0 + s * MAIN_SLOT[0], X0 + s * MAIN_SLOT[1]))
    holes.append((a, c, MAIN_SLOT[2], MAIN_SLOT[3]))
for (x0, x1, z0, z1) in holes_cut((X0 - AFT_BOX, X0 + AFT_BOX, AFT_PAN0, AFT_PAN1), holes):
    b.box((x0, x1, PAN_Y, PAN_Y + SKIN, z0, z1), BLACK)
for s in SIDES:
    quarter(side_box(s, AFT_BOX, LENS_W, PAN_Y, YC, AFT_PAN0, AFT_PAN1), (s, 0, 0), DOWN, BLACK)
    # Ribs inside: each bay's outer wall, the full length of the pan.
    b.box(side_box(s, BAY_DX[1], BAY_DX[1] + 0.5, PAN_Y + SKIN, YC, AFT_PAN0, AFT_PAN1), DARK)
# The keel between the bays, and the bays' ends.
b.box((X0 - BAY_DX[0], X0 + BAY_DX[0], PAN_Y + SKIN, YC, AFT_PAN0, AFT_PAN1), DARK)
for s in SIDES:
    b.box(side_box(s, BAY_DX[0], BAY_DX[1], PAN_Y + SKIN, YC, BAY_Z[0] - 0.5, BAY_Z[0]), DARK)
    b.box(side_box(s, BAY_DX[0], BAY_DX[1], PAN_Y + SKIN, YC, BAY_Z[1], BAY_Z[1] + 0.5), DARK)
# Front and back walls of the pan.
b.box((X0 - AFT_BOX, X0 + AFT_BOX, PAN_Y + SKIN, YC, AFT_PAN1 - 0.5, AFT_PAN1), BLACK)
b.box((X0 - AFT_BOX, X0 + AFT_BOX, PAN_Y + SKIN, YC, AFT_PAN0, AFT_PAN0 + 0.5), BLACK)
# The wide pan's front, faired back up into the chines.
for s in SIDES:
    b.wedge(side_box(s, FORE_PAN, AFT_BOX, PAN_Y, YC, AFT_PAN1, AFT_PAN1 + 8.0), AFT, UP, BLACK)
    b.corner(side_box(s, AFT_BOX, LENS_W, PAN_Y, YC, AFT_PAN1, AFT_PAN1 + 8.0), AFT, UP, (-s, 0, 0), BLACK)
# And its back, curving up to the trailing edge.
rounded((X0 - AFT_BOX, X0 + AFT_BOX, PAN_Y, YC, TE_BODY + 1.0, AFT_PAN0), AFT, DOWN, BLACK, ptype="curved_wedge")
for s in SIDES:
    b.corner(side_box(s, AFT_BOX, LENS_W, PAN_Y, YC, AFT_PAN0 - 7.0, AFT_PAN0), FWD, UP, (-s, 0, 0), BLACK)

# ---------------------------------------------------------------------------
# Cockpits: the pilot's under a glazed canopy, the systems officer's under a
# hatch behind, and a fairing tapering back into the spine.
CAN_W, CAN_Y0, CAN_TOP = 2.6, 15.0, 21.0
rounded((X0 - CAN_W, X0 + CAN_W, CAN_Y0, CAN_TOP, 188.0, 196.0), FWD, UP, GLASS)
half("half_cylinder", (X0 - CAN_W, X0 + CAN_W, CAN_Y0, CAN_TOP, 180.0, 188.0), FWD, UP, GLASS)
half("half_cylinder", (X0 - CAN_W, X0 + CAN_W, CAN_Y0, CAN_TOP, 172.0, 180.0), FWD, UP, BLACK)
half("half_cylinder", (X0 - CAN_W - 0.06, X0 + CAN_W + 0.06, CAN_Y0, CAN_TOP + 0.06, 179.7, 180.3), FWD, UP, DARK)
rounded((X0 - CAN_W, X0 + CAN_W, CAN_Y0, CAN_TOP, 150.0, 172.0), AFT, UP, BLACK)
# The systems officer's two small side windows.
for s in SIDES:
    b.box(side_box(s, 2.1, 2.16, 18.2, 19.2, 175.0, 178.0), GLASS)
SEAT = b.add("seat", (X0 - 1.5, X0 + 1.5, 14.0, 17.0, 184.5, 187.5), ([-1, 0, 0], [0, 1, 0], [0, 0, -1]),
             GREY, settings={})
# The pilot's eyes: seated in first person, the view comes from here.
CAMERA = b.add("camera", (X0 - 0.25, X0 + 0.25, 18.25, 18.75, 186.75, 187.25), ([-1, 0, 0], [0, 1, 0], [0, 0, -1]),
               DARK, material="plastic", settings={"fov": 80.0})
b.link(CAMERA, "seat", SEAT, "occupied")

# Boarding ladder on the left by the cockpit, just outside the chine, on two
# brackets under it. It folds away once the engines run or the gear is up.
LADDER = b.add("ladder", side_box(1, 8.0, 8.25, 1.0, 15.5, 184.5, 187.5), ([0, 0, -1], [0, 1, 0], [1, 0, 0]), METAL)
b.box(side_box(1, 4.0, 8.0, 12.0, YC, 185.5, 186.5), BLACK)

# ---------------------------------------------------------------------------
# Nacelles: round, from the inlet lips to the swivelling nozzles, with the
# spike cones standing out of the inlets.
NOZZLES, THRUSTERS, BURNERS, LIGHTS_RING, LIGHTS_CORE = [], [], [], [], []
THRUSTERS_BY_SIDE = {1: [], -1: []}
for s in SIDES:
    cx = X0 + s * NAC_DX
    ny0, ny1 = YC - NAC_R, YC + NAC_R
    # Hollow: a tube from the inlet lip to the tail, closed at the back and
    # behind the inlet. (Solid, the two would weigh 35 t.)
    b.along("pipe", (cx - NAC_R, cx + NAC_R, ny0, ny1, INLET - 64.0, INLET), FWD, BLACK)
    b.along("pipe", (cx - NAC_R, cx + NAC_R, ny0, ny1, NAC_END, INLET - 64.0), FWD, BLACK)
    b.along("cylinder", (cx - 4.6, cx + 4.6, YC - 4.6, YC + 4.6, NAC_END, NAC_END + 1.0), FWD, BLACK)
    # The duct's dark back wall, and the spike on its shaft.
    b.along("cylinder", (cx - 4.6, cx + 4.6, YC - 4.6, YC + 4.6, INLET - 4.3, INLET - 4.0), FWD, ENGINE)
    b.along("cylinder", (cx - 3.0, cx + 3.0, YC - 3.0, YC + 3.0, INLET - 4.3, INLET), FWD, BLACK)
    b.along("cone", (cx - 3.0, cx + 3.0, YC - 3.0, YC + 3.0, INLET, SPIKE_TIP), FWD, BLACK)
    # The nacelle's own chine: a thin strake on its outer side, carrying the
    # wing's leading edge forward to the inlet.
    b.flat_tri(side_box(s, NAC_DX + NAC_R - 0.5, NAC_DX + NAC_R + 2.0, YC - 0.15, YC + 0.15, 113.2, INLET - 4.5),
               (s, 0, 0), FWD, BLACK)
    # A fixed fin hidden inside the nacelle, well aft, that turns the nose
    # into the airflow (the canted fins outside are for looks).
    b.add("aero_panel", (cx - 0.125, cx + 0.125, YC - 4.7, YC + 4.7, 54.0, 80.0),
          ([0, 1, 0], [1, 0, 0], [0, 0, -1]), BLACK)

# The swivelling nozzles: each turns on a servo on the nacelle's tail,
# carrying a round can with the engine's hidden thrusters and its glow.
NOZ_R = 5.2
NOZ_Z0, NOZ_Z1 = 41.0, 51.2
for s in SIDES:
    cx = X0 + s * NAC_DX
    # Mount on the nacelle's tail, touching only the servo's base.
    b.box((cx - 1.5, cx + 0.7, YC - 1.5, YC + 1.5, 51.0, NAC_END), DARK)
    servo = b.add("servo", (cx - 1.5, cx + 1.5, YC - 1.5, YC + 1.5, 48.5, 51.0),
                  ([0, 0, 1], [1, 0, 0], [0, 1, 0]), DARK,
                  settings={"default_angle": 0.0, "positive_angle": VECTOR_MAX, "negative_angle": -VECTOR_MAX,
                            "speed": 60.0, "easing": 400.0, "max_torque": 8000000.0,
                            "when_idle": "Return to default angle"})
    NOZZLES.append(servo)
    # A broad hub on the servo's output face (+X), back to the turbine face
    # and out into the can.
    b.box((cx + 1.5, cx + 4.0, YC - 2.5, YC + 2.5, 47.5, 51.0), DARK)
    # The turbine face: a thick plug filling the can, so the can joins it
    # all round. The engine and the afterburner behind it are as wide as they
    # can be, so their push spreads over the plug. (All balsa: the can's
    # outline takes in everything inside it, and parts may only share space
    # in one material.)
    b.along("cylinder", (cx - 4.3, cx + 4.3, YC - 4.3, YC + 4.3, 46.0, 47.5), FWD, "#1a1110")
    b.along("pipe", (cx - NOZ_R, cx + NOZ_R, YC - NOZ_R, YC + NOZ_R, NOZ_Z0, NOZ_Z1), FWD, ENGINE)
    t = b.add("thruster", (cx - 3.0, cx + 3.0, YC - 3.0, YC + 3.0, 44.0, 46.0),
              ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), ENGINE,
              settings={"thrust": THRUST, "ideal": True})
    THRUSTERS.append(t)
    THRUSTERS_BY_SIDE[s].append(t)
    # The afterburner pushes on the nacelle itself, from inside its tail
    # (on the light swivelling can, at top speed the game's speed limit
    # would clip each tick's push to it, and hold the jet back).
    BURNERS.append(b.add("thruster", (cx - 3.0, cx + 3.0, YC - 3.0, YC + 3.0, NAC_END + 1.0, NAC_END + 2.0),
                         ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), ENGINE,
                         settings={"thrust": AFTERBURNER, "ideal": True}))
    b.box((cx - 3.0, cx + 3.0, YC - 3.0, YC + 3.0, 43.0, 44.0), ENGINE)    # the can's back plate
    # The back of the engine: a dark disc set into the can all round, with
    # the lights on it: a hot core and glowing quarters round it.
    b.along("cylinder", (cx - 4.3, cx + 4.3, YC - 4.3, YC + 4.3, 42.7, 43.0), FWD, ENGINE)
    LZ0, LZ1 = 42.58, 42.7
    LIGHTS_CORE.append(b.add("light_panel", (cx - 1.0, cx + 1.0, YC - 1.0, YC + 1.0, LZ0, LZ1),
                             ([1, 0, 0], [0, 0, -1], [0, 1, 0]), ENGINE,
                             settings={"color": "#ffd36a", "brightness": 5.0}))
    for (qx0, qx1, qy0, qy1) in [(-2.9, -1.0, -1.0, 1.0), (1.0, 2.9, -1.0, 1.0),
                                 (-1.0, 1.0, 1.0, 2.9), (-1.0, 1.0, -2.9, -1.0)]:
        LIGHTS_RING.append(b.add("light_panel", (cx + qx0, cx + qx1, YC + qy0, YC + qy1, LZ0, LZ1),
                                 ([1, 0, 0], [0, 0, -1], [0, 1, 0]), ENGINE,
                                 settings={"color": "#ff5a14", "brightness": 3.0}))
    for (fx, fy) in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
        xa, xb = sorted((cx + fx * 1.0, cx + fx * 2.6))
        ya, yb = sorted((YC + fy * 1.0, YC + fy * 2.6))
        LIGHTS_RING.append(b.add("light_panel", (xa, xb, ya, yb, LZ0, LZ1), ([1, 0, 0], [0, 0, -1], [0, 1, 0]),
                                 ENGINE, settings={"color": "#ff5a14", "brightness": 1.5}))

# ---------------------------------------------------------------------------
# Fins on the nacelles, canted 15 degrees in. Each is built in strips up its
# height; each strip a parallelogram in section (two thin wedges), so the fin
# is one flat slab leaning in, with a smooth swept leading edge in front.
FIN_CANT = math.radians(15.0)
FIN_SPAN = 12.6
FIN_TE, FIN_LE_ROOT, FIN_LE_TIP = 52.0, 79.0, 66.3
FIN_STRIPS = 16
FIN_BASE = YC + NAC_R                     # the nacelle's top
fin_y0 = FIN_BASE - 1.0                   # the first strip starts inside the nacelle
fin_y1 = FIN_BASE + FIN_SPAN * math.cos(FIN_CANT)
delta = (fin_y1 - fin_y0) / FIN_STRIPS
shift = delta * math.tan(FIN_CANT)        # each strip leans in this much: the fin's thickness


def fin_le(y):
    return FIN_LE_ROOT - (y - FIN_BASE) * (FIN_LE_ROOT - FIN_LE_TIP) / (fin_y1 - FIN_BASE)


FIN_TIPS = {}


def snap(v):
    """To a hundredth of a cell: a part's middle and size are stored to
    half that, so edges on this grid meet their neighbours' exactly (a gap
    of a millimetre and they wouldn't weld)."""
    return round(v * 100.0) / 100.0


for s in SIDES:
    for k in range(FIN_STRIPS):
        yb = snap(fin_y0 + k * delta)
        yt = snap(fin_y0 + (k + 1) * delta)
        cb = NAC_DX - (fin_y0 + k * delta - FIN_BASE) * math.tan(FIN_CANT)    # the fin's middle at the strip's bottom
        x_in, x_mid_in, x_mid, x_out = (snap(cb - 1.5 * shift), snap(cb - 0.5 * shift),
                                        snap(cb - 0.5 * shift), snap(cb + 0.5 * shift))
        le_top, le_bottom = snap(fin_le(yt)), snap(fin_le(yb))
        # The outer half: right angle at the bottom, legs out and up.
        b.flat_tri(side_box(s, x_mid, x_out, yb, yt, FIN_TE, le_top), (s, 0, 0), UP, BLACK)
        # The inner half: right angle at the top, legs in and down.
        b.flat_tri(side_box(s, x_in, x_mid_in, yb, yt, FIN_TE, le_top), (-s, 0, 0), DOWN, BLACK)
        # The swept leading edge ahead of them (as wide as most of the strip).
        b.flat_tri(side_box(s, snap(cb - 1.25 * shift), snap(cb + 0.25 * shift), yb, yt, le_top, le_bottom),
                   FWD, UP, BLACK)
    FIN_TIPS[s] = NAC_DX - (fin_y1 - FIN_BASE) * math.tan(FIN_CANT)

# ---------------------------------------------------------------------------
# Wings: thin, flat outer panels from the nacelles to the tips; elevons on
# their trailing edges and on the body's. Each elevon is split, a top and a
# bottom panel on door hinge servos, so they also open both ways as air
# brakes.
WY0, WY1 = YC - 0.3, YC + 0.3
WING_ROOT = NAC_DX + 2.0                  # inside the nacelle, for a deep joint
LE_ROOT_DX, LE_ROOT_Z = NAC_DX + NAC_R, 113.2
TIP_DX, TIP_LE_Z, TIP_TE_Z = 50.8, 85.0, 61.0
SURFACES = {}    # (side, name, "top"/"bottom") -> servo index
TOP_AXES = ([-1, 0, 0], [0, 0, -1], [0, -1, 0])
BOTTOM_AXES = ([1, 0, 0], [0, 0, -1], [0, 1, 0])


def split_surface(s, dx0, dx1, y0, y1, hinge_z, chord, name):
    """A split trailing edge: two door hinge servos (top and bottom) just
    behind hinge_z, each with a thin panel behind it."""
    mid = (y0 + y1) / 2
    servo_settings = {"default_angle": 0.0, "positive_angle": 60.0, "negative_angle": -60.0,
                      "speed": 150.0, "easing": 1000.0, "max_torque": 600000.0,
                      "when_idle": "Return to default angle"}
    top = b.add("door_hinge_servo", side_box(s, dx0, dx1, mid, y1, hinge_z - 1.0, hinge_z), TOP_AXES, DARK,
                settings=dict(servo_settings))
    bottom = b.add("door_hinge_servo", side_box(s, dx0, dx1, y0, mid, hinge_z - 1.0, hinge_z), BOTTOM_AXES, DARK,
                   settings=dict(servo_settings))
    t = min(0.2, (y1 - y0) / 3)
    b.box(side_box(s, dx0, dx1, y1 - t, y1, hinge_z - 1.0 - chord, hinge_z - 1.0), BLACK, ptype="aero_panel")
    b.box(side_box(s, dx0, dx1, y0, y0 + t, hinge_z - 1.0 - chord, hinge_z - 1.0), BLACK, ptype="aero_panel")
    SURFACES[(s, name, "top")] = top
    SURFACES[(s, name, "bottom")] = bottom


TIPS = {}
for s in SIDES:
    b.box(side_box(s, WING_ROOT, TIP_DX, WY0, WY1, TIP_TE_Z, TIP_LE_Z), BLACK, ptype="aero_panel")
    b.box(side_box(s, WING_ROOT, LE_ROOT_DX, WY0, WY1, TIP_LE_Z, LE_ROOT_Z), BLACK, ptype="aero_panel")
    b.tri_panel(side_box(s, LE_ROOT_DX, TIP_DX, WY0, WY1, TIP_LE_Z, LE_ROOT_Z), (s, 0, 0), FWD, BLACK)
    # Behind the elevons' inner end, a filler on the nacelle.
    b.box(side_box(s, WING_ROOT, 30.95, WY0, WY1, 57.0, TIP_TE_Z), BLACK, ptype="aero_panel")
    split_surface(s, 31.0, 49.5, WY0, WY1, TIP_TE_Z, 4.0, "outboard")
    # Navigation light on each tip: red on the left, green on the right.
    TIPS[s] = b.add("light_panel", side_box(s, TIP_DX, TIP_DX + 0.125, YC - 0.25, YC + 0.25, 72.0, 74.0),
                    ([0, 0, 1], [s, 0, 0], [0, s, 0]), "#ff2222" if s > 0 else "#22ff44",
                    settings={"color": "#ff2222" if s > 0 else "#22ff44", "brightness": 2.0})
# The body's trailing edge: a thin strip behind the body's taper, and the
# inner elevons behind that.
INNER_HINGE = 53.0
b.box((X0 - LENS_W + 1.0, X0 + LENS_W - 1.0, WY0, WY1, INNER_HINGE, TE_BODY + 2.0), BLACK, ptype="aero_panel")
for s in SIDES:
    split_surface(s, 3.0, 17.0, WY0, WY1, INNER_HINGE, 4.0, "inboard")

# Lifting surfaces hidden inside the body, just above the chine line: the
# chines and the body between the nacelles lift like the wing they are.
LIFT_Y0, LIFT_Y1 = YC + 0.05, YC + 0.45
b.box((X0 - 16.0, X0 + 16.0, LIFT_Y0, LIFT_Y1, 80.0, INLET), BLACK, ptype="aero_panel_dragless")
for s in SIDES:
    # The chine ahead of the inlets, a triangle from the nose out to the nacelle.
    b.tri_panel(side_box(s, 2.0, 16.0, LIFT_Y0, LIFT_Y1, INLET, 200.0), (s, 0, 0), FWD, BLACK,
                ptype="aero_panel_triangle_dragless")
b.box((X0 - 2.0, X0 + 2.0, LIFT_Y0, LIFT_Y1, INLET, 210.0), BLACK, ptype="aero_panel_dragless")

# ---------------------------------------------------------------------------
# Landing gear. The nose leg slides up into its well on a piston; the main
# legs swing forward into theirs on servos, each wheel turning into a slot
# beside the missile bays.
NOSE_TRAVEL = PAN_Y + 0.1
GEAR_PISTONS, MAIN_SERVOS = [], []
NOSE_Z = (NOSE_WELL[0] + NOSE_WELL[1]) / 2
# Piston barrel at the opening, on plates to the well's front and back walls.
nose_piston = b.add("piston", (X0 - 0.6, X0 + 0.6, PAN_Y, PAN_Y + 1.5, NOSE_Z - 0.6, NOSE_Z + 0.6),
                    ([1, 0, 0], [0, -1, 0], [0, 0, -1]), GREY, material="steel",
                    settings={"current_length": NOSE_TRAVEL, "target_length": 0.0, "max_length": NOSE_TRAVEL,
                              "speed": 1.4, "easing": 2.0, "max_force": 3000000.0,
                              "when_idle": "Return to starting length"})
GEAR_PISTONS.append(nose_piston)
for (z0, z1) in [(NOSE_WELL[0], NOSE_Z - 0.6), (NOSE_Z + 0.6, NOSE_WELL[1])]:
    b.box((X0 - 0.4, X0 + 0.4, PAN_Y + 0.4, PAN_Y + 1.5, z0, z1), DARK, material="aluminum")
NOSE_STEER = b.add("servo", (X0 - 0.6, X0 + 0.6, 2.1, 3.3, NOSE_Z - 0.6, NOSE_Z + 0.6),
                   ([1, 0, 0], [0, -1, 0], [0, 0, -1]), GREY, material="steel",
                   settings={"default_angle": 0.0, "positive_angle": 35.0, "negative_angle": -35.0,
                             "speed": 60.0, "easing": 400.0, "max_torque": 300000.0,
                             "when_idle": "Return to default angle"})
b.box((X0 - 0.4, X0 + 0.4, 3.3, PAN_Y, NOSE_Z - 0.4, NOSE_Z + 0.4), METAL, material="steel")
NW_D, NW_W, NW_DX = 3.0, 0.9, 1.15
b.box((X0 - NW_DX + NW_W / 2, X0 + NW_DX - NW_W / 2, NW_D / 2 - 0.6, 2.1, NOSE_Z - 0.5, NOSE_Z + 0.5), METAL,
      material="steel")
for o in (-NW_DX, NW_DX):
    b.add("wheel", (X0 + o - NW_W / 2, X0 + o + NW_W / 2, 0.0, NW_D, NOSE_Z - NW_D / 2, NOSE_Z + NW_D / 2),
          IDENT, "#151515", material="aluminum", settings={"free_spinning": True, "friction": 20.0})

# Main legs: the servo sits beside the well on an aluminium mount from the
# rib to the pan's roof; the leg hangs from its outboard face, the wheel
# beside the leg. Swinging the leg 90 degrees forward lays the wheel in the
# well.
MW_D, MW_W = 3.4, 1.2
HINGE_Y = PAN_Y + MW_D / 2 + 0.55          # retracted, the wheel lies between the skin and the roof
for s in SIDES:
    sx0, sx1 = 9.6, 11.2                    # servo, out from the centreline
    b.box(side_box(s, BAY_DX[1] + 0.5, sx0, PAN_Y + SKIN, YC, MAIN_Z - 3.0, MAIN_Z + 3.0), DARK, material="aluminum")
    servo = b.add("servo", side_box(s, sx0, sx1, HINGE_Y - 0.8, HINGE_Y + 0.8, MAIN_Z - 0.8, MAIN_Z + 0.8),
                  ([0, 0, s], [s, 0, 0], [0, 1, 0]),
                  GREY, material="steel",
                  settings={"default_angle": 0.0, "positive_angle": -90.0 * s, "negative_angle": 0.0,
                            "speed": 45.0, "easing": 120.0, "max_torque": 5000000.0,
                            "when_idle": "Return to default angle"})
    MAIN_SERVOS.append(servo)
    # The leg: from the servo's face down to the axle, and a fork out to the wheel.
    axle_y = MW_D / 2
    b.box(side_box(s, sx1, sx1 + 0.8, axle_y - 0.6, HINGE_Y + 0.8, MAIN_Z - 0.4, MAIN_Z + 0.4), METAL,
          material="steel")
    b.box(side_box(s, sx1 + 0.8, sx1 + 1.0, axle_y - 0.6, axle_y + 0.6, MAIN_Z - 0.5, MAIN_Z + 0.5), METAL,
          material="steel")
    b.add("wheel", side_box(s, sx1 + 1.0, sx1 + 1.0 + MW_W, 0.0, MW_D, MAIN_Z - MW_D / 2, MAIN_Z + MW_D / 2),
          IDENT, "#151515", material="aluminum", settings={"free_spinning": True, "friction": 20.0})

# ---------------------------------------------------------------------------
# Missiles: two a side in the bays under the body, out of sight behind
# doors. Y opens every bay at once and lets all four go together.
MISSILES = []    # (gate, rocket, detector, explosive)
DOOR_SERVOS = []


def missile(cx, z):
    d = 1.2
    rail = YC - 0.25                     # the gate's rail: the missile's top
    y0, y1 = rail - d, rail
    yc = (y0 + y1) / 2
    rocket = b.add("solid_rocket", (cx - d / 2, cx + d / 2, y0, y1, z, z + 7.0),
                   ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), WHITE, material="aluminum",
                   settings={"thrust": 85000.0, "burn_time": 6.0, "ideal": False})
    b.along("cylinder", (cx - d / 2, cx + d / 2, y0, y1, z + 7.0, z + 12.0), FWD, WHITE, material="aluminum")
    det = b.add("impact_detector", (cx - 0.45, cx + 0.45, yc - 0.45, yc + 0.45, z + 12.0, z + 12.9),
                IDENT, RED, material="aluminum", settings={"threshold": 40.0, "pulse": 0.2})
    b.along("cylinder", (cx - d / 2, cx + d / 2, y0, y1, z + 12.0, z + 13.4), FWD, RED, material="aluminum")
    exp = b.add("explosive_block", (cx - d / 2, cx + d / 2, y0, y1, z + 13.4, z + 16.0), IDENT, WHITE,
                material="aluminum", settings={"blast_radius": BLAST})
    b.along("cone", (cx - d / 2, cx + d / 2, y0, y1, z + 16.0, z + 19.0), FWD, WHITE, material="aluminum")
    for (zf, span, chord) in [(z, 0.7, 2.2), (z + 13.6, 0.5, 1.5)]:
        for (ux, uy) in [(1, 0), (-1, 0), (0, -1)]:
            if ux:
                xa = cx + ux * d / 2
                fb = (min(xa, xa + ux * span), max(xa, xa + ux * span), yc - 0.05, yc + 0.05, zf, zf + chord)
            else:
                ya = yc + uy * d / 2
                fb = (cx - 0.05, cx + 0.05, min(ya, ya + uy * span), max(ya, ya + uy * span), zf, zf + chord)
            b.tri_panel(fb, (ux, uy, 0), FWD, WHITE, material="aluminum")
    rack = b.add("reload_gate", (cx - 0.3, cx + 0.3, rail, YC, z + 5.0, z + 13.0),
                 ([1, 0, 0], [0, -1, 0], [0, 0, -1]), METAL, material="aluminum",
                 settings={"reload_time": MISSILE_RELOAD, "reloads": 0.0, "safe_time": MISSILE_SAFE,
                           "push_speed": 8.0})
    MISSILES.append((rack, rocket, det, exp))


def bay_door(s, hinge_dx, toward):
    """A door along one edge of a bay: a door hinge servo against the bay's
    wall, its leaf the edge of the door, and a panel on the leaf reaching
    halfway across. `toward` is +1 when the door reaches outward from its
    hinge, -1 when inward. Opening swings it down, hanging from its edge."""
    # The leaf points across the bay, away from the wall it hangs on.
    across = (s * toward, 0, 0)           # world direction from the hinge toward the bay's middle
    x_axis = cross(list(across), [0, 1, 0])
    a, c = sorted((X0 + s * hinge_dx, X0 + s * (hinge_dx + toward * 1.0)))
    servo = b.add("door_hinge_servo", (a, c, PAN_Y, PAN_Y + 1.0, BAY_Z[0] + 0.05, BAY_Z[1] - 0.05),
                  (x_axis, list(across), [0, 1, 0]), DARK,
                  settings={"default_angle": 0.0, "positive_angle": -100.0, "negative_angle": 0.0,
                            "speed": 360.0, "easing": 3000.0, "max_torque": 400000.0,
                            "when_idle": "Return to default angle"})
    DOOR_SERVOS.append(servo)
    mid = (BAY_DX[0] + BAY_DX[1]) / 2
    a, c = sorted((X0 + s * (hinge_dx + toward * 1.0), X0 + s * (mid - toward * 0.05)))
    b.box((a, c, PAN_Y, PAN_Y + 0.4, BAY_Z[0] + 0.05, BAY_Z[1] - 0.05), BLACK)


for s in SIDES:
    missile(X0 + s * 3.2, BAY_Z[0] + 3.5)
    missile(X0 + s * 6.4, BAY_Z[0] + 3.5)
    bay_door(s, BAY_DX[1], -1)     # the outer door, hinged on the outer wall
    bay_door(s, BAY_DX[0], 1)      # the inner door, hinged on the keel

# ---------------------------------------------------------------------------
# Sensors in the fuselage; the height finder in the bottom of the left
# nacelle, where nothing the plane fires passes under it.
ATT = b.add("attitude_sensor", (X0 - 0.5, X0 + 0.5, 15.0, 16.0, 118.0, 119.0),
            ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), DARK)
SPEED = b.add("speed_sensor", (X0 - 0.5, X0 + 0.5, 15.0, 16.0, 120.0, 121.0),
              ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), DARK)
DIST = b.add("distance_sensor", side_box(1, NAC_DX - 0.5, NAC_DX + 0.5, YC - NAC_R, YC - NAC_R + 0.5, 90.0, 91.0),
             ([1, 0, 0], [0, 0, -1], [0, 1, 0]), DARK, settings={"range": 3000.0})
BEACON = b.add("light_panel", (X0 - 0.5, X0 + 0.5, YC + CORE_R - 0.1, YC + CORE_R + 0.025, 119.0, 120.0), IDENT, "#ff1010",
               settings={"color": "#ff1010", "brightness": 3.0})

# ---------------------------------------------------------------------------
# Controls. Each reads the controller and its keyboard twin together, the
# same buttons as the F-14 (less the wing sweep).
pad_pitch = pad("Left stick Y (up +)", curve=1.6, deadzone=0.1)
key_pitch = key("W", second="S")
pitch_in = gate("Add", V(pad_pitch), V(key_pitch))
pad_roll = pad("Left stick X (right +)", curve=1.6, deadzone=0.1)
key_roll = key("D", second="A")
roll_in = gate("Add", V(pad_roll), V(key_roll))
pad_yaw = pad("D-pad right", second="D-pad left")
key_yaw = key("X", second="Z")
yaw_in = gate("Add", V(pad_yaw), V(key_yaw))

# Throttle: the right trigger, M for cruise, K for full power. Once that is
# all the way in, the left trigger (or Shift) lights the afterburners on top.
pad_rt = pad("RT / R2 trigger", deadzone=0.05)
key_k = key("K")
key_m = key("M", mode="Toggle")
cruise = gate("Multiply", V(key_m), value=0.55)
t1 = gate("Max", V(pad_rt), R(cruise))
throttle = gate("Max", R(t1), V(key_k))
engines_on = gate("Compare", R(throttle), value=0.02)
full_power = gate("Compare", R(throttle), value=0.97)
pad_lt = pad("LT / L2 trigger", deadzone=0.05)
key_shift = key("Shift")
burn_ask = gate("Max", V(pad_lt), V(key_shift))
burn_wanted = gate("Multiply", R(burn_ask), T(full_power))
# The afterburners give no more than drag needs plus a few g of push: share
# allowed 0.12 + (speed / 700 m/s) squared, up to all of it. In the last few
# m/s short of the game's top speed they ease off, so the jet sits at it
# rather than straining past.
burn_v2 = gate("Multiply", (SPEED, "speed"), (SPEED, "speed"))
burn_share = gate("Multiply", R(burn_v2), value=1.0 / 490000.0)
burn_cap_raw = gate("Add", R(burn_share), value=0.12)
burn_cap = gate("Min", R(burn_cap_raw), value=1.0)
top_k = gate("Constant", value=TOP_SPEED + 2.0)
top_room = gate("Subtract", R(top_k), (SPEED, "speed"))
top_share = gate("Multiply", R(top_room), value=1.0 / 6.0)
top_cap = gate("Clamp", R(top_share), value=1.0)
burn_cap2 = gate("Min", R(burn_cap), R(top_cap))
burn_target = gate("Min", R(burn_wanted), R(burn_cap2))
# They light up and die away over a few seconds (a PID following its own
# output, a 4 s lag).
burn = logic("pid_controller", {"kp": 0.0, "ki": 0.25, "kd": 0.0, "output_min": 0.0, "output_max": 1.0},
             {"setpoint": R(burn_target)})
b.link(burn, "measurement", burn, "output")
burning = gate("Compare", O(burn), value=0.01)

# Gain schedule: the faster it goes, the less surface a turn rate takes.
v2 = gate("Multiply", (SPEED, "speed"), (SPEED, "speed"))
v_sched = gate("Max", (SPEED, "speed"), value=92.3)
k_const = gate("Constant", value=120.0)
sched_slow = gate("Divide", R(k_const), R(v_sched))
v2_sched = gate("Max", R(v2), value=1.0)
k2_const = gate("Constant", value=50000.0)
sched_fast = gate("Divide", R(k2_const), R(v2_sched))
sched = gate("Min", R(sched_slow), R(sched_fast))
# Below about 25 m/s, and on the ground, the sticks move the surfaces
# straight; the stability system has it all by 55 m/s and 10 m up.
v_over = gate("Subtract", (SPEED, "speed"), value=25.0)
v_share = gate("Multiply", R(v_over), value=1.0 / 30.0)
v_fade = gate("Clamp", R(v_share), value=1.0)
h_over = gate("Subtract", (DIST, "distance"), value=4.0)
h_share = gate("Multiply", R(h_over), value=1.0 / 6.0)
h_fade = gate("Clamp", R(h_share), value=1.0)
fade = gate("Min", R(v_fade), R(h_fade))
one = gate("Constant", value=1.0)
unfade = gate("Subtract", R(one), R(fade))


def stability_axis(stick, rate_per_unit, measured, pid_settings, direct_gain, extra=None, share=None):
    """Rate command, attitude hold for one axis; the stick moves the
    surfaces straight at low speed. `extra` adds to the rate asked for;
    `share` (a gate) is how much is the stability system's, if not `fade`.
    Returns the command in degrees."""
    own = fade if share is None else share[0]
    own_un = unfade if share is None else share[1]
    if isinstance(rate_per_unit, int):
        cmd = gate("Multiply", R(stick), R(rate_per_unit))
    else:
        cmd = gate("Multiply", R(stick), value=rate_per_unit)
    if extra is not None:
        cmd = gate("Add", R(cmd), R(extra))
    err = gate("Subtract", R(cmd), measured)
    err_f = gate("Multiply", R(err), R(own))
    setpoint = gate("Add", measured, R(err_f))
    pid = logic("pid_controller", pid_settings, {"setpoint": R(setpoint), "measurement": measured})
    flying = gate("Multiply", O(pid), R(sched))
    direct = gate("Multiply", R(stick), value=direct_gain)
    direct_f = gate("Multiply", R(direct), R(own_un))
    return gate("Add", R(flying), R(direct_f))


# Pitch: up to 15 degrees a second, and no more than about 4 g.
v_floor = gate("Max", (SPEED, "speed"), value=60.0)
g_cap = gate("Constant", value=4.0 * 9.81 * 57.2958)
g_rate = gate("Divide", R(g_cap), R(v_floor))
pitch_rate = gate("Min", R(g_rate), value=15.0)
# In a level turn the nose has to come round as well as across: the pitch
# rate a turn takes (yaw rate times the tangent of the bank) is added, so let
# go in a bank it holds its height.
bank = gate("Multiply", (ATT, "roll"), value=1.0 / 57.2958)
bank_sq = gate("Multiply", R(bank), R(bank))
bank_f = gate("Multiply", R(bank_sq), value=1.0 / 3.0)
bank_f1 = gate("Add", R(bank_f), value=1.0)
bank_tan = gate("Multiply", R(bank), R(bank_f1))
bank_tan = sym_clamp(bank_tan, 1.73)
turn_pitch = gate("Multiply", R(bank_tan), (ATT, "yaw_rate"))
P_raw = stability_axis(pitch_in, pitch_rate, (ATT, "pitch_rate"),
                       {"kp": 2.5, "ki": 1.5, "kd": 0.0, "output_min": -30.0, "output_max": 30.0}, 30.0,
                       extra=turn_pitch)
# On the runway, past 6 degrees nose up the stick is eased off, 15 degrees
# of elevon for every degree more: the nozzles touch the runway at about 8.
over_six = gate("Subtract", (ATT, "pitch"), value=6.0)
over_pos = gate("Max", R(over_six), value=0.0)
guard_full = gate("Multiply", R(over_pos), value=15.0)
guard = gate("Multiply", R(guard_full), R(unfade))
P_ = gate("Subtract", R(P_raw), R(guard))
# Roll: 70 degrees a second, less when fast.
roll_cap = gate("Constant", value=20000.0)
roll_fast = gate("Divide", R(roll_cap), R(v_floor))
roll_rate = gate("Min", R(roll_fast), value=70.0)
R_ = stability_axis(roll_in, roll_rate, (ATT, "roll_rate"),
                    {"kp": 1.0, "ki": 0.6, "kd": 0.0, "output_min": -45.0, "output_max": 45.0}, 30.0)
# Yaw: the D-pad asks for a turn; the sideslip asks for a turn into the
# airflow, as big fins would. Differential thrust and the drag of the split
# elevons do it.
side_cap = gate("Constant", value=2.0 * 9.81 * 57.2958)
side_rate = gate("Divide", R(side_cap), R(v_floor))
yaw_rate = gate("Min", R(side_rate), value=8.0)
fwd_floor = gate("Max", (SPEED, "forward"), value=30.0)
slip = gate("Divide", (SPEED, "sideways"), R(fwd_floor))
slip_deg = gate("Multiply", R(slip), value=57.2958 * SLIP_GAIN)
slip_lim = sym_clamp(slip_deg, 12.0)
slip_cmd = gate("Multiply", R(slip_lim), R(h_fade))      # (not on the runway: it would turn into a crosswind)
# Yaw is the stability system's from 25 to 55 m/s even on the runway, where
# it holds the heading on the takeoff roll as a rudder would.
v_unfade = gate("Subtract", R(one), R(v_fade))
Y_ = stability_axis(yaw_in, yaw_rate, (ATT, "yaw_rate"),
                    {"kp": 4.0, "ki": 1.0, "kd": 0.0, "output_min": -40.0, "output_max": 40.0}, 30.0,
                    extra=slip_cmd, share=(v_fade, v_unfade))

# Air brake: D-pad down (or Q) opens the outer elevons both ways (less when fast).
pad_brake = pad("D-pad down")
key_brake = key("Q")
brake_on = bgate("OR", P(pad_brake), P(key_brake))
brake_full = gate("Multiply", (brake_on, "result"), value=50.0)
brake_v2 = gate("Max", R(v2), value=22500.0)
brake_k = gate("Constant", value=22500.0)
brake_share = gate("Divide", R(brake_k), R(brake_v2))
brake = gate("Multiply", R(brake_full), R(brake_share))
# Steering by drag too: the yaw command opens the outer elevon on the side to
# turn toward, a little.
yaw_right = gate("Max", R(Y_), value=0.0)
neg_y = gate("Multiply", R(Y_), value=-1.0)
yaw_left = gate("Max", R(neg_y), value=0.0)
drag_r = gate("Multiply", R(yaw_right), value=0.5)
drag_l = gate("Multiply", R(yaw_left), value=0.5)
drag = {-1: gate("Add", R(drag_r), R(brake)), 1: gate("Add", R(drag_l), R(brake))}

# Mixing. A positive deflection lifts the trailing edge (the top panel
# opens); a negative one drops it. Stick back lifts every trailing edge;
# stick right lifts the right side and drops the left.
r_in = gate("Multiply", R(R_), value=0.4)
deflection = {
    (-1, "inboard"): gate("Add", R(P_), R(r_in)),
    (1, "inboard"): gate("Subtract", R(P_), R(r_in)),
    (-1, "outboard"): gate("Add", R(P_), R(R_)),
    (1, "outboard"): gate("Subtract", R(P_), R(R_)),
}
for (s, name), dsrc in deflection.items():
    neg_d = gate("Multiply", R(dsrc), value=-1.0)
    up_only = gate("Max", R(dsrc), value=0.0)
    down_only = gate("Max", R(neg_d), value=0.0)
    if name == "outboard":
        up_only = gate("Add", R(up_only), R(drag[s]))
        down_only = gate("Add", R(down_only), R(drag[s]))
    top_g = gate("Multiply", R(up_only), value=-1.0)       # positive turns both leaves inward
    bottom_g = gate("Multiply", R(down_only), value=-1.0)
    b.link(SURFACES[(s, name, "top")], "angle", top_g, "result")
    b.link(SURFACES[(s, name, "bottom")], "angle", bottom_g, "result")

# Nose wheel: steered by the yaw input and the roll stick, fully up to
# 15 m/s and not at all by 40.
steer_in = gate("Add", R(roll_in), R(yaw_in))
v_left = gate("Subtract", (SPEED, "speed"), value=40.0)
v_left_neg = gate("Multiply", R(v_left), value=-1.0 / 25.0)
steer_share = gate("Clamp", R(v_left_neg), value=1.0)
steer_scaled = gate("Multiply", R(steer_in), R(steer_share))
steer = gate("Multiply", R(steer_scaled), value=-30.0)
b.link(NOSE_STEER, "angle", steer, "result")

# Engines: each has its own throttle, for yaw: a turn to the right opens the
# left engine up and the right one down.
# (Not at taxiing speeds: there the nose wheel steers, and a split
# throttle would push the jet forward from idle.)
diff_raw = gate("Multiply", R(Y_), value=DIFF_THRUST / 40.0)
diff = gate("Multiply", R(diff_raw), R(v_fade))
# Reverse thrust, for taxiing: RB (or N) on the ground pushes the jet back,
# gently (REVERSE of full thrust), in place of the throttle.
pad_rb = pad("RB / R1")
key_n = key("N")
rev_ask = bgate("OR", P(pad_rb), P(key_n))
rev_high = gate("Compare", (DIST, "distance"), value=5.0)
rev_low = bgate("NOT", T(rev_high))
reversing = bgate("AND", (rev_ask, "result"), (rev_low, "result"))
not_reversing = bgate("NOT", (reversing, "result"))
rev_part = gate("Multiply", (reversing, "result"), value=-REVERSE)
for s in SIDES:
    side_thr = gate("Add" if s > 0 else "Subtract", R(throttle), R(diff))
    side_thr = gate("Clamp", R(side_thr), value=1.0)
    side_on = gate("Compare", R(side_thr), value=0.02)
    fwd_part = gate("Multiply", R(side_thr), (not_reversing, "result"))
    side_final = gate("Add", R(fwd_part), R(rev_part))
    side_run = bgate("OR", T(side_on), (reversing, "result"))
    for t in THRUSTERS_BY_SIDE[s]:
        b.link(t, "throttle", side_final, "result")
        b.link(t, "on", side_run, "result")
for t in BURNERS:
    b.link(t, "throttle", burn, "output")
    b.link(t, "on", burning, "is_true")
# Thrust vectoring: both nozzles with the pitch command (less with the
# afterburners lit: they don't swivel, but they make the nozzles' share of
# the push that much smaller), and, flying,
# each against the other with the roll command. A positive angle pushes the
# tail down: nose up. On the runway the stick swivels them too, which is
# what lifts the heavy nose for takeoff.
burn_ratio = gate("Multiply", O(burn), value=AFTERBURNER / THRUST)
thrust_ratio = gate("Add", R(burn_ratio), value=1.0)
vec_p_raw = gate("Multiply", R(P_), value=VEC_PITCH)
vec_p = gate("Divide", R(vec_p_raw), R(thrust_ratio))
vec_rf = gate("Multiply", R(R_), R(fade))
vec_r_raw = gate("Multiply", R(vec_rf), value=VEC_ROLL)
vec_r = gate("Divide", R(vec_r_raw), R(thrust_ratio))
for s, n in zip(SIDES, NOZZLES):
    # Rolling right lifts the left side: its nozzle swings to push up.
    side_vec = gate("Subtract" if s > 0 else "Add", R(vec_p), R(vec_r))
    side_vec = sym_clamp(side_vec, VECTOR_MAX)
    b.link(n, "angle", side_vec, "result")
# The glow: orange with the throttle, yellow and then white-blue at the core
# as the afterburners come in.
ring_r = gate("Multiply", R(throttle), value=255.0)
ring_g_dry = gate("Multiply", R(throttle), value=80.0)
ring_g_wet = gate("Multiply", O(burn), value=120.0)
ring_g = gate("Add", R(ring_g_dry), R(ring_g_wet))
ring_b = gate("Multiply", O(burn), value=40.0)
core_g_dry = gate("Multiply", R(throttle), value=200.0)
core_g_wet = gate("Multiply", O(burn), value=55.0)
core_g = gate("Add", R(core_g_dry), R(core_g_wet))
core_b = gate("Multiply", O(burn), value=255.0)
for l in LIGHTS_RING:
    b.link(l, "on", engines_on, "is_true")
    b.link(l, "red", ring_r, "result")
    b.link(l, "green", ring_g, "result")
    b.link(l, "blue", ring_b, "result")
for l in LIGHTS_CORE:
    b.link(l, "on", engines_on, "is_true")
    b.link(l, "red", ring_r, "result")
    b.link(l, "green", core_g, "result")
    b.link(l, "blue", core_b, "result")
beacon = logic("pwm_generator", {"frequency": 1.0, "duty": 12.0})
b.link(BEACON, "on", beacon, "output")

# Landing gear: up by itself climbing past GEAR_UP_AT m above the ground,
# down by itself sinking below GEAR_DOWN_AT. D-pad up (or G) also raises or
# lowers it any time off the ground (on the ground a press does nothing),
# and that holds until the next time the jet climbs or sinks past those
# heights.
pad_gear = pad("D-pad up")
key_gear = key("G")
gear_press = bgate("OR", P(pad_gear), P(key_gear))
tap = bgate("Timer", (gear_press, "result"), seconds=0.15)
airborne = gate("Compare", (DIST, "distance"), value=5.0)
high = gate("Compare", (DIST, "distance"), value=GEAR_UP_AT)
not_low = gate("Compare", (DIST, "distance"), value=GEAR_DOWN_AT)
low = bgate("NOT", T(not_low))
climbed_past = bgate("Timer", T(high), seconds=0.15)
sank_past = bgate("Timer", (low, "result"), seconds=0.15)
gear_up = bgate("Latch")
up_fresh = bgate("Timer", (gear_up, "result"), seconds=0.4)
gear_down_now = bgate("NOT", (gear_up, "result"))
down_fresh = bgate("Timer", (gear_down_now, "result"), seconds=0.4)
can_raise = bgate("AND", (gear_down_now, "result"), T(airborne))
can_raise2 = bgate("AND", (can_raise, "result"), (bgate("NOT", (down_fresh, "result")), "result"))
go_up = bgate("AND", (tap, "result"), (can_raise2, "result"))
can_lower = bgate("AND", (gear_up, "result"), (bgate("NOT", (up_fresh, "result")), "result"))
go_down = bgate("AND", (tap, "result"), (can_lower, "result"))
raise_gear = bgate("OR", (go_up, "result"), (climbed_past, "result"))
lower_gear = bgate("OR", (go_down, "result"), (sank_past, "result"))
b.link(gear_up, "a", raise_gear, "result")
b.link(gear_up, "b", lower_gear, "result")
for p in GEAR_PISTONS:
    b.link(p, "extend", gear_up, "result")
for sv in MAIN_SERVOS:
    b.link(sv, "go_positive", gear_up, "result")

# Missiles: Y (or R) opens every bay door, lets all four missiles go
# together a moment later, lights them once they have dropped clear, and
# closes the doors. A bay hangs a fresh missile after the reload time, behind
# its closed doors. Only 20 m or more above the ground.
pad_y = pad("Y / Triangle", mode="Pulse")
key_r = key("R", mode="Pulse")
shot_raw = bgate("OR", P(pad_y), P(key_r))
high_enough = gate("Compare", (DIST, "distance"), value=MISSILE_FLOOR)
shot = bgate("AND", (shot_raw, "result"), T(high_enough))
doors_open = bgate("Timer", (shot, "result"), seconds=1.6)


def pulse_at(seconds):
    """On for a moment, `seconds` after the shot."""
    longer = bgate("Timer", (shot, "result"), seconds=seconds + 0.05)
    shorter = bgate("Timer", (shot, "result"), seconds=seconds)
    return bgate("AND", (longer, "result"), (bgate("NOT", (shorter, "result")), "result"))


release = pulse_at(0.4)
ignite = pulse_at(0.75)
for sv in DOOR_SERVOS:
    b.link(sv, "go_positive", doors_open, "result")
for (rack, rocket, det, exp) in MISSILES:
    b.link(rack, "release", release, "result")
    b.link(rocket, "ignite", ignite, "result")
    b.link(exp, "detonate", det, "triggered")

# The ladder folds away while the engines run or the gear is up.
ladder_away = bgate("OR", T(engines_on), (gear_up, "result"))
b.link(LADDER, "stowed", ladder_away, "result")

b.write(OUT)

# Names of the parts the tests look at, by index in the file.
names = {"seat": SEAT, "camera": CAMERA, "att": ATT, "speed": SPEED, "dist": DIST, "ladder": LADDER,
         "steer": NOSE_STEER, "nozzle_L": NOZZLES[0], "nozzle_R": NOZZLES[1],
         "thrust_L": THRUSTERS[0], "thrust_R": THRUSTERS[1], "burner_L": BURNERS[0], "burner_R": BURNERS[1],
         "core_L": LIGHTS_CORE[0], "tip_L": TIPS[1], "tip_R": TIPS[-1],
         "main_L": MAIN_SERVOS[0], "main_R": MAIN_SERVOS[1]}
for (s_, name, half_), idx in SURFACES.items():
    names["%s_%s_%s" % (name, "L" if s_ > 0 else "R", half_)] = idx
for i, p_ in enumerate(GEAR_PISTONS):
    names["gear_%d" % i] = p_
for i, d_ in enumerate(DOOR_SERVOS):
    names["door_%d" % i] = d_
for i, (rack, rocket, det, exp) in enumerate(MISSILES):
    names["missile_%d" % i] = rocket
    names["rack_%d" % i] = rack
    names["warhead_%d" % i] = exp
with open(OUT + ".names.json", "w") as f:
    json.dump(names, f)

# ---------------------------------------------------------------------------
# A rough weigh-in (overlaps counted twice), for tuning: the weight, where
# its centre is, and where the lift centres.
DENSITY = {"balsa": 150.0, "aluminum": 2700.0, "steel": 7850.0, "plastic": 1050.0}
FILL = {"wedge": 0.5, "corner_wedge": 1 / 6, "cylinder": 0.785, "cone": 0.262, "pipe": 0.283,
        "half_cylinder": 0.785, "half_cone": 0.262, "half_frustum": 0.458, "rounded_wedge": 0.524,
        "curved_wedge": 0.667, "convex_curve": 0.785, "aero_panel_triangle": 0.5,
        "aero_panel_triangle_dragless": 0.5, "servo": 0.5, "door_hinge_servo": 0.5, "piston": 0.5,
        "wheel": 0.5, "light_panel": 0.5, "impact_detector": 0.4, "explosive_block": 0.8, "reload_gate": 0.8,
        "ladder": 0.3, "seat": 0.4, "attitude_sensor": 0.3, "speed_sensor": 0.3, "distance_sensor": 0.3}
LOGIC = {"gamepad_input", "input_block", "number_gate", "boolean_gate", "pid_controller", "pwm_generator",
         "camera"}
mass = mz = 0.0
area = az = 0.0
for p_ in b.parts:
    if p_["type"] in LOGIC:
        continue
    sx, sy, sz = p_["size"]
    m = sx * sy * sz / 64.0 * FILL.get(p_["type"], 1.0) * DENSITY.get(p_["material"], 1000.0)
    mass += m
    mz += m * p_["pos"][2]
    if p_["type"].startswith("aero_panel") and abs(p_["y_axis"][1]) > 0.5:
        a = sx * sz / 16.0 * (0.5 if "triangle" in p_["type"] else 1.0)
        z = p_["pos"][2]
        if "triangle" in p_["type"]:
            z += p_["z_axis"][2] * sz / 6.0 * -1.0
        area += a
        az += a * z
print("parts %d logic %d | missiles %d | ~%.1f t, centre of mass z %.1f, of lift z %.1f, area %.0f m2" % (
    len(b.parts), _logic_slot[0], len(MISSILES), mass / 1000.0, mz / mass, az / area, area))
