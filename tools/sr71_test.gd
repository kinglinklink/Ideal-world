extends SceneTree
## Systems and flight test for the SR-71 build (tools/make_sr71.py), made
## from the F-14's test:
##     godot --headless --path . -s tools/sr71_test.gd -- <sr71.json> [ground|takeoff|air|missile|fast|reload|ladder|dud|gear|camera] [nofail]
## missile: from 400 m, one press of Y; every bay should let go at once.
## camera: seated in first person, checks the view comes from the camera part.
## Loads it, spawns it, sits in it and works its controls through a fake
## controller, printing what every system does and every part that breaks.
## ground: on the pad; takeoff: from the start of Wild Horse Island's runway;
## air and missile: from 400 m at 120 m/s with a test pilot holding height.
## ladder: on foot by the boarding ladder, walks into it, climbs, and checks
## the seat is in reach from the top.
## barrage (the Mark 2): from 400 m, holds Y for a stream of missiles, drops
## the bombs one at a time and then holds X as they reload; reports every
## shot and blast, the nearest blast to the jet and anything the jet lost.
## dud: on the pad, fires missiles at a wall put 40 m ahead.
## gear: out over the lake, the gear going up and down by itself with the
## height, and by hand.
## nofail turns structural failure off. Environment switches for more detail:
## F14_STRESS=1 the most loaded joints, F14_PEAK=<ratio> every joint past that
## share of its strength, F14_CONTACT=1 the main body's contacts, F14_GEAR=1
## the gear pistons, F14_JUMP=1 the first moments after spawning.

