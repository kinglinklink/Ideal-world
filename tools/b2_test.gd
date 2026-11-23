extends SceneTree
## Systems and flight test for the B-2 build (tools/make_b2.py):
##     godot --headless --path . -s tools/b2_test.gd -- <b2.json> [ground|takeoff|air|bomb|low|ladder] [nofail]
## Loads it, spawns it, sits in it and works its controls through a fake
## controller, printing what every system does, every part that breaks, every
## blast, and how long the physics ticks take.
## ground: on the pad. takeoff: To runway, then off. air: from B2_HEIGHT
## (default 400) m at 130 m/s with a test pilot holding height. bomb: the
## bombs, big and small, and the missiles, from B2_HEIGHT (default 1200) m.
## low: bombs asked for too low (nothing should drop). ladder: on foot,
## climb the ladder through the hatch and sit.
## B2_STRESS=1 the most loaded joints; B2_FINE=1 a line every 0.1 s.

const Origin = preload("res://scripts/origin.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const FailureLog = preload("res://scripts/failure_log.gd")
const Gamepad = preload("res://scripts/gamepad.gd")
const Profiler = preload("res://scripts/profiler.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")

var main: Node
var spawner: Node
var grid: Node
var controller: Node
var frame := 0
var file := ""
var mode := "ground"
var no_fail := false
var names: Dictionary = {}
var uids: Dictionary = {}
var main_body: RigidBody3D
var step := -1
var clock := 0.0
var seen_breaks := 0
var cruise := 130.0
var blasts: Array = []        # [time, radius, distance from the plane]
var released := 0
var alive := 0.0
var tick_start := 0
var wall_start := 0
var worst_frame := 0.0

# Each phase: [seconds, controls held, label, test pilot holds height and wings]
const GROUND := [
	[2.0, {}, "idle"],
	[1.0, {"Left stick Y (up +)": 1.0}, "stick back"],
	[1.0, {"Left stick Y (up +)": -1.0}, "stick forward"],
	[1.0, {"Left stick X (right +)": 1.0}, "stick right"],
	[0.5, {"A / Cross": 1.0}, "carpet on the ground (nothing drops)"],
	[0.5, {"Y / Triangle": 1.0}, "big bomb on the ground (nothing)"],
	[0.5, {"LT / L2 trigger": 1.0}, "missiles on the ground (nothing)"],
	[1.0, {}, "-"],
	[0.5, {"RT / R2 trigger": 0.3}, "a little throttle"],
	[1.5, {}, "throttle off"],
	[0.5, {}, "done"],
]
const TAKEOFF := [
	[3.0, {}, "idle on the runway"],
	[6.0, {"RT / R2 trigger": 1.0}, "full throttle roll"],
	[3.0, {"RT / R2 trigger": 1.0, "Left stick Y (up +)": 1.0}, "rotate"],
	[6.0, {"RT / R2 trigger": 1.0}, "climb out", true],
	[12.0, {"RT / R2 trigger": 0.8}, "climbing, gear should go up", true],
	[2.0, {"RT / R2 trigger": 0.6}, "done", true],
]
const AIR := [
	[4.0, {}, "level", true],
	[2.0, {"Left stick Y (up +)": 1.0}, "pull", false],
	[4.0, {}, "let go", true],
	[2.0, {"Left stick Y (up +)": -1.0}, "push", false],
	[4.0, {}, "let go", true],
	[2.0, {"Left stick X (right +)": 1.0}, "roll right", false],
	[4.0, {}, "let go", true],
	[2.0, {"Left stick X (right +)": -1.0}, "roll left", false],
	[4.0, {}, "let go", true],
	[8.0, {"RT / R2 trigger": 1.0}, "full throttle", true],
	[6.0, {"RT / R2 trigger": 0.0}, "throttle off", true],
	[1.0, {}, "done", true],
]
const BOMB := [
	[3.0, {}, "level", true],
	[0.3, {"A / Cross": 1.0}, "carpet: every small bay", true],
	[4.0, {}, "falling", true],
	[3.0, {"A / Cross": 1.0}, "carpet held: bays drop as they reload", true],
	[0.3, {"Y / Triangle": 1.0}, "the big one", true],
	[1.0, {}, "-", true],
	[0.3, {"Y / Triangle": 1.0}, "big again: still reloading, nothing", true],
	[3.0, {}, "-", true],
	[0.3, {"Y / Triangle": 1.0}, "big again, reloaded", true],
	[2.0, {"LT / L2 trigger": 1.0}, "missiles held", true],
	[0.3, {"D-pad up": 1.0}, "front row", true],
	[0.3, {"X / Square": 1.0}, "middle row", true],
	[0.3, {"D-pad down": 1.0}, "back row", true],
	[0.3, {"LB / L1": 1.0}, "left half", true],
	[0.3, {"RB / R1": 1.0}, "right half", true],
	[0.3, {"D-pad left": 1.0}, "left outer columns", true],
	[0.3, {"D-pad right": 1.0}, "right outer columns", true],
	[0.3, {"B / Circle": 1.0}, "centre stick", true],
	[14.0, {}, "falling", true],
	[1.0, {}, "done", true],
]
const LOW := [
	[3.0, {}, "level, low", true],
	[0.5, {"A / Cross": 1.0}, "carpet asked, too low: nothing", true],
	[0.5, {"Y / Triangle": 1.0}, "big asked, too low: nothing", true],
	[0.5, {"LT / L2 trigger": 1.0}, "missiles: high enough for these", true],
	[3.0, {}, "-", true],
	[0.5, {}, "done", true],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	file = args[0]
	for arg in args:
		if arg in ["air", "ground", "takeoff", "bomb", "low", "ladder"]:
			mode = arg
	no_fail = args.has("nofail")
	names = JSON.parse_string(FileAccess.get_file_as_string(file + ".names.json"))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _flying() -> bool:
	return mode in ["air", "bomb", "low"]


func _height() -> float:
	var asked := OS.get_environment("B2_HEIGHT")
	if asked != "":
		return float(asked)
	return {"bomb": 1200.0, "low": 90.0}.get(mode, 400.0)


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


func _angle(name: String) -> String:
	var outputs: Dictionary = spawner.outputs_of(int(uids.get(name, 0)))
	return "%5.1f" % float(outputs.get("angle", 0.0))


func _attitude() -> String:
	var b := main_body.global_transform.basis
	var nose := b.z
	var right := -b.x
	var pitch := rad_to_deg(asin(clampf(nose.y, -1.0, 1.0)))
	var roll := rad_to_deg(atan2(-right.y, b.y.y))
	var heading := rad_to_deg(atan2(nose.x, -nose.z))
	var v := main_body.linear_velocity
	var dist: float = float(spawner.outputs_of(int(uids.get("dist", 0))).get("distance", 0.0))
	return "pitch %6.1f roll %6.1f hdg %6.1f | v %5.1f fwd %5.1f climb %5.1f | above ground %6.0f" % [
		pitch, roll, heading, v.length(), v.dot(nose), v.y, dist]


func _systems() -> String:
	var line := "elevons L %s/%s %s/%s R %s/%s %s/%s | steer %s" % [
		_angle("inner_L_top"), _angle("inner_L_bottom"), _angle("outer_L_top"), _angle("outer_L_bottom"),
		_angle("inner_R_top"), _angle("inner_R_bottom"), _angle("outer_R_top"), _angle("outer_R_bottom"), _angle("steer")]
	var gear := ""
	for i in 3:
		gear += " %.1f" % float(spawner.outputs_of(int(uids.get("gear_%d" % i, 0))).get("length", 0.0))
	line += " | gear%s" % gear
	var thrust: Dictionary = spawner._outputs.get(int(uids.get("thrust_0", 0)), {})
	line += " | thrust %.0fk" % (float(thrust.get("thrust", 0.0)) / 1000.0)
	var loaded := 0
	var bays := 0
	for name in uids:
		if str(name).begins_with("bay_"):
			bays += 1
			loaded += int(float(spawner.outputs_of(int(uids[name])).get("loaded", 0.0)))
	var rails := ""
	for i in 4:
		rails += "%d" % int(float(spawner.outputs_of(int(uids.get("rail_%d" % i, 0))).get("loaded", 0.0)))
	var big := int(float(spawner.outputs_of(int(uids.get("big_rack", 0))).get("loaded", 0.0)))
	var ladder: Dictionary = spawner.record_of(int(uids.get("ladder", 0)))
	var away: bool = (not ladder.is_empty()) and float(spawner.input_value(ladder.get("links", {}), "stowed", 0.0)) != 0.0
	line += " | bays %d/%d big %d rails %s ladder %s | bodies %d blasts %d" % [loaded, bays, big, rails,
			"away" if away else "out", spawner.all_bodies().size(), blasts.size()]
	return line


func _report_bodies() -> void:
	print("B2: %d bodies" % spawner.all_bodies().size())
	var list: Array = spawner.all_bodies()
	list.sort_custom(func(a, b): return a.mass > b.mass)
	for item in list.slice(0, 6):
		var rb := item as RigidBody3D
		print("B2:   %7.0f kg  centre %s" % [rb.mass, str((spawner.grid_basis().inverse() * (rb.global_transform * rb.center_of_mass - spawner._grid_frame.origin) / 0.25).snapped(Vector3.ONE * 0.1))])


func _on_destroyed(_uid: int, type: String, at: Vector3, props: Dictionary) -> void:
	if type == "explosive_block":
		var from_plane := at.distance_to(main_body.global_position) if is_instance_valid(main_body) else -1.0
		blasts.append([alive, float(props.get("blast_radius", 0.0)), from_plane])
		if blasts.size() <= 6 or float(props.get("blast_radius", 0.0)) > 200.0:
			print("B2:   blast %.0f m at %.0f m from the plane (map y %.0f)" % [float(props.get("blast_radius", 0.0)), from_plane, Origin.to_map(at).y])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		spawner = main.get_node("Spawner")
		grid = main.get_node("BuildGrid")
		controller = main.get_node("BuildController")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		if no_fail:
			load("res://scripts/stress.gd").failure = false
		if OS.get_environment("B2_STRESS") != "":
			load("res://scripts/stress.gd").view = true
		var save_name := "_b2_test"
		DirAccess.copy_absolute(file, SaveManager.path_for(save_name))
		print("B2: loaded ", SaveManager.load_build(grid, save_name))
		DirAccess.remove_absolute(SaveManager.path_for(save_name))
		_map_uids()
		var mass := 0.0
		var moment := Vector3.ZERO
		for uid in grid.all_uids():
			var record: Dictionary = grid.get_part(uid)
			if BuildGrid.is_hidden_control(record):
				continue
			var m := BuildGrid.mass_of(record)
			mass += m
			moment += BuildGrid.centroid_of(record) * m
		print("B2: build mass %.0f kg (overlaps twice), centre of mass (cells) %s" % [mass, str((moment / mass / 0.25).snapped(Vector3.ONE * 0.1))])
		print("B2: centre of lift ", grid.center_of_lift())
		if mode == "takeoff":
			main.send_build_to_runway()
		else:
			controller.toggle_spawn()
		main_body = spawner.heaviest_body()
		_report_bodies()
		spawner.part_destroyed.connect(_on_destroyed)
		for name in uids:
			if str(name).begins_with("bay_") or str(name).begins_with("rail_") or name == "big_rack":
				var gate: Dictionary = spawner._reload_gates.get(int(uids[name]), {})
				var payload: Array = gate.get("payload", [])
				if payload.size() < 4:
					print("B2: %s has %d parts on its rail" % [name, payload.size()])
		if mode != "ladder":
			print("B2: seated ", controller.sit_in(spawner))
		main.get_node("Player").damage_enabled = false
		Profiler.on = true
	if frame == 12 and _flying():
		var forward: Vector3 = main_body.global_transform.basis.z
		# Low: out over the lake, clear of the island's hills.
		var lift := Vector3(0, _height(), 0) + (forward * 3000.0 if mode == "low" else Vector3.ZERO)
		for body in spawner.all_bodies():
			var rb := body as RigidBody3D
			rb.global_position += lift
			rb.linear_velocity = forward * cruise
		spawner.teleport(Transform3D.IDENTITY)   # no crash from the lift
		for body in spawner.all_bodies():
			(body as RigidBody3D).linear_velocity = forward * cruise
		main.get_node("Terrain").make_solid_now()
	if frame <= 12:
		return false
	if mode == "ladder":
		return _ladder_test(delta)
	if not is_instance_valid(main_body):
		print("B2: the main body is gone")
		return true
	alive += delta
	var script: Array = GROUND
	match mode:
		"takeoff":
			script = TAKEOFF
		"air":
			script = AIR
		"bomb":
			script = BOMB
		"low":
			script = LOW
	if step == -1 or clock >= float(script[step][0]):
		step += 1
		clock = 0.0
		if step >= script.size():
			_report_bodies()
			_timing(true)
			print("B2: blasts %d, nearest to the plane %.0f m" % [blasts.size(), _nearest_blast()])
			return true
		print("B2: --- ", script[step][2])
	var held: Dictionary = (script[step][1] as Dictionary).duplicate()
	if _flying() and not held.has("RT / R2 trigger"):
		var fwd := main_body.linear_velocity.dot(main_body.global_transform.basis.z)
		held["RT / R2 trigger"] = clampf((cruise - fwd) * 0.08 + 0.35, 0.0, 1.0)
	if (_flying() or mode == "takeoff") and bool(script[step].size() > 3 and script[step][3]):
		var b := main_body.global_transform.basis
		var right := -b.x
		var roll := rad_to_deg(atan2(-right.y, b.y.y))
		var climb := main_body.linear_velocity.y
		# Height above the ground, from the plane's own height finder.
		var alt: float = float(spawner.outputs_of(int(uids.get("dist", 0))).get("distance", 0.0))
		var want_climb := clampf((_height() + 20.0 - alt) * 0.1, -8.0, 8.0)
		if not held.has("Left stick Y (up +)"):
			held["Left stick Y (up +)"] = clampf((want_climb - climb) * 0.15, -0.8, 0.8)
		if not held.has("Left stick X (right +)"):
			held["Left stick X (right +)"] = clampf(-roll * 0.04, -0.7, 0.7)
	Gamepad.fake = held
	clock += delta
	if fmod(clock, 0.1 if OS.get_environment("B2_FINE") != "" else 0.5) < delta:
		print("B2: %4.1fs %s" % [clock, _attitude()])
		print("B2:        %s" % _systems())
		if OS.get_environment("B2_STRESS") != "":
			_stress_report()
		_breaks()
		_timing(false)
	return false


func _breaks() -> void:
	var log_node = FailureLog.instance
	if log_node == null:
		return
	var entries: Array = log_node._entries
	while seen_breaks < entries.size():
		var text: String = entries[seen_breaks]["text"]
		var found := RegEx.create_from_string("\\(part (\\d+)\\)").search(text)
		if found != null:
			var record: Dictionary = grid.get_part(int(found.get_string(1)))
			if not record.is_empty():
				text += "  [%s @ %s]" % [record["type"], str(Vector3(record["pos"]) / 200.0)]
		print("B2:   BREAK ", text)
		seen_breaks += 1


## Physics ticks run and wall time taken since the last line, and where the
## time went.
func _timing(final: bool) -> void:
	var ticks := Engine.get_physics_frames()
	var now := Time.get_ticks_usec()
	if tick_start > 0 and ticks > tick_start:
		var per_tick := float(now - wall_start) / float(ticks - tick_start) / 1000.0
		var totals: Dictionary = Profiler.take()
		var parts := ""
		for key in totals:
			parts += " %s %.2f" % [key, float(totals[key]) / float(ticks - tick_start) / 1000.0]
		print("B2:        %.2f ms a tick (%d ticks):%s" % [per_tick, ticks - tick_start, parts])
	tick_start = ticks
	wall_start = now


func _nearest_blast() -> float:
	var nearest := INF
	for item in blasts:
		nearest = minf(nearest, float(item[2]))
	return nearest


var _ladder_best := 0.0
var _ladder_climbed := false


## On foot under the hatch, facing the ladder: push forward, climb, ask for
## the seat.
func _ladder_test(delta: float) -> bool:
	var player: Node = main.get_node("Player")
	if step == -1:
		var ladder: Array = spawner.part_frame(int(uids.get("ladder", 0)))
		var at: Vector3 = (ladder[0] as Transform3D).origin
		var back: Vector3 = main_body.global_transform.basis.z.normalized()   # toward the nose
		back.y = 0.0
		back = back.normalized()
		var feet := at + back * 0.5
		var terrain: Node = main.get_node("Terrain")
		feet.y = terrain.ground_at(feet) + 0.05
		player.teleport(feet, atan2(back.x, back.z))
		_ladder_best = feet.y
		print("B2: --- under the hatch, feet y %.2f, ladder middle y %.2f" % [feet.y, at.y])
		step = 0
		clock = 0.0
		return false
	clock += delta
	var y: float = player.global_position.y
	_ladder_best = maxf(_ladder_best, y)
	if step == 0:
		Gamepad.fake = {} if clock < 1.0 else {"Left stick Y (up +)": 1.0}
		if fmod(clock, 0.25) < delta:
			print("B2:  %.2fs feet y %.2f on ladder %s" % [clock, y, str(player._ladder != Vector3.ZERO)])
		if player._ladder != Vector3.ZERO:
			_ladder_climbed = true
		if clock >= 5.0:
			Gamepad.fake = {}
			print("B2: --- climbed: %s, highest feet y %.2f" % [str(_ladder_climbed), _ladder_best])
			controller._seat_request = true
			step = 1
			clock = 0.0
		return false
	if clock >= 0.2:
		print("B2: --- asked for the seat: seated %s" % str(player.seated))
		return true
	return false


## The most loaded joints in the build: part, what it hangs from, the face
## area and the mass beyond it.
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
	for item in list.slice(0, 8):
		print("B2:   ratio %5.2f %s <- %s area %.4f m2 beyond %6.0f kg" % [item[0], _describe(int(item[1]) >> 3),
				_describe(int(item[2]) >> 3), item[3], item[4]])


func _describe(uid: int) -> String:
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return "?"
	var pos: Vector3 = Vector3(record["pos"]) / 200.0
	return "%s %s@(%.2f,%.2f,%.2f)%s" % [record["type"], str(record.get("material", "")), pos.x, pos.y, pos.z, str(record.get("size", ""))]
