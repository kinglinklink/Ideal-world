extends Node3D
## Wizard towers: huge round stone towers with pointed roofs, standing at
## random places on dry land each time the game starts. They are wider than
## the Cromwell château and several times taller.
##
## Each tower is built of stone blocks: SIDES round, RINGS high. Every block
## has health (HP_PER_M3 for the stone it holds) and bullets, shells and
## blasts wear it away (combat.gd asks here). A destroyed block is gone. When
## a ring has lost half its blocks it can no longer carry what is above it:
## that ring and everything over it break loose, a body per ring and one for
## the roof, and come down under gravity, tipping toward the side that was
## shot away. Fallen pieces settle and turn to fixed rubble after a while.
## Everything is put back when the build goes back to Build mode.
##
## Positions here are map positions: this node is a child of terrain.gd.

const MapInfo = preload("res://scripts/map_info.gd")
const Origin = preload("res://scripts/origin.gd")
const Units = preload("res://scripts/units.gd")

const COUNT := 6
const SIDES := 24
const RINGS := 18
const WALL := 10.0                  # metres thick
const RADIUS_RANGE := Vector2(95.0, 120.0)
const HEIGHT_RANGE := Vector2(430.0, 580.0)   # of the shaft, above the highest ground under it
const MERLON := 7.0                 # height of the battlements
const SPACING := 6000.0             # metres between towers
const CLEAR_OF_TOWNS := 3000.0
const CLEAR_OF_START := 4000.0
const HP_PER_M3 := 0.6
const STONE_DENSITY := 2400.0
const MAX_DEBRIS_MASS := 50000000.0   # kg; heavier pieces are held to this, for the physics' sake
const SETTLE_TIME := 3.0            # s of lying still before a fallen piece turns to fixed rubble
const DEBRIS_LIFE := 90.0           # s after which a fallen piece is fixed wherever it is
const STONE := Color(0.62, 0.62, 0.66)
const ROOF := Color(0.23, 0.17, 0.46)
const GOLD := Color(0.95, 0.76, 0.25)
const WINDOW := Color(1.0, 0.85, 0.45)

var map_points: Array = []    # [Vector2 map x and z, label] for the mini map
var terrain: Node3D = null    # terrain.gd

var _towers: Array = []       # see _make_tower
var _debris: Array = []       # {"body", "still", "age"}
var _moving: Array = []       # the ones of those not yet settled
var _stone_look: StandardMaterial3D
var _glow_look: StandardMaterial3D
var _last_offset := Vector3.ZERO
var _damaged := false


func setup(the_terrain: Node3D, world: Dictionary) -> void:
	terrain = the_terrain
	_last_offset = Origin.offset
	_stone_look = StandardMaterial3D.new()
	_stone_look.vertex_color_use_as_albedo = true
	_stone_look.roughness = 0.95
	_stone_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_look = StandardMaterial3D.new()
	_glow_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_look.albedo_color = WINDOW
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for spot in _choose_spots(world, rng):
		var place: Array = spot
		var tower := _make_tower(place[0], place[1], place[2], place[3], rng)
		_towers.append(tower)
		_build(_towers.size() - 1)
		map_points.append([Vector2(float(place[0]), float(place[1])), "Wizard tower"])


## Clearings for the forest: [Vector2 map x and z, radius] per tower.
func clearings() -> Array:
	var list: Array = []
	for item in _towers:
		var tower: Dictionary = item
		var base: Vector3 = tower["base"]
		list.append([Vector2(base.x, base.z), float(tower["radius"]) + 15.0])
	return list


# --- Where they stand ----------------------------------------------------------

