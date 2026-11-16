extends Node3D
## Every tree on the map: ponderosa-style pines, placed by tools/bake_map.py.
##
## Trees are drawn in 1 km squares, each one MultiMesh for the trunks and one
## for the crowns, so the graphics card draws thousands in one go. A square is
## only built when the camera comes within the draw distance (plus a margin)
## and is freed again when it is far away, so memory and drawing stay small
## even with 600,000 trees; a few squares are built per frame. The ground
## shader darkens wooded ground, so forests still read from the air.
##
## The file holds four floats per tree: x and z from the middle of its
## square, its height y and its size. Each tree's turn and shade of green
## come from its place in the file, the same every time.
##
## A tree is solid only where the ground is: terrain.gd asks for the trunks of
## each 128 m square of ground it makes solid.

const MapInfo = preload("res://scripts/map_info.gd")
const Origin = preload("res://scripts/origin.gd")
const Kit = preload("res://scripts/mesh_kit.gd")

const FLOATS := 4               # per tree in the file
const TRUNK_RADIUS := 0.3       # metres, for a tree of size 1; solid up into the crown
const SOLID_HEIGHT := 7.0
const BUILD_MARGIN := 300.0     # squares are built this far beyond the draw distance
const FREE_MARGIN := 1200.0     # and freed this far beyond it
const BUILDS_PER_FRAME := 1

## How far away trees are drawn, in metres. The settings menu changes it.
var draw_distance := 2600.0

var _trees := PackedFloat32Array()
var _tiles: Dictionary = {}     # Vector2i collision square -> Vector2i(first tree, count)
var _cells: Array = []          # [Vector2i square, first tree, count]
var _built: Dictionary = {}     # Vector2i square -> [trunk MultiMeshInstance3D, crown MultiMeshInstance3D]
var _trunk_shapes: Dictionary = {}
var _trunk_mesh: ArrayMesh
var _crown_mesh: ArrayMesh
var _check := 0.0


func setup(world: Dictionary) -> void:
	if FileAccess.file_exists(MapInfo.TREES_FILE):
		_trees = FileAccess.get_file_as_bytes(MapInfo.TREES_FILE).to_float32_array()
	if FileAccess.file_exists(MapInfo.TREE_TILES_FILE):
		var table := FileAccess.get_file_as_bytes(MapInfo.TREE_TILES_FILE).to_int32_array()
		for index in range(0, table.size() - 3, 4):
			_tiles[Vector2i(table[index], table[index + 1])] = Vector2i(table[index + 2], table[index + 3])
	for item in world.get("tree_cells", []):
		var cell: Array = item
		_cells.append([Vector2i(int(cell[0]), int(cell[1])), int(cell[2]), int(cell[3])])
	_trunk_mesh = _make_trunk_mesh()
	_crown_mesh = _make_crown_mesh()


## Sets how far trees are drawn, and applies it to the squares already built.
func set_draw_distance(metres: float) -> void:
	draw_distance = metres
	for key in _built:
		var pair: Array = _built[key]
		for item in pair:
			var instance: MultiMeshInstance3D = item
			instance.visibility_range_end = draw_distance


