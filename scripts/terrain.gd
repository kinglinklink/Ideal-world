extends Node3D
## The world map: Flathead Lake at true size, from the data baked by
## tools/bake_map.py. See map_info.gd for where everything sits.
##
## Drawing: a few square grids of vertices follow the camera, each twice as
## coarse as the one inside it, and terrain.gdshader lifts every vertex to the
## height in the baked pictures. One draw per grid covers the whole 60 km map.
##
## Collision: the ground is solid only in 128 m squares near the character
## and near every spawned body, built as they are needed and dropped a few
## seconds after nothing is near them. Each square also holds the trunks of
## its trees.
##
## Also here: the lake surface, and the wall round the edge of the world: the
## four straight sides of a rectangle round the lake, square to north. The
## trees are in forest.gd, the airports and buildings in landmarks.gd, and
## the real towns (roads, houses, bridges) in towns.gd.
##
## Re-centring (origin.gd): everything here is laid out in map positions under
## this node, and main.gd moves this node by the world offset. So children
## never move themselves; the shaders are told the offset to read the map.
## Functions taking `x, z` want map positions; those taking a Vector3 want a
## world position.

const MapInfo = preload("res://scripts/map_info.gd")
const Origin = preload("res://scripts/origin.gd")
const Units = preload("res://scripts/units.gd")
const Forest = preload("res://scripts/forest.gd")
const Landmarks = preload("res://scripts/landmarks.gd")
const Towns = preload("res://scripts/towns.gd")
const TERRAIN_SHADER = preload("res://shaders/terrain.gdshader")
const WATER_SHADER = preload("res://shaders/water.gdshader")

const LEVELS := 10           # grids round the camera
const LEVEL_QUADS := 96      # each grid is this many squares across
const FINEST := 2.0          # metres between vertices in the finest grid

const TILE_SAMPLES := 33     # heights across one collision square (4 m apart, the detail data's own spacing)
const PLAYER_REACH := 320.0  # metres round the character kept solid
const BODY_REACH := 200.0    # metres round each spawned body
const LOOKAHEAD := 1.5       # seconds of travel ahead of a moving body also kept solid
const KEEP_TIME := 4.0       # seconds a square lingers after nothing needs it
const REPLAN_TIME := 0.1     # seconds between working out which squares are needed
const TILES_PER_TICK := 1    # squares built per physics step while moving
const GROUND_FRICTION := 0.8

const WALL_HEIGHT := 24.0          # metres of wall you can see above the ground
const WALL_FOOTING := 4.0          # metres it reaches below the ground
const BARRIER_HEIGHT := 12000.0    # the unseen barrier above it reaches this high
const WALL_THICKNESS := 3.0
const WALL_PIECE := 32.0           # metres: the seen wall follows the ground in pieces this long
const WATER_KIND := 5              # the surface kind of the lake in the baked pictures

var world: Dictionary = {}         # world.json
var forest: Node3D = null          # forest.gd
var landmarks: Node3D = null       # landmarks.gd
var towns: Node3D = null           # towns.gd

var _coarse := PackedByteArray()
var _detail := PackedByteArray()
var _coarse_texture: ImageTexture
var _detail_texture: ImageTexture
var _noise: NoiseTexture2D
var _levels: Array = []            # [MeshInstance3D, ShaderMaterial, vertex spacing]
var _water: MeshInstance3D
var _water_material: ShaderMaterial
var _tiles: Dictionary = {}        # Vector2i square -> [StaticBody3D, time it was last needed]
var _pending: Array = []           # squares needed but not built yet, nearest first
var _replan := 0.0
var _player: Node3D = null
var _spawner: Node3D = null
var _clock := 0.0


