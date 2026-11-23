extends Node3D
## Runs the logic blocks, sensors, lights, vanish blocks, propellers and
## lift-gas tanks of a spawned build.
##
## Every physics tick each sensor measures, then the gates and PID
## controllers work out their outputs, a few passes over so a chain of gates
## settles in the same tick. Outputs go to the spawner (set_outputs), where
## motors, pistons, thrusters, guns and other gates read them through their
## links. The spawner runs first, so a part reads what the logic put out one
## tick before: 1/240 s.

const Units = preload("res://scripts/units.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Origin = preload("res://scripts/origin.gd")
const Aero = preload("res://scripts/aero.gd")
const Weather = preload("res://scripts/weather.gd")
const Profiler = preload("res://scripts/profiler.gd")

const GATE_PASSES := 4       # chains of up to this many gates settle in one tick
const GRAVITY := 9.81
const MAX_LIGHTS := 24       # light panels past this many glow but do not light their surroundings
const PROP_BLADE_FACTOR := 0.04   # thrust coefficient per blade
const PROP_EFFICIENCY := 0.8
const SEA_LEVEL_AIR := 1.225
const GATES := ["boolean_gate", "number_gate", "pid_controller", "pwm_generator"]
const SENSORS := ["speed_sensor", "altitude_sensor", "attitude_sensor", "distance_sensor", "impact_detector"]
const GRAPH_RATE := 30.0          # samples per second on a graph screen
const GRAPH_DRAW_EVERY := 0.1     # seconds between redraws of the picture on a screen
const GRAPH_SIZE := Vector2i(256, 160)
const GRAPH_LINES := ["a", "b", "c", "d"]
const GRAPH_COLORS := [Color(1.0, 0.85, 0.2), Color(0.3, 0.9, 1.0), Color(1.0, 0.4, 0.8), Color(0.45, 1.0, 0.45)]
const MAX_GRAPHS := 12            # screens past this many still record but are not drawn in the world

var spawner: Node3D = null    # spawner.gd
var terrain: Node3D = null    # terrain.gd, for the distance sensor to see the ground

var _generation := -1
var _gates: Array = []        # uids, in the order they run
var _compiled: Array = []     # one entry per gate in _gates: see _compile
var _detectors: Array = []    # impact detectors: [uid, state, outputs, threshold, pulse]
var _order_dirty := false     # gates were added: put them in order again before the next tick
var _outputs_table: Dictionary = {}   # the spawner's outputs and destroyed parts, read directly
var _dead_table: Dictionary = {}
var _state: Dictionary = {}   # uid -> what a gate, PID or detector remembers between ticks
var _sensors: Array = []
var _lights: Array = []       # {"uid", "glow" material, "lamp" OmniLight3D or null, "plain": original overrides}
var _vanish: Array = []       # {"uid", "gone"}
var _props: Array = []        # {"uid", "radius", "advance", "factor"}
var _tanks: Array = []        # {"uid", "lift"}
var _graphs: Array = []       # see _new_graph
var _instruments: Array = []  # see _new_instrument
var _graph_clock := 0.0
var _graph_timer := 0.0
var _graph_draw := 0.0


func setup(the_spawner: Node3D) -> void:
	spawner = the_spawner
	add_to_group("logic")


func _physics_process(delta: float) -> void:
	var started := Profiler.start()
	_physics_tick(delta)
	Profiler.add("logic", started)


func _physics_tick(delta: float) -> void:
	if spawner == null:
		return
	if not bool(spawner.spawned):
		if _generation != -1:
			_clear()
		return
	if int(spawner.generation) != _generation:
		_clear()
		_start()
	for uid in _sensors:
		_run_sensor(uid, delta)
	_run_detectors(delta)
	if _order_dirty:
		_sort_gates()
	for pass_index in GATE_PASSES:
		var last_pass := pass_index == GATE_PASSES - 1
		var middle := pass_index != 0 and not last_pass
		for entry in _compiled:
			if middle and not entry[2 if entry[1] == KIND_OTHER else 9]:
				continue   # settled on the first pass: see _sort_gates
			if entry[1] == KIND_OTHER:
				_run_gate(entry[0], delta, pass_index)
			else:
				_run_compiled(entry, delta, last_pass)
	_run_lights()
	_run_vanish()
	_run_propellers()
	_run_tanks()
	_run_graphs(delta)
	_run_instruments()


func _start() -> void:
	_generation = int(spawner.generation)
	if not spawner.parts_added.is_connected(_on_parts_added):
		spawner.parts_added.connect(_on_parts_added)
	if not spawner.teleported.is_connected(_on_teleported):
		spawner.teleported.connect(_on_teleported)
	_outputs_table = spawner._outputs
	_dead_table = spawner._dead
	var records: Dictionary = spawner.all_records()
	for key in records:
		_add_part(int(key), records[key])


## Parts made while spawned (a reload gate's payload) join in.
## The build was teleported and stopped: impact detectors would read the
## stop as a crash, so they start again from the next tick.
func _on_teleported() -> void:
	for key in _state:
		var state: Variant = _state[key]
		if state is Dictionary and (state as Dictionary).has("primed"):
			state["primed"] = false


func _on_parts_added(uids: Array) -> void:
	if _generation != int(spawner.generation):
		return   # not started on this spawn yet; _start will find them
	for item in uids:
		var record: Dictionary = spawner.record_of(int(item))
		if not record.is_empty():
			_add_part(int(item), record)


func _add_part(uid: int, record: Dictionary) -> void:
	var type: String = record["type"]
	var props: Dictionary = record.get("props", {})
	var size_m: Vector3 = Units.to_metres(record["size"])
	if GATES.has(type):
		_gates.append(uid)
		_state[uid] = {"latched": false, "was_on": false, "timer": 0.0, "integral": 0.0,
				"last": 0.0, "primed": false}
		_compiled.append(_compile(uid, record))
		_order_dirty = true
	elif type == "impact_detector":
		# Many of these (one in every bomb), so they keep what they need:
		# their settings and the dictionary their outputs live in.
		var out := {"triggered": 0.0, "acceleration": 0.0}
		spawner.set_outputs(uid, out)
		_state[uid] = {"velocity": Vector3.ZERO, "primed": false, "pulse": 0.0}
		_detectors.append([uid, _state[uid], out, float(props.get("threshold", 10.0)),
				float(props.get("pulse", 0.1))])
	elif SENSORS.has(type):
		_sensors.append(uid)
		_state[uid] = {"velocity": Vector3.ZERO, "primed": false, "pulse": 0.0}
	elif type == "light_panel":
		_lights.append(_new_light(uid, props, size_m))
	elif type == "vanish_block":
		_vanish.append({"uid": uid, "gone": false, "returns": bool(props.get("returns", false)), "input": "vanish"})
	elif type == "ladder":
		_vanish.append({"uid": uid, "gone": false, "returns": true, "input": "stowed"})
	elif type == "propeller":
		var radius := 0.5 * maxf(size_m.x, size_m.z)
		var pitch := deg_to_rad(clampf(float(props.get("pitch", 20.0)), 0.0, 89.0))
		var blades := clampf(float(props.get("blades", 4.0)), 2.0, 12.0)
		# Metres the propeller would screw forward per radian it turns, at
		# three-quarters of its radius.
		var advance := 0.75 * radius * tan(pitch)
		_props.append({"uid": uid, "radius": radius, "advance": advance,
				"factor": PROP_BLADE_FACTOR * blades})
	elif type == "graph_display":
		_graphs.append(_new_graph(uid, props, size_m))
	elif type == "instrument":
		_instruments.append(_new_instrument(uid, props))
	elif type == "lift_gas_tank":
		var cells := size_m.x * size_m.y * size_m.z / pow(Units.CELL, 3)
		_tanks.append({"uid": uid, "lift": maxf(float(props.get("lift_per_block", 1.0)), 0.0) * cells})


func _clear() -> void:
	_generation = -1
	for item in _lights:
		var light: Dictionary = item
		var lamp: Node = light["lamp"]
		if is_instance_valid(lamp):
			lamp.queue_free()
	_gates.clear()
	_compiled.clear()
	_detectors.clear()
	_state.clear()
	_sensors.clear()
	_lights.clear()
	_vanish.clear()
	_props.clear()
	_tanks.clear()
	_graphs.clear()
	for item in _instruments:
		var dial: Node = (item as Dictionary)["viewport"]
		if is_instance_valid(dial):
			dial.queue_free()
	_instruments.clear()
	_graph_clock = 0.0


# --- Gates -------------------------------------------------------------------

# --- Gates, worked out once ---------------------------------------------------
# A boolean or number gate runs four times a tick, so what it reads, what it
# does and where it puts its result are looked up once, at spawn: its
# operation as a number, each input as [source uid, output] (empty if not
# linked), and the dictionary its outputs live in, filled in place.

const KIND_OTHER := 0
const KIND_BOOL := 1
const KIND_NUMBER := 2
const BOOL_OPS := {"AND": 0, "OR": 1, "NOT": 2, "XOR": 3, "NAND": 4, "NOR": 5, "Latch": 6, "Timer": 7}
const NUMBER_OPS := {"Constant": 0, "Add": 1, "Subtract": 2, "Multiply": 3, "Divide": 4, "Absolute value": 5,
		"Min": 6, "Max": 7, "Clamp": 8, "Compare": 9, "Select": 10, "Map range": 11, "Modulo": 12, "Between": 13}


## [uid, kind, operation, a, b, c, value, outputs, state]
func _compile(uid: int, record: Dictionary) -> Array:
	var type: String = record["type"]
	var props: Dictionary = record.get("props", {})
	var links: Dictionary = record.get("links", {})
	var sources: Array = []
	for port in ["a", "b", "c"]:
		if links.has(port):
			var link: Dictionary = links[port]
			sources.append([int(link.get("uid", 0)), str(link.get("output", ""))])
		else:
			sources.append([])
	if type == "boolean_gate":
		var out := {"result": 0.0}
		spawner.set_outputs(uid, out)
		return [uid, KIND_BOOL, int(BOOL_OPS.get(str(props.get("operation", "AND")), -1)),
				sources[0], sources[1], sources[2], maxf(float(props.get("seconds", 1.0)), 0.0), out, _state[uid], true]
	if type == "number_gate":
		var operation := int(NUMBER_OPS.get(str(props.get("operation", "Constant")), -1))
		var value := float(props.get("value", 0.0))
		var out := {"result": value if operation == 0 else 0.0, "is_true": 1.0 if operation == 0 and value != 0.0 else 0.0}
		spawner.set_outputs(uid, out)
		return [uid, KIND_NUMBER, operation, sources[0], sources[1], sources[2], value, out, _state[uid], true]
	return [uid, KIND_OTHER, true]


## Puts the gates in the order signals flow through them, so on the first
## pass of a tick each gate reads what the gates before it worked out this
## tick. A gate that isn't in a loop, and isn't fed by one, is then settled
## after the first pass: it is skipped on the middle passes, and runs again
## on the last (when latches and timers move). Gates in loops, and those fed
## by them, run on every pass, in the order they were built.
func _sort_gates() -> void:
	_order_dirty = false
	var index_of := {}
	for i in _compiled.size():
		index_of[int(_compiled[i][0])] = i
	var feeds: Array = []      # index -> indices of the gates it feeds
	var waiting: Array = []    # index -> how many gates feed it
	feeds.resize(_compiled.size())
	waiting.resize(_compiled.size())
	for i in _compiled.size():
		feeds[i] = []
		waiting[i] = 0
	var looped := {}
	for i in _compiled.size():
		var record: Dictionary = spawner.record_of(int(_compiled[i][0]))
		var links: Dictionary = record.get("links", {})
		for port in links:
			var source := int((links[port] as Dictionary).get("uid", 0))
			if not index_of.has(source):
				continue
			var j: int = index_of[source]
			if j == i:
				looped[i] = true   # reads its own output
				continue
			(feeds[j] as Array).append(i)
			waiting[i] = int(waiting[i]) + 1
	var order: Array = []
	var ready: Array = []
	for i in _compiled.size():
		if int(waiting[i]) == 0:
			ready.append(i)
	var head := 0
	while head < ready.size():
		var i: int = ready[head]
		head += 1
		order.append(i)
		for k in feeds[i]:
			waiting[k] = int(waiting[k]) - 1
			if int(waiting[k]) == 0:
				ready.append(k)
	var placed := {}
	for i in order:
		placed[i] = true
	# What is left is in a loop or fed by one: every pass, in build order.
	var stirred := looped.duplicate()
	for i in _compiled.size():
		if not placed.has(i):
			stirred[i] = true
	var spread: Array = stirred.keys()
	while not spread.is_empty():
		var i: int = spread.pop_back()
		for k in feeds[i]:
			if not stirred.has(k):
				stirred[k] = true
				spread.append(k)
	var sorted: Array = []
	for i in order:
		sorted.append(i)
	for i in _compiled.size():
		if not placed.has(i):
			sorted.append(i)
	var result: Array = []
	for i in sorted:
		var entry: Array = _compiled[i]
		entry[entry.size() - 1] = stirred.has(i)
		result.append(entry)
	_compiled = result


func _read(source: Array, unlinked: float) -> float:
	if source.is_empty():
		return unlinked
	# Most links come from another gate or sensor, whose outputs are in the
	# spawner's table: read it straight. Anything else (keys, controller,
	# seats, destroyed parts) the spawner works out.
	var reported: Variant = _outputs_table.get(source[0])
	if reported != null and not _dead_table.has(source[0]):
		return float((reported as Dictionary).get(source[1], 0.0))
	return spawner.read_output(source[0], source[1], unlinked)


func _run_compiled(entry: Array, delta: float, last_pass: bool) -> void:
	if _dead_table.has(entry[0]):
		return
	var out: Dictionary = entry[7]
	var operation: int = entry[2]
	if entry[1] == KIND_BOOL:
		var a: bool = _read(entry[3], 0.0) != 0.0
		var b: bool = _read(entry[4], 0.0) != 0.0
		var on := false
		match operation:
			0: on = a and b
			1: on = a or b
			2: on = not a
			3: on = a != b
			4: on = not (a and b)
			5: on = not (a or b)
			6:
				# Latch: A switches it on, B switches it off.
				var state: Dictionary = entry[8]
				if last_pass:
					if b:
						state["latched"] = false
					elif a:
						state["latched"] = true
				on = state["latched"]
			7:
				# Timer: when A switches on, the result stays on for the timer length.
				var state: Dictionary = entry[8]
				if last_pass:
					if a and not state["was_on"]:
						state["timer"] = entry[6]
					elif state["timer"] > 0.0:
						state["timer"] = maxf(float(state["timer"]) - delta, 0.0)
					state["was_on"] = a
				on = float(state["timer"]) > 0.0 or (a and not state["was_on"])
		out["result"] = 1.0 if on else 0.0
		return
	var value: float = entry[6]
	var a: float = _read(entry[3], 0.0)
	var b: float = _read(entry[4], value)   # an unlinked B is the constant
	var c: float = _read(entry[5], 0.0)
	var result := 0.0
	var is_true := false
	match operation:
		0: result = value
		1: result = a + b
		2: result = a - b
		3: result = a * b
		4: result = a / b if absf(b) > 1e-9 else 0.0
		5: result = absf(a)
		6: result = minf(a, b)
		7: result = maxf(a, b)
		8: result = clampf(a, minf(b, c), maxf(b, c))
		9:
			is_true = a > b
			result = 1.0 if is_true else 0.0
		10: result = b if a != 0.0 else c
		11: result = (a - b) / (c - b) if absf(c - b) > 1e-9 else 0.0
		12: result = fposmod(a, b) if absf(b) > 1e-9 else 0.0
		13:
			is_true = a >= minf(b, c) and a <= maxf(b, c)
			result = 1.0 if is_true else 0.0
	if not is_finite(result):
		result = 0.0
	if operation != 9 and operation != 13:
		is_true = result != 0.0
	out["result"] = result
	out["is_true"] = 1.0 if is_true else 0.0


func _run_gate(uid: int, delta: float, pass_index: int) -> void:
	var last_pass := pass_index == GATE_PASSES - 1
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return
	var links: Dictionary = record.get("links", {})
	var props: Dictionary = record.get("props", {})
	var state: Dictionary = _state[uid]
	var type: String = record["type"]
	if type == "boolean_gate":
		var a: bool = spawner.input_value(links, "a", 0.0) != 0.0
		var b: bool = spawner.input_value(links, "b", 0.0) != 0.0
		var on := false
		match str(props.get("operation", "AND")):
			"AND": on = a and b
			"OR": on = a or b
			"NOT": on = not a
			"XOR": on = a != b
			"NAND": on = not (a and b)
			"NOR": on = not (a or b)
			"Latch":
				# A switches it on, B switches it off.
				if last_pass:
					if b:
						state["latched"] = false
					elif a:
						state["latched"] = true
				on = state["latched"]
			"Timer":
				# When A switches on, the result stays on for the timer length.
				if last_pass:
					if a and not state["was_on"]:
						state["timer"] = maxf(float(props.get("seconds", 1.0)), 0.0)
					elif state["timer"] > 0.0:
						state["timer"] = maxf(float(state["timer"]) - delta, 0.0)
					state["was_on"] = a
				on = float(state["timer"]) > 0.0 or (a and not state["was_on"])
		spawner.set_outputs(uid, {"result": 1.0 if on else 0.0})
	elif type == "number_gate":
		var value := float(props.get("value", 0.0))
		var a: float = spawner.input_value(links, "a", 0.0)
		var b: float = spawner.input_value(links, "b", value)   # an unlinked B is the constant
		var c: float = spawner.input_value(links, "c", 0.0)
		var result := 0.0
		var is_true := false
		match str(props.get("operation", "Constant")):
			"Constant": result = value
			"Add": result = a + b
			"Subtract": result = a - b
			"Multiply": result = a * b
			"Divide": result = a / b if absf(b) > 1e-9 else 0.0
			"Absolute value": result = absf(a)
			"Min": result = minf(a, b)
			"Max": result = maxf(a, b)
			"Clamp": result = clampf(a, minf(b, c), maxf(b, c))
			"Compare":
				is_true = a > b
				result = 1.0 if is_true else 0.0
			"Select": result = b if a != 0.0 else c
			"Map range":
				# A from the range B to C onto 0 to 1.
				result = (a - b) / (c - b) if absf(c - b) > 1e-9 else 0.0
			"Modulo":
				# A wrapped into 0 up to B: a crank's angle into one turn, say.
				result = fposmod(a, b) if absf(b) > 1e-9 else 0.0
			"Between":
				# On while A is between B and C: a spark window, say.
				is_true = a >= minf(b, c) and a <= maxf(b, c)
				result = 1.0 if is_true else 0.0
		if not is_finite(result):
			result = 0.0
		if not ["Compare", "Between"].has(str(props.get("operation", ""))):
			is_true = result != 0.0
		spawner.set_outputs(uid, {"result": result, "is_true": 1.0 if is_true else 0.0})
	elif type == "pwm_generator":
		# On for `duty` of each cycle, at `frequency` cycles a second. The clock
		# moves once a tick, on the first pass, so the output is there for the
		# rest of the chain in the same tick.
		var enabled: bool = spawner.input_value(links, "enable", 1.0) != 0.0
		var frequency: float = clampf(spawner.input_value(links, "frequency", float(props.get("frequency", 2.0))),
				0.0, 120.0)
		var duty: float = clampf(spawner.input_value(links, "duty", float(props.get("duty", 50.0)) / 100.0), 0.0, 1.0)
		if not bool(state["primed"]):
			state["primed"] = true
			state["last"] = 0.0
		if pass_index == 0:
			state["last"] = fposmod(float(state["last"]) + frequency * delta, 1.0) if enabled else 0.0
		var phase: float = state["last"]
		var on := enabled and duty > 0.0 and (duty >= 1.0 or phase < duty)
		spawner.set_outputs(uid, {"output": 1.0 if on else 0.0, "phase": phase})
	elif type == "pid_controller":
		if not last_pass:
			return   # it integrates over time, so it runs once a tick
		var setpoint: float = spawner.input_value(links, "setpoint", 0.0)
		var measured: float = spawner.input_value(links, "measurement", 0.0)
		var low := float(props.get("output_min", -1.0))
		var high := float(props.get("output_max", 1.0))
		if high < low:
			var swap := low
			low = high
			high = swap
		var kp := float(props.get("kp", 1.0))
		var ki := float(props.get("ki", 0.0))
		var kd := float(props.get("kd", 0.0))
		var error := setpoint - measured
		# Rate taken from the measurement, so a jump in the setpoint does not kick.
		var rate := 0.0
		if state["primed"]:
			rate = -(measured - float(state["last"])) / maxf(delta, 1e-6)
		state["last"] = measured
		state["primed"] = true
		var integral := float(state["integral"]) + error * delta
		var output := kp * error + ki * integral + kd * rate
		# Stop winding up the integral while the output is pinned at a limit.
		if (output > high and error > 0.0) or (output < low and error < 0.0):
			integral = float(state["integral"])
			output = kp * error + ki * integral + kd * rate
		state["integral"] = integral
		spawner.set_outputs(uid, {"output": clampf(output, low, high) if is_finite(output) else 0.0})


# --- Sensors -----------------------------------------------------------------

func _run_sensor(uid: int, delta: float) -> void:
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return
	var frame_and_body: Array = spawner.part_frame(uid)
	if frame_and_body.is_empty():
		return
	var frame: Transform3D = frame_and_body[0]
	var body: RigidBody3D = frame_and_body[1]
	var props: Dictionary = record.get("props", {})
	var velocity := _velocity_at(body, frame.origin)
	match str(record["type"]):
		"speed_sensor":
			# Also through the air (the wind taken off), along its own axes
			# (its front is -Z, as the attitude sensor's): sideways over
			# forward is the sideslip, upward over forward the angle of
			# attack (negative).
			var axes := frame.basis.orthonormalized()
			var air := velocity - Weather.wind_at(frame.origin)
			spawner.set_outputs(uid, {
				"speed": velocity.length(), "forward": air.dot(-axes.z),
				"sideways": air.dot(axes.x), "upward": air.dot(axes.y),
			})
		"altitude_sensor":
			spawner.set_outputs(uid, {"altitude": Origin.to_map(frame.origin).y + MapInfo.BASE_ELEVATION})
		"attitude_sensor":
			var forward := -frame.basis.z.normalized()
			var right := frame.basis.x.normalized()
			var up := frame.basis.y.normalized()
			var pitch := rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
			var roll := rad_to_deg(atan2(-right.y, up.y))
			var yaw := fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)   # 0 north, 90 east
			var spin: Vector3 = frame.basis.orthonormalized().inverse() * body.angular_velocity
			spawner.set_outputs(uid, {
				"pitch": pitch, "roll": roll, "yaw": yaw,
				"pitch_rate": rad_to_deg(spin.x), "roll_rate": rad_to_deg(-spin.z),
				"yaw_rate": rad_to_deg(-spin.y),
			})
		"distance_sensor":
			var reach := maxf(float(props.get("range", 100.0)), 0.0)
			spawner.set_outputs(uid, {"distance": _distance(body, frame, reach)})
		"impact_detector":
			var state: Dictionary = _state[uid]
			var g := 0.0
			if state["primed"]:
				g = (velocity - (state["velocity"] as Vector3)).length() / maxf(delta, 1e-6) / GRAVITY
			state["velocity"] = velocity
			state["primed"] = true
			if g >= float(props.get("threshold", 10.0)):
				state["pulse"] = maxf(float(props.get("pulse", 0.1)), delta)
			else:
				state["pulse"] = maxf(float(state["pulse"]) - delta, 0.0)
			spawner.set_outputs(uid, {"triggered": 1.0 if float(state["pulse"]) > 0.0 else 0.0,
					"acceleration": g})


