extends Node3D
## Every tree on the map, placed by tools/bake_map.py, as the trees that
## really grow round Flathead Lake. Where each one stands decides its kind:
## cottonwoods, aspens, birches, hawthorns and serviceberries on the shore;
## ponderosa pine, Douglas-fir and juniper on low, dry, south-facing slopes;
## Douglas-fir, western redcedar, larch and Rocky Mountain maple where it is
## low and shaded; Douglas-fir, larch and lodgepole pine higher up; then
## Engelmann spruce and subalpine fir, and mountain hemlock near the tree
## line. Larches and the broadleaf trees turn colour in autumn and are bare
## in winter (tree_crown.gdshader).
##
## Trees are drawn in 1 km squares, one MultiMesh for each kind of tree in
## the square, so the graphics card draws thousands in one go. A square is
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
const CROWN_SHADER = preload("res://shaders/tree_crown.gdshader")

const FLOATS := 4               # per tree in the file
const TRUNK_RADIUS := 0.3       # metres, for a tree of size 1; solid up into the crown
const SOLID_HEIGHT := 7.0
const BUILD_MARGIN := 300.0     # squares are built this far beyond the draw distance
const FREE_MARGIN := 1200.0     # and freed this far beyond it
const BUILDS_PER_FRAME := 1

## How far away trees are drawn, in metres. The settings menu changes it.
var draw_distance := 2600.0
var clearings: Array = []      # [Vector2 map x and z, radius]: no trees inside (wizard towers)

var _trees := PackedFloat32Array()
var _tiles: Dictionary = {}     # Vector2i collision square -> Vector2i(first tree, count)
var _cells: Array = []          # [Vector2i square, first tree, count]
var _built: Dictionary = {}     # Vector2i square -> [trunk MultiMeshInstance3D, crown MultiMeshInstance3D]
var _trunk_shapes: Dictionary = {}
var _look: ShaderMaterial          # every tree's material
var _meshes: Array = []            # one per kind, in SPECIES order
var terrain: Node = null           # terrain.gd, for the lie of the land under each tree

const SHORE_RISE := 14.0           # m above the lake that counts as the shore
const GRID := 32.0                 # m between ground samples for slopes, when a square is built
const SHRUB_DISTANCE := 700.0      # m beyond which shrubs aren't drawn

## The kinds of tree: [name, shrub].
const SPECIES := [
	["Douglas-fir", false], ["Ponderosa pine", false], ["Lodgepole pine", false], ["Western larch", false],
	["Western redcedar", false], ["Engelmann spruce", false], ["Subalpine fir", false], ["Mountain hemlock", false],
	["Rocky Mountain juniper", true], ["Black cottonwood", false], ["Quaking aspen", false], ["Paper birch", false],
	["Rocky Mountain maple", true], ["Douglas hawthorn", true], ["Serviceberry", true],
]
enum { DOUGLAS_FIR, PONDEROSA, LODGEPOLE, LARCH, REDCEDAR, SPRUCE, SUBALPINE_FIR, HEMLOCK, JUNIPER,
		COTTONWOOD, ASPEN, BIRCH, MAPLE, HAWTHORN, SERVICEBERRY }
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
	_make_meshes()


## The season on the trees: gold larches in autumn, snow above the snow line.
func set_season(autumn: float, snow_line_y: float, cold: float) -> void:
	if _look == null:
		return
	_look.set_shader_parameter("autumn", autumn)
	_look.set_shader_parameter("snow_line_y", snow_line_y)
	_look.set_shader_parameter("cold", cold)


## Sets how far trees are drawn, and applies it to the squares already built.
func set_draw_distance(metres: float) -> void:
	draw_distance = metres
	for key in _built:
		var pair: Array = _built[key]
		for item in pair:
			var instance: MultiMeshInstance3D = item
			instance.visibility_range_end = minf(draw_distance, SHRUB_DISTANCE) if instance.has_meta("shrub") else draw_distance


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


## Whether a tree at map position x, z stands in a clearing (under a tower).
func _cleared(x: float, z: float) -> bool:
	for item in clearings:
		var clearing: Array = item
		var middle: Vector2 = clearing[0]
		if middle.distance_squared_to(Vector2(x, z)) < float(clearing[1]) * float(clearing[1]):
			return true
	return false


