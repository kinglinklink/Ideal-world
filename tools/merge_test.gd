extends SceneTree
## Headless test of merged drawing: a spawned build's plain parts become one
## mesh; destroying a part rebuilds it without that part; a part that needs
## its own look (damage_fx asks for its nodes) is drawn on its own again;
## the stress view puts every part back on its own.
##     godot --headless --path . -s tools/merge_test.gd

const Units = preload("res://scripts/units.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Stress = preload("res://scripts/stress.gd")

var main: Node = null
var frame := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _count(spawner: Node) -> Array:
	var merged := 0
	var own := 0
	var triangles := 0
	for body in spawner.all_bodies():
		for child in (body as Node).get_children():
			var shown := child as MeshInstance3D
			if shown == null or not shown.visible or shown.is_queued_for_deletion():
				continue
			if shown.name.begins_with("Merged"):
				merged += 1
				for surface in shown.mesh.get_surface_count():
					triangles += (shown.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			else:
				own += 1
	return [merged, own, triangles]


func _process(_delta: float) -> bool:
	frame += 1
	var grid: Node = main.get_node("BuildGrid")
	var spawner: Node = main.get_node("Spawner")
	var c := Units.UNITS_PER_CELL
	match frame:
		5:
			main.get_node("Menus").start_game()
		8:
			for x in 10:
				for z in 10:
					grid.add_part(BuildGrid.make_record("block", Vector3i((30 + x) * c, c, (30 + z) * c) + Vector3i(c / 2, c / 2, c / 2),
							Basis.IDENTITY, Vector3i(c, c, c), "steel" if x < 5 else "oak", Color(0.5, 0.5, 0.5)))
			main.get_node("BuildController").toggle_spawn()
		12:
			print("MERGE: spawned: merged meshes, own meshes, triangles ", _count(spawner))
			spawner.destroy_part(spawner.live_parts()[0])
		20:
			print("MERGE: one destroyed: ", _count(spawner), " parts ", spawner.live_parts().size())
			spawner.part_nodes(spawner.live_parts()[5])
		22:
			print("MERGE: one on its own: ", _count(spawner))
			Stress.view = true
		26:
			print("MERGE: stress view: ", _count(spawner))
			Stress.view = false
		30:
			print("MERGE: stress view off: ", _count(spawner))
			return true
	return false
