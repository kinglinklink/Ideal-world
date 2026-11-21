extends SceneTree
## Headless test that collision follows each part's drawn shape. For every
## part whose shape is less than its box, spawns it alone held fixed and
## casts rays straight down onto points across its box: a ray must hit
## where the drawn mesh has something under it and miss where it doesn't.
## Also checks two triangle panels touching only across their empty halves
## don't weld, and that a ring has a hole.
##     godot --headless --path . -s tools/collision_test.gd

const Units = preload("res://scripts/units.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const Spawner = preload("res://scripts/spawner.gd")

const TYPES := ["aero_panel_triangle", "aero_panel_triangle_dragless", "wedge", "triangle_wedge", "corner_wedge",
		"pyramid", "cone", "cylinder", "sphere", "concave_curve", "arch", "ring", "pipe", "torus", "half_cylinder"]

var main: Node = null
var frame := 0
var index := 0
var failures := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


## Whether the drawn mesh (unit space) has anything under (x, z), by a ray on its faces.
static func mesh_covers(type: String, x: float, z: float) -> bool:
	var faces := PartLibrary.get_mesh(type).get_faces()
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 2.0, z), Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
		if hit != null:
			return true
	return false


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame < 10 or frame % 4 != 0:
		return false
	var grid: Node = main.get_node("BuildGrid")
	var controller: Node = main.get_node("BuildController")
	var spawner: Node = main.get_node("Spawner")
	if index < TYPES.size():
		var type: String = TYPES[index]
		if bool(controller.spawned):
			# Cast rays down through the spawned part, 9 x 9 across its box.
			var body: RigidBody3D = spawner.heaviest_body()
			var space := body.get_world_3d().direct_space_state
			var size := 2.0   # metres: the part was placed 8 cells across
			var centre: Vector3 = body.global_transform * body.center_of_mass
			var place: Array = spawner.part_frame(spawner.live_parts()[0])
			var middle: Vector3 = (place[0] as Transform3D).origin
			var wrong := 0
			var checked := 0
			for i in 9:
				for k in 9:
					var u := -0.45 + 0.9 * i / 8.0
					var w := -0.45 + 0.9 * k / 8.0
					var expect := mesh_covers(type, u, w)
					# Skip points right at an edge of the drawn shape.
					if mesh_covers(type, u + 0.04, w) != expect or mesh_covers(type, u - 0.04, w) != expect \
							or mesh_covers(type, u, w + 0.04) != expect or mesh_covers(type, u, w - 0.04) != expect:
						continue
					var from := middle + Vector3(u * size, 3.0, w * size)
					var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, Units.LAYER_BODIES)
					var hit := space.intersect_ray(query)
					var got: bool = not hit.is_empty() and hit["collider"] == body
					checked += 1
					if got != expect:
						wrong += 1
			print("COLLIDE: %-30s %d of %d points wrong, %d collision shapes" % [type, wrong, checked,
					body.get_children().filter(func(n): return n is CollisionShape3D).size()])
			if wrong > 0:
				failures += 1
			controller.toggle_spawn()
			grid.clear()
			index += 1
		else:
			var c := Units.UNITS_PER_CELL
			var units := Vector3i(8, 8, 8) * c
			if PartLibrary.is_aero_panel(type):
				units.y = c
			grid.add_part(BuildGrid.make_record(type, Vector3i(40 * c, 10 * c, 40 * c) + units / 2, Basis.IDENTITY, units, "steel", Color.WHITE))
			controller.toggle_spawn()
			spawner.hold(spawner.heaviest_body())
		return false
	# Two triangle panels side by side along X: the first's empty half faces the second's empty half.
	if index == TYPES.size():
		var c := Units.UNITS_PER_CELL
		var units := Vector3i(4 * c, c, 4 * c)
		var turned := Basis(Vector3.UP, PI)
		var a: Dictionary = BuildGrid.make_record("aero_panel_triangle", Vector3i(40 * c, 10 * c, 40 * c) + units / 2, Basis.IDENTITY, units, "steel", Color.WHITE)
		var b: Dictionary = BuildGrid.make_record("aero_panel_triangle", Vector3i(44 * c, 10 * c, 40 * c) + units / 2, turned, units, "steel", Color.WHITE)
		grid.add_part(a)
		grid.add_part(b)
		var report: Dictionary = spawner.spawn(grid)
		print("COLLIDE: two triangles touching along a box face: %d bodies" % int(report["bodies"]))
		spawner.despawn()
		grid.clear()
		# The same two turned so their solid halves meet.
		var a2 := a.duplicate(true)
		a2["rot"] = turned
		var b2 := b.duplicate(true)
		b2["rot"] = Basis.IDENTITY
		grid.add_part(a2)
		grid.add_part(b2)
		report = spawner.spawn(grid)
		print("COLLIDE: the same turned to meet: %d bodies" % int(report["bodies"]))
		spawner.despawn()
		grid.clear()
		print("COLLIDE: done, %d part types with wrong collision" % failures)
		return true
	return false