func _build_cell(cell: Array) -> void:
	var square: Vector2i = cell[0]
	var first: int = cell[1]
	var count: int = cell[2]
	if count <= 0 or (first + count) * FLOATS > _trees.size():
		_built[square] = []
		return
	var origin_x := (square.x + 0.5) * MapInfo.CELL
	var origin_z := (square.y + 0.5) * MapInfo.CELL
	var ground := _ground_grid(square)
	# A 3 x 4 transform and a colour per tree, as MultiMesh wants them, in a
	# buffer for each kind of tree.
	var rows := PackedFloat32Array()
	rows.resize(count * 16)
	var kinds := PackedInt32Array()
	kinds.resize(count)
	kinds.fill(-1)
	var per_kind := PackedInt32Array()
	per_kind.resize(SPECIES.size())
	for index in count:
		var at := (first + index) * FLOATS
		var size := _trees[at + 3]
		var x := _trees[at] + origin_x
		var z := _trees[at + 2] + origin_z
		if not clearings.is_empty() and _cleared(x, z):
			continue
		var tree := first + index
		var kind := species_of(tree, _trees[at + 1], _slope_from(ground, x, z))
		var turn := _hash(tree) * TAU
		# Each tree a little taller or squatter, and its own shade.
		var tall := size * (0.85 + 0.3 * _hash(tree * 17 + 1))
		var cosine := cos(turn) * size
		var sine := sin(turn) * size
		var shade := 0.85 + 0.3 * _hash(tree * 7 + 3)
		var hue := 0.06 * (_hash(tree * 13 + 5) - 0.5)
		var row := [cosine, 0.0, sine, _trees[at], 0.0, tall, 0.0, _trees[at + 1],
				-sine, 0.0, cosine, _trees[at + 2], shade + hue, shade, shade - hue, 1.0]
		for value in 16:
			rows[index * 16 + value] = row[value]
		kinds[index] = kind
		per_kind[kind] += 1
	# One buffer per kind, of its trees' rows.
	var buffers: Array = []
	for kind in SPECIES.size():
		var chosen := PackedFloat32Array()
		chosen.resize(per_kind[kind] * 16)
		var filled := 0
		for index in count:
			if kinds[index] == kind:
				for value in 16:
					chosen[filled * 16 + value] = rows[index * 16 + value]
				filled += 1
		buffers.append(chosen)
	var middle := Vector3(origin_x, 0.0, origin_z)
	var pair: Array = []
	for kind in SPECIES.size():
		var chosen: PackedFloat32Array = buffers[kind]
		if chosen.is_empty():
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = _meshes[kind]
		batch.instance_count = floori(chosen.size() / 16.0)
		batch.buffer = chosen
		var reach := MapInfo.CELL * 0.5 + 10.0
		batch.custom_aabb = AABB(Vector3(-reach, -300.0, -reach), Vector3(reach * 2.0, 2600.0, reach * 2.0))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.position = middle
		var shrub: bool = SPECIES[kind][1]
		instance.visibility_range_end = minf(draw_distance, SHRUB_DISTANCE) if shrub else draw_distance
		instance.visibility_range_end_margin = 150.0
		if shrub:
			instance.set_meta("shrub", true)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		pair.append(instance)
	_built[square] = pair


# --- Where each kind grows ---------------------------------------------------

## The ground's height every GRID metres over a square and a little round it,
## for the slopes under its trees. Empty without the terrain.
func _ground_grid(square: Vector2i) -> Dictionary:
	if terrain == null:
		return {}
	var corner := Vector2(square) * MapInfo.CELL - Vector2(GRID, GRID)
	var steps := int(MapInfo.CELL / GRID) + 3
	var heights := PackedFloat32Array()
	heights.resize(steps * steps)
	for row in steps:
		for column in steps:
			heights[row * steps + column] = terrain.height_at(corner.x + column * GRID, corner.y + row * GRID)
	return {"corner": corner, "steps": steps, "heights": heights}


## The slope of the ground at x, z: Vector2(rise per metre east, rise per
## metre south).
func _slope_from(ground: Dictionary, x: float, z: float) -> Vector2:
	if ground.is_empty():
		return _slope_at(x, z)
	var corner: Vector2 = ground["corner"]
	var steps: int = ground["steps"]
	var heights: PackedFloat32Array = ground["heights"]
	var column := clampi(int((x - corner.x) / GRID), 0, steps - 2)
	var row := clampi(int((z - corner.y) / GRID), 0, steps - 2)
	var here := heights[row * steps + column]
	return Vector2(heights[row * steps + column + 1] - here, heights[(row + 1) * steps + column] - here) / GRID


