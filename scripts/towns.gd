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
const GLASS := Color(0.16, 0.2, 0.25)
const DOOR := Color(0.32, 0.22, 0.16)
const TRIM := Color(0.92, 0.92, 0.9)
const FLOOR_HEIGHT := 3.0          # metres a storey
const WINDOW_EVERY := 3.2          # metres between windows along a wall
const PITCHED_KINDS := ["yes", "house", "residential", "detached", "semidetached_house", "garage", "cabin", "farm", "shed", "hut", "bungalow"]
## The US 93 bridge at Polson, over the Flathead River where it leaves the
## lake: rebuilt big, a cable-stayed bridge that humps POLSON_RISE metres in
## the middle so boats and small planes fit underneath.
const POLSON_A := Vector3(4137.2, -20.6, 17508.3)
const POLSON_B := Vector3(3736.8, -20.5, 17381.6)
const POLSON_RISE := 16.0
const POLSON_WIDTH := 18.0
const POLSON_TOWER := 72.0          # metres the towers stand above the deck

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

	_raise_polson_road()

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
	_windows(surface, outline, base, top, kind, shade)
	surface.set_color(roof_color)
	if outline.size() == 4 and PITCHED_KINDS.has(kind) and top - base < 12.0 and _pitched_roof(surface, outline, top):
		pass
	else:
		_flat_roof(surface, outline, top, roof_color)
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


## Windows in rows, one row a storey, across every wall long enough, and a
## door in the middle of the longest wall. They stand 3 cm proud of the wall.
func _windows(surface: SurfaceTool, outline: PackedVector2Array, base: float, top: float, kind: String, shade: int) -> void:
	var turn := 1.0 if _signed_area(outline) > 0.0 else -1.0
	var storeys := clampi(int((top - base) / FLOOR_HEIGHT), 1, 40)
	var big := BIG_KINDS.has(kind)
	var longest := -1
	var longest_length := 0.0
	for index in outline.size():
		var length := outline[index].distance_to(outline[(index + 1) % outline.size()])
		if length > longest_length:
			longest_length = length
			longest = index
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		var along := b - a
		var length := along.length()
		if length < 2.5:
			continue
		var direction := along / length
		var out2 := Vector2(direction.y, -direction.x) * turn * 0.03
		var out := Vector3(out2.x, 0.0, out2.y)
		var count := int(length / WINDOW_EVERY)
		var wide := 1.1 if not big else 2.2
		var tall := 1.3 if not big else 1.0
		for storey in storeys:
			var sill := base + storey * FLOOR_HEIGHT + (0.9 if not big else 1.6)
			if sill + tall > top - 0.3:
				break
			for slot in count:
				var middle := a + direction * ((slot + 0.5) * length / count)
				if index == longest and storey == 0 and slot == count / 2:
					continue   # the door goes here
				if big and (slot + shade) % 3 == 2:
					continue   # warehouses have fewer windows
				var left := middle - direction * wide * 0.5
				var right := middle + direction * wide * 0.5
				surface.set_color(GLASS)
				_quad(surface, Vector3(left.x, sill, left.y) + out, Vector3(right.x, sill, right.y) + out,
						Vector3(right.x, sill + tall, right.y) + out, Vector3(left.x, sill + tall, left.y) + out)
	if longest >= 0 and longest_length >= 2.5:
		var a := outline[longest]
		var b := outline[(longest + 1) % outline.size()]
		var direction := (b - a).normalized()
		var out2 := Vector2(direction.y, -direction.x) * turn * 0.04
		var out := Vector3(out2.x, 0.0, out2.y)
		var count := maxi(int(longest_length / WINDOW_EVERY), 1)
		var middle := a + direction * ((count / 2 + 0.5) * longest_length / count)
		var wide := 1.0 if not big else 4.0
		var tall := minf(2.1 if not big else 3.6, top - base - 0.2)
		var left := middle - direction * wide * 0.5
		var right := middle + direction * wide * 0.5
		surface.set_color(DOOR if not big else Color(0.45, 0.47, 0.5))
		_quad(surface, Vector3(left.x, base, left.y) + out, Vector3(right.x, base, right.y) + out,
				Vector3(right.x, base + tall, right.y) + out, Vector3(left.x, base + tall, left.y) + out)


