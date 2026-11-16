extends Node3D
## Every tree on the map: ponderosa-style pines, placed by tools/bake_map.py.
##
## Trees are drawn in 1 km squares, each one MultiMesh for the trunks and one
## for the crowns, so the graphics card draws thousands in one go. Squares
## farther than DRAW_DISTANCE from the camera are not drawn; the ground shader
## darkens wooded ground so forests still read from the air.
##
## A tree is solid only where the ground is: terrain.gd asks for the trunks of
## each 128 m square of ground it makes solid.

const MapInfo = preload("res://scripts/map_info.gd")
const Kit = preload("res://scripts/mesh_kit.gd")

const DRAW_DISTANCE := 2600.0   # metres
const FLOATS := 16              # per tree: a 3 x 4 transform and a colour
const TRUNK_RADIUS := 0.3       # metres, for a tree of size 1; solid up into the crown
const SOLID_HEIGHT := 7.0

var _trees := PackedFloat32Array()
var _tiles: Dictionary = {}     # Vector2i square -> Vector2i(first tree, count)
var _trunk_shapes: Dictionary = {}


func setup(world: Dictionary) -> void:
	if FileAccess.file_exists(MapInfo.TREES_FILE):
		_trees = FileAccess.get_file_as_bytes(MapInfo.TREES_FILE).to_float32_array()
	if FileAccess.file_exists(MapInfo.TREE_TILES_FILE):
		var table := FileAccess.get_file_as_bytes(MapInfo.TREE_TILES_FILE).to_int32_array()
		for index in range(0, table.size() - 3, 4):
			_tiles[Vector2i(table[index], table[index + 1])] = Vector2i(table[index + 2], table[index + 3])

	var trunk_mesh := _trunk_mesh()
	var crown_mesh := _crown_mesh()
	var cells: Array = world.get("tree_cells", [])
	for item in cells:
		var cell: Array = item
		var first := int(cell[2])
		var count := int(cell[3])
		if count <= 0 or (first + count) * FLOATS > _trees.size():
			continue
		var buffer := _trees.slice(first * FLOATS, (first + count) * FLOATS)
		var middle := Vector3((float(cell[0]) + 0.5) * MapInfo.CELL, 0.0, (float(cell[1]) + 0.5) * MapInfo.CELL)
		for part in 2:
			var batch := MultiMesh.new()
			batch.transform_format = MultiMesh.TRANSFORM_3D
			batch.use_colors = true
			batch.mesh = trunk_mesh if part == 0 else crown_mesh
			batch.instance_count = count
			batch.buffer = buffer
			var half := MapInfo.CELL * 0.5 + 10.0
			batch.custom_aabb = AABB(Vector3(-half, -300.0, -half), Vector3(half * 2.0, 2600.0, half * 2.0))
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = batch
			instance.position = middle
			instance.visibility_range_end = DRAW_DISTANCE
			instance.visibility_range_end_margin = 150.0
			add_child(instance)


## Adds the trunks of the trees in one 128 m square to a body, as cylinders
## that reach up into the crowns.
func add_trunks(body: StaticBody3D, square: Vector2i) -> void:
	if not _tiles.has(square):
		return
	var run: Vector2i = _tiles[square]
	var per_cell := int(MapInfo.CELL / MapInfo.TILE)
	var cell_x := floori(float(square.x) / per_cell)
	var cell_z := floori(float(square.y) / per_cell)
	var middle_x := (cell_x + 0.5) * MapInfo.CELL
	var middle_z := (cell_z + 0.5) * MapInfo.CELL
	for index in range(run.x, run.x + run.y):
		var at := index * FLOATS
		if at + 11 >= _trees.size():
			break
		var size := snappedf(_trees[at + 5], 0.1)
		if not _trunk_shapes.has(size):
			var cylinder := CylinderShape3D.new()
			cylinder.radius = TRUNK_RADIUS * size
			cylinder.height = SOLID_HEIGHT * size
			_trunk_shapes[size] = cylinder
		var trunk: CylinderShape3D = _trunk_shapes[size]
		var collider := CollisionShape3D.new()
		collider.shape = trunk
		collider.position = Vector3(_trees[at + 3] + middle_x, _trees[at + 7] + trunk.height * 0.5,
				_trees[at + 11] + middle_z)
		body.add_child(collider)


# --- Models ------------------------------------------------------------------

func _trunk_mesh() -> ArrayMesh:
	var surface := Kit.new_surface()
	Kit.add_cylinder(surface, Vector3(0.0, 1.0, 0.0), 1, 0.2, 2.0, 6)
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.25, 0.16)
	bark.roughness = 1.0
	mesh.surface_set_material(0, bark)
	return mesh


## A pine in three tiers. Each tree's own colour comes from its instance.
func _crown_mesh() -> ArrayMesh:
	var surface := Kit.new_surface()
	Kit.add_frustum(surface, Vector3(0.0, 3.0, 0.0), 1, 1.8, 0.6, 2.4, 8)
	Kit.add_frustum(surface, Vector3(0.0, 4.9, 0.0), 1, 1.3, 0.3, 2.2, 8)
	Kit.add_frustum(surface, Vector3(0.0, 6.6, 0.0), 1, 0.8, 0.0, 1.8, 8)
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var needles := StandardMaterial3D.new()
	needles.vertex_color_use_as_albedo = true
	needles.roughness = 1.0
	mesh.surface_set_material(0, needles)
	return mesh