## Loads the map and builds everything, with solid ground already in place
## round `player`. Call before the first physics step.
func setup(player: Node3D, spawner: Node3D, noise: NoiseTexture2D) -> void:
	_player = player
	_spawner = spawner
	_noise = noise
	world = JSON.parse_string(FileAccess.get_file_as_string(MapInfo.WORLD_FILE))
	_coarse_texture = _load_heights(MapInfo.COARSE_FILE, true)
	_detail_texture = _load_heights(MapInfo.DETAIL_FILE, false)
	_build_levels()
	_build_water()
	_build_walls()

	forest = Forest.new()
	forest.name = "Forest"
	add_child(forest)
	forest.setup(world)

	landmarks = Landmarks.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)
	landmarks.setup(world)

	towns = Towns.new()
	towns.name = "Towns"
	add_child(towns)
	towns.setup(world)

	# Solid ground round the start, before anything can fall.
	_build_all_needed()


func _load_heights(path: String, coarse: bool) -> ImageTexture:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		push_error("Could not read the map file %s. Run tools/bake_map.py." % path)
		image = Image.create_empty(2, 2, false, Image.FORMAT_RGB8)
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	if coarse:
		_coarse = image.get_data()
	else:
		_detail = image.get_data()
	return ImageTexture.create_from_image(image)


# --- Heights -----------------------------------------------------------------

## The ground height at a point, in metres above the build pad. Matches what
## is drawn and what is solid.
func height_at(x: float, z: float) -> float:
	var gx := (x - MapInfo.DETAIL_ORIGIN.x) / MapInfo.DETAIL_SPACING
	var gz := (z - MapInfo.DETAIL_ORIGIN.y) / MapInfo.DETAIL_SPACING
	if gx >= 0.0 and gz >= 0.0 and gx <= MapInfo.DETAIL_SIZE.x - 1.001 and gz <= MapInfo.DETAIL_SIZE.y - 1.001:
		return _bilinear(_detail, MapInfo.DETAIL_SIZE.x, gx, gz, MapInfo.DETAIL_SCALE, MapInfo.DETAIL_OFFSET)
	gx = clampf((x - MapInfo.COARSE_ORIGIN.x) / MapInfo.COARSE_SPACING, 0.0, MapInfo.COARSE_SIZE.x - 1.001)
	gz = clampf((z - MapInfo.COARSE_ORIGIN.y) / MapInfo.COARSE_SPACING, 0.0, MapInfo.COARSE_SIZE.y - 1.001)
	return _bilinear(_coarse, MapInfo.COARSE_SIZE.x, gx, gz, MapInfo.COARSE_SCALE, MapInfo.COARSE_OFFSET)


## The ground height under a world position.
func ground_at(world_position: Vector3) -> float:
	var map := Origin.to_map(world_position)
	return height_at(map.x, map.z)


## True if a map position is over the lake (not just low ground).
func is_lake(x: float, z: float) -> bool:
	var gx := (x - MapInfo.DETAIL_ORIGIN.x) / MapInfo.DETAIL_SPACING
	var gz := (z - MapInfo.DETAIL_ORIGIN.y) / MapInfo.DETAIL_SPACING
	var data := _detail
	var width := MapInfo.DETAIL_SIZE.x
	if gx < 0.0 or gz < 0.0 or gx > MapInfo.DETAIL_SIZE.x - 1.001 or gz > MapInfo.DETAIL_SIZE.y - 1.001:
		gx = (x - MapInfo.COARSE_ORIGIN.x) / MapInfo.COARSE_SPACING
		gz = (z - MapInfo.COARSE_ORIGIN.y) / MapInfo.COARSE_SPACING
		if gx < 0.0 or gz < 0.0 or gx > MapInfo.COARSE_SIZE.x - 1.001 or gz > MapInfo.COARSE_SIZE.y - 1.001:
			return false
		data = _coarse
		width = MapInfo.COARSE_SIZE.x
	var index := (int(gz + 0.5) * width + int(gx + 0.5)) * 3 + 2
	if index >= data.size():
		return false
	return data[index] % 8 == WATER_KIND


## True if a world position is over the lake.
func lake_at(world_position: Vector3) -> bool:
	var map := Origin.to_map(world_position)
	return is_lake(map.x, map.z)


