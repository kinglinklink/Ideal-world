extends Node3D
## The towns round the lake: real roads and buildings from OpenStreetMap,
## laid on the ground by tools/bake_map.py (see tools/towns.py).
##
## Roads are ribbons draped just above the ground: asphalt grey, highways
## with a yellow centre line, gravel tracks brown. Buildings are their real
## outlines raised to their height, solid inside the wall and scenery beyond
## it. Bridges are solid decks on piers. Each 1 km square is built when the
## camera comes within BUILD_DISTANCE and freed when it is far away, a square
## per frame; the bridges are always there.
##
## Buildings can be destroyed. Each has health for the space it encloses:
## HP_PER_M3 by what it is built of (wood for houses and sheds, brick for
## schools, churches and apartments, concrete for shops, warehouses and
## industry). Bullets, shells and blasts take it away (combat.gd asks here),
## and a building at zero falls to a heap of rubble you can drive over. All
## damage is undone when the build goes back to Build mode.
##
## Map data (c) OpenStreetMap contributors, ODbL.

const MapInfo = preload("res://scripts/map_info.gd")
const Origin = preload("res://scripts/origin.gd")
const Units = preload("res://scripts/units.gd")

const ROADS_FILE := "res://map_data/roads.bin"
const RUNS_FILE := "res://map_data/road_runs.bin"
const BUILD_DISTANCE := 3200.0
const FREE_DISTANCE := 4800.0
const MINOR_ROAD_DISTANCE := 1800.0   # small roads are drawn only this far
const WIDTHS := [11.0, 9.0, 8.0, 7.0, 6.0, 6.0, 4.0, 3.5]
const ASPHALT := Color(0.23, 0.23, 0.25)
const GRAVEL := Color(0.55, 0.48, 0.37)
const LINE := Color(0.92, 0.78, 0.22)
const WALLS := [
	Color(0.86, 0.83, 0.76), Color(0.93, 0.92, 0.88), Color(0.70, 0.74, 0.78), Color(0.78, 0.68, 0.55),
	Color(0.62, 0.48, 0.38), Color(0.82, 0.80, 0.70), Color(0.66, 0.70, 0.64), Color(0.90, 0.86, 0.80),
]
const ROOFS := [
	Color(0.30, 0.30, 0.32), Color(0.42, 0.28, 0.22), Color(0.25, 0.32, 0.27), Color(0.36, 0.36, 0.40),
]
const BIG_KINDS := ["warehouse", "industrial", "commercial", "retail", "barn"]
const BRICK_KINDS := ["school", "church", "apartments", "hotel", "civic", "public", "university", "college"]
const CONCRETE_KINDS := ["warehouse", "industrial", "commercial", "retail", "hospital", "office", "supermarket"]
const HP_PER_M3 := {"wood": 2.0, "brick": 4.0, "concrete": 6.0}
const MAX_HP := 150000.0
const RUBBLE := Color(0.42, 0.39, 0.35)

var _samples := PackedFloat32Array()
var _runs: Dictionary = {}        # Vector2i square -> Array of [first sample, count, code]
var _buildings: Dictionary = {}   # Vector2i square -> Array of building entries from world.json
var _squares: Array = []          # every square with something in it
var _built: Dictionary = {}       # Vector2i square -> Array of nodes
var _check := 0.0
var _road_look: StandardMaterial3D
var _house_look: StandardMaterial3D
var _hp: Dictionary = {}          # Vector3i(square x, square z, index) -> HP left, once hit
var _fallen: Dictionary = {}      # Vector3i -> true for buildings brought down
var _dirty: Dictionary = {}       # squares to build again, with their rubble


