"""Writes the F-14 build: a 1.5x scale Tomcat in black balsa with red trim.

    python3 tools/make_f14.py <out.json> [thrust_newtons_per_engine]

The nose points along +Z, up is +Y, and the pilot's left is +X. One metre of
the real aeroplane is 6 cells here (1.5x scale, 0.25 m cells). Ground is y 0.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from build_kit import Build, X0, side_box, holes_cut, IDENT  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/f14.json"
THRUST = float(sys.argv[2]) if len(sys.argv) > 2 else 300000.0

BLACK = "#17171a"
DARK = "#24252a"
GREY = "#3b3d44"
RED = "#a1111b"
GLASS = "#15283f"
WHITE = "#e9e9e6"
ENGINE = "#0d0d0f"
METAL = "#55585f"

b = Build("F-14 Tomcat")
SIDES = (1, -1)          # +1 the pilot's left (+X), -1 the right (-X)

# Heights (y, cells) and stations (z, cells)
BELLY = 7.0              # bottom of the nacelles and the forward fuselage
DECK = 16.0              # top of the nacelles and the flat centre "pancake"
WALL = 0.5               # skin thickness

# ---------------------------------------------------------------------------
# Logic parts: weightless and hidden once spawned, kept in rows on the floor
# in a corner of the grid.
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
# Forward fuselage: radome, cockpit section, canopy.
FF_Z0, FF_Z1 = 141.0, 166.0          # cockpit section
FF_X = 5.0                           # half width
NOSE_BAY = (125.6, 130.4, 158.0, 165.0)    # x0, x1, z0, z1 of the nose wheel well
NOSE_POCKET = (125.6, 130.4, 150.6, 158.0)  # where the nose door waits, inside


def shell_side(x0, x1, y0, y1, z0, z1, color=BLACK):
    b.box((x0, x1, y0, y1, z0, z1), color)


# Bottom skin with the nose wheel well cut out.
for (x0, x1, z0, z1) in holes_cut((X0 - FF_X, X0 + FF_X, FF_Z0, FF_Z1), [NOSE_BAY]):
    b.box((x0, x1, BELLY, BELLY + WALL, z0, z1), BLACK)
# Side walls, top deck, front bulkhead (the radome closes the front).
for s in SIDES:
    b.box(side_box(s, FF_X - WALL, FF_X, BELLY, 16.5, FF_Z0, FF_Z1), BLACK)
b.box((X0 - FF_X, X0 + FF_X, 16.0, 16.5, 158.0, FF_Z1), BLACK)          # deck ahead of the windscreen
# Chines: the lower and upper edges bevelled.
for s in SIDES:
    lo = side_box(s, FF_X, FF_X + 1.0, BELLY, BELLY + 1.5, FF_Z0, FF_Z1)
    b.wedge(lo, (-s, 0, 0), (0, 1, 0), BLACK)       # a ledge that slopes down and out
# Cockpit floor.
b.box((X0 - FF_X + WALL, X0 + FF_X - WALL, 12.5, 13.0, FF_Z0, 158.0), DARK)

# A block across the front of the cockpit section, above the nose wheel
# well, that the radome is set against.
b.box((X0 - FF_X + WALL, X0 + FF_X - WALL, 12.0, 16.0, 164.0, FF_Z1), DARK)
# Radome: a tapered nose to a red tip.
b.along("frustum", (X0 - FF_X, X0 + FF_X, 8.5, 16.5, FF_Z1, 178.0), (0, 0, 1), BLACK)
b.along("frustum", (X0 - 2.5, X0 + 2.5, 10.5, 14.5, 178.0, 181.5), (0, 0, 1), BLACK)
b.along("cone", (X0 - 1.25, X0 + 1.25, 11.5, 13.5, 181.5, 185.0), (0, 0, 1), RED)
# Chin: from the belly up to the radome.
b.wedge((X0 - FF_X, X0 + FF_X, BELLY, 8.5, FF_Z1, 171.0), (0, 0, -1), (0, 1, 0), BLACK)

# Canopy: windscreen, bubble, and the fairing behind it.
b.wedge((X0 - 3.0, X0 + 3.0, 16.5, 21.5, 152.0, 160.0), (0, 0, -1), (0, -1, 0), GLASS)
b.add("half_cylinder", (X0 - 3.0, X0 + 3.0, 16.5, 22.0, 141.0, 152.0), IDENT, GLASS)
for zf in (146.5, 151.8):    # canopy frames
    b.add("half_cylinder", (X0 - 3.05, X0 + 3.05, 16.5, 22.05, zf, zf + 0.3), IDENT, BLACK)
b.wedge((X0 - 3.0, X0 + 3.0, DECK, 21.0, 126.0, 141.0), (0, 0, 1), (0, -1, 0), BLACK)
# The deck either side of the canopy.
for s in SIDES:
    b.box(side_box(s, 3.0, FF_X, 16.0, 16.5, FF_Z0, 158.0), BLACK)
# Seat, facing the nose, on the cockpit floor.
SEAT = b.add("seat", (X0 - 1.5, X0 + 1.5, 13.0, 16.0, 150.5, 153.5), ([-1, 0, 0], [0, 1, 0], [0, 0, -1]),
             GREY, settings={})
# The radar operator's seat behind, for looks.
b.box((X0 - 1.2, X0 + 1.2, 13.0, 14.0, 143.5, 146.0), GREY)
b.box((X0 - 1.2, X0 + 1.2, 14.0, 17.5, 143.0, 143.5), GREY)
# Nose wheel well: walls round it inside, up to the deck.
for s in SIDES:
    b.box(side_box(s, 2.4, 2.9, BELLY + WALL, 16.0, 158.0, 165.0), DARK)

# ---------------------------------------------------------------------------
# Nacelles with the intakes, the centre fuselage between them, the spine.
NAC_IN, NAC_OUT = 5.0, 13.0          # nacelle sides, out from the centreline
NAC_Z0, NAC_Z1 = 83.0, 148.0          # tail end, intake lips
BODY_LIFT_Z = 112.0                   # the flat top lifts ahead of this
MAIN_BAY = (9.4, 12.5, 108.0, 115.5)    # dx0, dx1, z0, z1 of each main wheel well
MAIN_POCKET = (9.4, 12.5, 100.4, 108.0)  # where each main door waits, inside


def nacelle(s):
    # Belly with the wheel well cut out.
    hole = MAIN_BAY
    rect = (NAC_IN, NAC_OUT, NAC_Z0, NAC_Z1 - 0.8)
    for (a0, a1, z0, z1) in holes_cut(rect, [hole]):
        b.box(side_box(s, a0, a1, BELLY, BELLY + WALL, z0, z1), BLACK)
    # Side walls; the outer one carries a red pinstripe.
    b.box(side_box(s, NAC_IN, NAC_IN + WALL, BELLY, DECK, NAC_Z0, NAC_Z1 - 0.8), BLACK)
    b.box(side_box(s, NAC_OUT - WALL, NAC_OUT, BELLY, DECK, NAC_Z0, NAC_Z1 - 0.8), BLACK)
    b.box(side_box(s, NAC_OUT, NAC_OUT + 0.06, 11.4, 11.6, 86.0, 146.0), RED)
    # Top: a lifting surface ahead of BODY_LIFT_Z, like the real Tomcat's flat
    # body; plain skin behind, so the lift stays near the centre of mass.
    b.box(side_box(s, NAC_IN, NAC_OUT, DECK - WALL, DECK, BODY_LIFT_Z, NAC_Z1 - 0.8), BLACK, ptype="aero_panel")
    b.box(side_box(s, NAC_IN, NAC_OUT, DECK - WALL, DECK, NAC_Z0, BODY_LIFT_Z), BLACK)
    # The rest of the engine's weight, low in the back of the nacelle.
    cx = X0 + s * 9.0
    b.box((cx - 1.5, cx + 1.5, BELLY + WALL, BELLY + WALL + 2.0, NAC_Z0 + WALL, NAC_Z0 + WALL + 2.4), ENGINE,
          material="steel")
    # Tail end.
    b.box(side_box(s, NAC_IN, NAC_OUT, BELLY, DECK, NAC_Z0, NAC_Z0 + WALL), BLACK)
    # Intake: red lips, and the dark engine face back inside.
    b.box(side_box(s, NAC_IN, NAC_OUT, BELLY, BELLY + WALL, NAC_Z1 - 0.8, NAC_Z1), RED)
    b.box(side_box(s, NAC_IN, NAC_OUT, DECK - WALL, DECK, NAC_Z1 - 0.8, NAC_Z1), RED)
    b.box(side_box(s, NAC_IN, NAC_IN + WALL, BELLY, DECK, NAC_Z1 - 0.8, NAC_Z1), RED)
    b.box(side_box(s, NAC_OUT - WALL, NAC_OUT, BELLY, DECK, NAC_Z1 - 0.8, NAC_Z1), RED)
    b.box(side_box(s, NAC_IN + WALL, NAC_OUT - WALL, BELLY + WALL, DECK - WALL, 141.0, 141.5), ENGINE)
    cx = X0 + s * 9.0
    b.along("cone", (cx - 1.5, cx + 1.5, 10.0, 13.0, 141.5, 143.5), (0, 0, 1), GREY)
    # Raked top of the intake: a wedge from the lip back over the duct.
    b.wedge(side_box(s, NAC_IN, NAC_OUT, DECK, DECK + 0.8, 136.0, NAC_Z1), (0, 0, 1), (0, -1, 0), BLACK)
    # Longerons under the top skin, wall to wall, so the nacelle's outer side
    # and the glove hang on wide joints. They stop short of the wheel well.
    b.box(side_box(s, NAC_IN + WALL, 8.9, DECK - WALL - 2.0, DECK - WALL, 96.0, 140.5), DARK)
    b.box(side_box(s, 8.9, NAC_OUT - WALL, DECK - WALL - 2.0, DECK - WALL, 116.0, 140.5), DARK)
    # Wheel well walls inside the nacelle.
    x0, x1, z0, z1 = MAIN_BAY
    b.box(side_box(s, x0 - WALL, x0, BELLY + WALL, DECK - WALL, z0 - 8.0, z1), DARK)
    b.box(side_box(s, x0, NAC_OUT - WALL, BELLY + WALL, DECK - WALL, z1, z1 + WALL), DARK)
    b.box(side_box(s, x0, NAC_OUT - WALL, 8.6, 9.1, z0 - 8.0, z0), DARK)   # roof over the door pocket


for s in SIDES:
    nacelle(s)

# Centre fuselage between the nacelles: tunnel roof, flat top, spine.
b.box((X0 - NAC_IN, X0 + NAC_IN, 10.0, 10.5, NAC_Z0, FF_Z0), BLACK)
b.box((X0 - NAC_IN, X0 + NAC_IN, DECK - WALL, DECK, BODY_LIFT_Z, FF_Z0), BLACK, ptype="aero_panel")
b.box((X0 - NAC_IN, X0 + NAC_IN, DECK - WALL, DECK, NAC_Z0, BODY_LIFT_Z), BLACK)
b.box((X0 - NAC_IN, X0 + NAC_IN, 10.0, DECK, NAC_Z0, NAC_Z0 + WALL), BLACK)
b.box((X0 - 2.5, X0 + 2.5, DECK, 17.0, 96.0, 126.0), BLACK)                    # spine
# Strips along the tunnel roof's edges, so each nacelle joins the middle of
# the jet over a deep joint.
for s in SIDES:
    b.box(side_box(s, NAC_IN - 1.5, NAC_IN, 10.5, 11.5, NAC_Z0 + WALL, FF_Z0 - WALL), BLACK)
# A beam under the flat top between the nacelles, aft, tying them together.
b.box((X0 - NAC_IN, X0 + NAC_IN, DECK - WALL - 2.0, DECK - WALL, NAC_Z0 + WALL, BODY_LIFT_Z), DARK)
b.wedge((X0 - 2.5, X0 + 2.5, DECK, 17.0, 88.0, 96.0), (0, 0, 1), (0, -1, 0), BLACK)
# Keel: a solid balsa beam down the middle, from the centre of the jet to
# the cockpit, that carries the nose's weight into the body. Hidden inside.
b.box((X0 - 1.5, X0 + 1.5, BELLY + WALL, 10.5, 112.0, 147.5), BLACK)
# Join the cockpit section to the nacelles: the bulkhead under the canopy fairing.
b.box((X0 - NAC_IN, X0 + NAC_IN, BELLY, DECK, FF_Z0 - WALL, FF_Z0), BLACK)
# Beaver tail between the nozzles, with a red edge.
b.box((X0 - 4.0, X0 + 4.0, 11.5, 13.0, 72.0, NAC_Z0), BLACK)
b.box((X0 - 4.0, X0 + 4.0, 11.5, 13.0, 71.4, 72.0), RED)

# Gun pack under the tunnel: two long cannons with depleted uranium shells.
GUN_Z0, GUN_Z1 = 110.0, 136.0
b.box((X0 - 2.7, X0 + 2.7, 5.5, 10.0, GUN_Z0, GUN_Z1), BLACK)
b.box((X0 - 4.4, X0 + 4.4, BELLY, 10.0, GUN_Z0, GUN_Z1), BLACK)
b.wedge((X0 - 4.4, X0 + 4.4, 5.5, BELLY, GUN_Z0 - 4.0, GUN_Z0), (0, 0, 1), (0, 1, 0), BLACK)
CANNONS = []
for s in SIDES:
    CANNONS.append(b.add("large_cannon", side_box(s, 2.7, 4.3, 5.5, 7.0, GUN_Z0, GUN_Z1 + 2.0),
                         ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), GREY,
                         settings={"projectile_material": "Depleted uranium", "unlimited_ammo": True}))
# Nose guns either side of the radome's root.
GUNS = []
for s in SIDES:
    GUNS.append(b.add("machine_gun", side_box(s, FF_X, FF_X + 1.0, 9.0, 10.0, 160.0, 163.0),
                      ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), GREY,
                      settings={"fire_rate": 25.0, "range": 1500.0, "unlimited_ammo": True}))

# ---------------------------------------------------------------------------
# Gloves: the fixed inner wing, with the pivots under them.
GLOVE_Y0, GLOVE_Y1 = 14.5, 16.0
PIVOT_DX, PIVOT_Z = 19.5, 119.0
PIVOTS = {}
for s in SIDES:
    # Leading edge from the intake lip out to the pivot.
    b.tri_panel(side_box(s, NAC_OUT, 20.5, GLOVE_Y0, GLOVE_Y1, 123.0, 147.0), (0, 0, 1), (s, 0, 0), BLACK)
    b.box(side_box(s, NAC_OUT, 21.5, GLOVE_Y0, GLOVE_Y1, 107.0, 123.0), BLACK, ptype="aero_panel")
    b.flat_tri(side_box(s, NAC_OUT, 17.5, GLOVE_Y0, GLOVE_Y1, 94.0, 107.0), (s, 0, 0), (0, 0, -1), BLACK)
    # Red leading edge strip.
    b.tri_panel(side_box(s, NAC_OUT, 20.5, GLOVE_Y1, GLOVE_Y1 + 0.05, 123.0, 147.0), (0, 0, 1), (s, 0, 0), RED,
                ptype="aero_panel_triangle_dragless")
    b.tri_panel(side_box(s, NAC_OUT, 20.0, GLOVE_Y1 + 0.05, GLOVE_Y1 + 0.1, 124.5, 147.0), (0, 0, 1), (s, 0, 0), BLACK,
                ptype="aero_panel_triangle_dragless")
    # Pivot fairing.
    b.along("cylinder", side_box(s, 19.5, 22.5, GLOVE_Y0, GLOVE_Y1, PIVOT_Z - 1.5, PIVOT_Z + 1.5), (0, 1, 0), BLACK)
    # The sweep servo hangs under the glove; the wing hangs from its output.
    PIVOTS[s] = b.add("servo", side_box(s, PIVOT_DX - 1.5, PIVOT_DX + 1.5, 13.8, 15.0, PIVOT_Z - 1.5, PIVOT_Z + 1.5),
                      ([1, 0, 0], [0, -1, 0], [0, 0, -1]), DARK,
                      settings={"default_angle": 0.0, "positive_angle": 48.0 * s, "negative_angle": 0.0,
                                "speed": 15.0, "easing": 30.0, "max_torque": 5000000.0,
                                "when_idle": "Return to default angle"})

# ---------------------------------------------------------------------------
# Wings: each hangs from its sweep servo. The trailing edge is two split
# surfaces, each a top and a bottom panel on door hinge servos.
WING_Y0, WING_Y1 = 13.0, 13.8
HINGE_Z = 108.0                       # back of the wing box, front of the hinges
SURF_Z0 = 103.0                       # trailing edge of the surfaces
TIP_DX = 58.6
LE_ROOT_Z, LE_TIP_Z = 125.0, 112.4
WING_SEGS = [(30.2, 44.0), (44.4, 58.4)]     # inboard, outboard surfaces (dx)
SURFACES = {}    # (side, seg, "top"/"bottom") -> servo index
TOP_AXES = ([-1, 0, 0], [0, 0, -1], [0, -1, 0])
BOTTOM_AXES = ([1, 0, 0], [0, 0, -1], [0, 1, 0])


def split_surface(s, dx0, dx1, y0, y1, hinge_z, chord, name):
    """A split trailing edge: two door hinge servos (top and bottom) just
    behind hinge_z, each with a thin panel behind it."""
    mid = (y0 + y1) / 2
    servo_settings = {"default_angle": 0.0, "positive_angle": 60.0, "negative_angle": -60.0,
                      "speed": 120.0, "easing": 900.0, "max_torque": 300000.0,
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


for s in SIDES:
    # The wing box: under the glove at the root, out to the tip.
    b.box(side_box(s, 17.8, 30.0, WING_Y0, WING_Y1, SURF_Z0, LE_ROOT_Z), BLACK, ptype="aero_panel")
    b.box(side_box(s, 30.0, TIP_DX, WING_Y0, WING_Y1, HINGE_Z, LE_TIP_Z), BLACK, ptype="aero_panel")
    b.tri_panel(side_box(s, 30.0, TIP_DX, WING_Y0, WING_Y1, LE_TIP_Z, LE_ROOT_Z), (s, 0, 0), (0, 0, 1), BLACK)
    # Red tip cap and a red band near the tip.
    b.box(side_box(s, TIP_DX, TIP_DX + 0.6, WING_Y0, WING_Y1, SURF_Z0 + 0.5, LE_TIP_Z), RED)
    b.box(side_box(s, 52.0, 54.0, WING_Y1, WING_Y1 + 0.05, HINGE_Z, LE_TIP_Z - 0.5), RED, ptype="aero_panel_dragless")
    # Gap filler between the two surfaces.
    b.box(side_box(s, 44.1, 44.3, WING_Y0, WING_Y1, SURF_Z0 + 1.0, HINGE_Z), BLACK)
    split_surface(s, WING_SEGS[0][0], WING_SEGS[0][1], WING_Y0, WING_Y1, HINGE_Z, 4.0, "inboard")
    split_surface(s, WING_SEGS[1][0], WING_SEGS[1][1], WING_Y0, WING_Y1, HINGE_Z, 4.0, "outboard")
    # Navigation light on each tip: red on the left, green on the right.
    lamp = b.add("light_panel", side_box(s, TIP_DX + 0.6, TIP_DX + 0.725, 13.1, 13.7, 108.0, 110.0),
                 ([0, 0, 1], [s, 0, 0], [0, s, 0]),
                 "#ff2222" if s > 0 else "#22ff44",
                 settings={"color": "#ff2222" if s > 0 else "#22ff44", "brightness": 2.0})

# ---------------------------------------------------------------------------
# Tail: horizontal stabilisers with split elevators, twin fins with rudders.
STAB_Y0, STAB_Y1 = 12.0, 12.6
for s in SIDES:
    b.box(side_box(s, NAC_OUT, 28.0, STAB_Y0, STAB_Y1, 73.0, 77.0), BLACK, ptype="aero_panel")
    b.tri_panel(side_box(s, NAC_OUT, 28.0, STAB_Y0, STAB_Y1, 77.0, 96.0), (s, 0, 0), (0, 0, 1), BLACK)
    b.box(side_box(s, 28.0, 28.6, STAB_Y0, STAB_Y1, 73.0, 77.0), RED)
    split_surface(s, 13.6, 27.8, STAB_Y0, STAB_Y1, 73.0, 4.0, "stab")
    # Root fairing: a thick block the stabiliser's root is set into, so its
    # load goes into the nacelle wall over a wide joint.
    b.box(side_box(s, NAC_OUT, NAC_OUT + 1.4, 11.6, 12.8, 74.0, 96.0), BLACK)

FIN_DX = 9.0
RUDDERS = []
for s in SIDES:
    x0, x1 = X0 + s * FIN_DX - 0.25, X0 + s * FIN_DX + 0.25
    b.tri_panel((x0, x1, DECK, 29.5, 80.0, 96.0), (0, 0, 1), (0, 1, 0), BLACK)
    b.box((x0 - 0.03, x1 + 0.03, 27.0, 29.5, 80.0, 82.0), RED, ptype="aero_panel_dragless")
    rudder = b.add("door_hinge_servo", (x0, x1, 16.6, 29.0, 79.0, 80.0),
                   ([0, 1, 0], [0, 0, -1], [-1, 0, 0]), DARK,
                   settings={"default_angle": 0.0, "positive_angle": 30.0, "negative_angle": -30.0,
                             "speed": 90.0, "easing": 600.0, "max_torque": 300000.0,
                             "when_idle": "Return to default angle"})
    b.box((x1 - 0.2, x1, 16.7, 28.9, 74.0, 79.0), BLACK, ptype="aero_panel")
    b.box((x1 - 0.23, x1 + 0.03, 26.5, 28.9, 74.0, 74.6), RED)
    RUDDERS.append(rudder)

# ---------------------------------------------------------------------------
# Engines: each nozzle turns on a servo for thrust vectoring, carrying a
# hidden thruster and the lights that glow with the throttle.
ENG_Y = 11.5
NOZZLES, THRUSTERS, LIGHTS_RING, LIGHTS_CORE = [], [], [], []
for s in SIDES:
    cx = X0 + s * 9.0
    # Mount on the nacelle's tail plate, touching only the servo's base.
    b.box((cx - 1.0, cx + 0.45, ENG_Y - 1.0, ENG_Y + 1.0, 82.0, NAC_Z0), DARK)
    servo = b.add("servo", (cx - 1.0, cx + 1.0, ENG_Y - 1.0, ENG_Y + 1.0, 80.0, 82.0),
                  ([0, 0, 1], [1, 0, 0], [0, 1, 0]), DARK,
                  settings={"default_angle": 0.0, "positive_angle": 20.0, "negative_angle": -20.0,
                            "speed": 60.0, "easing": 400.0, "max_torque": 2000000.0,
                            "when_idle": "Return to default angle"})
    NOZZLES.append(servo)
    # Hub on the servo's output face (+X), then the nozzle can round it.
    b.box((cx + 1.0, cx + 1.6, ENG_Y - 1.0, ENG_Y + 1.0, 78.5, 82.0), DARK)
    b.box((cx - 1.6, cx + 1.6, ENG_Y - 1.4, ENG_Y + 1.4, 77.9, 78.5), DARK)
    # Nozzle: eight-sided can of black petals.
    r_out = 3.4
    for (a0, a1, b0, b1) in [(-r_out, r_out, r_out - 0.6, r_out), (-r_out, r_out, -r_out, -r_out + 0.6),
                             (-r_out, -r_out + 0.6, -r_out + 0.6, r_out - 0.6),
                             (r_out - 0.6, r_out, -r_out + 0.6, r_out - 0.6)]:
        b.box((cx + a0, cx + a1, ENG_Y + b0, ENG_Y + b1, 73.0, 82.6), ENGINE)
    for (fx, fy) in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
        bx = (cx + fx * (r_out - 0.6) - (1.0 if fx > 0 else 0), cx + fx * (r_out - 0.6) + (0 if fx > 0 else 1.0))
        by = (ENG_Y + fy * (r_out - 0.6) - (1.0 if fy > 0 else 0), ENG_Y + fy * (r_out - 0.6) + (0 if fy > 0 else 1.0))
        b.corner((min(bx), max(bx), min(by), max(by), 73.0, 82.6), (-fx, 0, 0), (0, -fy, 0), (0, 0, -1), ENGINE)
    # Petal ring at the exit, slightly flared, and the turbine face inside.
    # The turbine face is a thick plug that fills the can up to the hub, so
    # each petal and the hub join it over a wide face and the engine's push
    # has a strong path.
    b.box((cx - 2.8, cx + 2.8, ENG_Y - 2.8, ENG_Y + 2.8, 77.5, 79.9), "#1a1110")
    # Hidden thruster in the middle of the nozzle. Steel, so the nozzle's
    # own heft takes the engine's push rather than its balsa petals.
    THRUSTERS.append(b.add("thruster", (cx - 1.0, cx + 1.0, ENG_Y - 1.0, ENG_Y + 1.0, 75.5, 77.5),
                           ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), ENGINE, material="steel",
                           settings={"thrust": THRUST, "ideal": True}))
    # Lights at the exit: a hot core and four glowing quarters round it.
    LIGHTS_CORE.append(b.add("light_panel", (cx - 1.0, cx + 1.0, ENG_Y - 1.0, ENG_Y + 1.0, 75.38, 75.5),
                             ([1, 0, 0], [0, 0, -1], [0, 1, 0]), "#ffd36a",
                             settings={"color": "#ffd36a", "brightness": 5.0}))
    for (qx, qy) in [(-2.75, -1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -2.75)]:
        w = 1.75 if qx in (-2.75, 1.0) else 2.0
        h = 2.0 if qx in (-2.75, 1.0) else 1.75
        if qy == 1.0:
            box = (cx - 1.0, cx + 1.0, ENG_Y + 1.0, ENG_Y + 2.75, 76.4, 76.525)
        elif qy == -2.75:
            box = (cx - 1.0, cx + 1.0, ENG_Y - 2.75, ENG_Y - 1.0, 76.4, 76.525)
        elif qx == -2.75:
            box = (cx - 2.75, cx - 1.0, ENG_Y - 1.0, ENG_Y + 1.0, 76.4, 76.525)
        else:
            box = (cx + 1.0, cx + 2.75, ENG_Y - 1.0, ENG_Y + 1.0, 76.4, 76.525)
        LIGHTS_RING.append(b.add("light_panel", box, ([1, 0, 0], [0, 0, -1], [0, 1, 0]), "#ff5a14",
                                 settings={"color": "#ff5a14", "brightness": 3.0}))
    # And the four corners, so the glow fills the nozzle. These don't throw
    # light of their own (the game lights only the first 24 panels).
    for (fx, fy) in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
        xa, xb = sorted((cx + fx * 1.0, cx + fx * 2.75))
        ya, yb = sorted((ENG_Y + fy * 1.0, ENG_Y + fy * 2.75))
        LIGHTS_RING.append(b.add("light_panel", (xa, xb, ya, yb, 76.4, 76.525), ([1, 0, 0], [0, 0, -1], [0, 1, 0]),
                                 "#ff5a14", settings={"color": "#ff5a14", "brightness": 1.5}))
    # The light frames hold onto the hub: a cross of thin bars behind them,
    # broken where the thruster sits.
    for (a0, a1) in [(-2.75, -1.0), (1.0, 2.75)]:
        b.box((cx + a0, cx + a1, ENG_Y - 0.15, ENG_Y + 0.15, 76.525, 77.9), "#1a1110")
        b.box((cx - 0.15, cx + 0.15, ENG_Y + a0, ENG_Y + a1, 76.525, 77.9), "#1a1110")

# ---------------------------------------------------------------------------
# Landing gear: each leg a piston that pulls it up into its well, and a door
# that slides forward under it once it is up.
GEAR_TRAVEL = 8.2
DOOR_PISTONS, GEAR_PISTONS = [], []


def gear_leg(cx, cz, wheel_d, wheel_w, wheels, steer=False):
    """A leg at (cx, cz) whose piston sits in the belly opening. wheels: list
    of x offsets of each wheel's middle."""
    # Piston, pointing down, low in the well so it has room to rise.
    # The gear is steel: light parts between a heavy airframe and the ground
    # make the physics joints soft and bouncy.
    p = b.add("piston", (cx - 0.9, cx + 0.9, BELLY, BELLY + 1.5, cz - 0.9, cz + 0.9),
              ([1, 0, 0], [0, -1, 0], [0, 0, -1]), GREY, material="steel",
              settings={"current_length": GEAR_TRAVEL, "target_length": 0.0, "max_length": GEAR_TRAVEL,
                        "speed": 1.2, "easing": 2.0, "max_force": 2000000.0,
                        "when_idle": "Return to starting length"})
    GEAR_PISTONS.append(p)
    top = BELLY       # the piston's rod end, its lower face
    steer_servo = None
    if steer:
        steer_servo = b.add("servo", (cx - 0.9, cx + 0.9, top - 1.5, top, cz - 0.9, cz + 0.9),
                            ([1, 0, 0], [0, -1, 0], [0, 0, -1]), GREY, material="steel",
                            settings={"default_angle": 0.0, "positive_angle": 30.0, "negative_angle": -30.0,
                                      "speed": 60.0, "easing": 400.0, "max_torque": 100000.0,
                                      "when_idle": "Return to default angle"})
        top -= 1.5
    axle_y = wheel_d / 2
    # Strut down to the axle beam.
    b.box((cx - 0.4, cx + 0.4, axle_y + 0.6, top, cz - 0.4, cz + 0.4), METAL, material="steel")
    xs = [cx + o for o in wheels]
    lo = min(xs) + wheel_w / 2 if len(xs) > 1 else cx - 0.4
    hi = max(xs) - wheel_w / 2 if len(xs) > 1 else cx + 0.4
    if len(xs) == 1:
        # One wheel beside the strut: a fork on the strut's side.
        o = wheels[0]
        if o > 0:
            lo, hi = cx - 0.4, cx + o - wheel_w / 2
        else:
            lo, hi = cx + o + wheel_w / 2, cx + 0.4
    b.box((lo, hi, axle_y - 0.6, axle_y + 0.6, cz - 0.5, cz + 0.5), METAL, material="steel")
    for x in xs:
        b.add("wheel", (x - wheel_w / 2, x + wheel_w / 2, 0.0, wheel_d, cz - wheel_d / 2, cz + wheel_d / 2),
              IDENT, "#151515", material="aluminum", settings={"free_spinning": True, "friction": 20.0})
    # Mount the piston's barrel to the well sides.
    return p, steer_servo