static func _signed_area(outline: PackedVector2Array) -> float:
	var total := 0.0
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## A gabled roof over a four-cornered house: the ridge along its longer
## side, rising a third of its width, overhanging 30 cm, with gable ends.
## Returns false if the outline is too far from a rectangle.
func _pitched_roof(surface: SurfaceTool, outline: PackedVector2Array, top: float) -> bool:
	var a := outline[0]
	var b := outline[1]
	var c := outline[2]
	var d := outline[3]
	if absf((b - a).dot(c - b)) > 0.2 * (b - a).length() * (c - b).length():
		return false
	# Long sides a-b and d-c, or b-c and a-d.
	if (b - a).length() < (c - b).length():
		var keep := a
		a = b
		b = c
		c = d
		d = keep
	var width := (d - a).length()
	var rise := width / 3.0
	var across := (d - a).normalized() * 0.3
	var along := (b - a).normalized() * 0.3
	var a2 := a - across - along
	var b2 := b - across + along
	var c2 := c + across + along
	var d2 := d + across - along
	var ridge_a := (a + d) * 0.5 - along
	var ridge_b := (b + c) * 0.5 + along
	var eave := top - 0.15
	_quad(surface, Vector3(a2.x, eave, a2.y), Vector3(b2.x, eave, b2.y), Vector3(ridge_b.x, top + rise, ridge_b.y), Vector3(ridge_a.x, top + rise, ridge_a.y))
	_quad(surface, Vector3(c2.x, eave, c2.y), Vector3(d2.x, eave, d2.y), Vector3(ridge_a.x, top + rise, ridge_a.y), Vector3(ridge_b.x, top + rise, ridge_b.y))
	# Undersides, so the roof isn't see-through from below.
	_quad(surface, Vector3(ridge_a.x, top + rise - 0.1, ridge_a.y), Vector3(ridge_b.x, top + rise - 0.1, ridge_b.y), Vector3(b2.x, eave - 0.1, b2.y), Vector3(a2.x, eave - 0.1, a2.y))
	_quad(surface, Vector3(ridge_b.x, top + rise - 0.1, ridge_b.y), Vector3(ridge_a.x, top + rise - 0.1, ridge_a.y), Vector3(d2.x, eave - 0.1, d2.y), Vector3(c2.x, eave - 0.1, c2.y))
	# The gable ends, in the wall colour's trim.
	surface.set_color(TRIM)
	var mid_a := (a + d) * 0.5
	var mid_b := (b + c) * 0.5
	for triangle in [[a, d, mid_a], [c, b, mid_b]]:
		var p: Vector2 = triangle[0]
		var q: Vector2 = triangle[1]
		var r: Vector2 = triangle[2]
		for corner in [Vector3(p.x, top, p.y), Vector3(q.x, top, q.y), Vector3(r.x, top + rise, r.y)]:
			surface.add_vertex(corner)
		for corner in [Vector3(q.x, top, q.y), Vector3(p.x, top, p.y), Vector3(r.x, top + rise, r.y)]:
			surface.add_vertex(corner)
	return true


## A flat roof with a low parapet round its edge.
func _flat_roof(surface: SurfaceTool, outline: PackedVector2Array, top: float, roof_color: Color) -> void:
	surface.set_color(roof_color)
	var triangles := Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		# An outline that crosses itself: fan out from the first corner.
		for index in range(1, outline.size() - 1):
			triangles.append_array(PackedInt32Array([0, index, index + 1]))
	for index in triangles:
		var corner := outline[index]
		surface.add_vertex(Vector3(corner.x, top, corner.y))
	surface.set_color(roof_color.lightened(0.15))
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		_quad(surface, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, top + 0.5, b.y), Vector3(a.x, top + 0.5, a.y))
		_quad(surface, Vector3(b.x, top, b.y), Vector3(a.x, top, a.y), Vector3(a.x, top + 0.5, a.y), Vector3(b.x, top + 0.5, b.y))


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


## Where along the Polson bridge a map point is: [share of the way from A
## to B, metres off its middle line].
static func _polson_place(x: float, z: float) -> Vector2:
	var a := Vector2(POLSON_A.x, POLSON_A.z)
	var b := Vector2(POLSON_B.x, POLSON_B.z)
	var along := b - a
	var point := Vector2(x, z) - a
	var t := point.dot(along) / along.length_squared()
	var side := absf(point.cross(along.normalized()))
	return Vector2(t, side)