## Impact detectors: the acceleration in g, from the change of speed of the
## point they sit at since the last tick; on for their signal length once it
## passes their trigger level.
func _run_detectors(delta: float) -> void:
	var keep := false
	for entry in _detectors:
		var uid: int = entry[0]
		if _dead_table.has(uid):
			keep = true
			continue
		var frame_and_body: Array = spawner.part_frame(uid)
		if frame_and_body.is_empty():
			continue
		var body: RigidBody3D = frame_and_body[1]
		var velocity := _velocity_at(body, (frame_and_body[0] as Transform3D).origin)
		var state: Dictionary = entry[1]
		var g := 0.0
		if state["primed"]:
			g = (velocity - (state["velocity"] as Vector3)).length() / maxf(delta, 1e-6) / GRAVITY
		state["velocity"] = velocity
		state["primed"] = true
		if g >= float(entry[3]):
			state["pulse"] = maxf(float(entry[4]), delta)
		else:
			state["pulse"] = maxf(float(state["pulse"]) - delta, 0.0)
		var out: Dictionary = entry[2]
		out["triggered"] = 1.0 if float(state["pulse"]) > 0.0 else 0.0
		out["acceleration"] = g
	# Destroyed ones are dropped from the list now and then.
	if keep and Engine.get_physics_frames() % 60 == 0:
		_detectors = _detectors.filter(func(entry: Array) -> bool: return not _dead_table.has(int(entry[0])))


