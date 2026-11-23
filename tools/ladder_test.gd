extends SceneTree
## Headless test of climbing ladders wherever they are:
##     godot --headless --path . -s tools/ladder_test.gd
## Builds a 3 m wall (3 m deep, so there is room on top) on the pad with a full-height ladder on its front and a
## default-size ladder on its side, then for each ladder walks the character
## into it with the controller's left stick and holds it there: first in
## build mode, then with the build spawned, then with it spawned again as a
## fleet vehicle away from the pad. Also climbs by holding A (jump) against
## it instead of pushing the stick; climbs halfway, hangs there, and climbs
## back down by pulling the stick back; and pushes off it with jump and back. Prints, for each, whether the character got on and
## how high its feet got against the ladder's top.

const Gamepad = preload("res://scripts/gamepad.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")

const SAVE := "_ladder_test"
const SIDE := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))   # back (-Z) to world -X

var main: Node
var grid: Node
var spawner: Node
var controller: Node
var fleet: Node
var player: Node
var frame := 0
var wall := 0
var tall := 0        # 1 m wide, 3 m: on the wall's front (+Z) face
var short := 0       # default size: on the wall's +X face
var cases: Array = []   # [label, where: "grid"|"spawned"|"fleet", uid, keys]
var index := -1
var clock := 0.0
var got_on := false
var best := 0.0
var top := 0.0
var bottom := 0.0
var fleet_spawner: Node = null
var results: Array = []
var trace := OS.get_environment("LADDER_TRACE") == "1"
var settle := 0.0
var phase := 0
var phase_clock := 0.0
var hang_y := -1000.0
var hang_drift := 0.0
var fastest_down := 0.0
var feet_start := Vector3.ZERO
var out_dir := Vector3.ZERO
const CLIMB_DOWN_LIMIT := 2.5   # m/s: faster than a climb down would be falling     # seconds left before the next case starts


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _cells(low: Vector3, high: Vector3) -> Array:
	var centre := (low + high) * 0.5 * 200.0
	return [Vector3i(centre.round()), Vector3i(((high - low) * 200.0).round())]


func _add(type: String, low: Vector3, high: Vector3, rot: Basis, material: String) -> int:
	var place := _cells(low, high)
	var size: Vector3i = place[1]
	if rot != Basis.IDENTITY:
		# Size is along the part's own axes.
		var local := (rot.inverse() * Vector3(size)).abs()
		size = Vector3i(local.round())
	var record := BuildGrid.make_record(type, place[0], rot, size, material, Color(0.6, 0.6, 0.6))
	var uid: int = grid.add_part(record)
	if uid == 0:
		print("LADDER: could not place ", type, ": ", grid.check(record))
	return uid


## The ladder's frame in the world, and the body it is on (null on the grid).
func _ladder_frame(where: String, uid: int) -> Array:
	match where:
		"grid":
			var node: Node3D = grid.get_node_for(uid)
			return [node.global_transform, null]
		"spawned":
			return spawner.part_frame(uid)
		_:
			return fleet_spawner.part_frame(uid)


func _start_case() -> void:
	var case: Array = cases[index]
	var where: String = case[1]
	var uid: int = case[2]
	var frame_info := _ladder_frame(where, uid)
	if frame_info.is_empty():
		print("LADDER: %s: no ladder found" % case[0])
		return
	var place: Transform3D = frame_info[0]
	var record: Dictionary = grid.get_part(uid)
	var half_height := float((record["size"] as Vector3i).y) / 200.0 * 0.25 * 0.5
	var out := place.basis.z.normalized()   # its front, +Z
	out.y = 0.0
	out = out.normalized()
	var up := place.basis.y.normalized()
	top = (place.origin + up * half_height).y
	bottom = (place.origin - up * half_height).y
	var feet := place.origin - up * half_height + out * 0.6 + Vector3(0, 0.05, 0)
	player.teleport(feet, atan2(out.x, out.z))
	best = feet.y
	got_on = false
	clock = 0.0
	phase = 0
	phase_clock = 0.0
	hang_y = -1000.0
	hang_drift = 0.0
	fastest_down = 0.0
	feet_start = feet
	out_dir = out
	print("LADDER: --- %s: feet y %.2f, ladder %.2f to %.2f" % [case[0], feet.y, bottom, top])


func _end_case() -> void:
	var case: Array = cases[index]
	var how: String = case[3]
	Gamepad.fake = {}
	var climbed := best - bottom
	var y: float = player.global_position.y
	var on_now: bool = player._ladder != Vector3.ZERO
	var floor_now: bool = player.is_on_floor()
	var ok := got_on
	var note := ""
	if how == "push" or how == "jump":
		ok = ok and best > top - 0.6
		# The tall ladder leads onto the top of the wall: the character
		# should be standing up there at the end.
		if case[2] == tall:
			ok = ok and floor_now and absf(y - top) < 0.15
	elif how == "down":
		# Hung still, came down no faster than a climb, and stepped off at the bottom.
		ok = ok and hang_drift < 0.05 and fastest_down < CLIMB_DOWN_LIMIT \
				and floor_now and not on_now and absf(y - bottom) < 0.1
		note = ", drifted %.3f m hanging, fastest down %.2f m/s" % [hang_drift, fastest_down]
	elif how == "pushoff":
		var away: float = (player.global_position - feet_start).dot(out_dir)
		ok = ok and floor_now and not on_now and absf(y - bottom) < 0.1 and away > 0.3
		note = ", landed %.2f m further out than it started" % away
	results.append("%s: %s (on %s, feet rose %.2f m of %.2f, ended at %.2f%s)" % [case[0], "PASS" if ok else "FAIL", str(got_on), climbed, top - bottom, y - bottom, note])
	print("LADDER: %s: got on %s, highest feet y %.2f, ended y %.2f on ladder %s on floor %s, ladder top %.2f -> %s" % [case[0], str(got_on), best, y, str(on_now), str(floor_now), top, "PASS" if ok else "FAIL"])


