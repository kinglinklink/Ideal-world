extends SceneTree
## Headless test of the test stand, the Inspector and the performance
## overlay. Builds a steel base with a motor (driven by a Constant number
## block) turning a flywheel, and a flat aero panel wing; puts it on the
## stand; runs the dyno (a motor holds its speed until the brake passes its
## max torque, 100 N m, then stalls) and a wind tunnel sweep (lift should
## grow with the angle of attack); then switches on the Inspector and the
## overlay and reads them.
##     godot --headless --path . -s tools/stand_test.gd

const Units = preload("res://scripts/units.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Profiler = preload("res://scripts/profiler.gd")

var main: Node = null
var frame := 0
var step := 0
var wait := 0
var motor_uid := 0
var gate_uid := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _put(grid: Node, type: String, cell: Vector3i, size: Vector3i, material := "steel") -> int:
	var c := Units.UNITS_PER_CELL
	var units := size * c
	var pos := cell * c + units / 2
	return grid.add_part(BuildGrid.make_record(type, pos, Basis.IDENTITY, units, material, Color(0.6, 0.6, 0.6)))


func _process(_delta: float) -> bool:
	frame += 1
	var stand: Node = main.get_node("TestStand")
	var spawner: Node = main.get_node("Spawner")
	var grid: Node = main.get_node("BuildGrid")
	match step:
		0:
			if frame == 5:
				main.get_node("Menus").start_game()
			if frame == 10:
				# A 4 x 4 steel base, a motor on it turning a 2 x 2 flywheel,
				# and a 6 x 3 wing on a post at the front.
				for x in 4:
					for z in 4:
						_put(grid, "block", Vector3i(40 + x, 0, 40 + z), Vector3i(1, 1, 1))
				motor_uid = _put(grid, "motor", Vector3i(42, 1, 42), Vector3i(1, 1, 1))
				_put(grid, "block", Vector3i(42, 2, 42), Vector3i(1, 1, 1), "aluminum")
				gate_uid = _put(grid, "number_gate", Vector3i(43, 1, 43), Vector3i(1, 1, 1))
				var gate: Dictionary = grid.get_part(gate_uid)
				gate["props"] = {"operation": "Constant", "value": 1.0}
				grid.update_parts({gate_uid: gate})
				grid.set_links(motor_uid, {"speed": {"uid": gate_uid, "output": "result"}})
				_put(grid, "block", Vector3i(40, 1, 40), Vector3i(1, 2, 1))
				for x in 6:
					for z in 3:
						_put(grid, "aero_panel", Vector3i(39 + x, 3, 37 + z), Vector3i(1, 1, 1), "aluminum")
				print("STAND: parts ", grid.part_count(), " motor ", motor_uid, " gate ", gate_uid)
			if frame == 15:
				print("STAND: open ", stand.open_stand(), " spawned ", main.get_node("BuildController").spawned,
						" held ", spawner.held_body != null, " held mass %.0f kg" % (spawner.held_body.mass if spawner.held_body else 0.0))
				var at: Vector3 = spawner.held_body.global_position
				print("STAND: held at ", at.snapped(Vector3.ONE * 0.1), " stand centre (local) ", stand.centre, " in world ", stand.global_transform * stand.centre)
				stand.start_dyno()
				step = 1
		1:
			if frame % 240 == 0:
				print("STAND: dyno ", stand.mode, " rows ", stand.results.size(),
						" | ", stand._status.text)
			if stand.mode == "":
				var free := 0.0
				var torque_at_free := 0.0
				for row in stand.results:
					free = maxf(free, float(row[0]))
				for row in stand.results:
					if float(row[0]) > 0.9 * free:
						torque_at_free = maxf(torque_at_free, float(row[1]))
				print("STAND: dyno done rows %d, free %.0f rpm, held speed up to %.1f N m | %s" % [
						stand.results.size(), free, torque_at_free, stand._status.text])
				print("STAND: csv ", stand.last_csv, " exists ", FileAccess.file_exists(stand.last_csv))
				stand.start_tunnel(60.0, -4.0, 12.0, 4.0)
				step = 2
		2:
			if stand.mode == "":
				for row in stand.results:
					print("STAND: tunnel %5.1f deg  lift %8.1f N  drag %7.1f N  side %6.1f  pitch %8.1f  L/D %5.2f" % [row[0], row[2], row[3], row[4], row[5], row[6]])
				print("STAND: ", stand._status.text)
				var inspector: Node = main.get_node("Inspector")
				inspector._set_active(true)
				main.get_node("PerfOverlay").toggle()
				wait = frame
				step = 3
		3:
			if frame - wait == 400:
				var inspector: Node = main.get_node("Inspector")
				var shown := 0
				for label in inspector._labels:
					if (label as Label3D).visible:
						shown += 1
				print("STAND: inspector labels ", shown, " gate at ", spawner.part_position(gate_uid) != null,
						" motor dead ", spawner.is_dead(motor_uid), " live parts ", spawner.live_parts().size())
				for entry in main.get_node("FailureLog")._entries:
					print("STAND: failure log: ", entry["text"])
				print("STAND: motor card\n", inspector.card_text(motor_uid))
				print("STAND: overlay\n", main.get_node("PerfOverlay")._text.text)
				stand.close_stand()
				print("STAND: closed, spawned ", main.get_node("BuildController").spawned, " held ", spawner.held_body)
				return true
	return frame > 60000