def door(x0, x1, pocket_z0, pocket_z1, travel):
    """A door waiting in a pocket inside the belly, aft of its well, and the
    piston behind it that slides it forward by `travel`."""
    d = b.box((x0 + 0.05, x1 - 0.05, BELLY + WALL + 0.05, BELLY + WALL + 0.45, pocket_z0 + 0.05, pocket_z1 - 0.05), DARK)
    cx = (x0 + x1) / 2
    p = b.add("piston", (cx - 0.7, cx + 0.7, BELLY + WALL + 0.05, BELLY + WALL + 0.95, pocket_z0 - 1.95, pocket_z0 + 0.05),
              ([1, 0, 0], [0, 0, 1], [0, -1, 0]), GREY,
              settings={"current_length": 0.0, "target_length": travel, "max_length": travel,
                        "speed": 1.6, "easing": 3.0, "max_force": 50000.0,
                        "when_idle": "Return to starting length"})
    DOOR_PISTONS.append(p)
    # The block the piston pushes from, at the back of the pocket.
    b.box((cx - 0.7, cx + 0.7, BELLY + WALL, BELLY + WALL + 1.0, pocket_z0 - 2.5, pocket_z0 - 1.95), DARK)
    return d


# Nose gear: twin wheels, steerable, in front of the cockpit.
NOSE_X, NOSE_Z = X0, 161.5
nose_piston, NOSE_STEER = gear_leg(NOSE_X, NOSE_Z, 3.2, 1.1, [-1.3, 1.3], steer=True)
for s in SIDES:   # barrel mounts out to the well walls, aluminium, on wide plates
    b.box(side_box(s, 0.9, 2.4, BELLY + 0.4, BELLY + 1.5, NOSE_Z - 0.9, NOSE_Z + 0.9), DARK, material="aluminum")
    b.box(side_box(s, 2.2, 2.4, BELLY + WALL, 12.0, 158.5, 164.5), DARK, material="aluminum")
