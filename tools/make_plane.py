"""Builds a scaled copy of the "advanced plane" with mixed controls.

    python3 tools/make_plane.py <original.json> <out.json> [scale] [--pid]

Keeps every part of the plane, drops the ground control station, scales the
plane about its middle and puts it in the middle of the build pad. New parts:
an all-moving delta rudder on the roof behind the cockpit-side of the fin,
and a logic pad on the floor that mixes the keys:

    W / S  elevators (nose up / down)
    D / A  ailerons (roll right / left)
    E / Q  flaperons: both ailerons together (nose up / down)
    X / Z  rudder (yaw right / left)
    K      main thruster, I nose lift thruster

With --pid the ailerons hold a bank angle: A/D ask for up to 35 degrees of
bank and letting go levels the wings.
"""
import json
import sys

SRC, OUT = sys.argv[1], sys.argv[2]
S = float(sys.argv[3]) if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else 1.5
USE_PID = "--pid" in sys.argv

src = json.load(open(SRC))
P = src["parts"]

STATION = {9, 10, 11, 12, 13, 14, 15, 30, 31, 32, 119}
LEFT_AIL, RIGHT_AIL, LEFT_ELEV, RIGHT_ELEV = 1, 4, 2, 3
MAIN_THRUST, NOSE_THRUST = 0, 118

# Original frame -> new frame.
CX, FLOOR, CZ = 66.5, 2.0, 43.0
NX, NFLOOR, NZ = 128.0, 1.0, 128.0


def place(p):
    return [round(NX + (p[0] - CX) * S, 5), round(NFLOOR + (p[1] - FLOOR) * S, 5), round(NZ + (p[2] - CZ) * S, 5)]


parts = []
new_index = {}
for i, p in enumerate(P):
    if i in STATION:
        continue
    q = json.loads(json.dumps(p))
    q["pos"] = place(p["pos"])
    q["size"] = [round(v * S, 5) for v in p["size"]]
    q.pop("links", None)
    new_index[i] = len(parts)
    parts.append(q)

# The block under the seat only met the hull wedges along their ridge lines,
# which no longer counts as touching once scaled up: reach it up to the seat.
SEAT_FLOOR = 114
q = parts[new_index[SEAT_FLOOR]]
q["size"][1] = round(1.25 * S, 5)
q["pos"][1] = round(NFLOOR + (5.625 - FLOOR) * S, 5)

# Main thrust grows with the area (S^2), so thrust against drag, and so the
# top speed, stays the original's; more would tear the balsa apart. The nose
# kicker lifts a nose S^3 heavier, so it grows with the mass.
parts[new_index[MAIN_THRUST]]["settings"]["thrust"] = round(50000.0 * S ** 2, 1)
parts[new_index[NOSE_THRUST]]["settings"]["thrust"] = round(5000.0 * S ** 3, 1)
for i in (LEFT_AIL, RIGHT_AIL, LEFT_ELEV, RIGHT_ELEV):
    s = parts[new_index[i]]["settings"]
    s["max_torque"] = round(50000.0 * S ** 4, 1)
    s["positive_angle"] = 0.0
    s["negative_angle"] = 0.0

BALSA = "#dec294"


def add(part):
    parts.append(part)
    return len(parts) - 1


# --- Delta rudder: servo on the roof, a pin, and a vertical triangle panel. ---
# Original-frame layout (scaled with everything else): roof top at y 9, the
# fixed fin starts at z 27, so the rudder sits on z 19.5..26.5.
def orig_part(ptype, pos, size, xa, ya, za, **extra):
    d = {"type": ptype, "material": "balsa", "color": BALSA, "pos": place(pos),
         "size": [round(v * S, 5) for v in size], "x_axis": xa, "y_axis": ya, "z_axis": za}
    d.update(extra)
    return d


rudder_servo = add(orig_part("servo", [66.5, 9.5, 23.5], [1, 1, 1], [1, 0, 0], [0, 1, 0], [0, 0, 1], settings={
    "default_angle": 0.0, "easing": 400.0, "max_torque": round(30000.0 * S ** 4, 1), "negative_angle": 0.0,
    "positive_angle": 0.0, "speed": 16.0, "when_idle": "Return to default angle"}))
add(orig_part("cylinder", [66.5, 10.5, 23.5], [0.5, 1, 0.5], [1, 0, 0], [0, 1, 0], [0, 0, 1]))
add(orig_part("aero_panel_triangle", [66.5, 14.0, 23.0], [6, 0.125, 7], [0, 1, 0], [1, 0, 0], [0, 0, -1]))

sensor = None
if USE_PID:
    # Attitude sensor on the roof: blue Z toward the tail, green Y up.
    sensor = add(orig_part("attitude_sensor", [66.5, 9.5, 45.5], [1, 1, 1], [-1, 0, 0], [0, 1, 0], [0, 0, -1]))

