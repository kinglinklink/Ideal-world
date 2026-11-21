extends RefCounted
## Four instruments on a tilted, moving build, to check the dials.

const Units = preload("res://scripts/units.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")


func step(main: Node, frame: int, tree: SceneTree) -> bool:
	var grid: Node = main.get_node("BuildGrid")
	var spawner: Node = main.get_node("Spawner")
	var c := Units.UNITS_PER_CELL
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		var kinds := ["Airspeed", "Altitude", "Artificial horizon", "Fuel"]
		for index in 4:
			var record := BuildGrid.make_record("instrument", Vector3i((28 + index * 3) * c, 8 * c, 30 * c) + Vector3i(c, c, c / 8),
					Basis.IDENTITY, Vector3i(2 * c, 2 * c, c / 4), "steel", Color(0.12, 0.12, 0.13))
			record["props"] = {"kind": kinds[index], "top": 50.0, "bottom": 0.0, "label": ""}
			grid.add_part(record)
		for x in 12:
			grid.add_part(BuildGrid.make_record("block", Vector3i((28 + x) * c, 7 * c, 30 * c) + Vector3i(c / 2, c / 2, c / 2),
					Basis.IDENTITY, Vector3i(c, c, c), "steel", Color(0.5, 0.5, 0.5)))
		main.get_node("BuildController").toggle_spawn()
	if frame == 10:
		var body: RigidBody3D = spawner.heaviest_body()
		spawner.hold(body)
		body.global_transform = Transform3D(Basis(Vector3.FORWARD, 0.35) * Basis(Vector3.RIGHT, 0.2), body.global_position)
		var camera := Camera3D.new()
		camera.name = "ShotCamera"
		main.add_child(camera)
	if frame > 10:
		var camera: Camera3D = main.get_node("ShotCamera")
		var body: RigidBody3D = spawner.heaviest_body()
		camera.make_current()
		camera.look_at_from_position(body.global_position + Vector3(0.6, 0.6, 4.5), body.global_position + Vector3(0.6, 0.5, 0.0), Vector3.UP)
	if frame == 60:
		tree.snap("instruments")
	return frame > 62
