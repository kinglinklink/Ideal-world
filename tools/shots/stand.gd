extends RefCounted
## The test stand with a small build on it, the Inspector on, the
## performance overlay up and the stand's panel open.

const Units = preload("res://scripts/units.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")


func _put(grid: Node, type: String, cell: Vector3i, size: Vector3i, material := "steel") -> int:
	var c := Units.UNITS_PER_CELL
	var units := size * c
	return grid.add_part(BuildGrid.make_record(type, cell * c + units / 2, Basis.IDENTITY, units, material, Color(0.6, 0.6, 0.6)))


func step(main: Node, frame: int, tree: SceneTree) -> bool:
	var grid: Node = main.get_node("BuildGrid")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		for x in 4:
			for z in 4:
				_put(grid, "block", Vector3i(40 + x, 0, 40 + z), Vector3i(1, 1, 1))
		var motor := _put(grid, "motor", Vector3i(42, 1, 42), Vector3i(1, 1, 1))
		_put(grid, "block", Vector3i(42, 2, 42), Vector3i(1, 1, 1), "aluminum")
		var gate := _put(grid, "number_gate", Vector3i(40, 1, 43), Vector3i(1, 1, 1))
		var record: Dictionary = grid.get_part(gate)
		record["props"] = {"operation": "Constant", "value": 0.5}
		grid.update_parts({gate: record})
		grid.set_links(motor, {"speed": {"uid": gate, "output": "result"}})
		_put(grid, "block", Vector3i(40, 1, 40), Vector3i(1, 2, 1))
		for x in 6:
			for z in 3:
				_put(grid, "aero_panel", Vector3i(39 + x, 3, 37 + z), Vector3i(1, 1, 1), "aluminum")
	if frame == 10:
		main.get_node("TestStand").open_stand()
	if frame == 40:
		main.get_node("Inspector")._set_active(true)
		main.get_node("PerfOverlay").toggle()
		var stand: Node3D = main.get_node("TestStand")
		var target: Vector3 = stand.global_transform * stand.centre
		var player: Node3D = main.get_node("Player")
		player.global_position = target + Vector3(-7.0, 0.2, 7.0)
		player.set("yaw", -PI * 0.25)
	if frame == 69:
		tree.snap("stand")
	return frame > 70