static func _bilinear(data: PackedByteArray, width: int, gx: float, gz: float, value_scale: float, offset: float) -> float:
	var col := int(gx)
	var row := int(gz)
	var fx := gx - col
	var fz := gz - row
	var i := (row * width + col) * 3
	var j := i + width * 3
	var h00 := float(data[i] * 256 + data[i + 1])
	var h10 := float(data[i + 3] * 256 + data[i + 4])
	var h01 := float(data[j] * 256 + data[j + 1])
	var h11 := float(data[j + 3] * 256 + data[j + 4])
	var value := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)
	return value / value_scale - offset


# --- Drawing -----------------------------------------------------------------

func _shared_uniforms(material: ShaderMaterial) -> void:
	material.set_shader_parameter("coarse_map", _coarse_texture)
	material.set_shader_parameter("detail_map", _detail_texture)
	material.set_shader_parameter("noise_map", _noise)
	material.set_shader_parameter("coarse_origin", MapInfo.COARSE_ORIGIN)
	material.set_shader_parameter("coarse_spacing", MapInfo.COARSE_SPACING)
	material.set_shader_parameter("coarse_size", Vector2(MapInfo.COARSE_SIZE))
	material.set_shader_parameter("detail_origin", MapInfo.DETAIL_ORIGIN)
	material.set_shader_parameter("detail_spacing", MapInfo.DETAIL_SPACING)
	material.set_shader_parameter("detail_size", Vector2(MapInfo.DETAIL_SIZE))
	material.set_shader_parameter("map_offset", Vector2(Origin.offset.x, Origin.offset.z))


func _build_levels() -> void:
	for level in LEVELS:
		var spacing: float = FINEST * pow(2.0, level)
		var plane := PlaneMesh.new()
		plane.size = Vector2(LEVEL_QUADS, LEVEL_QUADS)
		plane.subdivide_width = LEVEL_QUADS - 1
		plane.subdivide_depth = LEVEL_QUADS - 1
		# The shader moves every vertex, so the usual bounds would be wrong.
		plane.custom_aabb = AABB(Vector3(-LEVEL_QUADS, -1000.0, -LEVEL_QUADS), Vector3(LEVEL_QUADS * 2.0, 6000.0, LEVEL_QUADS * 2.0))
		var material := ShaderMaterial.new()
		material.shader = TERRAIN_SHADER
		_shared_uniforms(material)
		material.set_shader_parameter("coarse_code", Vector2(MapInfo.COARSE_SCALE, MapInfo.COARSE_OFFSET))
		material.set_shader_parameter("detail_code", Vector2(MapInfo.DETAIL_SCALE, MapInfo.DETAIL_OFFSET))
		material.set_shader_parameter("lake_y", MapInfo.LAKE_Y)
		material.set_shader_parameter("base_elevation", MapInfo.BASE_ELEVATION)
		material.set_shader_parameter("vertex_step", spacing)
		material.set_shader_parameter("inner_box", Vector4.ZERO)
		plane.material = material
		var ring := MeshInstance3D.new()
		ring.name = "Ground%d" % level
		ring.mesh = plane
		ring.scale = Vector3(spacing, 1.0, spacing)
		if level > 3:
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_levels.append([ring, material, spacing])
	_place_levels(Vector3.ZERO)


## Centres every grid on the camera, each snapped to its own vertex spacing
## so the ground does not shimmer as the camera moves.
func _place_levels(eye: Vector3) -> void:
	var inner_centre := Vector2.ZERO
	var inner_half := 0.0
	for level in _levels.size():
		var entry: Array = _levels[level]
		var ring: MeshInstance3D = entry[0]
		var material: ShaderMaterial = entry[1]
		var spacing: float = entry[2]
		var snap := spacing * 2.0
		var centre := Vector2(floorf(eye.x / snap) * snap, floorf(eye.z / snap) * snap)
		ring.position = Vector3(centre.x, 0.0, centre.y)
		if level == 0:
			material.set_shader_parameter("inner_box", Vector4.ZERO)
		else:
			# Leave a hole for the finer grid, less one of its squares, so the
			# two overlap a little and no crack shows between them.
			var finer: float = spacing * 0.5
			material.set_shader_parameter("inner_box",
					Vector4(inner_centre.x, inner_centre.y, inner_half - finer, 1.0))
		inner_centre = centre
		inner_half = LEVEL_QUADS * 0.5 * spacing