## Random spots on dry land inside the wall, clear of the towns, airports
## and the start, and well apart: [x, z, radius, lowest ground] each.
func _choose_spots(world: Dictionary, rng: RandomNumberGenerator) -> Array:
	var bounds: Array = world.get("bounds", [-10000.0, -10000.0, 10000.0, 10000.0])
	var towns: Array = []
	for item in world.get("town_names", []):
		var town: Dictionary = item
		var at: Array = town["at"]
		towns.append(Vector2(float(at[0]), float(at[1])))
	var runways: Array = []
	for item in world.get("runways", []):
		var runway: Dictionary = item
		var at: Array = runway["centre"]
		runways.append([Vector2(float(at[0]), float(at[1])), float(runway["length"]) * 0.5 + 900.0])
	var chosen: Array = []
	for _attempt in 6000:
		if chosen.size() >= COUNT:
			break
		var x := rng.randf_range(float(bounds[0]) + 2500.0, float(bounds[2]) - 2500.0)
		var z := rng.randf_range(float(bounds[1]) + 2500.0, float(bounds[3]) - 2500.0)
		var here := Vector2(x, z)
		if here.length() < CLEAR_OF_START:
			continue
		var crowded := false
		for town in towns:
			if here.distance_to(town) < CLEAR_OF_TOWNS:
				crowded = true
		for runway in runways:
			if here.distance_to(runway[0]) < float(runway[1]):
				crowded = true
		for other in chosen:
			if here.distance_to(Vector2(float(other[0]), float(other[1]))) < SPACING:
				crowded = true
		if crowded:
			continue
		var radius := rng.randf_range(RADIUS_RANGE.x, RADIUS_RANGE.y)
		var low := INF
		var high := -INF
		var wet := false
		for index in 17:
			var spot := here
			if index > 0:
				var angle := TAU * index / 16.0
				spot += Vector2(cos(angle), sin(angle)) * (radius + 20.0 if index % 2 == 0 else radius * 0.6)
			if terrain.is_lake(spot.x, spot.y):
				wet = true
				break
			var ground: float = terrain.height_at(spot.x, spot.y)
			low = minf(low, ground)
			high = maxf(high, ground)
		if wet or low < MapInfo.LAKE_Y + 20.0 or high - low > 70.0:
			continue
		chosen.append([x, z, radius, low, high])
	var spots: Array = []
	for item in chosen:
		var spot: Array = item
		spots.append([spot[0], spot[1], spot[2], [spot[3], spot[4]]])
	return spots


func _make_tower(x: float, z: float, radius: float, ground: Array, rng: RandomNumberGenerator) -> Dictionary:
	var bottom := float(ground[0]) - 15.0
	var height := float(ground[1]) - bottom + rng.randf_range(HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	var ring_height := height / RINGS
	var block_volume := (radius * radius - (radius - WALL) * (radius - WALL)) * PI / SIDES * ring_height
	var hp := PackedFloat32Array()
	hp.resize(RINGS * SIDES)
	hp.fill(block_volume * HP_PER_M3)
	return {
		"base": Vector3(x, bottom, z), "radius": radius, "ring_height": ring_height,
		"block_hp": block_volume * HP_PER_M3, "block_mass": block_volume * STONE_DENSITY,
		"hp": hp, "standing": RINGS, "roof_on": true, "seed": rng.randi(),
		"body": null, "mesh": null, "dirty": false,
	}


# --- Building ------------------------------------------------------------------

## (Re)builds a tower's standing part: its body, one collision shape per
## block left, and its mesh.
func _build(index: int) -> void:
	var tower: Dictionary = _towers[index]
	var old_body: Node = tower["body"]
	if old_body != null and is_instance_valid(old_body):
		old_body.queue_free()
	var body := StaticBody3D.new()
	body.physics_material_override = Units.world_surface()
	body.name = "WizardTower%d" % index
	body.collision_layer = Units.LAYER_WORLD
	body.collision_mask = 0
	body.position = tower["base"]
	body.set_meta("structure", self)
	add_child(body)
	tower["body"] = body
	var radius: float = tower["radius"]
	var ring_height: float = tower["ring_height"]
	var standing: int = tower["standing"]
	var hp: PackedFloat32Array = tower["hp"]
	var block_shape := ConvexPolygonShape3D.new()
	block_shape.points = _block_corners(radius, 0, 0.0, ring_height)
	for ring in standing:
		for side in SIDES:
			if hp[ring * SIDES + side] <= 0.0:
				continue
			var collider := CollisionShape3D.new()
			collider.shape = block_shape
			collider.transform = Transform3D(Basis(Vector3.UP, -side * TAU / SIDES), Vector3(0.0, ring * ring_height, 0.0))
			collider.set_meta("piece", Vector3i(index, ring, side))
			body.add_child(collider)
	var top := standing * ring_height
	if bool(tower["roof_on"]) and standing == RINGS:
		var roof := CollisionShape3D.new()
		roof.shape = _roof_shape(radius)
		roof.position = Vector3(0.0, top + MERLON, 0.0)
		body.add_child(roof)
	var stone := _new_surface()
	var glow := _new_surface()
	var seed_value: int = tower["seed"]
	for ring in standing:
		for side in SIDES:
			if hp[ring * SIDES + side] <= 0.0:
				continue
			_add_block(stone, glow, radius, ring, side, ring_height, Vector3.ZERO, seed_value)
	if standing == RINGS:
		_add_battlements(stone, radius, top, hp, seed_value)
		if bool(tower["roof_on"]):
			_add_roof(stone, radius, Vector3(0.0, top + MERLON, 0.0))
	var mesh := MeshInstance3D.new()
	mesh.mesh = _commit(stone, glow)
	body.add_child(mesh)
	tower["mesh"] = mesh
	tower["dirty"] = false


func _new_surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


func _commit(stone: SurfaceTool, glow: SurfaceTool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for pair in [[stone, _stone_look], [glow, _glow_look]]:
		var surface: SurfaceTool = pair[0]
		var arrays := surface.commit_to_arrays()
		if arrays.size() <= Mesh.ARRAY_VERTEX or not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array):
			continue
		if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	return mesh


## The eight corners of a block of the wall, round the tower's axis: side 0
## spans the angles 0 to one step, from `y0` to `y1`.
func _block_corners(radius: float, side: int, y0: float, y1: float) -> PackedVector3Array:
	var inner := radius - WALL
	var a0 := side * TAU / SIDES
	var a1 := (side + 1) * TAU / SIDES
	var points := PackedVector3Array()
	for y in [y0, y1]:
		var level: float = y
		points.append(Vector3(cos(a0) * inner, level, sin(a0) * inner))
		points.append(Vector3(cos(a0) * radius, level, sin(a0) * radius))
		points.append(Vector3(cos(a1) * radius, level, sin(a1) * radius))
		points.append(Vector3(cos(a1) * inner, level, sin(a1) * inner))
	return points


func _quad(surface: SurfaceTool, corners: Array, normals: Array) -> void:
	for index in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normals[index])
		surface.add_vertex(corners[index])


