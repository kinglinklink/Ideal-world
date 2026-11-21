extends RefCounted
## A spawned build of mixed shapes and materials, drawn merged and then
## each part on its own, to check they look the same.

const Units = preload("res://scripts/units.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")


func step(main: Node, frame: int, tree: SceneTree) -> bool:
	var grid: Node = main.get_node("BuildGrid")
	var spawner: Node = main.get_node("Spawner")
	var c := Units.UNITS_PER_CELL
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		var materials := ["oak", "steel", "brick", "carbon_fiber", "concrete", "wood"]
		for x in 6:
			for z in 6:
				grid.add_part(BuildGrid.make_record("block", Vector3i((30 + x * 2) * c, c, (30 + z * 2) * c) + Vector3i(c, c / 2, c),
						Basis.IDENTITY, Vector3i(2 * c, c, 2 * c), materials[(x + z) % 6], Color(0.8, 0.8, 0.8) if materials[(x + z) % 6] != "steel" else Color(0.48, 0.5, 0.54)))
		grid.add_part(BuildGrid.make_record("block", Vector3i(36 * c, 2 * c + c / 2, 36 * c), Basis.IDENTITY, Vector3i(12 * c, c, c), "wood", Color(0.62, 0.44, 0.27)))
		grid.add_part(BuildGrid.make_record("wedge", Vector3i(33 * c, 2 * c + c / 2, 33 * c), Basis.IDENTITY, Vector3i(2 * c, c, 2 * c), "aluminum", Color(0.8, 0.82, 0.84)))
		main.get_node("BuildController").toggle_spawn()
	if frame == 12:
		var player: Node3D = main.get_node("Player")
		var body: RigidBody3D = spawner.heaviest_body()
		player.global_position = body.global_position + Vector3(-6.0, 0.0, -6.0)
		player.set("yaw", PI * 0.75)
	if frame == 40:
		var merged := 0
		for body in spawner.all_bodies():
			for child in (body as Node).get_children():
				if child is MeshInstance3D and (child as MeshInstance3D).visible:
					merged += 1
		print("SHOT: visible meshes on bodies (merged): ", merged)
		tree.snap("merged")
		spawner.merging = false
	if frame == 50:
		var shown := 0
		for body in spawner.all_bodies():
			for child in (body as Node).get_children():
				if child is MeshInstance3D and (child as MeshInstance3D).visible:
					shown += 1
		print("SHOT: visible meshes on bodies (separate): ", shown)
		tree.snap("separate")
	return frame > 52