func _build_water() -> void:
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(80000.0, 80000.0)
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	_shared_uniforms(material)
	sheet.material = material
	_water_material = material
	_water = MeshInstance3D.new()
	_water.name = "Lake"
	_water.mesh = sheet
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var middle := MapInfo.COARSE_ORIGIN + Vector2(MapInfo.COARSE_SIZE) * MapInfo.COARSE_SPACING * 0.5
	_water.position = Vector3(middle.x, MapInfo.LAKE_Y, middle.y)
	add_child(_water)


## The wall round the world: the four sides of the rectangle in world.json.
## A stone wall you can see follows the ground in short pieces, all in one
## straight line per side, so there are no corners to snag on. Each side's
## solid part is a single straight slab from below the lowest ground along it
## up to the barrier height, so nothing can fly out either.
func _build_walls() -> void:
	var lines: Array = world.get("walls", [])
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = Units.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in lines:
		var points: Array = line
		for index in points.size():
			var a_point: Array = points[index]
			var b_point: Array = points[(index + 1) % points.size()]
			var a := Vector2(float(a_point[0]), float(a_point[1]))
			var b := Vector2(float(b_point[0]), float(b_point[1]))
			var length := a.distance_to(b)
			if length < 0.5:
				continue
			var pieces := maxi(1, int(ceil(length / WALL_PIECE)))
			var lowest := INF
			var previous := a
			var previous_ground := height_at(a.x, a.y)
			for piece in range(1, pieces + 1):
				var next := a.lerp(b, float(piece) / pieces)
				var next_ground := height_at(next.x, next.y)
				var middle := (previous + next) * 0.5
				var middle_ground := height_at(middle.x, middle.y)
				var low := minf(minf(previous_ground, next_ground), middle_ground) - WALL_FOOTING
				var high := maxf(maxf(previous_ground, next_ground), middle_ground) + WALL_HEIGHT
				lowest = minf(lowest, low)
				var corners := [Vector3(previous.x, low, previous.y), Vector3(next.x, low, next.y),
						Vector3(next.x, high, next.y), Vector3(previous.x, high, previous.y)]
				# One face; the stone is drawn from both sides.
				for face in [[0, 1, 2], [0, 2, 3]]:
					var tri: Array = face
					for corner in tri:
						var at: Vector3 = corners[corner]
						surface.add_vertex(at)
				previous = next
				previous_ground = next_ground
			var slab := BoxShape3D.new()
			slab.size = Vector3(length + WALL_THICKNESS, BARRIER_HEIGHT, WALL_THICKNESS)
			var collider := CollisionShape3D.new()
			collider.shape = slab
			var along := (b - a) / length
			var turn := Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(-along.y, 0.0, along.x))
			var centre := (a + b) * 0.5
			collider.transform = Transform3D(turn, Vector3(centre.x, lowest + BARRIER_HEIGHT * 0.5, centre.y))
			body.add_child(collider)
	surface.generate_normals()
	var mesh := surface.commit()
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.53, 0.50)
	stone.roughness = 1.0
	stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, stone)
	var wall := MeshInstance3D.new()
	wall.name = "WallStone"
	wall.mesh = mesh
	body.add_child(wall)


# --- Every frame -------------------------------------------------------------

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and not _levels.is_empty():
		_place_levels(Origin.to_map(camera.global_position))


## Called by main.gd after the world has shifted (this node has already moved).
func origin_shifted() -> void:
	var offset := Vector2(Origin.offset.x, Origin.offset.z)
	for entry in _levels:
		var level: Array = entry
		var material: ShaderMaterial = level[1]
		material.set_shader_parameter("map_offset", offset)
	if _water_material != null:
		_water_material.set_shader_parameter("map_offset", offset)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_place_levels(Origin.to_map(camera.global_position))