## The same as _slope_from, from the same points on the same GRID, for
## one tree on its own (so its trunk matches its kind).
func _slope_at(x: float, z: float) -> Vector2:
	if terrain == null:
		return Vector2.ZERO
	var bx := floorf(x / GRID) * GRID
	var bz := floorf(z / GRID) * GRID
	var here: float = terrain.height_at(bx, bz)
	return Vector2(float(terrain.height_at(bx + GRID, bz)) - here, float(terrain.height_at(bx, bz + GRID)) - here) / GRID


## Which kind a tree is, from where it stands: its height (game metres; the
## lake is at MapInfo.LAKE_Y) and the slope of the ground (see _slope_from).
## The same tree always comes out the same.
static func species_of(tree: int, y: float, slope: Vector2) -> int:
	var above_sea := y + MapInfo.BASE_ELEVATION + 160.0 * (_hash(tree * 29 + 11) - 0.5)
	var steep := slope.length()
	# How much the slope faces south (+Z is south), from -1 to 1: south
	# faces are dry and warm, north faces shaded and moist.
	var south := 0.0
	if steep > 0.02:
		south = clampf(-slope.y / steep, -1.0, 1.0) * clampf(steep / 0.25, 0.0, 1.0)
	var weights: Array
	if y < MapInfo.LAKE_Y + SHORE_RISE:
		weights = [[COTTONWOOD, 30], [ASPEN, 14], [BIRCH, 15], [HAWTHORN, 8], [SERVICEBERRY, 7], [MAPLE, 5],
				[DOUGLAS_FIR, 10], [PONDEROSA, 6], [REDCEDAR, 5]]
	elif above_sea < 1250.0:
		if south > 0.25:
			weights = [[PONDEROSA, 45], [DOUGLAS_FIR, 25], [JUNIPER, 10], [SERVICEBERRY, 6], [HAWTHORN, 4], [ASPEN, 4], [LARCH, 4]]
		elif south < -0.25:
			weights = [[DOUGLAS_FIR, 30], [REDCEDAR, 22], [LARCH, 15], [MAPLE, 8], [BIRCH, 6], [ASPEN, 6],
					[PONDEROSA, 5], [SERVICEBERRY, 5], [SPRUCE, 3]]
		else:
			weights = [[DOUGLAS_FIR, 35], [PONDEROSA, 25], [LARCH, 12], [ASPEN, 8], [MAPLE, 6], [LODGEPOLE, 5],
					[SERVICEBERRY, 5], [JUNIPER, 4]]
	elif above_sea < 1750.0:
		if south > 0.25:
			weights = [[DOUGLAS_FIR, 30], [LODGEPOLE, 25], [PONDEROSA, 20], [LARCH, 15], [ASPEN, 5], [JUNIPER, 5]]
		elif south < -0.25:
			weights = [[DOUGLAS_FIR, 25], [LARCH, 25], [LODGEPOLE, 20], [SPRUCE, 10], [REDCEDAR, 8], [SUBALPINE_FIR, 7], [MAPLE, 5]]
		else:
			weights = [[DOUGLAS_FIR, 30], [LODGEPOLE, 30], [LARCH, 22], [PONDEROSA, 8], [ASPEN, 5], [SPRUCE, 5]]
	elif above_sea < 2150.0:
		weights = [[SUBALPINE_FIR, 32], [SPRUCE, 30], [LODGEPOLE, 22], [LARCH, 10], [HEMLOCK, 6]]
	else:
		weights = [[SUBALPINE_FIR, 45], [HEMLOCK, 30], [SPRUCE, 20], [JUNIPER, 5]]
	# Junipers take the steep, rocky ground.
	if steep > 0.8:
		weights.append([JUNIPER, 20])
	var total := 0.0
	for item in weights:
		total += float(item[1])
	var pick := _hash(tree * 31 + 7) * total
	for item in weights:
		pick -= float(item[1])
		if pick <= 0.0:
			return int(item[0])
	return int(weights[0][0])


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
		if not clearings.is_empty() and _cleared(_trees[at] + middle_x, _trees[at + 2] + middle_z):
			continue
		var size := snappedf(_trees[at + 3], 0.1)
		var x := _trees[at] + middle_x
		var z := _trees[at + 2] + middle_z
		var kind := species_of(index, _trees[at + 1], _slope_at(x, z))
		var shrub: bool = SPECIES[kind][1]
		var key := Vector2(size, 1.0 if shrub else 0.0)
		if not _trunk_shapes.has(key):
			var cylinder := CylinderShape3D.new()
			cylinder.radius = TRUNK_RADIUS * size * (0.6 if shrub else 1.0)
			cylinder.height = SOLID_HEIGHT * size * (0.35 if shrub else 1.0)
			_trunk_shapes[key] = cylinder
		var trunk: CylinderShape3D = _trunk_shapes[key]
		var collider := CollisionShape3D.new()
		collider.shape = trunk
		collider.position = Vector3(_trees[at] + middle_x, _trees[at + 1] + trunk.height * 0.5, _trees[at + 2] + middle_z)
		body.add_child(collider)