## How fast a point fixed to a body is moving.
func _velocity_at(body: RigidBody3D, point: Vector3) -> Vector3:
	var centre: Vector3 = body.global_transform * body.center_of_mass
	return body.linear_velocity + body.angular_velocity.cross(point - centre)


## Metres from the sensor's face to whatever is in front of it, out to
## `reach`: anything solid, the ground, or the lake. `reach` if nothing.
func _distance(body: RigidBody3D, frame: Transform3D, reach: float) -> float:
	var forward := -frame.basis.z.normalized()
	var start := frame.origin
	var end := start + forward * reach
	var nearest := reach
	var query := PhysicsRayQueryParameters3D.create(start, end, Units.LAYER_WORLD | Units.LAYER_BODIES)
	query.exclude = [body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		nearest = start.distance_to(hit["position"])
	# The ground and the lake, which are only solid near the character:
	# along the line in up to 40 steps (2 m apart at most), then halving the
	# step where it first goes under, to a few centimetres. A long reach
	# (a bomber's height finder) costs no more than a short one.
	if terrain != null:
		var travel := minf(nearest, reach)
		var steps := clampi(int(ceil(travel / 2.0)), 1, 40)
		var above := 0.0
		for step in range(1, steps + 1):
			var along := travel * float(step) / steps
			if _under_ground(start + forward * along):
				var below := along
				while below - above > 0.05:
					var middle := (above + below) * 0.5
					if _under_ground(start + forward * middle):
						below = middle
					else:
						above = middle
				nearest = below
				break
			above = along
	return nearest


func _under_ground(point: Vector3) -> bool:
	return point.y < MapInfo.LAKE_Y or point.y < terrain.ground_at(point)


# --- Lights and vanishing ----------------------------------------------------

func _new_light(uid: int, props: Dictionary, size_m: Vector3) -> Dictionary:
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plain: Array = []
	for item in spawner.part_nodes(uid):
		var pair: Array = item
		var mesh: MeshInstance3D = pair[0]
		plain.append(mesh.material_override if mesh != null else null)
	var lamp: OmniLight3D = null
	if _lights.size() < MAX_LIGHTS:
		lamp = OmniLight3D.new()
		lamp.shadow_enabled = false
		lamp.omni_range = clampf(4.0 + 6.0 * maxf(size_m.x, size_m.z), 4.0, 40.0)
		lamp.visible = false
		add_child(lamp)
	var color := Color.WHITE
	var stored: Variant = props.get("color", Color.WHITE)
	if stored is Color:
		color = stored
	elif Color.html_is_valid(str(stored)):
		color = Color.html(str(stored))
	return {"uid": uid, "glow": glow, "lamp": lamp, "plain": plain, "color": color,
			"brightness": maxf(float(props.get("brightness", 1.0)), 0.0), "lit": -1}


func _run_lights() -> void:
	for item in _lights:
		var light: Dictionary = item
		var uid: int = light["uid"]
		var record: Dictionary = spawner.record_of(uid)
		var lamp: OmniLight3D = light["lamp"]
		if record.is_empty():
			if lamp != null:
				lamp.visible = false
			continue
		var links: Dictionary = record.get("links", {})
		var base: Color = light["color"]
		var on: bool = spawner.input_value(links, "on", 1.0) != 0.0
		var color := Color(
				clampf(spawner.input_value(links, "red", base.r * 255.0) / 255.0, 0.0, 1.0),
				clampf(spawner.input_value(links, "green", base.g * 255.0) / 255.0, 0.0, 1.0),
				clampf(spawner.input_value(links, "blue", base.b * 255.0) / 255.0, 0.0, 1.0))
		var glow: StandardMaterial3D = light["glow"]
		var nodes: Array = spawner.part_nodes(uid)
		var plain: Array = light["plain"]
		for index in nodes.size():
			var pair: Array = nodes[index]
			var mesh: MeshInstance3D = pair[0]
			if mesh == null:
				continue
			if on:
				mesh.material_override = glow
			elif index < plain.size():
				mesh.material_override = plain[index]
		if on:
			glow.albedo_color = color
			glow.emission = color
			glow.emission_energy_multiplier = float(light["brightness"])
		if lamp != null:
			lamp.visible = on and float(light["brightness"]) > 0.0
			if lamp.visible:
				var frame: Array = spawner.part_frame(uid)
				if not frame.is_empty():
					lamp.global_position = (frame[0] as Transform3D).origin
				lamp.light_color = color
				lamp.light_energy = float(light["brightness"])


func _run_vanish() -> void:
	for item in _vanish:
		var block: Dictionary = item
		var uid: int = block["uid"]
		var record: Dictionary = spawner.record_of(uid)
		if record.is_empty():
			continue
		var wanted: bool = spawner.input_value(record.get("links", {}), str(block.get("input", "vanish")), 0.0) != 0.0
		if not wanted and not bool(block["returns"]) and bool(block["gone"]):
			wanted = true   # set to stay gone
		if wanted == bool(block["gone"]):
			continue
		block["gone"] = wanted
		for pair_item in spawner.part_nodes(uid):
			var pair: Array = pair_item
			var mesh: MeshInstance3D = pair[0]
			var collider: CollisionShape3D = pair[1]
			if mesh != null:
				mesh.visible = not wanted
			if collider != null:
				collider.disabled = wanted


# --- Propellers and lift gas -------------------------------------------------

## A propeller pushes along its spin axis (its own Y) according to how fast
## it turns: the pitch sets how far each turn screws it through the air, and
## the thrust falls off as the air coming at it catches up with that. Spun
## the other way it pushes the other way. It takes torque to turn in
## proportion, so the motor driving it feels the load. Speed out is in rpm.
func _run_propellers() -> void:
	for item in _props:
		var prop: Dictionary = item
		var uid: int = prop["uid"]
		var frame_and_body: Array = spawner.part_frame(uid)
		if frame_and_body.is_empty():
			continue
		var frame: Transform3D = frame_and_body[0]
		var body: RigidBody3D = frame_and_body[1]
		var axis := frame.basis.y.normalized()
		var spin := body.angular_velocity.dot(axis)
		spawner.set_outputs(uid, {"speed": absf(spin) * 60.0 / TAU})
		if body.freeze:
			continue
		var advance: float = prop["advance"]
		var radius: float = prop["radius"]
		var pitch_speed := spin * advance
		var inflow := (_velocity_at(body, frame.origin) - Weather.wind_at(frame.origin)).dot(axis)
		var density := Aero.air_density(Origin.to_map(frame.origin).y)
		var disc := PI * radius * radius
		var thrust: float = density * disc * float(prop["factor"]) * (pitch_speed - inflow) * absf(pitch_speed)
		if absf(thrust) < 1e-4:
			continue
		body.sleeping = false
		body.apply_force(axis * thrust, frame.origin - body.global_position)
		spawner.note_force(uid * 8, axis * thrust)
		# The torque it takes to turn: against the spin, or with it when the
		# air drives it round (windmilling).
		body.apply_torque(-axis * thrust * advance / PROP_EFFICIENCY)


## A lift-gas tank lifts straight up by its setting per block of its size,
## scaled by the amount input (full when unlinked) and thinning with the air.
func _run_tanks() -> void:
	for item in _tanks:
		var tank: Dictionary = item
		var uid: int = tank["uid"]
		var record: Dictionary = spawner.record_of(uid)
		if record.is_empty():
			continue
		var frame_and_body: Array = spawner.part_frame(uid)
		if frame_and_body.is_empty():
			continue
		var frame: Transform3D = frame_and_body[0]
		var body: RigidBody3D = frame_and_body[1]
		if body.freeze:
			continue
		var amount := clampf(spawner.input_value(record.get("links", {}), "amount", 1.0), 0.0, 1.0)
		var thin := Aero.air_density(Origin.to_map(frame.origin).y) / SEA_LEVEL_AIR
		var lift: float = float(tank["lift"]) * amount * thin
		if lift <= 0.0:
			continue
		body.sleeping = false
		body.apply_force(Vector3.UP * lift, frame.origin - body.global_position)
		spawner.note_force(uid * 8, Vector3.UP * lift)


# --- Graph screens -------------------------------------------------------------

## A graph screen: up to four lines plotted against time, drawn on both of
## its big faces and, for the vehicle the character sits in, on screen too
## (game_hud.gd reads graphs_for_screen).
func _new_graph(uid: int, props: Dictionary, _size_m: Vector3) -> Dictionary:
	var graph := {
		"uid": uid,
		"window": clampf(float(props.get("window", 10.0)), 1.0, 600.0),
		"low": float(props.get("low", 0.0)),
		"high": float(props.get("high", 0.0)),
		"labels": [str(props.get("label_a", "A")), str(props.get("label_b", "B")),
				str(props.get("label_c", "C")), str(props.get("label_d", "D"))],
		"on_screen": bool(props.get("on_screen", true)),
		"times": PackedFloat32Array(),
		"values": [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()],
		"linked": [false, false, false, false],
		"image": null,
		"texture": null,
	}
	var record: Dictionary = spawner.record_of(uid)
	var links: Dictionary = record.get("links", {})
	for index in 4:
		(graph["linked"] as Array)[index] = links.has(GRAPH_LINES[index])
	if _graphs.size() < MAX_GRAPHS:
		var image := Image.create_empty(GRAPH_SIZE.x, GRAPH_SIZE.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.02, 0.04, 0.03))
		var texture := ImageTexture.create_from_image(image)
		graph["image"] = image
		graph["texture"] = texture
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.albedo_texture = texture
		look.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		for side in [1.0, -1.0]:
			var facing: float = side
			spawner.attach_extra(uid, func(place: Transform3D, size: Vector3) -> Node3D:
				var quad := QuadMesh.new()
				quad.size = Vector2(size.x * 0.9, size.y * 0.86)
				var screen := MeshInstance3D.new()
				screen.mesh = quad
				screen.material_override = look
				screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# The quad faces +Z; turned half round for the back face.
				var turn := Basis.IDENTITY if facing > 0.0 else Basis(Vector3.UP, PI)
				screen.transform = place * Transform3D(turn, Vector3(0.0, 0.0, facing * (size.z * 0.5 + 0.003)))
				return screen)
	return graph