## What the controller does this tick, for each way of using the ladder.
func _drive(how: String, y: float, delta: float) -> void:
	var up_stick := {"Left stick Y (up +)": 1.0}
	if clock < 0.5:
		Gamepad.fake = {}
		return
	if how == "push" or how == "jump":
		if y > top - 0.2 and player.is_on_floor():
			Gamepad.fake = {}   # standing on top: let go, so as to stay up there
		elif how == "jump" and got_on:
			Gamepad.fake = {"A / Cross": 1.0}   # on it: let go of the stick and hold jump instead
		else:
			Gamepad.fake = up_stick
		return
	# down and pushoff: climb halfway, hang, then come down.
	match phase:
		0:
			Gamepad.fake = up_stick
			if y > bottom + 1.5:
				phase = 1
				phase_clock = 0.0
				Gamepad.fake = {}
		1:
			phase_clock += delta
			if phase_clock > 0.25 and hang_y < -100.0:
				hang_y = y
			if hang_y > -100.0:
				hang_drift = maxf(hang_drift, absf(y - hang_y))
			if phase_clock > 1.0:
				phase = 2
				phase_clock = 0.0
		2:
			phase_clock += delta
			if how == "down":
				Gamepad.fake = {"Left stick Y (up +)": -1.0}
				fastest_down = maxf(fastest_down, -player.get_real_velocity().y)
				if player.is_on_floor() and player._ladder == Vector3.ZERO:
					phase = 3
			else:
				Gamepad.fake = {"Left stick Y (up +)": -1.0, "A / Cross": 1.0}
				if phase_clock > 0.1:
					phase = 3
		_:
			Gamepad.fake = {}


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		grid = main.get_node("BuildGrid")
		spawner = main.get_node("Spawner")
		controller = main.get_node("BuildController")
		fleet = main.get_node("Fleet")
		player = main.get_node("Player")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		player.damage_enabled = false
		var c := 124.0
		wall = _add("block", Vector3(c, 0, c - 8), Vector3(c + 4, 12, c + 4), Basis.IDENTITY, "wood")
		tall = _add("ladder", Vector3(c, 0, c + 4), Vector3(c + 4, 12, c + 4.25), Basis.IDENTITY, "steel")
		short = _add("ladder", Vector3(c + 4, 0, c + 1.5), Vector3(c + 4.25, 4, c + 2.5), SIDE, "steel")
		print("LADDER: wall %d, tall ladder %d, short ladder %d" % [wall, tall, short])
		cases = [
			["build mode, tall", "grid", tall, "push"],
			["build mode, short", "grid", short, "push"],
			["build mode, tall, holding A", "grid", tall, "jump"],
			["build mode, tall, hang and climb down", "grid", tall, "down"],
			["build mode, tall, push off", "grid", tall, "pushoff"],
			["spawned, tall", "spawned", tall, "push"],
			["spawned, short", "spawned", short, "push"],
			["spawned, tall, hang and climb down", "spawned", tall, "down"],
			["fleet, tall", "fleet", tall, "push"],
			["fleet, short", "fleet", short, "push"],
			["fleet, tall, hang and climb down", "fleet", tall, "down"],
		]
	if frame < 10:
		return false
	if settle > 0.0:
		settle -= delta
		if settle <= 0.0:
			_start_case()
		return false
	if index >= 0 and index < cases.size():
		clock += delta
		var case: Array = cases[index]
		var y: float = player.global_position.y
		best = maxf(best, y)
		if player._ladder != Vector3.ZERO:
			got_on = true
		_drive(str(case[3]), y, delta)
		if trace:
			print("LADDER:     %.3f y %.3f on %s floor %s v %s real %s at %s" % [clock, y, str(player._ladder != Vector3.ZERO), str(player.is_on_floor()), str(player.velocity.snapped(Vector3(0.01, 0.01, 0.01))), str(player.get_real_velocity().snapped(Vector3(0.01, 0.01, 0.01))), str(player.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])
		if fmod(clock, 0.5) < delta:
			print("LADDER:   %.1fs feet y %.2f on ladder %s" % [clock, y, str(player._ladder != Vector3.ZERO)])
		if clock < 5.0:
			return false
		_end_case()
	index += 1
	if index >= cases.size():
		print("LADDER: ====")
		for line in results:
			print("LADDER: ", line)
		SaveManager.delete_save(SAVE)
		return true
	var where: String = cases[index][1]
	if where == "spawned" and not bool(controller.spawned):
		controller.toggle_spawn()
		print("LADDER: spawned: ", controller.spawned)
		settle = 2.0
	elif where == "fleet" and fleet_spawner == null:
		if bool(controller.spawned):
			controller.toggle_spawn()
		print("LADDER: saved ", SaveManager.save_build(grid, SAVE))
		var away: Vector3 = (grid.get_node_for(wall) as Node3D).global_position + Vector3(0, 0, -20)
		var made: Array = fleet.spawn_save_at(SAVE, away, 0.0)
		print("LADDER: fleet: ", made[0])
		fleet_spawner = made[1]
		settle = 3.0
	else:
		settle = delta * 0.5
	return false