# --- Models ------------------------------------------------------------------
# Each kind is one mesh: bark (UV.x = 1) and foliage (UV.x = 0) in their
# own colours, with the kind in UV.y for the shader. Base at the origin;
# about 7 to 10 m tall for a tree of size 1, shrubs 3 m.

const BARK_GREY := Color(0.36, 0.3, 0.25)


func _make_meshes() -> void:
	_look = ShaderMaterial.new()
	_look.shader = CROWN_SHADER
	_meshes.clear()
	for kind in SPECIES.size():
		var surface := Kit.new_surface()
		_model(surface, kind)
		var mesh: ArrayMesh = surface.commit()
		mesh.surface_set_material(0, _look)
		_meshes.append(mesh)


func _bark(surface: SurfaceTool, kind: int, colour: Color) -> void:
	surface.set_uv(Vector2(1.0, (kind + 0.5) / 16.0))
	surface.set_color(colour)


func _leaves(surface: SurfaceTool, kind: int, colour: Color) -> void:
	surface.set_uv(Vector2(0.0, (kind + 0.5) / 16.0))
	surface.set_color(colour)


## A cone of boughs in tiers: from `low` to `high`, widest `width` at the bottom.
func _tiers(surface: SurfaceTool, low: float, high: float, width: float, tiers: int, sides: int = 8, droop: float = 0.35) -> void:
	var step := (high - low) / tiers
	for tier in tiers:
		var t := float(tier) / tiers
		var bottom := width * (1.0 - t) * (1.0 - 0.15 * t)
		var top := bottom * droop
		var length := step * (1.6 if tier < tiers - 1 else 1.3)
		Kit.add_frustum(surface, Vector3(0.0, low + step * tier + length * 0.5, 0.0), 1, bottom, top if tier < tiers - 1 else 0.0, length, sides)


## A rounded mass of leaves: a squashed or stretched ball.
func _blob(surface: SurfaceTool, centre: Vector3, radii: Vector3, sides: int = 7, rings: int = 5) -> void:
	for ring in rings:
		var a := PI * ring / rings
		var b := PI * (ring + 1) / rings
		for side in sides:
			var c := TAU * side / sides
			var d := TAU * (side + 1) / sides
			var p1 := centre + Vector3(sin(a) * cos(c), cos(a), sin(a) * sin(c)) * radii
			var p2 := centre + Vector3(sin(b) * cos(c), cos(b), sin(b) * sin(c)) * radii
			var p3 := centre + Vector3(sin(b) * cos(d), cos(b), sin(b) * sin(d)) * radii
			var p4 := centre + Vector3(sin(a) * cos(d), cos(a), sin(a) * sin(d)) * radii
			Kit.add_triangle(surface, p1, p2, p3, (p1 + p2 + p3) / 3.0 - centre)
			Kit.add_triangle(surface, p1, p3, p4, (p1 + p3 + p4) / 3.0 - centre)