# --- Instruments ------------------------------------------------------------

const MAX_INSTRUMENTS := 16
const INSTRUMENT_SIZE := 192

## A dial drawn in its own little viewport, shown on both faces of the part.
func _new_instrument(uid: int, props: Dictionary) -> Dictionary:
	var dial := {"uid": uid, "kind": str(props.get("kind", "Airspeed")), "top": float(props.get("top", 100.0)),
			"bottom": float(props.get("bottom", 0.0)), "label": str(props.get("label", "")), "viewport": null, "face": null}
	if _instruments.size() >= MAX_INSTRUMENTS:
		return dial
	var viewport := SubViewport.new()
	viewport.size = Vector2i(INSTRUMENT_SIZE, INSTRUMENT_SIZE)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var face := DialFace.new()
	face.size = Vector2(INSTRUMENT_SIZE, INSTRUMENT_SIZE)
	face.kind = dial["kind"]
	face.label = dial["label"]
	viewport.add_child(face)
	add_child(viewport)
	dial["viewport"] = viewport
	dial["face"] = face
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_texture = viewport.get_texture()
	for side in [1.0, -1.0]:
		var facing: float = side
		spawner.attach_extra(uid, func(place: Transform3D, size: Vector3) -> Node3D:
			var quad := QuadMesh.new()
			quad.size = Vector2(size.x * 0.9, size.y * 0.9)
			var screen := MeshInstance3D.new()
			screen.mesh = quad
			screen.material_override = look
			screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var turn := Basis.IDENTITY if facing > 0.0 else Basis(Vector3.UP, PI)
			screen.transform = place * Transform3D(turn, Vector3(0.0, 0.0, facing * (size.z * 0.5 + 0.004)))
			return screen)
	return dial