door(NOSE_POCKET[0], NOSE_POCKET[1], NOSE_POCKET[2], NOSE_POCKET[3], NOSE_BAY[3] - NOSE_BAY[2])

# Main gear: one big wheel each side, under the nacelles.
MAIN_Z = (MAIN_BAY[2] + MAIN_BAY[3]) / 2
for s in SIDES:
    cx = X0 + s * 10.4
    gear_leg(cx, MAIN_Z, 5.2, 1.5, [s * 1.2])
    # Barrel mount: an aluminium plate on the inner well wall, wide so the
    # gear's jolts spread into the balsa.
    b.box(side_box(s, 9.4, 9.5, BELLY + WALL, 10.5, 108.2, 115.3), DARK, material="aluminum")
    x0, x1, z0, z1 = MAIN_BAY
    xa, xb = sorted((X0 + s * x0, X0 + s * x1))
    door(xa, xb, MAIN_POCKET[2], MAIN_POCKET[3], z1 - z0)

# ---------------------------------------------------------------------------
# Missiles: two under each glove, held by electromagnets.
MISSILES = []    # (magnet, rocket, detector, explosive)


def missile(cx, cz0, length=19.0):
    d = 1.2
    y0, y1 = 12.6 - 0.05 - d, 12.6 - 0.05
    yc = (y0 + y1) / 2
    z = cz0
    rocket = b.add("solid_rocket", (cx - d / 2, cx + d / 2, y0, y1, z, z + 7.0),
                   ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), WHITE,
                   settings={"thrust": 9000.0, "burn_time": 5.0, "ideal": False})
    b.along("cylinder", (cx - d / 2, cx + d / 2, y0, y1, z + 7.0, z + 12.0), (0, 0, 1), WHITE)
    det = b.add("impact_detector", (cx - 0.45, cx + 0.45, yc - 0.45, yc + 0.45, z + 12.0, z + 12.9),
                IDENT, RED, settings={"threshold": 40.0, "pulse": 0.2})
    b.along("cylinder", (cx - d / 2, cx + d / 2, y0, y1, z + 12.9, z + 13.4), (0, 0, 1), RED)
    exp = b.add("explosive_block", (cx - d / 2, cx + d / 2, y0, y1, z + 13.4, z + 16.0), IDENT, WHITE,
                settings={"blast_radius": 4.0})
    b.along("cone", (cx - d / 2, cx + d / 2, y0, y1, z + 16.0, z + length), (0, 0, 1), WHITE)
    # Fins: a cross at the tail and a smaller one forward.
    for (zf, span, chord) in [(z, 0.7, 2.2), (z + 13.6, 0.5, 1.5)]:
        for (ux, uy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            if ux:
                xa = cx + ux * d / 2
                fb = (min(xa, xa + ux * span), max(xa, xa + ux * span), yc - 0.05, yc + 0.05, zf, zf + chord)
            else:
                ya = yc + uy * d / 2
                if uy > 0:
                    continue   # no top fin: it would touch the rail
                fb = (cx - 0.05, cx + 0.05, min(ya, ya + uy * span), max(ya, ya + uy * span), zf, zf + chord)
            b.tri_panel(fb, (ux, uy, 0), (0, 0, 1), WHITE)
    # The magnet on the pylon above it, face down, a hair off the missile.
    mag = b.add("magnet", (cx - 0.3, cx + 0.3, 12.6, 12.85, z + 5.0, z + 13.0),
                ([1, 0, 0], [0, -1, 0], [0, 0, -1]), GREY,
                settings={"strength": 2000000.0, "on_unlinked": True, "grabs_ground": False})
    # Pylon up to the glove.
    b.box((cx - 0.3, cx + 0.3, 12.85, GLOVE_Y0, z + 6.0, z + 12.0), BLACK)
    MISSILES.append((mag, rocket, det, exp))


for s in SIDES:
    missile(X0 + s * 14.6, 117.0)
    missile(X0 + s * 17.4, 112.0)

# ---------------------------------------------------------------------------
# Sensors inside the centre fuselage.
ATT = b.add("attitude_sensor", (X0 - 0.5, X0 + 0.5, 10.5, 11.5, 118.0, 119.0),
            ([-1, 0, 0], [0, 1, 0], [0, 0, -1]), DARK)
SPEED = b.add("speed_sensor", (X0 - 0.5, X0 + 0.5, 10.5, 11.5, 120.0, 121.0), IDENT, DARK)
DIST = b.add("distance_sensor", (X0 - 0.5, X0 + 0.5, 9.5, 10.0, 100.0, 101.0),
             ([1, 0, 0], [0, 0, -1], [0, 1, 0]), DARK, settings={"range": 60.0})
# Anti-collision beacon on the spine.
BEACON = b.add("light_panel", (X0 - 0.5, X0 + 0.5, 17.0, 17.125, 110.0, 111.0), IDENT, "#ff1010",
               settings={"color": "#ff1010", "brightness": 3.0})

# ---------------------------------------------------------------------------
# Controls. Each control reads a controller and its keyboard twin together.
pad_pitch = pad("Left stick Y (up +)", curve=1.6, deadzone=0.1)
key_pitch = key("W", second="S")
pitch_in = gate("Add", V(pad_pitch), V(key_pitch))
pad_roll = pad("Left stick X (right +)", curve=1.6, deadzone=0.1)
key_roll = key("D", second="A")
roll_in = gate("Add", V(pad_roll), V(key_roll))
pad_yaw = pad("D-pad right", second="D-pad left")
key_yaw = key("X", second="Z")
yaw_in = gate("Add", V(pad_yaw), V(key_yaw))

# Throttle: the right trigger, M for cruise, K for full afterburner.
pad_rt = pad("RT / R2 trigger", deadzone=0.05)
key_k = key("K")
key_m = key("M", mode="Toggle")
cruise = gate("Multiply", V(key_m), value=0.55)
t1 = gate("Max", V(pad_rt), R(cruise))
throttle = gate("Max", R(t1), V(key_k))
engines_on = gate("Compare", R(throttle), value=0.02)
burner = gate("Compare", R(throttle), value=0.9)

# Gain schedule: the surfaces bite harder the faster the jet goes, so the
# stability system's commands are scaled by (120 m/s / speed) squared,
# between 0.2 and 1.3.
v2 = gate("Multiply", (SPEED, "speed"), (SPEED, "speed"))
v2_floor = gate("Max", R(v2), value=11077.0)
k_const = gate("Constant", value=14400.0)
sched_raw = gate("Divide", R(k_const), R(v2_floor))
sched = gate("Max", R(sched_raw), value=0.2)
# Below about 25 m/s the stability system lets go and the sticks move the
# surfaces straight; it takes over fully by 55 m/s. On the ground its
# setpoints follow what it measures, so nothing winds up before takeoff.
v_over = gate("Subtract", (SPEED, "speed"), value=25.0)
v_share = gate("Multiply", R(v_over), value=1.0 / 30.0)
fade = gate("Clamp", R(v_share), value=1.0)
one = gate("Constant", value=1.0)
unfade = gate("Subtract", R(one), R(fade))


def stability_axis(stick, rate_per_unit, measured, pid_settings, direct_gain):
    """A rate-command, attitude-hold loop for one axis, with the stick moving
    the surfaces straight at low speed. Returns the command, in degrees.
    rate_per_unit is a number (a float), or the index of a gate whose result
    is the rate."""
    if isinstance(rate_per_unit, int):
        cmd = gate("Multiply", R(stick), R(rate_per_unit))
    else:
        cmd = gate("Multiply", R(stick), value=rate_per_unit)
    err = gate("Subtract", R(cmd), measured)
    err_f = gate("Multiply", R(err), R(fade))
    setpoint = gate("Add", measured, R(err_f))
    pid = logic("pid_controller", pid_settings, {"setpoint": R(setpoint), "measurement": measured})
    flying = gate("Multiply", O(pid), R(sched))
    direct = gate("Multiply", R(stick), value=direct_gain)
    direct_f = gate("Multiply", R(direct), R(unfade))
    return gate("Add", R(flying), R(direct_f))


# Pitch: the stick asks for a pitch rate; let go and the attitude holds.
# Full stick asks for 22 degrees a second, or less when fast: no more than
# about 5 g (rate = 5 g / speed), so a full pull won't tear the balsa apart.
v_floor = gate("Max", (SPEED, "speed"), value=60.0)
g_cap = gate("Constant", value=5.0 * 9.81 * 57.2958)
g_rate = gate("Divide", R(g_cap), R(v_floor))
pitch_rate = gate("Min", R(g_rate), value=22.0)
P_ = stability_axis(pitch_in, pitch_rate, (ATT, "pitch_rate"),
                    {"kp": 1.1, "ki": 0.9, "kd": 0.0, "output_min": -28.0, "output_max": 28.0}, 25.0)
# Roll: the stick asks for a roll rate; let go and the bank holds.
R_ = stability_axis(roll_in, 110.0, (ATT, "roll_rate"),
                    {"kp": 0.35, "ki": 0.15, "kd": 0.0, "output_min": -40.0, "output_max": 40.0}, 30.0)
# Yaw: the D-pad asks for a yaw rate; the rudders also damp any wagging.
Y_ = stability_axis(yaw_in, 14.0, (ATT, "yaw_rate"),
                    {"kp": 1.2, "ki": 0.0, "kd": 0.0, "output_min": -30.0, "output_max": 30.0}, 25.0)

# Air brake: D-pad down (or Q) opens every split surface both ways.
pad_brake = pad("D-pad down")
key_brake = key("Q")
brake_on = bgate("OR", P(pad_brake), P(key_brake))
brake = gate("Multiply", (brake_on, "result"), value=55.0)

# Mixing. A positive deflection lifts the trailing edge (the top panel
# opens); a negative one drops it (the bottom panel opens). Stick back lifts
# every trailing edge; stick right lifts the right side and drops the left.
half_r = gate("Multiply", R(R_), value=0.5)
p06 = gate("Multiply", R(P_), value=0.6)
SIGN_TOP, SIGN_BOTTOM = -1.0, -1.0    # positive turns both leaves inward, so both are flipped
deflection = {
    (-1, "inboard"): gate("Add", R(P_), R(half_r)),
    (1, "inboard"): gate("Subtract", R(P_), R(half_r)),
    (-1, "outboard"): gate("Add", R(p06), R(R_)),
    (1, "outboard"): gate("Subtract", R(p06), R(R_)),
}
# The stabilisers roll the jet too, like the real Tomcat's rolling tail.
deflection[(-1, "stab")] = gate("Add", R(P_), R(R_))
deflection[(1, "stab")] = gate("Subtract", R(P_), R(R_))
opened = {}
for key_, dsrc in list(deflection.items()):
    if dsrc in opened:
        top_g, bottom_g = opened[dsrc]
    else:
        neg_d = gate("Multiply", R(dsrc), value=-1.0)
        top_g = gate("Max", R(dsrc), R(brake))
        bottom_g = gate("Max", R(neg_d), R(brake))
        if SIGN_TOP < 0:
            top_g = gate("Multiply", R(top_g), value=-1.0)
        if SIGN_BOTTOM < 0:
            bottom_g = gate("Multiply", R(bottom_g), value=-1.0)
        opened[dsrc] = (top_g, bottom_g)
    s, name = key_
    b.link(SURFACES[(s, name, "top")], "angle", top_g, "result")
    b.link(SURFACES[(s, name, "bottom")], "angle", bottom_g, "result")
for r in RUDDERS:
    b.link(r, "angle", Y_, "result")
# Thrust vectoring follows the pitch command.
vector = gate("Multiply", R(P_), value=0.7)
for n in NOZZLES:
    b.link(n, "angle", vector, "result")
# Nose wheel steering from the yaw input.
steer = gate("Multiply", R(yaw_in), value=25.0)
b.link(NOSE_STEER, "angle", steer, "result")
# Engines.
for t in THRUSTERS:
    b.link(t, "throttle", throttle, "result")
    b.link(t, "on", engines_on, "is_true")
ring_r = gate("Multiply", R(throttle), value=255.0)
ring_g = gate("Multiply", R(throttle), value=80.0)
zero = gate("Constant", value=0.0)
core_g = gate("Multiply", R(throttle), value=200.0)
core_b = gate("Multiply", T(burner), value=170.0)
for l in LIGHTS_RING:
    b.link(l, "on", engines_on, "is_true")
    b.link(l, "red", ring_r, "result")
    b.link(l, "green", ring_g, "result")
    b.link(l, "blue", zero, "result")
for l in LIGHTS_CORE:
    b.link(l, "on", engines_on, "is_true")
    b.link(l, "red", ring_r, "result")
    b.link(l, "green", core_g, "result")
    b.link(l, "blue", core_b, "result")
beacon = logic("pwm_generator", {"frequency": 1.0, "duty": 12.0})
b.link(BEACON, "on", beacon, "output")

# Wings: V on the keyboard or LB on the controller sweeps them back and forth.
key_v = key("V", mode="Toggle")
pad_lb = pad("LB / L1", mode="Toggle")
sweep = bgate("XOR", P(key_v), P(pad_lb))
for s in SIDES:
    b.link(PIVOTS[s], "go_positive", sweep, "result")

# Landing gear: D-pad up (or G) asks for gear up. The gear only goes up once
# off the ground; the doors close after it is in, and open before it comes
# down.
pad_gear = pad("D-pad up", mode="Toggle")
key_gear = key("G", mode="Toggle")
gear_wanted = bgate("XOR", P(pad_gear), P(key_gear))
airborne = gate("Compare", (DIST, "distance"), value=5.0)
go_up = bgate("AND", (gear_wanted, "result"), T(airborne))
not_wanted = bgate("NOT", (gear_wanted, "result"))
gear_up = bgate("Latch", (go_up, "result"), (not_wanted, "result"))
been_up = bgate("Latch", (gear_up, "result"))
closing_wait = bgate("Timer", (gear_up, "result"), seconds=2.6)
not_closing_wait = bgate("NOT", (closing_wait, "result"))
doors_shut = bgate("AND", (gear_up, "result"), (not_closing_wait, "result"))
gear_down_wanted = bgate("NOT", (gear_up, "result"))
opening_wait = bgate("Timer", (gear_down_wanted, "result"), seconds=2.2)
hold_up = bgate("AND", (opening_wait, "result"), (been_up, "result"))
retract = bgate("OR", (gear_up, "result"), (hold_up, "result"))
for p in GEAR_PISTONS:
    b.link(p, "extend", retract, "result")
for p in DOOR_PISTONS:
    b.link(p, "extend", doors_shut, "result")

# Guns: B (or the left mouse button) fires the nose guns, A (or F) the
# cannons.
pad_b = pad("B / Circle")
mouse_l = logic("mouse_click", {"button": "Left", "mode": "Hold"})
guns = bgate("OR", P(pad_b), P(mouse_l))
for g in GUNS:
    b.link(g, "fire", guns, "result")
pad_a = pad("A / Cross")
key_f = key("F")
cannons = bgate("OR", P(pad_a), P(key_f))
for c in CANNONS:
    b.link(c, "fire", cannons, "result")

# Missiles: each press of Y (or R) lets the next one go, inner pair first.
pad_y = pad("Y / Triangle", mode="Toggle")
key_r = key("R", mode="Toggle")
salvo = bgate("XOR", P(pad_y), P(key_r))
not_salvo = bgate("NOT", (salvo, "result"))
f1 = bgate("Latch", (salvo, "result"))
c2 = bgate("AND", (not_salvo, "result"), (f1, "result"))
f2 = bgate("Latch", (c2, "result"))
c3 = bgate("AND", (salvo, "result"), (f2, "result"))
f3 = bgate("Latch", (c3, "result"))
c4 = bgate("AND", (not_salvo, "result"), (f3, "result"))
f4 = bgate("Latch", (c4, "result"))
order = [MISSILES[0], MISSILES[2], MISSILES[1], MISSILES[3]]
for (mag, rocket, det, exp), fire in zip(order, [f1, f2, f3, f4]):
    hold = bgate("NOT", (fire, "result"))
    b.link(mag, "on", hold, "result")
    b.link(rocket, "ignite", fire, "result")
    # The warhead arms 0.8 s after launch, well clear of the jet.
    safe = bgate("Timer", (fire, "result"), seconds=0.8)
    armed = bgate("AND", (fire, "result"), (bgate("NOT", (safe, "result")), "result"))
    boom = bgate("AND", (armed, "result"), (det, "triggered"))
    b.link(exp, "detonate", boom, "result")

b.write(OUT)
# Names of the parts the systems test looks at, by index in the file.
import json  # noqa: E402
names = {"seat": SEAT, "att": ATT, "speed": SPEED, "dist": DIST,
         "pivot_L": PIVOTS[1], "pivot_R": PIVOTS[-1], "nozzle_L": NOZZLES[0], "nozzle_R": NOZZLES[1],
         "rudder_L": RUDDERS[0], "rudder_R": RUDDERS[1], "steer": NOSE_STEER,
         "thrust_L": THRUSTERS[0], "thrust_R": THRUSTERS[1], "core_L": LIGHTS_CORE[0],
         "cannon_L": CANNONS[0], "gun_L": GUNS[0]}
for (s_, name, half), idx in SURFACES.items():
    names["%s_%s_%s" % (name, "L" if s_ > 0 else "R", half)] = idx
for i, p_ in enumerate(GEAR_PISTONS):
    names["gear_%d" % i] = p_
for i, p_ in enumerate(DOOR_PISTONS):
    names["door_%d" % i] = p_
for i, (mag, rocket, det, exp) in enumerate(MISSILES):
    names["missile_%d" % i] = rocket
    names["magnet_%d" % i] = mag
with open(OUT + ".names.json", "w") as f:
    json.dump(names, f)
print("parts", len(b.parts), "logic", _logic_slot[0])