func _process(delta: float) -> void:
	_check -= delta
	var camera := get_viewport().get_camera_3d()
	if camera == null or _cells.is_empty():
		return
	var eye := Origin.to_map(camera.global_position)
	var here := Vector2(eye.x, eye.z)
	var half := MapInfo.CELL * 0.5
	var near_enough := draw_distance + BUILD_MARGIN + half
	var too_far := draw_distance + FREE_MARGIN + half
	# Build the nearest missing squares first, a few per frame.
	var wanted: Array = []
	for item in _cells:
		var cell: Array = item
		var square: Vector2i = cell[0]
		var middle := (Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL
		var distance := middle.distance_to(here)
		if distance < near_enough and not _built.has(square):
			wanted.append([distance, cell])
	if not wanted.is_empty():
		wanted.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
		for index in mini(BUILDS_PER_FRAME, wanted.size()):
			var entry: Array = wanted[index]
			_build_cell(entry[1])
	# Every so often, free the squares that are far away.
	if _check <= 0.0:
		_check = 1.0
		var drop: Array = []
		for key in _built:
			var square: Vector2i = key
			var middle := (Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL
			if middle.distance_to(here) > too_far:
				drop.append(square)
		for key in drop:
			var pair: Array = _built[key]
			for item in pair:
				var instance: Node = item
				instance.queue_free()
			_built.erase(key)


func _build_cell(cell: Array) -> void:
	var square: Vector2i = cell[0]
	var first: int = cell[1]
	var count: int = cell[2]
	if count <= 0 or (first + count) * FLOATS > _trees.size():
		_built[square] = []
		return
	# A 3 x 4 transform and a colour per tree, as MultiMesh wants them.
	var buffer := PackedFloat32Array()
	buffer.resize(count * 16)
	for index in count:
		var at := (first + index) * FLOATS
		var size := _trees[at + 3]
		var turn := _hash(first + index) * TAU
		var cosine := cos(turn) * size
		var sine := sin(turn) * size
		var shade := _hash((first + index) * 7 + 3)
		var o := index * 16
		buffer[o] = cosine
		buffer[o + 1] = 0.0
		buffer[o + 2] = sine
		buffer[o + 3] = _trees[at]
		buffer[o + 4] = 0.0
		buffer[o + 5] = size
		buffer[o + 6] = 0.0
		buffer[o + 7] = _trees[at + 1]
		buffer[o + 8] = -sine
		buffer[o + 9] = 0.0
		buffer[o + 10] = cosine
		buffer[o + 11] = _trees[at + 2]
		buffer[o + 12] = 0.10 + 0.10 * shade
		buffer[o + 13] = 0.32 + 0.16 * _hash((first + index) * 13 + 5)
		buffer[o + 14] = 0.14 + 0.10 * shade
		buffer[o + 15] = 1.0
	var middle := Vector3((square.x + 0.5) * MapInfo.CELL, 0.0, (square.y + 0.5) * MapInfo.CELL)
	var pair: Array = []
	for part in 2:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = _trunk_mesh if part == 0 else _crown_mesh
		batch.instance_count = count
		batch.buffer = buffer
		var reach := MapInfo.CELL * 0.5 + 10.0
		batch.custom_aabb = AABB(Vector3(-reach, -300.0, -reach), Vector3(reach * 2.0, 2600.0, reach * 2.0))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.position = middle
		instance.visibility_range_end = draw_distance
		instance.visibility_range_end_margin = 150.0
		if part == 0:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		pair.append(instance)
	_built[square] = pair


## A number from 0 to 1 that looks random but is always the same for `n`.
static func _hash(n: int) -> float:
	var value := (n * 1103515245 + 12345) & 0x7fffffff
	value = (value ^ (value >> 13)) * 1274126177 & 0x7fffffff
	return float(value % 10007) / 10006.0


## Adds the trunks of the trees in one 128 m square to a body, as cylinders
## that reach up into the crowns. `square` and the body are in map positions.
func add_trunks(body: StaticBody3D, square: Vector2i) -> void:
	if not _tiles.has(square):
		return
	var run: Vector2i = _tiles[square]
	var per_cell := int(MapInfo.CELL / MapInfo.TILE)
	var middle_x := (floori(float(square.x) / per_cell) + 0.5) * MapInfo.CELL
	var middle_z := (floori(float(square.y) / per_cell) + 0.5) * MapInfo.CELL
	for index in range(run.x, run.x + run.y):
		var at := index * FLOATS
		if at + 3 >= _trees.size():
			break
		var size := snappedf(_trees[at + 3], 0.1)
		if not _trunk_shapes.has(size):
			var cylinder := CylinderShape3D.new()
			cylinder.radius = TRUNK_RADIUS * size
			cylinder.height = SOLID_HEIGHT * size
			_trunk_shapes[size] = cylinder
		var trunk: CylinderShape3D = _trunk_shapes[size]
		var collider := CollisionShape3D.new()
		collider.shape = trunk
		collider.position = Vector3(_trees[at] + middle_x, _trees[at + 1] + trunk.height * 0.5, _trees[at + 2] + middle_z)
		body.add_child(collider)


# --- Models ------------------------------------------------------------------

func _make_trunk_mesh() -> ArrayMesh:
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
func _make_crown_mesh() -> ArrayMesh:
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