func _fuel_share() -> float:
	for sibling in get_parent().get_children():
		if sibling != self and sibling.has_method("total_fuel") and sibling.get("spawner") == spawner:
			var capacity: float = sibling.total_capacity()
			return float(sibling.total_fuel()) / capacity if capacity > 0.0 else 0.0
	return 0.0


func _run_instruments() -> void:
	for item in _instruments:
		var dial: Dictionary = item
		var face: Control = dial["face"]
		if face == null or not is_instance_valid(face):
			continue
		var uid: int = dial["uid"]
		var frame: Array = spawner.part_frame(uid)
		if frame.is_empty():
			continue
		var place: Transform3D = frame[0]
		var body: RigidBody3D = frame[1]
		var reading := 0.0
		var shown := 0.0
		match str(dial["kind"]):
			"Airspeed":
				reading = (body.linear_velocity - Weather.wind_at(place.origin)).length()
				shown = reading / maxf(float(dial["top"]), 1e-6)
				face.set("text", "%.0f m/s" % reading)
			"Altitude":
				reading = Origin.to_map(place.origin).y + MapInfo.BASE_ELEVATION
				shown = fposmod(reading / maxf(float(dial["top"]), 1e-6), 1.0)
				face.set("text", "%.0f m" % reading)
			"Fuel":
				reading = _fuel_share()
				shown = reading
				face.set("text", "%.0f%%" % (reading * 100.0))
			"Value":
				var record: Dictionary = spawner.record_of(uid)
				reading = spawner.input_value(record.get("links", {}), "value", 0.0)
				var bottom: float = dial["bottom"]
				shown = (reading - bottom) / maxf(float(dial["top"]) - bottom, 1e-6)
				face.set("text", "%.2f" % reading if absf(reading) < 100.0 else "%.0f" % reading)
			"Artificial horizon":
				# The part's face looks back at the pilot: the vehicle's nose is its -Z.
				var nose := -place.basis.z.normalized()
				var right := place.basis.x.normalized()
				face.set("pitch", asin(clampf(nose.y, -1.0, 1.0)))
				face.set("roll", atan2(right.y, place.basis.y.normalized().y))
		face.set("needle", shown)
		face.queue_redraw()