const SaveManager = preload("res://scripts/save_manager.gd")
const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
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
var blasts: Array = []        # [radius, distance from the jet, from the seat]
var shots := {"missile": 0, "bomb": 0}
var was_loaded := {}          # rack name -> loaded last tick
var jet_lost: Array = []      # types of the jet's own parts destroyed (not payload)
var duds := 0

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
	[0.5, {"RB / R1": 1.0}, "reverse thrust"],
	[1.0, {}, "-"],
	[0.2, {"Y / Triangle": 1.0}, "missiles on the ground (should do nothing)"],
	[1.0, {}, "-"],
	[0.5, {"RT / R2 trigger": 0.5}, "half throttle"],
	[0.3, {"RT / R2 trigger": 1.0}, "full throttle"],
	[1.5, {}, "throttle off"],
	[1.0, {}, "done"],
]
const TAKEOFF := [
	[3.0, {}, "idle on the runway"],
	[0.2, {"D-pad up": 1.0}, "gear up pressed on the ground (should do nothing)"],
	[4.0, {"RT / R2 trigger": 1.0}, "full throttle roll"],
	[5.0, {"RT / R2 trigger": 1.0, "Left stick Y (up +)": 0.6}, "rotate at 50 m/s, hold it"],
	[2.0, {"RT / R2 trigger": 1.0, "Left stick Y (up +)": 0.2}, "climb out"],
	[9.0, {"RT / R2 trigger": 0.8}, "climbing: the gear goes up by itself past 50 m"],
	[1.0, {"RT / R2 trigger": 0.5}, "done"],
]
# Flat out at low level, with the afterburners: how fast does it get?
const FAST := [
	[2.2, {}, "level (the gear went up by itself)", true],
	[32.0, {"RT / R2 trigger": 1.0, "LT / L2 trigger": 1.0}, "full afterburner", true],
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
	[0.2, {"Y / Triangle": 1.0}, "one press of Y: all four", true],
	[3.0, {}, "away", true],
	[1.0, {}, "reloading", true],
	[0.2, {"Y / Triangle": 1.0}, "again, reloaded", true],
	[3.0, {}, "away", true],
]
# Missiles: a second press while the bays reload lets nothing go.
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
# The gear by itself and by hand, out over the lake. The fifth element is a
# height above the ground for the test pilot to hold.
const GEAR := [
	[4.0, {}, "at 80 m: the gear went up by itself", true, 80.0],
	[14.0, {}, "down to 25 m: the gear comes down by itself below 35 m", true, 25.0],
	[14.0, {}, "back up to 80 m: the gear goes up by itself past 50 m", true, 80.0],
	[0.2, {"D-pad up": 1.0}, "D-pad up at 80 m: gear down by hand", true, 80.0],
	[7.0, {}, "stays down", true, 80.0],
	[0.2, {"D-pad up": 1.0}, "D-pad up again: gear up by hand", true, 80.0],
	[7.0, {}, "up", true, 80.0],
	[1.0, {}, "done", true, 80.0],
]
# A missile fired on the pad at a wall 40 m ahead: within its safe time it
# should hit as a dud, not blow up the jet.
const DUD := [
	[1.0, {}, "idle on the pad, a wall 40 m ahead"],
	[0.2, {"Y / Triangle": 1.0}, "missile at the wall"],
	[4.0, {}, "after"],
	[1.0, {}, "done"],
]
# The Mark 2's weapons, from 400 m.
const BARRAGE := [
	[2.0, {}, "level", true],
	[3.0, {"Y / Triangle": 1.0}, "hold Y: a stream of missiles", true],
	[2.0, {}, "away", true],
	[0.2, {"X / Square": 1.0}, "bomb 1", true],
	[1.0, {}, "-", true],
	[0.2, {"X / Square": 1.0}, "bomb 2", true],
	[0.5, {}, "-", true],
	[0.2, {"X / Square": 1.0}, "nothing loaded yet: no bomb", true],
	[2.5, {}, "reloading", true],
	[2.5, {"X / Square": 1.0}, "hold X: bombs as they reload", true],
	[14.0, {}, "falling", true],
	[1.0, {}, "done", true],
]
const AIR := [
	[3.0, {}, "level", true],
	[7.2, {}, "the gear went up by itself", true],
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
	[2.0, {"D-pad down": 1.0}, "air brake", true],
	[2.0, {}, "let go", true],
	[0.2, {"Y / Triangle": 1.0}, "missiles: every bay at once", true],
	[3.5, {}, "away", true],
	[0.2, {"D-pad up": 1.0}, "gear down", true],
	[6.0, {}, "gear coming down", true],
	[1.0, {}, "done", true],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	file = args[0]
	for arg in args:
		if arg in ["air", "ground", "missile", "takeoff", "fast", "reload", "ladder", "barrage", "dud", "gear", "camera"]:
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
	var line := "elev in L %s/%s R %s/%s out L %s/%s R %s/%s | noz %s %s steer %s | gear nose %s main %s %s | doors %s %s" % [
		_angle("inboard_L_top"), _angle("inboard_L_bottom"), _angle("inboard_R_top"), _angle("inboard_R_bottom"),
		_angle("outboard_L_top"), _angle("outboard_L_bottom"), _angle("outboard_R_top"), _angle("outboard_R_bottom"),
		_angle("nozzle_L"), _angle("nozzle_R"), _angle("steer"), _length("gear_0"), _angle("main_L"), _angle("main_R"),
		_angle("door_0"), _angle("door_1")]
	var thrust: Dictionary = spawner._outputs.get(int(uids.get("thrust_L", 0)), {})
	var thrust_r: Dictionary = spawner._outputs.get(int(uids.get("thrust_R", 0)), {})
	var burner: Dictionary = spawner._outputs.get(int(uids.get("burner_L", 0)), {})
	line += " | thrust %.0fk %.0fk + %.0fk" % [float(thrust.get("thrust", 0.0)) / 1000.0, float(thrust_r.get("thrust", 0.0)) / 1000.0, float(burner.get("thrust", 0.0)) / 1000.0]
	var racks := ""
	for name in _rack_names():
		racks += "%d" % int(float(spawner.outputs_of(int(uids.get(name, 0))).get("loaded", 0.0)))
	line += " | racks %s" % racks
	var ladder: Dictionary = spawner.record_of(int(uids.get("ladder", 0)))
	if not ladder.is_empty():
		line += " ladder %s" % ("away" if spawner.input_value(ladder.get("links", {}), "stowed", 0.0) != 0.0 else "out")
	var slip := 0.0
	var v := main_body.linear_velocity
	if v.length() > 5.0:
		slip = rad_to_deg(asin(clampf(v.normalized().dot(-main_body.global_transform.basis.x), -1.0, 1.0)))
	line += " | slip %.1f" % slip
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
	print("SR71: build mass %.0f kg, centre of mass (cells) %s" % [mass, str(cg.snapped(Vector3.ONE * 0.1))])
	var lift: Array = grid.center_of_lift()
	print("SR71: centre of lift ", lift)


func _report_bodies() -> void:
	var bodies: Array = spawner.all_bodies()
	print("SR71: %d bodies" % bodies.size())
	for body in bodies:
		var kinds := {}
		for piece in spawner._body_pieces.get(body, []):
			var type: String = spawner.record_of(spawner._uid_of(piece))["type"]
			kinds[type] = int(kinds.get(type, 0)) + 1
		var where := Origin.to_map((body as RigidBody3D).global_position)
		print("SR71:   %7.0f kg %s %s" % [(body as RigidBody3D).mass, str(where.snapped(Vector3.ONE * 0.1)), str(kinds)])


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
		if OS.get_environment("SR71_STRESS") != "":
			load("res://scripts/stress.gd").view = true
		var save_name := "_sr71_test"
		DirAccess.copy_absolute(file, SaveManager.path_for(save_name))
		var result: Dictionary = SaveManager.load_build(grid, save_name)
		DirAccess.remove_absolute(SaveManager.path_for(save_name))
		print("SR71: loaded ", result)
		_map_uids()
		_report_build()
		main.get_node("BuildController").toggle_spawn()
		main_body = spawner.heaviest_body()
		spawner.part_destroyed.connect(_on_destroyed)
		_report_bodies()
		var controller: Node = main.get_node("BuildController")
		if mode != "ladder":
			print("SR71: seated ", controller.sit_in(spawner))
		main.get_node("Player").damage_enabled = false
	if frame == 12 and mode == "takeoff":
		_to_runway()
	if frame == 12 and mode == "dud":
		var wall := StaticBody3D.new()
		wall.collision_layer = Units.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(30.0, 20.0, 2.0)
		shape.shape = box
		wall.add_child(shape)
		root.add_child(wall)
		var nose: Vector3 = main_body.global_transform.basis.z
		nose.y = 0.0
		wall.global_transform = Transform3D(Basis.looking_at(nose.normalized()), main_body.global_position + nose.normalized() * 40.0)
	if frame == 12 and _flying():
		var lift := Vector3(0, _cruise_height(), 0)
		var forward: Vector3 = main_body.global_transform.basis.z
		if mode == "gear":
			forward = _over_the_lake()
			lift = Vector3.ZERO
		for body in spawner.all_bodies():
			var rb := body as RigidBody3D
			rb.global_position += lift
			rb.linear_velocity = forward * start_speed
	if frame >= 9 and frame <= 400 and frame % 4 == 0 and OS.get_environment("SR71_GEAR") != "":
		var line := "SR71: f%d main y %.3f vy %.2f |" % [frame, main_body.global_position.y, main_body.linear_velocity.y]
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
	if frame >= 9 and frame <= 40 and OS.get_environment("SR71_JUMP") != "":
		print("SR71: frame %d main v %s w %s" % [frame, str(main_body.linear_velocity.snapped(Vector3.ONE * 0.01)), str(main_body.angular_velocity.snapped(Vector3.ONE * 0.01))])
		_jumpers()
	if frame <= 12:
		return false
	if mode == "ladder":
		return _ladder_test(delta)
	if mode == "camera":
		return _camera_test(delta)
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
	elif mode == "barrage":
		script = BARRAGE
	elif mode == "dud":
		script = DUD
	elif mode == "gear":
		script = GEAR
	if not is_instance_valid(main_body):
		print("SR71: the main body is gone")
		return true
	if step == -1 or clock >= float(script[step][0]):
		step += 1
		clock = 0.0
		if step >= script.size():
			_report_bodies()
			_report_weapons()
			_key_check()
			return true
		if mode in ["gear", "takeoff"]:
			print("SR71: (gear %s)" % ("down" if float(_length("gear_0")) > 4.0 else "up"))
		print("SR71: --- ", script[step][2])
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
		if script[step].size() > 4:
			# Hold a height above the ground, from the jet's height sensor.
			var agl: float = float(spawner.outputs_of(int(uids.get("dist", 0))).get("distance", 0.0))
			want_climb = clampf((float(script[step][4]) - agl) * 0.25, -4.0, 6.0)
		if not held.has("Left stick Y (up +)"):
			var firm := 0.1 if script[step].size() > 4 else 0.04
			held["Left stick Y (up +)"] = clampf((want_climb - climb) * firm, -0.6, 0.6)
		if not held.has("Left stick X (right +)"):
			held["Left stick X (right +)"] = clampf(-roll * 0.02, -0.6, 0.6)
	Gamepad.fake = held
	clock += delta
	_count_shots()
	if mode == "missile" and step >= 1 and frame % 3 == 0:
		var rocket_uid := int(uids.get("missile_0", 0))
		var frame_body: Array = spawner.part_frame(rocket_uid) if spawner.record_of(rocket_uid).size() > 0 else []
		if not frame_body.is_empty():
			var rel: Vector3 = main_body.global_transform.affine_inverse() * (frame_body[0] as Transform3D).origin
			var mb := frame_body[1] as RigidBody3D
			print("SR71: missile rel %s v %.1f rel-v %s" % [str((rel / 0.25).snapped(Vector3.ONE * 0.1)), mb.linear_velocity.length(), str((main_body.global_transform.basis.inverse() * (mb.linear_velocity - main_body.linear_velocity)).snapped(Vector3.ONE * 0.1))])
	if OS.get_environment("SR71_CONTACT") != "" and frame % 6 == 0:
		_contacts()
	if OS.get_environment("SR71_JOLT") != "":
		_jolts()
	if OS.get_environment("SR71_PEAK") != "":
		_peaks(float(OS.get_environment("SR71_PEAK")))
	if fmod(clock, 0.1 if OS.get_environment("SR71_FINE") != "" else 0.5) < delta:
		if OS.get_environment("SR71_STRESS") != "":
			_stress_report()
		print("SR71: %4.1fs %s" % [clock, _attitude()])
		print("SR71:        %s" % _systems())
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
				print("SR71:   BREAK ", text)
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
		print("SR71: jump v %s w %s %s" % [str((item[1] as Vector3).snapped(Vector3.ONE * 0.01)), str((item[2] as Vector3).snapped(Vector3.ONE * 0.01)), str(item[3])])


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
		print("SR71:   ratio %7.1f %s <- %s area %.4f m2 beyond %6.0f kg" % [item[0], _describe(int(item[1]) >> 3),
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
	print("SR71: on the runway at map (%.0f, %.0f), ground %.1f m, heading %.0f" % [start.x, start.y, ground, rad_to_deg(heading)])


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
		print("SR71:   contact %s at %s force %.0f kN" % [other.name if other is Node else "?", str(at.snapped(Vector3.ONE * 0.1)), impulse / 1000.0])


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
				print("SR71:   peak %.2f %s <- %s area %.4f" % [float(st._ratio[piece]), _describe(int(piece) >> 3),
						_describe(int(parent[piece]) >> 3), float(tree["area"][piece])])


## Seated, M is the cruise switch: it must not open the world map too.
func _key_check() -> void:
	if OS.get_environment("SR71_UNSEAT") != "":
		main.get_node("BuildController").seat_uid = 0
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_M
		key.physical_keycode = KEY_M
		key.pressed = pressed
		Input.parse_input_event(key)
	Input.flush_buffered_events()
	print("SR71: M pressed while seated: world map open ", main._hud.world_map_open())


func _rack_names() -> Array:
	var list: Array = []
	for i in 64:
		if uids.has("rack_%d" % i):
			list.append("rack_%d" % i)
	for i in 8:
		if uids.has("bomb_rack_%d" % i):
			list.append("bomb_rack_%d" % i)
	return list


## Counts each rack letting go (loaded, then not).
func _count_shots() -> void:
	for name in _rack_names():
		var loaded := float(spawner.outputs_of(int(uids.get(name, 0))).get("loaded", 0.0)) != 0.0
		if bool(was_loaded.get(name, false)) and not loaded:
			shots["bomb" if str(name).begins_with("bomb") else "missile"] += 1
			print("SR71:   %s let go at frame %d" % [name, frame])
		was_loaded[name] = loaded


func _on_destroyed(uid: int, type: String, at: Vector3, props: Dictionary) -> void:
	if not spawner.is_payload(uid):
		jet_lost.append(type)
	if type != "explosive_block":
		return
	if spawner.is_dropped_payload(uid) and spawner.is_payload_safe(uid):
		duds += 1
		return
	var seat_at: Vector3 = main.get_node("Player").global_position
	var from_jet := at.distance_to(main_body.global_position) if is_instance_valid(main_body) else -1.0
	blasts.append([float(props.get("blast_radius", 0.0)), from_jet, at.distance_to(seat_at)])
	if blasts.size() <= 8:
		print("SR71:   blast %.0f m, %.0f m from the jet, %.0f m from the pilot (map y %.0f)" % [
				float(props.get("blast_radius", 0.0)), from_jet, at.distance_to(seat_at), Origin.to_map(at).y])


func _report_weapons() -> void:
	var nearest_jet := INF
	var nearest_pilot := INF
	var radii := {}
	for item in blasts:
		nearest_jet = minf(nearest_jet, float(item[1]))
		nearest_pilot = minf(nearest_pilot, float(item[2]))
		radii[int(item[0])] = true
	print("SR71: === shots: %d missiles, %d bombs | blasts %d (radii %s), duds %d | nearest blast to the jet %.0f m, to the pilot %.0f m" % [
			shots["missile"], shots["bomb"], blasts.size(), str(radii.keys()), duds, nearest_jet, nearest_pilot])
	var lost := {}
	for type in jet_lost:
		lost[type] = int(lost.get(type, 0)) + 1
	print("SR71: === the jet's own parts destroyed: %d %s" % [jet_lost.size(), str(lost)])


## For the gear test: finds the longest straight run of open water within
## 5 km of the pad, and turns the jet and puts it 80 m over the start of it,
## heading along it. Returns its new forward.
func _over_the_lake() -> Vector3:
	var terrain: Node = spawner.terrain
	var forward0: Vector3 = main_body.global_transform.basis.z
	forward0.y = 0.0
	forward0 = forward0.normalized()
	var pivot: Vector3 = main_body.global_position
	var centre := Origin.to_map(pivot)
	var best_start := centre
	var best_dir := forward0
	var best_run := -1.0
	for gx in range(-10, 11):
		for gz in range(-10, 11):
			var x0 := centre.x + gx * 500.0
			var z0 := centre.z + gz * 500.0
			if float(terrain.height_at(x0, z0)) >= MapInfo.LAKE_Y - 0.5:
				continue
			for i in 12:
				var dir := Vector3(sin(TAU * i / 12.0), 0.0, cos(TAU * i / 12.0))
				var run := 0.0
				while run < 7000.0 and float(terrain.height_at(x0 + dir.x * run, z0 + dir.z * run)) < MapInfo.LAKE_Y - 0.5:
					run += 100.0
				if run > best_run:
					best_run = run
					best_dir = dir
					best_start = Vector3(x0, 0.0, z0)
	print("SR71: over the lake: %.0f m of open water ahead" % best_run)
	var target := Origin.to_world(Vector3(best_start.x, MapInfo.LAKE_Y + 82.0, best_start.z))
	var turn := Basis(Vector3.UP, forward0.signed_angle_to(best_dir, Vector3.UP))
	spawner.teleport(Transform3D(turn, target) * Transform3D(Basis.IDENTITY, -pivot))
	return best_dir


func _flying() -> bool:
	return mode in ["air", "missile", "fast", "reload", "barrage", "gear"]


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
			print("SR71:   jolt %.0f g body of %d pieces, %.0f kg" % [g, spawner._body_pieces.get(body, []).size(), body.mass])


## How high the test pilot flies: 400 m, or what F14_HEIGHT says.
func _cruise_height() -> float:
	var asked := OS.get_environment("SR71_HEIGHT")
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
		print("SR71: --- on foot by the ladder, feet y %.2f, ladder top y %.2f" % [feet.y, _ladder_top])
		step = 0
		clock = 0.0
		return false
	clock += delta
	var y: float = player.global_position.y
	_ladder_best = maxf(_ladder_best, y)
	if step == 0:
		# Settle, then push the stick forward, into the ladder.
		Gamepad.fake = {} if clock < 1.0 else {"Left stick Y (up +)": 1.0}
		if fmod(clock, 0.25) < delta or (OS.get_environment("SR71_LADDER") != "" and y > 1.3 and y < 1.9):
			var hits := ""
			for index in player.get_slide_collision_count():
				var hit: KinematicCollision3D = player.get_slide_collision(index)
				var who: Object = hit.get_collider()
				var kind := "?"
				if who is RigidBody3D:
					var uid: int = spawner.part_of_shape(who, hit.get_collider_shape_index())
					kind = str(spawner.record_of(uid).get("type", "?")) + "@" + str((Vector3(spawner.record_of(uid).get("pos", Vector3i.ZERO)) / 200.0).snapped(Vector3.ONE * 0.1))
				hits += " %s n%s" % [kind, str(hit.get_normal().snapped(Vector3.ONE * 0.01))]
			print("SR71:  %.2fs feet y %.2f on ladder %s |%s" % [clock, y, str(player._ladder != Vector3.ZERO), hits])
		if player._ladder != Vector3.ZERO:
			_ladder_climbed = true
		if clock >= 5.0:
			Gamepad.fake = {}
			print("SR71: --- climbed: %s, highest feet y %.2f (ladder top %.2f)" % [str(_ladder_climbed), _ladder_best, _ladder_top])
			controller._seat_request = true
			step = 1
			clock = 0.0
		return false
	if clock >= 0.2:
		print("SR71: --- asked for the seat: seated %s" % str(player.seated))
		return true
	return false


## Seated, switches to first person and checks the view comes from the
## camera part, looking along the nose, then back to third person.
func _camera_test(delta: float) -> bool:
	var player: Node = main.get_node("Player")
	clock += delta
	if step == -1:
		player.zoom = 0.0
		step = 0
		clock = 0.0
		return false
	if step == 0 and clock >= 1.0:
		var cam: Camera3D = player._camera
		var expected: Array = spawner.camera_for_seat(int(uids.get("seat", 0)))
		if expected.is_empty():
			print("SR71: no camera found for the seat")
			return true
		var at: Vector3 = (expected[0] as Transform3D).origin
		var looks: Vector3 = -cam.global_transform.basis.z
		var nose: Vector3 = main_body.global_transform.basis.z
		print("SR71: first person %s, view %.3f m from the camera part, %.1f deg off the nose, fov %.0f (camera's %.0f)" % [
				str(player.is_first_person()), cam.global_position.distance_to(at), rad_to_deg(looks.angle_to(nose)),
				cam.fov, float(expected[1])])
		var seat: Array = spawner.seat_frame(int(uids.get("seat", 0)))
		var local: Vector3 = main_body.global_transform.affine_inverse() * cam.global_position
		print("SR71: view in the jet (cells) %s, seat at %s" % [str((local / 0.25).snapped(Vector3.ONE * 0.1)),
				str(((main_body.global_transform.affine_inverse() * (seat[0] as Transform3D).origin) / 0.25).snapped(Vector3.ONE * 0.1))])
		player.zoom = 8.0
		step = 1
		clock = 0.0
		return false
	if step == 1 and clock >= 0.5:
		var cam2: Camera3D = player._camera
		var expected2: Array = spawner.camera_for_seat(int(uids.get("seat", 0)))
		print("SR71: third person: view %.1f m from the camera part, fov %.0f" % [
				cam2.global_position.distance_to((expected2[0] as Transform3D).origin), cam2.fov])
		return true
	return false