# --- Logic on the roof, in two rows either side of the fin, so the plane
# carries its own controls. Original-frame roof top: y 9, x 65..68, z 20..58.
roof_top = NFLOOR + (9.0 - FLOOR) * S
xs = [NX - 1.5 * S + 0.5, NX + 1.5 * S - 0.5]     # the roof's outer cells
z0, z1 = NZ + (40.0 - CZ) * S, NZ + (57.0 - CZ) * S
sensor_z = NZ + (45.5 - CZ) * S
slots = iter([(x, z + 0.5) for z in range(int(z0), int(z1)) for x in xs
              if abs(z + 0.5 - sensor_z) > 1.5 * S])


def logic(ptype, settings, links=None):
    x, z = next(slots)
    d = {"type": ptype, "material": "frictionless", "color": "#e6f5ff", "pos": [x, roof_top + 0.25, z],
         "size": [1.0, 0.5, 1.0], "x_axis": [1, 0, 0], "y_axis": [0, 1, 0], "z_axis": [0, 0, 1],
         "settings": settings}
    if links:
        d["links"] = links
    return add(d)


def two_keys(key, second):
    return logic("input_block", {"key": key, "mode": "Hold", "output": "Number from two keys", "second_key": second})


def one_key(key):
    return logic("input_block", {"key": key, "mode": "Hold", "output": "Boolean", "second_key": ""})


def val(i):
    return {"part": i, "output": "value"}


def res(i):
    return {"part": i, "output": "result"}


def gate(op, a, b=None, value=0.0):
    links = {"a": a}
    if b is not None:
        links["b"] = b
    return logic("number_gate", {"operation": op, "value": value}, links)


i_pitch = two_keys("W", "S")
i_roll = two_keys("D", "A")
i_flap = two_keys("E", "Q")
# C opens the photo camera and J the missions board, so the rudder is on
# X/Z and the thrusters on K and I.
i_yaw = two_keys("X", "Z")
i_main = one_key("K")
i_nose = one_key("I")

ROLL_DEG, FLAP_DEG, ELEV_DEG, RUD_DEG = 10.0, 8.0, 15.0, 20.0
import os


def gain(name, default):
    return float(os.environ.get(name, default))


g_flap = gate("Multiply", val(i_flap), value=FLAP_DEG)
if USE_PID:
    # Roll: A/D ask for a bank angle; let go and the wings level. Positive
    # roll (right wing down) needs both ailerons negative, so the gains are
    # negative.
    bank_cmd = gate("Multiply", val(i_roll), value=gain("BANK", 40.0))
    roll_pid = logic("pid_controller", {"kp": gain("RKP", -0.5), "ki": gain("RKI", -0.05), "kd": gain("RKD", -0.12),
                                        "output_min": -ROLL_DEG, "output_max": ROLL_DEG},
                     {"setpoint": res(bank_cmd), "measurement": {"part": sensor, "output": "roll"}})
    roll_out = {"part": roll_pid, "output": "output"}
    # Pitch: W/S ask for a pitch rate; let go and it holds the attitude
    # (the integral is the trim).
    # E/Q also ask for a gentle pitch rate, so the flaperons pitch the nose
    # rather than the attitude hold cancelling them.
    rate_keys = gate("Multiply", val(i_pitch), value=gain("PRATE", 15.0))
    rate_cmd = gate("Add", res(rate_keys), res(g_flap))
    pitch_pid = logic("pid_controller", {"kp": gain("PKP", 1.0), "ki": gain("PKI", 0.6), "kd": gain("PKD", 0.0),
                                         "output_min": -ELEV_DEG, "output_max": ELEV_DEG},
                      {"setpoint": res(rate_cmd), "measurement": {"part": sensor, "output": "pitch_rate"}})
    elev_out = {"part": pitch_pid, "output": "output"}
else:
    roll_out = res(gate("Multiply", val(i_roll), value=-ROLL_DEG))
    elev_out = res(gate("Multiply", val(i_pitch), value=ELEV_DEG))
g_ail_left = gate("Subtract", roll_out, res(g_flap))
g_ail_right = gate("Add", roll_out, res(g_flap))
g_elev_left = gate("Add", elev_out, value=0.0)
g_elev_right = gate("Multiply", elev_out, value=-1.0)
g_rudder = gate("Multiply", val(i_yaw), value=RUD_DEG)

parts[new_index[LEFT_AIL]]["links"] = {"angle": res(g_ail_left)}
parts[new_index[RIGHT_AIL]]["links"] = {"angle": res(g_ail_right)}
parts[new_index[LEFT_ELEV]]["links"] = {"angle": res(g_elev_left)}
parts[new_index[RIGHT_ELEV]]["links"] = {"angle": res(g_elev_right)}
parts[rudder_servo]["links"] = {"angle": res(g_rudder)}
parts[new_index[MAIN_THRUST]]["links"] = {"on": {"part": i_main, "output": "pressed"}}
parts[new_index[NOSE_THRUST]]["links"] = {"on": {"part": i_nose, "output": "pressed"}}

out = {"block_size_m": 0.25, "format": "ideal-world-build", "name": sys.argv[4] if len(sys.argv) > 4 and not sys.argv[4].startswith("--") else "big delta plane",
       "parts": parts, "version": 1}
json.dump(out, open(OUT, "w"), indent=1)
print("parts", len(parts), "scale", S, "pid", USE_PID)