## The face of a dial: a needle sweeping 270° over twelve ticks with the
## reading written below, or for an artificial horizon, sky over ground
## moving with pitch and roll behind a fixed aircraft symbol.
class DialFace:
	extends Control
	var kind := "Airspeed"
	var label := ""
	var text := ""
	var needle := 0.0
	var pitch := 0.0
	var roll := 0.0

	func _draw() -> void:
		var middle := size * 0.5
		var radius := size.x * 0.46
		var font := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.06))
		if kind == "Artificial horizon":
			var sky := Color(0.25, 0.55, 0.9)
			var ground := Color(0.55, 0.36, 0.18)
			draw_circle(middle, radius, sky)
			# The horizon line moves down as the nose goes up, and tilts against the roll.
			var drop := clampf(pitch / deg_to_rad(45.0), -1.2, 1.2) * radius
			var across := Vector2(cos(-roll), sin(-roll))
			var down := Vector2(-across.y, across.x)
			var centre := middle + down * drop
			var points := PackedVector2Array()
			for step in 33:
				var angle := TAU * step / 32.0
				var point := middle + Vector2(cos(angle), sin(angle)) * radius
				if (point - centre).dot(down) > 0.0:
					points.append(point)
			if points.size() > 2:
				# Close the ground along the horizon line.
				var ordered := Array(points)
				ordered.sort_custom(func(a, b): return (a - centre).angle() < (b - centre).angle())
				draw_colored_polygon(PackedVector2Array(ordered), ground)
			draw_line(centre - across * radius * 1.2, centre + across * radius * 1.2, Color.WHITE, 2.0)
			for mark in [-20, -10, 10, 20]:
				var at := centre - down * radius * float(mark) / 45.0
				draw_line(at - across * radius * 0.2, at + across * radius * 0.2, Color(1, 1, 1, 0.7), 1.0)
			draw_line(middle + Vector2(-radius * 0.5, 0), middle + Vector2(-radius * 0.15, 0), Color(1.0, 0.8, 0.1), 4.0)
			draw_line(middle + Vector2(radius * 0.15, 0), middle + Vector2(radius * 0.5, 0), Color(1.0, 0.8, 0.1), 4.0)
			draw_circle(middle, 4.0, Color(1.0, 0.8, 0.1))
		else:
			draw_circle(middle, radius, Color(0.1, 0.1, 0.11))
			draw_arc(middle, radius, 0.0, TAU, 48, Color(0.7, 0.7, 0.72), 2.0)
			var start := deg_to_rad(135.0)
			for tick in 13:
				var tick_angle := start + deg_to_rad(270.0) * tick / 12.0
				var outer := middle + Vector2(cos(tick_angle), sin(tick_angle)) * radius * 0.92
				var inner := middle + Vector2(cos(tick_angle), sin(tick_angle)) * radius * (0.78 if tick % 3 == 0 else 0.85)
				draw_line(inner, outer, Color.WHITE, 2.0 if tick % 3 == 0 else 1.0)
			if kind == "Fuel":
				draw_arc(middle, radius * 0.88, start, start + deg_to_rad(270.0) * 0.15, 12, Color(0.9, 0.2, 0.1), 4.0)
			var angle := start + deg_to_rad(270.0) * clampf(needle, 0.0, 1.0)
			draw_line(middle, middle + Vector2(cos(angle), sin(angle)) * radius * 0.8, Color(1.0, 0.55, 0.1), 4.0)
			draw_circle(middle, 6.0, Color(0.8, 0.8, 0.8))
			draw_string(font, middle + Vector2(-radius, radius * 0.55), text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 22, Color.WHITE)
		var title := label if label != "" else kind
		draw_string(font, middle + Vector2(-radius, -radius * 0.35), title, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 16, Color(0.8, 0.85, 0.9))