func _physics_process(delta: float) -> void:
	_clock += delta
	_replan -= delta
	if _replan <= 0.0:
		_replan = REPLAN_TIME
		_plan_tiles()
	var built := 0
	while built < TILES_PER_TICK and not _pending.is_empty():
		var square: Vector2i = _pending.pop_front()
		if not _tiles.has(square):
			_tiles[square] = [_make_tile(square), _clock]
			built += 1


# --- Collision ---------------------------------------------------------------

## Builds every solid square needed right now, at once. Used at the start.
func _build_all_needed() -> void:
	_plan_tiles()
	for key in _pending:
		var square: Vector2i = key
		if not _tiles.has(square):
			_tiles[square] = [_make_tile(square), _clock]
	_pending.clear()


## Works out which solid squares are needed now: marks the ones already
## built, queues the rest nearest first, and drops the ones that have not
## been needed for a while.
func _plan_tiles() -> void:
	var wanted: Dictionary = {}
	if _player != null:
		_want_round(wanted, Origin.to_map(_player.global_position), PLAYER_REACH)
	if _spawner != null and bool(_spawner.spawned):
		for item in _spawner.body_motions():
			var motion: Array = item
			var at: Vector3 = Origin.to_map(motion[0])
			var moving: Vector3 = motion[1]
			_want_round(wanted, at, BODY_REACH)
			if moving.length() > 1.0:
				_want_round(wanted, at + moving * LOOKAHEAD, BODY_REACH)
	_pending.clear()
	for key in wanted:
		var square: Vector2i = key
		if _tiles.has(square):
			var entry: Array = _tiles[square]
			entry[1] = _clock
		else:
			_pending.append(square)
	# The nearest squares first, so the ground under the character comes first.
	if _player != null and _pending.size() > 1:
		var spot := Origin.to_map(_player.global_position)
		var here := Vector2(spot.x, spot.z) / MapInfo.TILE - Vector2(0.5, 0.5)
		_pending.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
			return (Vector2(p) - here).length_squared() < (Vector2(q) - here).length_squared())
	var stale: Array = []
	for key in _tiles:
		var entry: Array = _tiles[key]
		if _clock - float(entry[1]) > KEEP_TIME:
			stale.append(key)
	for key in stale:
		var entry: Array = _tiles[key]
		var tile: Node = entry[0]
		tile.queue_free()
		_tiles.erase(key)


func _want_round(wanted: Dictionary, at: Vector3, reach: float) -> void:
	var tile := MapInfo.TILE
	var low := Vector2i(floori((at.x - reach) / tile), floori((at.z - reach) / tile))
	var high := Vector2i(floori((at.x + reach) / tile), floori((at.z + reach) / tile))
	for i in range(low.x, high.x + 1):
		for k in range(low.y, high.y + 1):
			wanted[Vector2i(i, k)] = true


## One solid 128 m square of ground, with its tree trunks.
func _make_tile(square: Vector2i) -> StaticBody3D:
	var tile := MapInfo.TILE
	var step := tile / float(TILE_SAMPLES - 1)
	var x0 := square.x * tile
	var z0 := square.y * tile
	var heights := PackedFloat32Array()
	heights.resize(TILE_SAMPLES * TILE_SAMPLES)
	for row in TILE_SAMPLES:
		for col in TILE_SAMPLES:
			# The shape is scaled up by `step`, so its heights are scaled down.
			heights[row * TILE_SAMPLES + col] = height_at(x0 + col * step, z0 + row * step) / step
	var shape := HeightMapShape3D.new()
	shape.map_width = TILE_SAMPLES
	shape.map_depth = TILE_SAMPLES
	shape.map_data = heights
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = Transform3D(Basis.from_scale(Vector3(step, step, step)),
			Vector3(x0 + tile * 0.5, 0.0, z0 + tile * 0.5))
	var body := StaticBody3D.new()
	body.name = "Ground_%d_%d" % [square.x, square.y]
	body.collision_layer = Units.LAYER_WORLD
	body.collision_mask = 0
	var surface := PhysicsMaterial.new()
	surface.friction = GROUND_FRICTION
	body.physics_material_override = surface
	body.add_child(collider)
	if forest != null:
		forest.add_trunks(body, square)
	add_child(body)
	return body