## One block, drawn with rounded light on its outer and inner faces, and now
## and then a lit window. `shift` moves it (for a fallen ring's own body).
func _add_block(stone: SurfaceTool, glow: SurfaceTool, radius: float, ring: int, side: int, ring_height: float,
		shift: Vector3, seed_value: int) -> void:
	var y0 := ring * ring_height
	var c := _block_corners(radius, side, y0, y0 + ring_height)
	for index in c.size():
		c[index] += shift
	var a0 := side * TAU / SIDES
	var a1 := (side + 1) * TAU / SIDES
	var out0 := Vector3(cos(a0), 0.0, sin(a0))
	var out1 := Vector3(cos(a1), 0.0, sin(a1))
	var shade := 0.9 + 0.2 * _hash(seed_value + ring * 131 + side * 7)
	stone.set_color(STONE * shade)
	_quad(stone, [c[1], c[2], c[6], c[5]], [out0, out1, out1, out0])
	_quad(stone, [c[0], c[4], c[7], c[3]], [-out0, -out0, -out1, -out1])
	_quad(stone, [c[0], c[3], c[2], c[1]], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])
	_quad(stone, [c[4], c[5], c[6], c[7]], [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var side0 := Vector3(sin(a0), 0.0, -cos(a0))
	var side1 := Vector3(-sin(a1), 0.0, cos(a1))
	_quad(stone, [c[0], c[1], c[5], c[4]], [side0, side0, side0, side0])
	_quad(stone, [c[3], c[7], c[6], c[2]], [side1, side1, side1, side1])
	# A tall lit window on some blocks, set just proud of the wall.
	if ring >= 2 and ring <= RINGS - 2 and _hash(seed_value * 3 + ring * 17 + side * 29) < 0.14:
		var middle := (a0 + a1) * 0.5
		var out := Vector3(cos(middle), 0.0, sin(middle))
		var along := Vector3(-sin(middle), 0.0, cos(middle))
		var centre := out * (radius + 0.4) + Vector3(0.0, y0 + ring_height * 0.5, 0.0) + shift
		var half_width := radius * TAU / SIDES * 0.12
		var half_height := ring_height * 0.28
		glow.set_normal(out)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var spot: Vector2 = corner
			glow.add_vertex(centre + along * spot.x * half_width + Vector3.UP * spot.y * half_height)


## Battlements round the top of the wall: every other block carries a merlon.
func _add_battlements(stone: SurfaceTool, radius: float, top: float, hp: PackedFloat32Array, seed_value: int) -> void:
	for side in SIDES:
		if side % 2 == 1 or hp[(RINGS - 1) * SIDES + side] <= 0.0:
			continue
		var c := _block_corners(radius, side, top, top + MERLON)
		stone.set_color(STONE * (0.85 + 0.1 * _hash(seed_value + side)))
		var a0 := side * TAU / SIDES
		var a1 := (side + 1) * TAU / SIDES
		var out0 := Vector3(cos(a0), 0.0, sin(a0))
		var out1 := Vector3(cos(a1), 0.0, sin(a1))
		_quad(stone, [c[1], c[2], c[6], c[5]], [out0, out1, out1, out0])
		_quad(stone, [c[0], c[4], c[7], c[3]], [-out0, -out0, -out1, -out1])
		_quad(stone, [c[4], c[5], c[6], c[7]], [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		var side0 := Vector3(sin(a0), 0.0, -cos(a0))
		var side1 := Vector3(-sin(a1), 0.0, cos(a1))
		_quad(stone, [c[0], c[1], c[5], c[4]], [side0, side0, side0, side0])
		_quad(stone, [c[3], c[7], c[6], c[2]], [side1, side1, side1, side1])


func _roof_size(radius: float) -> Vector2:
	return Vector2(radius + 14.0, radius * 2.6)   # base radius, height


## The pointed roof: a tall cone overhanging the wall, with a gold ball on top.
func _add_roof(stone: SurfaceTool, radius: float, base: Vector3) -> void:
	var size := _roof_size(radius)
	var apex := base + Vector3(0.0, size.y, 0.0)
	var slope := size.x / size.y
	stone.set_color(ROOF)
	for side in 32:
		var a0 := side * TAU / 32.0
		var a1 := (side + 1) * TAU / 32.0
		var p0 := base + Vector3(cos(a0), 0.0, sin(a0)) * size.x
		var p1 := base + Vector3(cos(a1), 0.0, sin(a1)) * size.x
		var n0 := Vector3(cos(a0), slope, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), slope, sin(a1)).normalized()
		var n_top := (n0 + n1).normalized()
		_quad(stone, [p0, p1, apex, apex], [n0, n1, n_top, n_top])
		_quad(stone, [p0, base, base, p1], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])
	# The ball.
	stone.set_color(GOLD)
	var ball := 7.0
	var middle := apex + Vector3(0.0, ball * 0.8, 0.0)
	for row in 6:
		for side in 12:
			var corners: Array = []
			var normals: Array = []
			for step in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var turn: Vector2i = step
				var down := PI * float(row + turn.y) / 6.0
				var round_angle := TAU * float(side + turn.x) / 12.0
				var normal := Vector3(sin(down) * cos(round_angle), cos(down), sin(down) * sin(round_angle))
				corners.append(middle + normal * ball)
				normals.append(normal)
			_quad(stone, corners, normals)


func _roof_shape(radius: float) -> ConvexPolygonShape3D:
	var size := _roof_size(radius)
	var points := PackedVector3Array()
	for side in 16:
		var angle := side * TAU / 16.0
		points.append(Vector3(cos(angle) * size.x, 0.0, sin(angle) * size.x))
	points.append(Vector3(0.0, size.y, 0.0))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


# --- Every frame ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	for index in _towers.size():
		var tower: Dictionary = _towers[index]
		if bool(tower["dirty"]):
			_build(index)
	var kept: Array = []
	for item in _debris:
		var piece: Dictionary = item
		var body: RigidBody3D = piece["body"]
		if body.freeze:
			continue
		piece["age"] = float(piece["age"]) + delta
		if body.linear_velocity.length() < 0.4 and body.angular_velocity.length() < 0.05:
			piece["still"] = float(piece["still"]) + delta
		else:
			piece["still"] = 0.0
		if float(piece["still"]) > SETTLE_TIME or float(piece["age"]) > DEBRIS_LIFE:
			body.freeze = true   # rubble from now on
			continue
		kept.append(piece)
	# Pieces still moving, for the ground to stay solid under them.
	_moving = kept


## Where each falling piece is and how fast it goes: [position, velocity]
## pairs in the world, for terrain.gd to keep the ground solid under them.
func debris_motions() -> Array:
	var motions: Array = []
	for item in _moving:
		var piece: Dictionary = item
		var body: RigidBody3D = piece["body"]
		if is_instance_valid(body):
			motions.append([body.global_position, body.linear_velocity])
	return motions


## Fallen pieces are not moved with the rest of the world (they are their own
## top-level bodies), so they are moved here when the world re-centres.
func origin_shifted() -> void:
	var shift := Origin.offset - _last_offset
	_last_offset = Origin.offset
	for item in _debris:
		var piece: Dictionary = item
		var body: RigidBody3D = piece["body"]
		if is_instance_valid(body):
			body.global_position -= shift


# --- Damage --------------------------------------------------------------------

func _piece(collider: Object, shape: int) -> Variant:
	var body := collider as StaticBody3D
	if body == null or shape < 0 or not body.has_meta("structure") or body.get_meta("structure") != self:
		return null
	var node := body.shape_owner_get_owner(body.shape_find_owner(shape)) as Node
	if node == null or not node.has_meta("piece"):
		return null
	return node.get_meta("piece")


## Health left in the block a ray hit; the roof cannot be hurt (INF); -1 if
## it is not part of a tower.
func piece_health(collider: Object, shape: int) -> float:
	var body := collider as StaticBody3D
	if body == null or not body.has_meta("structure") or body.get_meta("structure") != self:
		return -1.0
	var key: Variant = _piece(collider, shape)
	if key == null:
		return INF
	var spot: Vector3i = key
	var tower: Dictionary = _towers[spot.x]
	var hp: PackedFloat32Array = tower["hp"]
	return maxf(hp[spot.y * SIDES + spot.z], 0.0)


func piece_id(collider: Object, shape: int) -> String:
	var key: Variant = _piece(collider, shape)
	return "tower roof" if key == null else "tower %s" % str(key)


func damage_piece(collider: Object, shape: int, amount: float) -> Array:
	var key: Variant = _piece(collider, shape)
	if key == null:
		return []
	return _damage(key, amount)


## Takes health from one block. Returns where it was, in the world, if that
## destroyed it.
func _damage(key: Vector3i, amount: float) -> Array:
	var tower: Dictionary = _towers[key.x]
	if key.y >= int(tower["standing"]) or amount <= 0.0:
		return []
	var hp: PackedFloat32Array = tower["hp"]
	var slot := key.y * SIDES + key.z
	if hp[slot] <= 0.0:
		return []
	hp[slot] = hp[slot] - amount
	tower["hp"] = hp
	_damaged = true
	if hp[slot] > 0.0:
		return []
	tower["dirty"] = true
	var body: StaticBody3D = tower["body"]
	for child in body.get_children():
		if child.has_meta("piece") and child.get_meta("piece") == key:
			(child as CollisionShape3D).disabled = true
	var where := _block_middle(tower, key.y, key.z)
	_check_collapse(key.x)
	return [where]


func _block_middle(tower: Dictionary, ring: int, side: int) -> Vector3:
	var angle := (side + 0.5) * TAU / SIDES
	var radius: float = tower["radius"]
	var spot := Vector3(cos(angle) * (radius - WALL * 0.5), (ring + 0.5) * float(tower["ring_height"]),
			sin(angle) * (radius - WALL * 0.5))
	return to_global(tower["base"] + spot)


## A blast: every block within `radius` of `centre` (in the world) takes
## `peak` x (1 - distance / radius). Returns where each block it destroyed was.
func blast(centre: Vector3, radius: float, peak: float) -> Array:
	var gone: Array = []
	for index in _towers.size():
		var tower: Dictionary = _towers[index]
		var base: Vector3 = to_global(tower["base"])
		var reach: float = float(tower["radius"]) + radius
		if Vector2(centre.x - base.x, centre.z - base.z).length() > reach:
			continue
		var half_block: float = maxf(float(tower["radius"]) * TAU / SIDES, float(tower["ring_height"])) * 0.5
		for ring in int(tower["standing"]):
			for side in SIDES:
				var middle := _block_middle(tower, ring, side)
				var distance := maxf(middle.distance_to(centre) - half_block, 0.0)
				if distance < radius:
					gone.append_array(_damage(Vector3i(index, ring, side), peak * (1.0 - distance / radius)))
	return gone


## Once a ring has lost half its blocks, it and everything above it fall.
func _check_collapse(index: int) -> void:
	var tower: Dictionary = _towers[index]
	var hp: PackedFloat32Array = tower["hp"]
	var standing: int = tower["standing"]
	for ring in standing:
		var left := 0
		var gap := Vector3.ZERO
		for side in SIDES:
			var angle := (side + 0.5) * TAU / SIDES
			if hp[ring * SIDES + side] > 0.0:
				left += 1
			else:
				gap += Vector3(cos(angle), 0.0, sin(angle))
		if left * 2 < SIDES:
			_collapse(index, ring, gap)
			return


## Everything from `ring` up breaks loose: one body per ring and one for the
## roof, tipping toward `gap` (the side that was shot away).
func _collapse(index: int, ring: int, gap: Vector3) -> void:
	var tower: Dictionary = _towers[index]
	var standing: int = tower["standing"]
	var radius: float = tower["radius"]
	var ring_height: float = tower["ring_height"]
	var hp: PackedFloat32Array = tower["hp"]
	var seed_value: int = tower["seed"]
	var base: Vector3 = tower["base"]
	var lean := gap.normalized() if gap.length() > 0.01 else Vector3.RIGHT
	# Tip over toward the gap: a turn about the level line across it.
	var tip_axis := Vector3.UP.cross(lean).normalized()
	var block_shape := ConvexPolygonShape3D.new()
	var middle_height := ring_height * 0.5
	block_shape.points = _block_corners(radius, 0, -middle_height, middle_height)
	for level in range(ring, standing):
		var stone := _new_surface()
		var glow := _new_surface()
		var blocks := 0
		var piece := _new_debris(to_global(base + Vector3(0.0, (level + 0.5) * ring_height, 0.0)))
		for side in SIDES:
			if hp[level * SIDES + side] <= 0.0:
				continue
			blocks += 1
			var collider := CollisionShape3D.new()
			collider.shape = block_shape
			collider.basis = Basis(Vector3.UP, -side * TAU / SIDES)
			piece.add_child(collider)
			_add_block(stone, glow, radius, level, side, ring_height,
					Vector3(0.0, -(level + 0.5) * ring_height, 0.0), seed_value)
		if blocks == 0:
			piece.queue_free()
			continue
		if level == RINGS - 1:
			_add_battlements(stone, radius, middle_height, hp, seed_value)
		_finish_debris(piece, stone, glow, minf(blocks * float(tower["block_mass"]), MAX_DEBRIS_MASS),
				tip_axis, level - ring, lean)
	if bool(tower["roof_on"]) and standing == RINGS:
		var stone := _new_surface()
		var glow := _new_surface()
		var piece := _new_debris(to_global(base + Vector3(0.0, standing * ring_height + MERLON, 0.0)))
		var roof := CollisionShape3D.new()
		roof.shape = _roof_shape(radius)
		piece.add_child(roof)
		_add_roof(stone, radius, Vector3.ZERO)
		var size := _roof_size(radius)
		var roof_mass := PI * size.x * size.x * size.y / 3.0 * 300.0   # timber and slate, mostly air
		_finish_debris(piece, stone, glow, minf(roof_mass, MAX_DEBRIS_MASS), tip_axis, standing - ring, lean)
		tower["roof_on"] = false
	tower["standing"] = ring
	tower["dirty"] = true


func _new_debris(at: Vector3) -> RigidBody3D:
	var piece := RigidBody3D.new()
	piece.top_level = true
	piece.collision_layer = Units.LAYER_BODIES
	piece.collision_mask = Units.LAYER_WORLD | Units.LAYER_BODIES
	piece.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	piece.continuous_cd = true
	add_child(piece)
	piece.global_position = at
	return piece


func _finish_debris(piece: RigidBody3D, stone: SurfaceTool, glow: SurfaceTool, mass: float, tip_axis: Vector3,
		height_up: int, lean: Vector3) -> void:
	piece.mass = maxf(mass, 1000.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _commit(stone, glow)
	piece.add_child(mesh)
	# Higher pieces start tipping a little faster and drift toward the gap.
	piece.angular_velocity = tip_axis * (0.05 + 0.01 * height_up)
	piece.linear_velocity = lean * (0.5 + 0.4 * height_up)
	_debris.append({"body": piece, "still": 0.0, "age": 0.0})


## Puts every tower back up, for a new spawn.
func reset_damage() -> void:
	if not _damaged:
		return
	_damaged = false
	for item in _debris:
		var piece: Dictionary = item
		var body: Node = piece["body"]
		if is_instance_valid(body):
			body.queue_free()
	_debris.clear()
	_moving.clear()
	for index in _towers.size():
		var tower: Dictionary = _towers[index]
		var hp: PackedFloat32Array = tower["hp"]
		hp.fill(float(tower["block_hp"]))
		tower["hp"] = hp
		tower["standing"] = RINGS
		tower["roof_on"] = true
		tower["dirty"] = true


static func _hash(n: int) -> float:
	var value := (n * 1103515245 + 12345) & 0x7fffffff
	value = (value ^ (value >> 13)) * 1274126177 & 0x7fffffff
	return float(value % 10007) / 10006.0