func _run_graphs(delta: float) -> void:
	if _graphs.is_empty():
		return
	_graph_clock += delta
	_graph_timer -= delta
	if _graph_timer <= 0.0:
		_graph_timer = 1.0 / GRAPH_RATE
		for item in _graphs:
			_sample_graph(item)
	_graph_draw -= delta
	if _graph_draw <= 0.0:
		_graph_draw = GRAPH_DRAW_EVERY
		for item in _graphs:
			var graph: Dictionary = item
			if graph["image"] != null and not spawner.record_of(int(graph["uid"])).is_empty():
				_draw_graph(graph)


func _sample_graph(graph: Dictionary) -> void:
	var record: Dictionary = spawner.record_of(int(graph["uid"]))
	if record.is_empty():
		return
	var links: Dictionary = record.get("links", {})
	var times: PackedFloat32Array = graph["times"]
	times.append(_graph_clock)
	var values: Array = graph["values"]
	for index in 4:
		var line: PackedFloat32Array = values[index]
		line.append(spawner.input_value(links, GRAPH_LINES[index], 0.0))
		values[index] = line
	# Forget what has scrolled off the left edge.
	var oldest := _graph_clock - float(graph["window"])
	var drop := 0
	while drop < times.size() - 2 and times[drop] < oldest:
		drop += 1
	if drop > 0:
		times = times.slice(drop)
		for index in 4:
			values[index] = (values[index] as PackedFloat32Array).slice(drop)
	graph["times"] = times