func setup(world: Dictionary) -> void:
	if FileAccess.file_exists(ROADS_FILE):
		_samples = FileAccess.get_file_as_bytes(ROADS_FILE).to_float32_array()
	if FileAccess.file_exists(RUNS_FILE):
		var table := FileAccess.get_file_as_bytes(RUNS_FILE).to_int32_array()
		for index in range(0, table.size() - 4, 5):
			var square := Vector2i(table[index], table[index + 1])
			if not _runs.has(square):
				_runs[square] = []
			var list: Array = _runs[square]
			list.append([table[index + 2], table[index + 3], table[index + 4]])
	var towns: Dictionary = world.get("towns", {})
	for item in towns.get("buildings", []):
		var entry: Array = item
		var square := Vector2i(int(entry[0]), int(entry[1]))
		if not _buildings.has(square):
			_buildings[square] = []
		var list: Array = _buildings[square]
		list.append(entry)
	var seen: Dictionary = {}
	for key in _runs:
		seen[key] = true
	for key in _buildings:
		seen[key] = true
	_squares = seen.keys()

	_road_look = StandardMaterial3D.new()
	_road_look.vertex_color_use_as_albedo = true
	_road_look.roughness = 0.95
	_road_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	_house_look = StandardMaterial3D.new()
	_house_look.vertex_color_use_as_albedo = true
	_house_look.roughness = 0.9
	_house_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_bridges(towns.get("bridges", []))