## The top of the Polson bridge's deck at a share `t` of the way across:
## a smooth hump, highest in the middle.
static func polson_deck(t: float) -> float:
	var ends := lerpf(POLSON_A.y, POLSON_B.y, t)
	return ends + POLSON_RISE * (1.0 - cos(TAU * clampf(t, 0.0, 1.0))) * 0.5


## The road over the bridge follows its deck. Road samples are kept
## relative to the middle of their 1 km square.
func _raise_polson_road() -> void:
	for key in _runs:
		var square: Vector2i = key
		var middle := (Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL
		for item in _runs[square]:
			var run: Array = item
			for index in int(run[1]):
				var at := (int(run[0]) + index) * 3
				if at + 2 >= _samples.size():
					break
				var place := _polson_place(_samples[at] + middle.x, _samples[at + 2] + middle.y)
				if place.x > 0.0 and place.x < 1.0 and place.y < POLSON_WIDTH * 0.5:
					_samples[at + 1] = polson_deck(place.x) + 0.02


## Every paved highway as lines of map points (motorways, trunk and primary
## roads), for traffic and car races to drive along. Runs are joined where
## one ends on the first point of the next.
func highway_lines() -> Array:
	var lines: Array = []
	for key in _runs:
		var square: Vector2i = key
		var middle := (Vector2(square) + Vector2(0.5, 0.5)) * MapInfo.CELL
		for item in _runs[square]:
			var run: Array = item
			var code: int = run[2]
			if code % 8 > 2 or code >= 8:
				continue
			var line := PackedVector3Array()
			for index in int(run[1]):
				var at := (int(run[0]) + index) * 3
				if at + 2 >= _samples.size():
					break
				line.append(Vector3(_samples[at] + middle.x, _samples[at + 1], _samples[at + 2] + middle.y))
			if line.size() >= 2:
				lines.append(line)
	return lines


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
		var middle_place := _polson_place((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		if middle_place.x > -0.02 and middle_place.x < 1.02 and middle_place.y < 6.0 and width > 8.0:
			continue   # the old Polson bridge: built new below
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
	_build_polson_bridge(body, surface)
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _house_look)
	var drawn := MeshInstance3D.new()
	drawn.mesh = mesh
	body.add_child(drawn)


## The big Polson bridge: a humped deck with concrete barriers, piers into
## the river, two H-shaped towers and fans of stay cables, and lights.
func _build_polson_bridge(body: StaticBody3D, surface: SurfaceTool) -> void:
	var a := POLSON_A
	var b := POLSON_B
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var span := flat.length()
	var along := flat / span
	var side := Vector3(-along.z, 0.0, along.x)
	var pieces := 36
	var concrete := Color(0.70, 0.70, 0.68)
	var steel := Color(0.85, 0.32, 0.18)
	surface.set_color(concrete)
	for index in pieces:
		var t0 := float(index) / pieces
		var t1 := float(index + 1) / pieces
		var p0 := Vector3(a.x, 0.0, a.z) + along * span * t0
		var p1 := Vector3(a.x, 0.0, a.z) + along * span * t1
		p0.y = polson_deck(t0)
		p1.y = polson_deck(t1)
		var run := p1 - p0
		var forward := run.normalized()
		var up := side.cross(forward).normalized()
		if up.y < 0.0:
			up = -up
		var turn := Basis(side, up, -forward)
		var middle := (p0 + p1) * 0.5
		# The deck, a little longer than each piece so they overlap.
		var deck := Transform3D(turn, middle - up * 0.6)
		var deck_size := Vector3(POLSON_WIDTH, 1.2, run.length() + 0.6)
		_solid_box(body, surface, deck, deck_size)
		# Concrete barriers along both edges.
		for edge in [-1.0, 1.0]:
			var barrier := Transform3D(turn, middle + side * float(edge) * (POLSON_WIDTH * 0.5 - 0.3) + up * 0.55)
			_solid_box(body, surface, barrier, Vector3(0.6, 1.1, run.length() + 0.6))
		# Piers down into the river, every few pieces.
		if index % 4 == 2:
			for edge in [-1.0, 1.0]:
				var foot := middle + side * float(edge) * POLSON_WIDTH * 0.32
				var drop := foot.y - (MapInfo.LAKE_Y - 12.0)
				_solid_box(body, surface, Transform3D(Basis.IDENTITY, Vector3(foot.x, foot.y - 1.2 - drop * 0.5, foot.z)),
						Vector3(2.6, drop, 2.6))
	# Two towers, at a third and two thirds of the way, straddling the deck.
	surface.set_color(steel)
	for share in [1.0 / 3.0, 2.0 / 3.0]:
		var t: float = share
		var base := Vector3(a.x, 0.0, a.z) + along * span * t
		var deck_top := polson_deck(t)
		var bottom := MapInfo.LAKE_Y - 12.0
		var top := deck_top + POLSON_TOWER
		for edge in [-1.0, 1.0]:
			var leg := base + side * float(edge) * (POLSON_WIDTH * 0.5 + 2.0)
			_solid_box(body, surface, Transform3D(Basis.IDENTITY, Vector3(leg.x, (bottom + top) * 0.5, leg.z)),
					Vector3(3.2, top - bottom, 4.0))
		# Cross beams under the deck, high up and at the top.
		for height in [deck_top - 2.0, deck_top + POLSON_TOWER * 0.55, top - 2.0]:
			var beam_turn := Basis(side, Vector3.UP, side.cross(Vector3.UP))
			_solid_box(body, surface, Transform3D(beam_turn, Vector3(base.x, float(height), base.z)),
					Vector3(POLSON_WIDTH + 8.0, 2.4, 2.4))
	# Stay cables: fans from each tower top down to both edges of the deck.
	surface.set_color(Color(0.92, 0.92, 0.9))
	for share in [1.0 / 3.0, 2.0 / 3.0]:
		var t: float = share
		var base := Vector3(a.x, 0.0, a.z) + along * span * t
		var top := polson_deck(t) + POLSON_TOWER - 4.0
		for edge in [-1.0, 1.0]:
			var anchor := base + side * float(edge) * (POLSON_WIDTH * 0.5 + 2.0)
			anchor.y = top
			for cable in range(1, 9):
				for direction in [-1.0, 1.0]:
					var reach_t: float = t + float(direction) * float(cable) * 0.038
					if reach_t < 0.02 or reach_t > 0.98:
						continue
					var deck_point := Vector3(a.x, 0.0, a.z) + along * span * reach_t + side * float(edge) * (POLSON_WIDTH * 0.5 - 0.2)
					deck_point.y = polson_deck(reach_t) + 1.0
					var line := deck_point - anchor
					var cable_turn := Basis.looking_at(line.normalized(), Vector3.UP if absf(line.normalized().y) < 0.99 else Vector3.FORWARD)
					_box(surface, Transform3D(cable_turn, (anchor + deck_point) * 0.5), Vector3(0.18, 0.18, line.length()))
	surface.set_color(concrete)
	# Lamps along the deck, lit at night.
	var lamps := Node3D.new()
	lamps.add_to_group("night_lights")
	lamps.visible = false
	add_child(lamps)
	for index in range(1, 12):
		var t := float(index) / 12.0
		for edge in [-1.0, 1.0]:
			var post := Vector3(a.x, 0.0, a.z) + along * span * t + side * float(edge) * (POLSON_WIDTH * 0.5 - 0.3)
			post.y = polson_deck(t)
			_box(surface, Transform3D(Basis.IDENTITY, post + Vector3(0.0, 4.0, 0.0)), Vector3(0.25, 8.0, 0.25))
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.85, 0.6)
			lamp.light_energy = 1.4
			lamp.omni_range = 22.0
			lamp.position = post + Vector3(0.0, 8.2, 0.0)
			lamp.distance_fade_enabled = true
			lamp.distance_fade_begin = 1500.0
			lamp.distance_fade_length = 400.0
			lamps.add_child(lamp)


func _solid_box(body: StaticBody3D, surface: SurfaceTool, place: Transform3D, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = place
	body.add_child(collider)
	_box(surface, place, size)


func _box(surface: SurfaceTool, place: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var c := []
	for corner in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		c.append(place * (corner * h))
	for face in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_quad(surface, c[face[0]], c[face[1]], c[face[2]], c[face[3]])