## The range a graph's lines are drawn over: its settings, or the lines'
## own lowest and highest if the settings' two ends are the same.
static func graph_range(graph: Dictionary) -> Vector2:
	var low: float = graph["low"]
	var high: float = graph["high"]
	if high > low:
		return Vector2(low, high)
	low = INF
	high = -INF
	var values: Array = graph["values"]
	var linked: Array = graph["linked"]
	for index in 4:
		if not linked[index]:
			continue
		for value in (values[index] as PackedFloat32Array):
			low = minf(low, value)
			high = maxf(high, value)
	if low > high:
		return Vector2(-1.0, 1.0)
	if high - low < 0.000001:
		return Vector2(low - 1.0, high + 1.0)
	var margin := (high - low) * 0.08
	return Vector2(low - margin, high + margin)


func _draw_graph(graph: Dictionary) -> void:
	var image: Image = graph["image"]
	var width := GRAPH_SIZE.x
	var height := GRAPH_SIZE.y
	image.fill(Color(0.02, 0.04, 0.03))
	# A faint grid: quarters up the screen, and the zero line brighter.
	var span := graph_range(graph)
	for quarter in range(1, 4):
		var row := int(height * quarter / 4.0)
		for x in range(0, width, 2):
			image.set_pixel(x, row, Color(0.1, 0.22, 0.14))
	if span.x < 0.0 and span.y > 0.0:
		var zero_row := int((1.0 - (0.0 - span.x) / (span.y - span.x)) * (height - 1))
		for x in width:
			image.set_pixel(x, clampi(zero_row, 0, height - 1), Color(0.25, 0.45, 0.3))
	var times: PackedFloat32Array = graph["times"]
	var values: Array = graph["values"]
	var linked: Array = graph["linked"]
	var window: float = graph["window"]
	if times.size() >= 2:
		var newest: float = times[times.size() - 1]
		for index in 4:
			if not linked[index]:
				continue
			var line: PackedFloat32Array = values[index]
			var color: Color = GRAPH_COLORS[index]
			var last := Vector2i(-1, -1)
			for sample in times.size():
				var x := int((1.0 - (newest - times[sample]) / window) * (width - 1))
				var fraction := (line[sample] - span.x) / (span.y - span.x)
				var y := int((1.0 - clampf(fraction, 0.0, 1.0)) * (height - 1))
				var point := Vector2i(clampi(x, 0, width - 1), y)
				if last.x >= 0:
					_line(image, last, point, color)
				last = point
	(graph["texture"] as ImageTexture).update(image)


## A straight line of pixels from `a` to `b`.
static func _line(image: Image, a: Vector2i, b: Vector2i, color: Color) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	if steps == 0:
		image.set_pixelv(a, color)
		return
	for step in steps + 1:
		var t := float(step) / steps
		image.set_pixel(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))), color)


## The graphs to draw on screen: those set to show there, on the vehicle
## the character is sitting in. Each is the dictionary from _new_graph.
func graphs_for_screen() -> Array:
	var shown: Array = []
	if spawner == null or not bool(spawner.spawned) or int(spawner.occupied_seat) == 0:
		return shown
	for item in _graphs:
		var graph: Dictionary = item
		if bool(graph["on_screen"]) and not spawner.record_of(int(graph["uid"])).is_empty():
			shown.append(graph)
	return shown