func _process(delta: float) -> void:
	_check -= delta
	for key in _dirty:
		var square: Vector2i = key
		if _built.has(square):
			_free_square(square)
			_build_square(square)
	_dirty.clear()
	var camera := get_viewport().get_camera_3d()
	if camera == null or _squares.is_empty():
		return
	var eye := Origin.to_map(camera.global_position)
	var here := Vector2(eye.x, eye.z)
	var nearest_missing := Vector2i.ZERO
	var nearest := INF
	for key in _squares:
		var square: Vector2i = key
		if _built.has(square):
			continue
		var distance := ((Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL).distance_to(here)
		if distance < BUILD_DISTANCE + MapInfo.CELL * 0.5 and distance < nearest:
			nearest = distance
			nearest_missing = square
	if nearest < INF:
		_build_square(nearest_missing)
	if _check <= 0.0:
		_check = 1.0
		var drop: Array = []
		for key in _built:
			var square: Vector2i = key
			if ((Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL).distance_to(here) > FREE_DISTANCE:
				drop.append(square)
		for key in drop:
			_free_square(key)


func _free_square(square: Vector2i) -> void:
	for item in _built[square]:
		var node: Node = item
		node.queue_free()
	_built.erase(square)


func _build_square(square: Vector2i) -> void:
	var nodes: Array = []
	var middle := Vector3((square.x + 0.5) * MapInfo.CELL, 0.0, (square.y + 0.5) * MapInfo.CELL)
	if _runs.has(square):
		var major := SurfaceTool.new()
		var minor := SurfaceTool.new()
		major.begin(Mesh.PRIMITIVE_TRIANGLES)
		minor.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any_major := false
		var any_minor := false
		for item in _runs[square]:
			var run: Array = item
			var code: int = run[2]
			var kind := code % 8
			if kind <= 3:
				any_major = _road_ribbon(major, run, kind, code >= 8) or any_major
			else:
				any_minor = _road_ribbon(minor, run, kind, code >= 8) or any_minor
		if any_major:
			nodes.append(_add_mesh(major, middle, MapInfo.CELL * 0.5 + BUILD_DISTANCE, _road_look))
		if any_minor:
			nodes.append(_add_mesh(minor, middle, MINOR_ROAD_DISTANCE, _road_look))
	if _buildings.has(square):
		var walls := SurfaceTool.new()
		walls.begin(Mesh.PRIMITIVE_TRIANGLES)
		var body := StaticBody3D.new()
		body.physics_material_override = Units.world_surface()
		body.name = "Buildings_%d_%d" % [square.x, square.y]
		body.collision_layer = Units.LAYER_WORLD
		body.collision_mask = 0
		body.position = middle
		body.set_meta("structure", self)
		var drawn := 0
		var list: Array = _buildings[square]
		for index in list.size():
			var entry: Array = list[index]
			var key := Vector3i(square.x, square.y, index)
			if _fallen.has(key):
				drawn += _rubble(walls, entry)
			else:
				drawn += _building(walls, body, entry, key)
		if drawn > 0:
			nodes.append(_add_mesh(walls, middle, BUILD_DISTANCE + MapInfo.CELL * 0.5, _house_look))
		if body.get_child_count() > 0:
			add_child(body)
			nodes.append(body)
		else:
			body.free()
	_built[square] = nodes


func _add_mesh(surface: SurfaceTool, middle: Vector3, distance: float, look: Material) -> MeshInstance3D:
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, look)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = middle
	instance.visibility_range_end = distance
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## One stretch of road as a flat ribbon through its samples. Bigger roads sit
## a few millimetres higher, so they show on top where roads cross.
func _road_ribbon(surface: SurfaceTool, run: Array, kind: int, unpaved: bool) -> bool:
	var first: int = run[0]
	var count: int = run[1]
	if count < 2 or (first + count) * 3 > _samples.size():
		return false
	var half: float = WIDTHS[kind] * 0.5
	var lift := (7 - kind) * 0.012
	var color := GRAVEL if unpaved else ASPHALT
	var points: Array = []
	for index in count:
		var at := (first + index) * 3
		points.append(Vector3(_samples[at], _samples[at + 1] + lift, _samples[at + 2]))
	var lefts: Array = []
	var rights: Array = []
	for index in count:
		var before: Vector3 = points[maxi(index - 1, 0)]
		var after: Vector3 = points[mini(index + 1, count - 1)]
		var along := Vector2(after.x - before.x, after.z - before.z)
		if along.length() < 0.001:
			along = Vector2(1.0, 0.0)
		along = along.normalized()
		var side := Vector3(-along.y, 0.0, along.x) * half
		var middle: Vector3 = points[index]
		lefts.append(middle - side)
		rights.append(middle + side)
	surface.set_color(color)
	for index in count - 1:
		_quad(surface, lefts[index], rights[index], rights[index + 1], lefts[index + 1])
	# A dashed yellow centre line on paved highways.
	if kind <= 1 and not unpaved:
		surface.set_color(LINE)
		for index in range(0, count - 1, 2):
			var a: Vector3 = points[index] + Vector3(0.0, 0.03, 0.0)
			var b: Vector3 = points[index + 1] + Vector3(0.0, 0.03, 0.0)
			var flat := Vector2(b.x - a.x, b.z - a.z)
			if flat.length() < 0.01:
				continue
			flat = flat.normalized() * 0.12
			var side := Vector3(-flat.y, 0.0, flat.x)
			_quad(surface, a - side, a + side, b + side, b - side)
		surface.set_color(color)
	return true


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for corner in [a, b, c, a, c, d]:
		surface.add_vertex(corner)


## One building: its outline raised from `base` to `top`, with a flat roof.
## Inside the wall it is solid. Returns 1 if it drew anything, else 0.
func _building(surface: SurfaceTool, body: StaticBody3D, entry: Array, key: Vector3i) -> int:
	var outline := PackedVector2Array()
	for item in entry[2]:
		var corner: Array = item
		outline.append(Vector2(float(corner[0]), float(corner[1])))
	if outline.size() < 3:
		return 0
	var base := float(entry[3])
	var top := float(entry[4])
	var shade := int(entry[5])
	var kind := str(entry[7]) if entry.size() > 7 else "yes"
	var wall_color: Color = WALLS[shade % WALLS.size()]
	if BIG_KINDS.has(kind):
		wall_color = Color(0.62, 0.64, 0.66)
	elif kind == "school" or kind == "church":
		wall_color = Color(0.62, 0.32, 0.26)
	var roof_color: Color = ROOFS[shade % ROOFS.size()]
	surface.set_color(wall_color)
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		_quad(surface, Vector3(a.x, base, a.y), Vector3(b.x, base, b.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y))
	surface.set_color(roof_color)
	var triangles := Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		# An outline that crosses itself: fan out from the first corner.
		for index in range(1, outline.size() - 1):
			triangles.append_array(PackedInt32Array([0, index, index + 1]))
	for index in triangles:
		var corner := outline[index]
		surface.add_vertex(Vector3(corner.x, top, corner.y))
	if int(entry[6]) == 0:
		return 1
	for piece in Geometry2D.decompose_polygon_in_convex(outline):
		var part: PackedVector2Array = piece
		if part.size() < 3:
			continue
		var points := PackedVector3Array()
		for corner in part:
			points.append(Vector3(corner.x, base, corner.y))
			points.append(Vector3(corner.x, top, corner.y))
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.set_meta("piece", key)
		body.add_child(collider)
	return 1


## What is left of a building brought down: a low heap on its outline.
func _rubble(surface: SurfaceTool, entry: Array) -> int:
	var outline := PackedVector2Array()
	for item in entry[2]:
		var corner: Array = item
		outline.append(Vector2(float(corner[0]), float(corner[1])))
	if outline.size() < 3:
		return 0
	var base := float(entry[3]) + 0.6
	var top := base + clampf((float(entry[4]) - base) * 0.15, 0.4, 2.5)
	var middle := Vector2.ZERO
	for corner in outline:
		middle += corner
	middle /= outline.size()
	surface.set_color(RUBBLE)
	# Sloping sides up to a smaller top, so it reads as a heap.
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		var a_top := middle.lerp(a, 0.6)
		var b_top := middle.lerp(b, 0.6)
		_quad(surface, Vector3(a.x, base - 0.6, a.y), Vector3(b.x, base - 0.6, b.y),
				Vector3(b_top.x, top, b_top.y), Vector3(a_top.x, top, a_top.y))
		for corner in [middle, b_top, a_top]:
			var spot: Vector2 = corner
			surface.add_vertex(Vector3(spot.x, top, spot.y))
	return 1


# --- Damage ------------------------------------------------------------------

## How much health a building starts with: the space it encloses, by what it
## is built of.
func max_health(entry: Array) -> float:
	var outline: Array = entry[2]
	var area := 0.0
	for index in outline.size():
		var a: Array = outline[index]
		var b: Array = outline[(index + 1) % outline.size()]
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	var volume := absf(area) * 0.5 * maxf(float(entry[4]) - float(entry[3]) - 0.6, 1.0)
	return minf(volume * float(HP_PER_M3[material_of(entry)]), MAX_HP)


func material_of(entry: Array) -> String:
	var kind := str(entry[7]) if entry.size() > 7 else "yes"
	if BRICK_KINDS.has(kind):
		return "brick"
	if CONCRETE_KINDS.has(kind):
		return "concrete"
	return "wood"


## The building a ray hit, or null if it was not one of these.
func _piece(collider: Object, shape: int) -> Variant:
	var body := collider as StaticBody3D
	if body == null or shape < 0 or not body.has_meta("structure") or body.get_meta("structure") != self:
		return null
	var owner_id := body.shape_find_owner(shape)
	var node := body.shape_owner_get_owner(owner_id) as Node
	if node == null or not node.has_meta("piece"):
		return null
	return node.get_meta("piece")


func _entry(key: Vector3i) -> Array:
	var list: Array = _buildings.get(Vector2i(key.x, key.y), [])
	return list[key.z] if key.z < list.size() else []


func _health(key: Vector3i) -> float:
	if _fallen.has(key):
		return 0.0
	if _hp.has(key):
		return _hp[key]
	var entry := _entry(key)
	return max_health(entry) if not entry.is_empty() else 0.0


## Health left in what a ray hit, or -1 if it is not a building of the towns.
func piece_health(collider: Object, shape: int) -> float:
	var key: Variant = _piece(collider, shape)
	if key == null:
		return -1.0
	return _health(key)


## A name for what a ray hit, so a shell does not hit the same thing twice.
func piece_id(collider: Object, shape: int) -> String:
	var key: Variant = _piece(collider, shape)
	return "" if key == null else "town %s" % str(key)


## Takes health from the building a ray hit. Returns where it stood (in the
## world) if that brought it down, else an empty array.
func damage_piece(collider: Object, shape: int, amount: float) -> Array:
	var key: Variant = _piece(collider, shape)
	if key == null:
		return []
	return _damage(key, amount)


func _damage(key: Vector3i, amount: float) -> Array:
	if _fallen.has(key) or amount <= 0.0:
		return []
	var left := _health(key) - amount
	if left > 0.0:
		_hp[key] = left
		return []
	_fallen[key] = true
	_hp.erase(key)
	var square := Vector2i(key.x, key.y)
	_dirty[square] = true
	# Take its walls out of the way at once.
	for item in _built.get(square, []):
		var node: Node = item
		if node is StaticBody3D:
			for child in node.get_children():
				if child.has_meta("piece") and child.get_meta("piece") == key:
					(child as CollisionShape3D).disabled = true
	var entry := _entry(key)
	var middle := _middle(square, entry)
	return [to_global(Vector3(middle.x, (float(entry[3]) + float(entry[4])) * 0.5, middle.y))]


## The middle of a building in map metres (x, z).
func _middle(square: Vector2i, entry: Array) -> Vector2:
	var sum := Vector2.ZERO
	var outline: Array = entry[2]
	for item in outline:
		var corner: Array = item
		sum += Vector2(float(corner[0]), float(corner[1]))
	sum /= maxf(outline.size(), 1.0)
	return sum + (Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL


## A blast at `centre` (in the world): every building within `radius` takes
## `peak` x (1 - distance / radius), the distance measured to its nearest
## side, roughly. Returns where each one it brought down stood.
func blast(centre: Vector3, radius: float, peak: float) -> Array:
	var fell: Array = []
	var at := to_local(centre)
	var low := Vector2i(floori((at.x - radius - 200.0) / MapInfo.CELL), floori((at.z - radius - 200.0) / MapInfo.CELL))
	var high := Vector2i(floori((at.x + radius + 200.0) / MapInfo.CELL), floori((at.z + radius + 200.0) / MapInfo.CELL))
	for sx in range(low.x, high.x + 1):
		for sz in range(low.y, high.y + 1):
			var square := Vector2i(sx, sz)
			var list: Array = _buildings.get(square, [])
			var square_middle := (Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL
			for index in list.size():
				var entry: Array = list[index]
				var key := Vector3i(sx, sz, index)
				if _fallen.has(key):
					continue
				var middle := _middle(square, entry)
				var flat := Vector2(at.x, at.z).distance_to(middle)
				if flat > radius + 200.0:
					continue
				var reach := 0.0
				for item in entry[2]:
					var corner: Array = item
					reach = maxf(reach, (Vector2(float(corner[0]), float(corner[1])) + square_middle).distance_to(middle))
				var below := maxf(float(entry[3]) - at.y, 0.0) + maxf(at.y - float(entry[4]), 0.0)
				var distance := Vector2(maxf(flat - reach, 0.0), below).length()
				if distance >= radius:
					continue
				fell.append_array(_damage(key, peak * (1.0 - distance / radius)))
	return fell


## Puts every building back up, for a new spawn.
func reset_damage() -> void:
	for key in _fallen:
		var spot: Vector3i = key
		_dirty[Vector2i(spot.x, spot.y)] = true
	_fallen.clear()
	_hp.clear()


## Bridges: a solid concrete deck along each span, on piers down into the water.
func _build_bridges(spans: Array) -> void:
	if spans.is_empty():
		return
	var body := StaticBody3D.new()
	body.physics_material_override = Units.world_surface()
	body.name = "Bridges"
	body.collision_layer = Units.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color(0.66, 0.66, 0.64))
	for item in spans:
		var span: Array = item
		var a := Vector3(float(span[0]), float(span[1]), float(span[2]))
		var b := Vector3(float(span[3]), float(span[4]), float(span[5]))
		var width := float(span[6]) + 2.0
		var length := a.distance_to(b)
		if length < 0.1:
			continue
		var along := (b - a) / length
		var side := Vector3(-along.z, 0.0, along.x).normalized()
		var up := side.cross(along).normalized()
		var turn := Basis(side, up, -along)
		var place := Transform3D(turn, (a + b) * 0.5 - up * 0.45)
		var size := Vector3(width, 0.8, length + 0.5)
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = place
		body.add_child(collider)
		_box(surface, place, size)
		# A pier under the start of each span.
		var pier := Transform3D(Basis.IDENTITY, Vector3(a.x, (a.y + MapInfo.LAKE_Y) * 0.5 - 6.0, a.z))
		_box(surface, pier, Vector3(1.6, a.y - MapInfo.LAKE_Y + 12.0, 1.6))
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _house_look)
	var drawn := MeshInstance3D.new()
	drawn.mesh = mesh
	body.add_child(drawn)


func _box(surface: SurfaceTool, place: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var c := []
	for corner in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		c.append(place * (corner * h))
	for face in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_quad(surface, c[face[0]], c[face[1]], c[face[2]], c[face[3]])
