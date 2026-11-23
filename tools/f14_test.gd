extends SceneTree
## Systems and flight test for the F-14 build (tools/make_f14.py):
##     godot --headless --path . -s tools/f14_test.gd -- <f14.json> [ground|takeoff|air|missile|fast|reload|ladder] [nofail]
## Loads it, spawns it, sits in it and works its controls through a fake
## controller, printing what every system does and every part that breaks.
## ground: on the pad; takeoff: from the start of Wild Horse Island's runway;
## air and missile: from 400 m at 120 m/s with a test pilot holding height.
## ladder: on foot by the boarding ladder, walks into it, climbs, and checks
## the seat is in reach from the top.
## nofail turns structural failure off. Environment switches for more detail:
## F14_STRESS=1 the most loaded joints, F14_PEAK=<ratio> every joint past that
## share of its strength, F14_CONTACT=1 the main body's contacts, F14_GEAR=1
## the gear pistons, F14_JUMP=1 the first moments after spawning.

const SaveManager = preload("res://scripts/save_manager.gd")
const Origin = preload("res://scripts/origin.gd")
const FailureLog = preload("res://scripts/failure_log.gd")
const Gamepad = preload("res://scripts/gamepad.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Units = preload("res://scripts/units.gd")

var main: Node
var spawner: Node
var grid: Node
var frame := 0
var file := ""
var mode := "ground"
var no_fail := false
var names: Dictionary = {}
var uids: Dictionary = {}     # name -> uid
var main_body: RigidBody3D
var step := -1
var clock := 0.0
var seen_breaks := 0
var start_speed := 120.0
var cruise := 120.0

# Each phase: [seconds, controller controls held, label, keys held]
const GROUND := [
	[1.5, {}, "idle"],
	[1.0, {"Left stick Y (up +)": 1.0}, "stick back"],
	[1.0, {"Left stick Y (up +)": -1.0}, "stick forward"],
	[1.0, {"Left stick X (right +)": 1.0}, "stick right"],
	[1.0, {"D-pad down": 1.0}, "air brake"],
	[1.0, {"D-pad right": 1.0}, "rudder right"],
	[0.2, {"D-pad up": 1.0}, "gear up asked, on the ground"],
	[2.0, {}, "gear should stay down"],
	[0.2, {"D-pad up": 1.0}, "gear request cancelled"],
	[0.2, {"LB / L1": 1.0}, "wings back"],
	[4.0, {}, "sweeping"],
	[0.2, {"LB / L1": 1.0}, "wings forward"],
	[4.0, {}, "sweeping"],
	[0.5, {"RT / R2 trigger": 0.5}, "half throttle"],
	[0.3, {"RT / R2 trigger": 1.0}, "full throttle"],
	[1.5, {}, "throttle off"],
	[0.5, {"A / Cross": 1.0}, "cannons"],
	[0.5, {"B / Circle": 1.0}, "guns"],
	[1.0, {}, "done"],
]
const TAKEOFF := [
	[3.0, {}, "idle on the runway"],
	[0.2, {"D-pad up": 1.0}, "gear up pressed on the ground (should do nothing)"],
	[3.5, {"RT / R2 trigger": 1.0}, "full throttle roll"],
	[3.0, {"RT / R2 trigger": 1.0, "Left stick Y (up +)": 0.6}, "rotate"],
	[2.0, {"RT / R2 trigger": 0.8}, "climb out"],
	[0.2, {"RT / R2 trigger": 0.8, "D-pad up": 1.0}, "gear up"],
	[7.0, {"RT / R2 trigger": 0.8}, "gear going up"],
	[1.0, {"RT / R2 trigger": 0.5}, "done"],
]
# Flat out at low level, with the afterburners: how fast does it get?
const FAST := [
	[2.0, {}, "level", true],
	[0.2, {"D-pad up": 1.0}, "gear up", true],
	[10.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0}, "full afterburner", true],
	[2.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0, "Left stick Y (up +)": 0.5}, "pull at speed", false],
	[3.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0}, "let go", true],
	[2.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0, "Left stick X (right +)": 1.0}, "roll at speed", false],
	[3.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0}, "let go", true],
	[1.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0, "D-pad right": 1.0}, "yaw at speed", false],
	[3.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0}, "let go", true],
	[0.2, {"Y / Triangle": 1.0}, "missile at speed", true],
	[8.0, {}, "throttle off", true],
	[4.0, {"D-pad down": 1.0}, "air brake", true],
	[1.0, {}, "done", true],
]
const MISSILE := [
	[2.0, {}, "level", true],
	[0.2, {"Y / Triangle": 1.0}, "missile 1", true],
	[3.0, {}, "away", true],
]
# Missiles: fire all four, then the first again once it has reloaded.
const RELOAD := [
	[2.0, {}, "level", true],
	[0.2, {"Y / Triangle": 1.0}, "missile", true],
	[0.4, {}, "-", true],
	[0.2, {"Y / Triangle": 1.0}, "missile", true],
	[0.4, {}, "-", true],
	[0.2, {"Y / Triangle": 1.0}, "missile", true],
	[0.4, {}, "-", true],
	[0.2, {"Y / Triangle": 1.0}, "missile", true],
	[0.4, {}, "-", true],
	[0.2, {"Y / Triangle": 1.0}, "nothing loaded: nothing fires", true],
	[3.5, {}, "reloading", true],
	[0.2, {"Y / Triangle": 1.0}, "first reloaded missile", true],
	[3.0, {}, "away", true],
]
const AIR := [
	[3.0, {}, "level", true],
	[0.2, {"D-pad up": 1.0}, "gear up", true],
	[7.0, {}, "gear going up", true],
	[1.0, {"Left stick Y (up +)": 1.0}, "pull", false],
	[3.0, {}, "let go", true],
	[1.0, {"Left stick Y (up +)": -1.0}, "push", false],
	[3.0, {}, "let go", true],
	[1.0, {"Left stick X (right +)": 1.0}, "roll right", false],
	[3.0, {}, "let go", true],
	[1.0, {"Left stick X (right +)": -1.0}, "roll left", false],
	[3.0, {}, "let go", true],
	[1.5, {"D-pad right": 1.0}, "yaw right", false],
	[3.0, {}, "let go", true],
	[0.2, {"LB / L1": 1.0}, "wings back", true],
	[5.0, {}, "swept", true],
	[1.0, {"Left stick Y (up +)": 1.0}, "pull, swept", false],
	[3.0, {}, "let go", true],
	[0.2, {"LB / L1": 1.0}, "wings forward", true],
	[5.0, {}, "spread", true],
	[2.0, {"D-pad down": 1.0}, "air brake", true],
	[2.0, {}, "let go", true],
	[0.2, {"Y / Triangle": 1.0}, "missile 1", true],
	[1.5, {}, "away", true],
	[0.2, {"Y / Triangle": 0.0}, "-", true],
	[0.2, {"Y / Triangle": 1.0}, "missile 2", true],
	[2.0, {}, "away", true],
	[1.0, {"A / Cross": 1.0}, "cannons", true],
	[1.0, {"B / Circle": 1.0}, "guns", true],
	[0.2, {"D-pad up": 1.0}, "gear down", true],
	[6.0, {}, "gear coming down", true],
	[1.0, {}, "done", true],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	file = args[0]
	for arg in args:
		if arg in ["air", "ground", "missile", "takeoff", "fast", "reload", "ladder"]:
			mode = arg
	no_fail = args.has("nofail")
	names = JSON.parse_string(FileAccess.get_file_as_string(file + ".names.json"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _angle(name: String) -> String:
	var out: Dictionary = spawner._outputs.get(int(uids.get(name, 0)), {})
	return "%5.1f" % float(out.get("angle", 0.0))


func _length(name: String) -> String:
	var uid := int(uids.get(name, 0))
	for item in spawner._sliders:
		if int(item["uid"]) == uid:
			return "%4.1f" % ((float(item["start"]) + float(item["setpoint"])) / Units.CELL)
	return "  - "


func _attitude() -> String:
	var b := main_body.global_transform.basis
	var nose := b.z
	var up := b.y
	var right := -b.x
	var pitch := rad_to_deg(asin(clampf(nose.y, -1, 1)))
	var roll := rad_to_deg(atan2(-right.y, up.y))
	var heading := rad_to_deg(atan2(nose.x, nose.z))
	var v := main_body.linear_velocity
	var alt := Origin.to_map(main_body.global_position).y
	return "pitch %6.1f roll %6.1f hdg %6.1f | v %5.1f fwd %5.1f climb %5.1f | alt %5.0f" % [
		pitch, roll, heading, v.length(), v.dot(nose), v.y, alt]


func _systems() -> String:
	var line := "surf in L %s/%s R %s/%s out L %s/%s R %s/%s stab L %s/%s R %s/%s | rud %s noz %s steer %s | wing %s %s | gear %s %s %s door %s %s %s" % [
		_angle("inboard_L_top"), _angle("inboard_L_bottom"), _angle("inboard_R_top"), _angle("inboard_R_bottom"),
		_angle("outboard_L_top"), _angle("outboard_L_bottom"), _angle("outboard_R_top"), _angle("outboard_R_bottom"),
		_angle("stab_L_top"), _angle("stab_L_bottom"), _angle("stab_R_top"), _angle("stab_R_bottom"),
		_angle("rudder_L"), _angle("nozzle_L"), _angle("steer"), _angle("pivot_L"), _angle("pivot_R"),
		_length("gear_0"), _length("gear_1"), _length("gear_2"), _length("door_0"), _length("door_1"), _length("door_2")]
	var thrust: Dictionary = spawner._outputs.get(int(uids.get("thrust_L", 0)), {})
	var burner: Dictionary = spawner._outputs.get(int(uids.get("burner_L", 0)), {})
	line += " | thrust %.0fk + %.0fk" % [float(thrust.get("thrust", 0.0)) / 1000.0, float(burner.get("thrust", 0.0)) / 1000.0]
	var racks := ""
	for i in 4:
		racks += "%d" % int(float(spawner.outputs_of(int(uids.get("rack_%d" % i, 0))).get("loaded", 0.0)))
	line += " | racks %s" % racks
	var ladder: Dictionary = spawner.record_of(int(uids.get("ladder", 0)))
	if not ladder.is_empty():
		line += " ladder %s" % ("away" if spawner.input_value(ladder.get("links", {}), "stowed", 0.0) != 0.0 else "out")
	var tip: Array = spawner.part_frame(int(uids.get("tip_L", 0)))
	if not tip.is_empty():
		var local: Vector3 = main_body.global_transform.affine_inverse() * (tip[0] as Transform3D).origin
		line += " | left tip z %.1f" % (local.z / 0.25)
	return line


func _map_uids() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	var parts: Array = data["parts"]
	var by_place := {}
	for uid in grid.all_uids():
		var record: Dictionary = grid.get_part(uid)
		by_place["%s %s" % [record["type"], str(record["pos"])]] = uid
	for name in names:
		var entry: Dictionary = parts[int(names[name])]
		var p: Array = entry["pos"]
		var pos := Vector3i(roundi(float(p[0]) * 200.0), roundi(float(p[1]) * 200.0), roundi(float(p[2]) * 200.0))
		uids[name] = by_place.get("%s %s" % [entry["type"], str(pos)], 0)


func _report_build() -> void:
	var mass := 0.0
	var moment := Vector3.ZERO
	for uid in grid.all_uids():
		var record: Dictionary = grid.get_part(uid)
		if BuildGrid.is_hidden_control(record):
			continue
		var m := BuildGrid.mass_of(record)
		mass += m
		moment += BuildGrid.centroid_of(record) * m
	var cg := moment / mass / Units.CELL
	print("F14: build mass %.0f kg, centre of mass (cells) %s" % [mass, str(cg.snapped(Vector3.ONE * 0.1))])
	var lift: Array = grid.center_of_lift()
	print("F14: centre of lift ", lift)


func _report_bodies() -> void:
	var bodies: Array = spawner.all_bodies()
	print("F14: %d bodies" % bodies.size())
	for body in bodies:
		var kinds := {}
		for piece in spawner._body_pieces.get(body, []):
			var type: String = spawner.record_of(spawner._uid_of(piece))["type"]
			kinds[type] = int(kinds.get(type, 0)) + 1
		var where := Origin.to_map((body as RigidBody3D).global_position)
		print("F14:   %7.0f kg %s %s" % [(body as RigidBody3D).mass, str(where.snapped(Vector3.ONE * 0.1)), str(kinds)])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		spawner = main.get_node("Spawner")
		grid = main.get_node("BuildGrid")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		if no_fail:
			load("res://scripts/stress.gd").failure = false
		if OS.get_environment("F14_STRESS") != "":
			load("res://scripts/stress.gd").view = true
		var save_name := "_f14_test"
		DirAccess.copy_absolute(file, SaveManager.path_for(save_name))
		var result: Dictionary = SaveManager.load_build(grid, save_name)
		DirAccess.remove_absolute(SaveManager.path_for(save_name))
		print("F14: loaded ", result)
		_map_uids()
		_report_build()
		main.get_node("BuildController").toggle_spawn()
		main_body = spawner.heaviest_body()
		_report_bodies()
		var controller: Node = main.get_node("BuildController")
		if mode != "ladder":
			print("F14: seated ", controller.sit_in(spawner))
		main.get_node("Player").damage_enabled = false
	if frame == 12 and mode == "takeoff":
		_to_runway()
	if frame == 12 and _flying():
		var lift := Vector3(0, _cruise_height(), 0)
		var forward: Vector3 = main_body.global_transform.basis.z
		for body in spawner.all_bodies():
			var rb := body as RigidBody3D
			rb.global_position += lift
			rb.linear_velocity = forward * start_speed
	if frame >= 9 and frame <= 400 and frame % 4 == 0 and OS.get_environment("F14_GEAR") != "":
		var line := "F14: f%d main y %.3f vy %.2f |" % [frame, main_body.global_position.y, main_body.linear_velocity.y]
		for item in spawner._sliders:
			var sl: Dictionary = item
			line += " s%d set %.3f ask %.2f" % [int(sl["uid"]), float(sl["setpoint"]), float(sl["asked"])]
		for body in spawner.all_bodies():
			var kinds: Array = []
			for piece in spawner._body_pieces.get(body, []):
				kinds.append(spawner.record_of(spawner._uid_of(piece))["type"])
			if kinds.has("wheel") and kinds.size() == 1:
				line += " tyre vy %.2f w %.1f" % [(body as RigidBody3D).linear_velocity.y, (body as RigidBody3D).angular_velocity.length()]
		print(line)
	if frame >= 9 and frame <= 40 and OS.get_environment("F14_JUMP") != "":
		print("F14: frame %d main v %s w %s" % [frame, str(main_body.linear_velocity.snapped(Vector3.ONE * 0.01)), str(main_body.angular_velocity.snapped(Vector3.ONE * 0.01))])
		_jumpers()
	if frame <= 12:
		return false
	if mode == "ladder":
		return _ladder_test(delta)
	var script: Array = GROUND
	if mode == "air":
		script = AIR
	elif mode == "missile":
		script = MISSILE
	elif mode == "takeoff":
		script = TAKEOFF
	elif mode == "fast":
		script = FAST
	elif mode == "reload":
		script = RELOAD
	if not is_instance_valid(main_body):
		print("F14: the main body is gone")
		return true
	if step == -1 or clock >= float(script[step][0]):
		step += 1
		clock = 0.0
		if step >= script.size():
			_report_bodies()
			_key_check()
			return true
		print("F14: --- ", script[step][2])
	var held: Dictionary = (script[step][1] as Dictionary).duplicate()
	# In the air a simple test pilot holds the speed with the trigger, and,
	# when the phase leaves the stick alone, holds the height and levels the
	# wings.
	if _flying() and not held.has("RT / R2 trigger"):
		var fwd := main_body.linear_velocity.dot(main_body.global_transform.basis.z)
		held["RT / R2 trigger"] = clampf((cruise - fwd) * 0.08 + 0.45, 0.0, 1.0)
	if _flying() and bool(script[step].size() > 3 and script[step][3]):
		var b := main_body.global_transform.basis
		var right := -b.x
		var roll := rad_to_deg(atan2(-right.y, b.y.y))
		var climb := main_body.linear_velocity.y
		var alt: float = Origin.to_map(main_body.global_position).y
		var want_climb := clampf((_cruise_height() - alt) * 0.1, -10.0, 10.0)
		if not held.has("Left stick Y (up +)"):
			held["Left stick Y (up +)"] = clampf((want_climb - climb) * 0.04, -0.6, 0.6)
		if not held.has("Left stick X (right +)"):
			held["Left stick X (right +)"] = clampf(-roll * 0.02, -0.6, 0.6)
	Gamepad.fake = held
	clock += delta
	if mode == "missile" and step >= 1 and frame % 3 == 0:
		var rocket_uid := int(uids.get("missile_0", 0))
		var frame_body: Array = spawner.part_frame(rocket_uid) if spawner.record_of(rocket_uid).size() > 0 else []
		if not frame_body.is_empty():
			var rel: Vector3 = main_body.global_transform.affine_inverse() * (frame_body[0] as Transform3D).origin
			var mb := frame_body[1] as RigidBody3D
			print("F14: missile rel %s v %.1f rel-v %s" % [str((rel / 0.25).snapped(Vector3.ONE * 0.1)), mb.linear_velocity.length(), str((main_body.global_transform.basis.inverse() * (mb.linear_velocity - main_body.linear_velocity)).snapped(Vector3.ONE * 0.1))])
	if OS.get_environment("F14_CONTACT") != "" and frame % 6 == 0:
		_contacts()
	if OS.get_environment("F14_JOLT") != "":
		_jolts()
	if OS.get_environment("F14_PEAK") != "":
		_peaks(float(OS.get_environment("F14_PEAK")))
	if fmod(clock, 0.1 if OS.get_environment("F14_FINE") != "" else 0.5) < delta:
		if OS.get_environment("F14_STRESS") != "":
			_stress_report()
		print("F14: %4.1fs %s" % [clock, _attitude()])
		print("F14:        %s" % _systems())
		var log_node = FailureLog.instance
		if log_node != null:
			var entries: Array = log_node._entries
			while seen_breaks < entries.size():
				var text: String = entries[seen_breaks]["text"]
				var found := RegEx.create_from_string("\\(part (\\d+)\\)").search(text)
				if found != null:
					var record: Dictionary = grid.get_part(int(found.get_string(1)))
					if not record.is_empty():
						text += "  [%s @ %s]" % [record["type"], str(Vector3(record["pos"]) / 200.0)]
				print("F14:   BREAK ", text)
				seen_breaks += 1
	return false


## Prints the bodies that moved fastest in the first moments after spawn.
func _jumpers() -> void:
	var list: Array = []
	for body in spawner.all_bodies():
		var rb := body as RigidBody3D
		var kinds := {}
		for piece in spawner._body_pieces.get(body, []):
			var type: String = spawner.record_of(spawner._uid_of(piece))["type"]
			kinds[type] = int(kinds.get(type, 0)) + 1
		list.append([rb.linear_velocity.length() + rb.angular_velocity.length(), rb.linear_velocity, rb.angular_velocity, kinds])
	list.sort_custom(func(a, b_): return a[0] > b_[0])
	for item in list.slice(0, 6):
		print("F14: jump v %s w %s %s" % [str((item[1] as Vector3).snapped(Vector3.ONE * 0.01)), str((item[2] as Vector3).snapped(Vector3.ONE * 0.01)), str(item[3])])


## The most loaded joints in the build: part, what it hangs from, the
## face area and the mass beyond it.
func _stress_report() -> void:
	var st: Node = spawner.stress
	var list: Array = []
	for body in spawner.all_bodies():
		var tree: Dictionary = st._trees.get(body, {})
		if tree.is_empty():
			continue
		var parent: Dictionary = tree["parent"]
		var area: Dictionary = tree["area"]
		var order: Array = tree["order"]
		var beyond: Dictionary = {}
		for index in range(order.size() - 1, -1, -1):
			var piece: int = order[index]
			beyond[piece] = float(beyond.get(piece, 0.0)) + spawner.mass_of_piece(piece)
			var up: int = parent[piece]
			if up >= 0:
				beyond[up] = float(beyond.get(up, 0.0)) + float(beyond[piece])
		for piece in parent:
			if int(parent[piece]) >= 0 and st._ratio.has(piece):
				list.append([float(st._ratio[piece]), piece, int(parent[piece]), float(area[piece]), float(beyond[piece])])
	list.sort_custom(func(a, b_): return a[0] > b_[0])
	for item in list.slice(0, 10):
		print("F14:   ratio %7.1f %s <- %s area %.4f m2 beyond %6.0f kg" % [item[0], _describe(int(item[1]) >> 3),
				_describe(int(item[2]) >> 3), item[3], item[4]])


func _describe(uid: int) -> String:
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return "?"
	var pos: Vector3 = Vector3(record["pos"]) / 200.0
	return "%s %s@(%.2f,%.2f,%.2f)%s" % [record["type"], str(record.get("material", "")), pos.x, pos.y, pos.z, str(record.get("size", ""))]


## Puts the build at the start of Wild Horse Island's runway, nose along it.
func _to_runway() -> void:
	var terrain: Node = main.get_node("Terrain")
	var runway: Dictionary = terrain.world["runways"][0]
	var centre: Array = runway["centre"]
	var heading := deg_to_rad(float(runway["heading"]))
	var along := Vector2(sin(heading), -cos(heading))
	var start := Vector2(float(centre[0]), float(centre[1])) - along * (float(runway["length"]) * 0.5 - 60.0)
	var ground := float(terrain.height_at(start.x, start.y))
	# Lowest point of the build now: the bottom of the lowest wheel.
	var low := INF
	for body in spawner.all_bodies():
		var rb := body as RigidBody3D
		low = minf(low, rb.global_position.y)
	var pivot: Vector3 = main_body.global_position
	var nose: Vector3 = main_body.global_transform.basis.z
	var turn := Basis(Vector3.UP, atan2(along.x, along.y) - atan2(nose.x, nose.z))
	var target := Origin.to_world(Vector3(start.x, 0.0, start.y))
	target.y = pivot.y + (ground - Origin.to_map(Vector3(0, low, 0)).y) + 0.6
	for body in spawner.all_bodies():
		var rb := body as RigidBody3D
		var rel: Vector3 = rb.global_position - pivot
		rb.global_transform = Transform3D(turn * rb.global_transform.basis, target + turn * rel)
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	main.get_node("Player").global_position += target - pivot
	print("F14: on the runway at map (%.0f, %.0f), ground %.1f m, heading %.0f" % [start.x, start.y, ground, rad_to_deg(heading)])


## Where the main body touches anything, in grid cells, and how hard.
func _contacts() -> void:
	var state := PhysicsServer3D.body_get_direct_state(main_body.get_rid())
	if state == null:
		return
	var origin: Vector3 = spawner.body_origin_in_grid(main_body)
	var from_world := main_body.global_transform.affine_inverse()
	for i in state.get_contact_count():
		var impulse := state.get_contact_impulse(i).length() * Engine.physics_ticks_per_second
		if impulse < 1000.0:
			continue
		var at: Vector3 = (from_world * state.get_contact_local_position(i) + origin) / 0.25
		var other: Object = state.get_contact_collider_object(i)
		print("F14:   contact %s at %s force %.0f kN" % [other.name if other is Node else "?", str(at.snapped(Vector3.ONE * 0.1)), impulse / 1000.0])


## Every joint loaded past `limit` of its strength right now.
func _peaks(limit: float) -> void:
	var st: Node = spawner.stress
	for body in spawner.all_bodies():
		var tree: Dictionary = st._trees.get(body, {})
		if tree.is_empty():
			continue
		var parent: Dictionary = tree["parent"]
		for piece in parent:
			if int(parent[piece]) >= 0 and float(st._ratio.get(piece, 0.0)) > limit:
				print("F14:   peak %.2f %s <- %s area %.4f" % [float(st._ratio[piece]), _describe(int(piece) >> 3),
						_describe(int(parent[piece]) >> 3), float(tree["area"][piece])])


## Seated, M is the cruise switch: it must not open the world map too.
func _key_check() -> void:
	if OS.get_environment("F14_UNSEAT") != "":
		main.get_node("BuildController").seat_uid = 0
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_M
		key.physical_keycode = KEY_M
		key.pressed = pressed
		Input.parse_input_event(key)
	Input.flush_buffered_events()
	print("F14: M pressed while seated: world map open ", main._hud.world_map_open())


func _flying() -> bool:
	return mode in ["air", "missile", "fast", "reload"]


## Bodies whose speed is changing faster than 10 g over the crash window.
var _jolt_history: Dictionary = {}
func _jolts() -> void:
	for item in spawner.all_bodies():
		var body := item as RigidBody3D
		var history: Array = _jolt_history.get(body, [])
		history.append(body.linear_velocity)
		if history.size() > 13:
			history.pop_front()
		_jolt_history[body] = history
		if history.size() < 13:
			continue
		var g: float = ((history[12] as Vector3) - (history[0] as Vector3)).length() / (12.0 / 240.0) / 9.81
		if g > 10.0:
			print("F14:   jolt %.0f g body of %d pieces, %.0f kg" % [g, spawner._body_pieces.get(body, []).size(), body.mass])


## How high the test pilot flies: 400 m, or what F14_HEIGHT says.
func _cruise_height() -> float:
	var asked := OS.get_environment("F14_HEIGHT")
	return float(asked) if asked != "" else 400.0


var _ladder_out := Vector3.ZERO
var _ladder_top := 0.0
var _ladder_best := 0.0
var _ladder_climbed := false


## On foot: stands the character on the ground in front of the boarding
## ladder, facing it, pushes the stick forward and watches it climb. At the
## top it asks for the seat, the way pressing E does.
func _ladder_test(delta: float) -> bool:
	var player: Node = main.get_node("Player")
	var controller: Node = main.get_node("BuildController")
	if step == -1:
		var ladder: Array = spawner.part_frame(int(uids.get("ladder", 0)))
		var seat: Array = spawner.seat_frame(int(uids.get("seat", 0)))
		var at: Vector3 = (ladder[0] as Transform3D).origin
		var side := (main_body.global_transform.affine_inverse() * at).x - (main_body.global_transform.affine_inverse() * (seat[0] as Transform3D).origin).x
		_ladder_out = main_body.global_transform.basis.x.normalized() * signf(side)
		_ladder_out.y = 0.0
		_ladder_out = _ladder_out.normalized()
		_ladder_top = at.y + 2.0
		var feet := at + _ladder_out * 0.9 - Vector3(0, 2.0, 0)
		player.teleport(feet, atan2(_ladder_out.x, _ladder_out.z))
		_ladder_best = feet.y
		print("F14: --- on foot by the ladder, feet y %.2f, ladder top y %.2f" % [feet.y, _ladder_top])
		step = 0
		clock = 0.0
		return false
	clock += delta
	var y: float = player.global_position.y
	_ladder_best = maxf(_ladder_best, y)
	if step == 0:
		# Settle, then push the stick forward, into the ladder.
		Gamepad.fake = {} if clock < 1.0 else {"Left stick Y (up +)": 1.0}
		if fmod(clock, 0.25) < delta:
			print("F14:  %.2fs feet y %.2f on ladder %s" % [clock, y, str(player._ladder != Vector3.ZERO)])
		if player._ladder != Vector3.ZERO:
			_ladder_climbed = true
		if clock >= 5.0:
			Gamepad.fake = {}
			print("F14: --- climbed: %s, highest feet y %.2f (ladder top %.2f)" % [str(_ladder_climbed), _ladder_best, _ladder_top])
			controller._seat_request = true
			step = 1
			clock = 0.0
		return false
	if clock >= 0.2:
		print("F14: --- asked for the seat: seated %s" % str(player.seated))
		return true
	return false