func _model(surface: SurfaceTool, kind: int) -> void:
	match kind:
		DOUGLAS_FIR:
			# Tall and conical, dark green, in layered boughs.
			_bark(surface, kind, Color(0.33, 0.25, 0.2))
			Kit.add_frustum(surface, Vector3(0.0, 1.5, 0.0), 1, 0.26, 0.12, 3.0, 6)
			_leaves(surface, kind, Color(0.11, 0.25, 0.13))
			_tiers(surface, 1.6, 9.6, 2.1, 5)
		PONDEROSA:
			# A long bare orange trunk and an open, rounded crown high up.
			_bark(surface, kind, Color(0.58, 0.36, 0.2))
			Kit.add_frustum(surface, Vector3(0.0, 3.6, 0.0), 1, 0.32, 0.16, 7.2, 7)
			_leaves(surface, kind, Color(0.22, 0.36, 0.14))
			_blob(surface, Vector3(0.0, 7.4, 0.0), Vector3(2.0, 1.3, 2.0))
			_blob(surface, Vector3(0.9, 8.6, 0.4), Vector3(1.3, 1.0, 1.3))
			_blob(surface, Vector3(-0.8, 6.4, -0.5), Vector3(1.4, 0.9, 1.4))
			_blob(surface, Vector3(0.1, 9.4, -0.3), Vector3(0.9, 0.8, 0.9))
		LODGEPOLE:
			# Thin and dead straight, with a short narrow crown at the top.
			_bark(surface, kind, Color(0.42, 0.35, 0.27))
			Kit.add_frustum(surface, Vector3(0.0, 3.2, 0.0), 1, 0.15, 0.07, 6.4, 6)
			_leaves(surface, kind, Color(0.16, 0.32, 0.14))
			_tiers(surface, 4.6, 9.0, 1.0, 3, 7)
		LARCH:
			# Narrow and airy, light green: gold in autumn, bare in winter.
			_bark(surface, kind, Color(0.45, 0.28, 0.2))
			Kit.add_frustum(surface, Vector3(0.0, 4.5, 0.0), 1, 0.2, 0.04, 9.0, 6)
			_leaves(surface, kind, Color(0.36, 0.54, 0.22))
			_tiers(surface, 2.6, 9.8, 1.35, 4, 6, 0.2)
		REDCEDAR:
			# A flared reddish trunk under a broad cone of drooping sprays.
			_bark(surface, kind, Color(0.5, 0.27, 0.18))
			Kit.add_frustum(surface, Vector3(0.0, 1.4, 0.0), 1, 0.45, 0.22, 2.8, 7)
			_leaves(surface, kind, Color(0.22, 0.4, 0.15))
			_tiers(surface, 1.2, 9.0, 2.5, 4, 9, 0.55)
		SPRUCE:
			# A dense blue-green spire, boughs to near the ground.
			_bark(surface, kind, Color(0.38, 0.3, 0.25))
			Kit.add_cylinder(surface, Vector3(0.0, 0.6, 0.0), 1, 0.17, 1.2, 6)
			_leaves(surface, kind, Color(0.14, 0.29, 0.25))
			_tiers(surface, 0.9, 8.6, 1.5, 6, 8, 0.3)
		SUBALPINE_FIR:
			# The narrowest spire of all: snow slides off it.
			_bark(surface, kind, Color(0.45, 0.42, 0.4))
			Kit.add_cylinder(surface, Vector3(0.0, 0.5, 0.0), 1, 0.13, 1.0, 6)
			_leaves(surface, kind, Color(0.11, 0.25, 0.2))
			_tiers(surface, 0.8, 7.2, 0.95, 6, 7, 0.4)
		HEMLOCK:
			# Narrow, soft and drooping, with a nodding tip.
			_bark(surface, kind, Color(0.4, 0.3, 0.26))
			Kit.add_cylinder(surface, Vector3(0.0, 0.6, 0.0), 1, 0.15, 1.2, 6)
			_leaves(surface, kind, Color(0.13, 0.29, 0.18))
			_tiers(surface, 0.9, 6.0, 1.25, 5, 8, 0.6)
			Kit.add_triangle(surface, Vector3(-0.15, 6.0, 0.0), Vector3(0.15, 6.0, 0.0), Vector3(0.45, 6.7, 0.0), Vector3(0, 0, 1))
			Kit.add_triangle(surface, Vector3(-0.15, 6.0, 0.0), Vector3(0.15, 6.0, 0.0), Vector3(0.45, 6.7, 0.0), Vector3(0, 0, -1))
		JUNIPER:
			# A small, gnarled, bushy tree of the dry and rocky ground.
			_bark(surface, kind, Color(0.48, 0.34, 0.27))
			Kit.add_frustum(surface, Vector3(0.0, 0.5, 0.0), 1, 0.16, 0.1, 1.0, 5)
			_leaves(surface, kind, Color(0.24, 0.34, 0.29))
			_blob(surface, Vector3(0.0, 1.5, 0.0), Vector3(1.0, 0.9, 1.0), 6, 4)
			_blob(surface, Vector3(0.4, 2.3, 0.2), Vector3(0.7, 0.8, 0.7), 6, 4)
			_blob(surface, Vector3(-0.5, 1.9, -0.3), Vector3(0.6, 0.7, 0.6), 6, 4)
		COTTONWOOD:
			# A big grey trunk forking into a broad, lumpy crown.
			_bark(surface, kind, Color(0.46, 0.43, 0.39))
			Kit.add_frustum(surface, Vector3(0.0, 1.8, 0.0), 1, 0.42, 0.26, 3.6, 7)
			_leaves(surface, kind, Color(0.24, 0.43, 0.15))
			for lump in [[Vector3(0.0, 5.4, 0.0), Vector3(2.6, 2.0, 2.6)], [Vector3(1.6, 4.6, 0.5), Vector3(1.6, 1.5, 1.6)],
					[Vector3(-1.4, 4.8, -0.8), Vector3(1.8, 1.5, 1.8)], [Vector3(0.3, 7.2, -0.3), Vector3(1.7, 1.4, 1.7)],
					[Vector3(-0.5, 4.3, 1.4), Vector3(1.4, 1.2, 1.4)]]:
				_blob(surface, lump[0], lump[1])
		ASPEN:
			# A slender white trunk and a small, narrow crown that quakes gold in autumn.
			_bark(surface, kind, Color(0.84, 0.85, 0.79))
			Kit.add_frustum(surface, Vector3(0.0, 2.6, 0.0), 1, 0.13, 0.07, 5.2, 6)
			_leaves(surface, kind, Color(0.3, 0.52, 0.19))
			_blob(surface, Vector3(0.0, 5.0, 0.0), Vector3(1.3, 1.6, 1.3))
			_blob(surface, Vector3(0.3, 6.2, 0.2), Vector3(0.9, 1.0, 0.9))
		BIRCH:
			# White, peeling bark and a light oval crown.
			_bark(surface, kind, Color(0.92, 0.9, 0.85))
			Kit.add_frustum(surface, Vector3(0.0, 2.2, 0.0), 1, 0.15, 0.08, 4.4, 6)
			Kit.add_frustum(surface, Vector3(0.35, 3.0, 0.0), 1, 0.08, 0.04, 2.0, 5)
			_leaves(surface, kind, Color(0.28, 0.48, 0.17))
			_blob(surface, Vector3(0.0, 4.6, 0.0), Vector3(1.6, 1.9, 1.6))
			_blob(surface, Vector3(0.6, 4.0, 0.3), Vector3(1.0, 1.0, 1.0))
		MAPLE:
			# Several thin stems with leafy tops: a shrub of moist canyons.
			_bark(surface, kind, Color(0.4, 0.33, 0.28))
			for stem in [Vector3(0.0, 0.0, 0.0), Vector3(0.35, 0.0, 0.2), Vector3(-0.3, 0.0, 0.25)]:
				Kit.add_cylinder(surface, stem + Vector3(0.0, 1.1, 0.0), 1, 0.06, 2.2, 5)
			_leaves(surface, kind, Color(0.27, 0.47, 0.16))
			_blob(surface, Vector3(0.0, 2.4, 0.0), Vector3(1.2, 0.9, 1.2), 6, 4)
			_blob(surface, Vector3(0.4, 3.0, 0.3), Vector3(0.8, 0.7, 0.8), 6, 4)
		HAWTHORN:
			# A dense, thorny little tree of riverbanks and coulees.
			_bark(surface, kind, Color(0.35, 0.29, 0.25))
			Kit.add_cylinder(surface, Vector3(0.0, 0.5, 0.0), 1, 0.08, 1.0, 5)
			_leaves(surface, kind, Color(0.22, 0.4, 0.15))
			_blob(surface, Vector3(0.0, 1.8, 0.0), Vector3(1.3, 1.0, 1.3), 6, 4)
			_blob(surface, Vector3(-0.3, 2.5, 0.2), Vector3(0.8, 0.6, 0.8), 6, 4)
		SERVICEBERRY:
			# A many-stemmed shrub of forest edges.
			_bark(surface, kind, Color(0.42, 0.36, 0.33))
			for stem in [Vector3(0.0, 0.0, 0.0), Vector3(0.25, 0.0, -0.2), Vector3(-0.25, 0.0, 0.1)]:
				Kit.add_cylinder(surface, stem + Vector3(0.0, 0.8, 0.0), 1, 0.05, 1.6, 5)
			_leaves(surface, kind, Color(0.29, 0.47, 0.2))
			_blob(surface, Vector3(0.1, 1.9, 0.0), Vector3(1.1, 0.9, 1.1), 6, 4)
			_blob(surface, Vector3(-0.3, 2.5, 0.0), Vector3(0.7, 0.6, 0.7), 6, 4)
