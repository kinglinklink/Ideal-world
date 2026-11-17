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

const GATE_PASSES := 4       # chains of up to this many gates settle in one tick
const GRAVITY := 9.81
const MAX_LIGHTS := 24       # light panels past this many glow but do not light their surroundings
const PROP_BLADE_FACTOR := 0.04   # thrust coefficient per blade
const PROP_EFFICIENCY := 0.8
const SEA_LEVEL_AIR := 1.225
const GATES := ["boolean_gate", "number_gate", "pid_controller"]
const SENSORS := ["speed_sensor", "altitude_sensor", "attitude_sensor", "distance_sensor", "impact_detector"]

var spawner: Node3D = null    # spawner.gd
var terrain: Node3D = null    # terrain.gd, for the distance sensor to see the ground

var _generation := -1
var _gates: Array = []        # uids, in the order they run
var _state: Dictionary = {}   # uid -> what a gate, PID or detector remembers between ticks
var _sensors: Array = []
var _lights: Array = []       # {"uid", "glow" material, "lamp" OmniLight3D or null, "plain": original overrides}
var _vanish: Array = []       # {"uid", "gone"}
var _props: Array = []        # {"uid", "radius", "advance", "factor"}
var _tanks: Array = []        # {"uid", "lift"}


func setup(the_spawner: Node3D) -> void:
	spawner = the_spawner


func _physics_process(delta: float) -> void:
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
	for pass_index in GATE_PASSES:
		for uid in _gates:
			_run_gate(uid, delta, pass_index == GATE_PASSES - 1)
	_run_lights()
	_run_vanish()
	_run_propellers()
	_run_tanks()


func _start() -> void:
	_generation = int(spawner.generation)
	var records: Dictionary = spawner.all_records()
	for key in records:
		var uid: int = key
		var record: Dictionary = records[uid]
		var type: String = record["type"]
		var props: Dictionary = record.get("props", {})
		var size_m: Vector3 = Units.to_metres(record["size"])
		if GATES.has(type):
			_gates.append(uid)
			_state[uid] = {"latched": false, "was_on": false, "timer": 0.0, "integral": 0.0,
					"last": 0.0, "primed": false}
		elif SENSORS.has(type):
			_sensors.append(uid)
			_state[uid] = {"velocity": Vector3.ZERO, "primed": false, "pulse": 0.0}
		elif type == "light_panel":
			_lights.append(_new_light(uid, props, size_m))
		elif type == "vanish_block":
			_vanish.append({"uid": uid, "gone": false, "returns": bool(props.get("returns", false))})
		elif type == "propeller":
			var radius := 0.5 * maxf(size_m.x, size_m.z)
			var pitch := deg_to_rad(clampf(float(props.get("pitch", 20.0)), 0.0, 89.0))
			var blades := clampf(float(props.get("blades", 4.0)), 2.0, 12.0)
			# Metres the propeller would screw forward per radian it turns, at
			# three-quarters of its radius.
			var advance := 0.75 * radius * tan(pitch)
			_props.append({"uid": uid, "radius": radius, "advance": advance,
					"factor": PROP_BLADE_FACTOR * blades})
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
	_state.clear()
	_sensors.clear()
	_lights.clear()
	_vanish.clear()
	_props.clear()
	_tanks.clear()


# --- Gates -------------------------------------------------------------------

func _run_gate(uid: int, delta: float, last_pass: bool) -> void:
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
			spawner.set_outputs(uid, {"speed": velocity.length()})
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
	# The ground and the lake, which are only solid near the character.
	if terrain != null:
		var travel := minf(nearest, reach)
		var steps := clampi(int(ceil(travel / 2.0)), 1, 200)
		for step in range(1, steps + 1):
			var along := travel * float(step) / steps
			var point := start + forward * along
			if point.y < MapInfo.LAKE_Y or point.y < terrain.ground_at(point):
				nearest = along
				break
	return nearest


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
		var wanted: bool = spawner.input_value(record.get("links", {}), "vanish", 0.0) != 0.0
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
		var inflow := _velocity_at(body, frame.origin).dot(axis)
		var density := Aero.air_density(Origin.to_map(frame.origin).y)
		var disc := PI * radius * radius
		var thrust: float = density * disc * float(prop["factor"]) * (pitch_speed - inflow) * absf(pitch_speed)
		if absf(thrust) < 1e-4:
			continue
		body.sleeping = false
		body.apply_force(axis * thrust, frame.origin - body.global_position)
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
