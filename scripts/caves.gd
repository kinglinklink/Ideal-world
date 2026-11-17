extends Node3D
## Caves: six of them, each a wide tunnel from a hillside down into a huge
## cavern, and a second passage on down into a deeper, bigger one lit by
## glowing crystals. Big enough to drive a truck through, and to fly a small
## plane round the caverns if you are brave.
##
## The sites were picked from the height data (tools/find_caves.py did the
## search): sloping ground clear of roads and buildings, with enough hill
## above for the caverns. The rest is worked out here when the map loads:
## the tunnel heads into the hill, dropping about 1 in 3, far enough that the
## cavern sits at least 35 m under the ground everywhere above it.
##
## The rock is one mesh per cave with the same triangles for collision. The
## tunnel mouth is a hole in the ground (terrain.gd leaves the ground out
## there, drawn and solid) with a ring of solid ground round it, since the
## ground's own collision gives way a few metres wider than the hole.
##
## Down in a cave the daylight goes (daylight.underground) and the
## character carries a headlamp.

const MapInfo = preload("res://scripts/map_info.gd")
const Origin = preload("res://scripts/origin.gd")
const Units = preload("res://scripts/units.gd")

## [name, entrance (map x, z), heading of the tunnel in degrees from +X toward +Z]
const SITES := [
	["Wild Horse Cavern", Vector2(963.4, 1088.3), -37.2],
	["Mission North Cave", Vector2(15571.0, -14863.3), 14.6],
	["Mission South Cave", Vector2(15582.4, 13562.7), 9.8],
	["Salish Cave", Vector2(-8505.3, -3514.5), 155.7],
	["Big Arm Cave", Vector2(-7955.6, 5511.9), 148.7],
	["Somers Ridge Cave", Vector2(-4541.4, -21489.0), -178.5],
]
const TUNNEL_RADIUS := 14.0
const PASSAGE_RADIUS := 11.0
const SLOPE := 0.32               # the tunnels' drop per metre
const CAVERN := Vector3(170.0, 60.0, 130.0)        # half-sizes: across, up, along
const DEEP_CAVERN := Vector3(230.0, 85.0, 190.0)
const DEEP_DROP := 140.0          # metres the deep cavern lies below the first
const COVER := 35.0               # metres of rock at least over a cavern
const RING_STEP := 6.0            # metres between rings of a tunnel
const RING_SIDES := 22
const COLLAR := 9.0               # metres of solid ground round a mouth

var terrain: Node = null          # terrain.gd
var caves: Array = []             # see _plan
var map_points: Array = []        # [Vector2, name] for the maps
var _rock: StandardMaterial3D
var _crystal: StandardMaterial3D
var _lamp: SpotLight3D = null
var _check := 0.0


func setup(the_terrain: Node) -> void:
	terrain = the_terrain
	_rock = StandardMaterial3D.new()
	_rock.vertex_color_use_as_albedo = true
	_rock.roughness = 0.95
	_rock.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crystal = StandardMaterial3D.new()
	_crystal.albedo_color = Color(0.4, 0.9, 1.0)
	_crystal.emission_enabled = true
	_crystal.emission = Color(0.35, 0.85, 1.0)
	_crystal.emission_energy_multiplier = 2.5
	_crystal.roughness = 0.2
	var mouths: Array = []
	for index in SITES.size():
		var site: Array = SITES[index]
		var plan: Dictionary = _plan(site[1], deg_to_rad(float(site[2])), index)
		if plan.is_empty():
			continue
		plan["name"] = site[0]
		caves.append(plan)
		_build(plan, index)
		mouths.append([plan["mouth_a"], plan["mouth_b"], TUNNEL_RADIUS * 0.9])
		map_points.append([site[1], str(site[0])])
	terrain.set_holes(mouths)


## Clearings for the forest: no trees in or right round the cave mouths.
func clearings() -> Array:
	var list: Array = []
	for item in caves:
		var cave: Dictionary = item
		var a: Vector2 = cave["mouth_a"]
		var b: Vector2 = cave["mouth_b"]
		list.append([(a + b) * 0.5, a.distance_to(b) * 0.5 + TUNNEL_RADIUS + 12.0])
	return list


# --- Planning ------------------------------------------------------------------------

## Where a cave's tunnel, caverns and passage go. Empty if the hill turns
## out too small for it after all.
func _plan(entrance: Vector2, heading: float, seed_value: int) -> Dictionary:
	var along := Vector2(cos(heading), sin(heading))
	var mouth_y: float = terrain.height_at(entrance.x, entrance.y)
	var start_y := mouth_y - TUNNEL_RADIUS * 0.3
	var length := 300.0
	var centre := Vector3.ZERO
	var end_y := 0.0
	for attempt in 6:
		var flat := entrance + along * (length + CAVERN.z * 0.8)
		var lowest := _lowest_ground(flat, CAVERN, heading)
		centre = Vector3(flat.x, lowest - CAVERN.y - COVER, flat.y)
		end_y = centre.y - CAVERN.y * 0.3
		length = maxf((start_y - end_y) / SLOPE, 120.0)
	if length > 1500.0:
		return {}
	# The tunnel: straight on its heading, with a gentle wander, descending.
	var random := RandomNumberGenerator.new()
	random.seed = 9001 + seed_value
	var tunnel := PackedVector3Array()
	var steps := int(ceil(length / RING_STEP))
	var wander := random.randf_range(-0.15, 0.15)
	var mouth_end := entrance
	var found_end := false
	for step in steps + 1:
		var t := float(step) / steps
		var bend := sin(t * PI) * wander * length * 0.15
		var side := Vector2(-along.y, along.x)
		var flat := entrance + along * length * t + side * bend
		var y := lerpf(start_y, end_y, t)
		tunnel.append(Vector3(flat.x, y, flat.y))
		if not found_end and y + TUNNEL_RADIUS * 0.85 < terrain.height_at(flat.x, flat.y) - 1.0:
			found_end = true
			mouth_end = flat + along * 4.0
	if not found_end:
		return {}
	# Past the mouth, the tunnel must stay well under the ground.
	for point in tunnel:
		if point.distance_to(tunnel[0]) < entrance.distance_to(mouth_end) + 10.0:
			continue
		if point.y + TUNNEL_RADIUS > terrain.height_at(point.x, point.z) - 5.0:
			return {}
	# The passage on down to the deep cavern, turning a little.
	var turn := heading + random.randf_range(-0.7, 0.7)
	var deep_along := Vector2(cos(turn), sin(turn))
	var start := Vector3(centre.x, centre.y - CAVERN.y * 0.35, centre.z) \
			+ Vector3(deep_along.x, 0.0, deep_along.y) * CAVERN.z * 0.6
	var deep_centre := start + Vector3(deep_along.x, 0.0, deep_along.y) * (DEEP_DROP / SLOPE + DEEP_CAVERN.z * 0.5)
	deep_centre.y = centre.y - DEEP_DROP
	var deep_lowest := _lowest_ground(Vector2(deep_centre.x, deep_centre.z), DEEP_CAVERN, turn)
	deep_centre.y = minf(deep_centre.y, deep_lowest - DEEP_CAVERN.y - COVER)
	var passage := PackedVector3Array()
	var passage_end := deep_centre - Vector3(deep_along.x, 0.0, deep_along.y) * DEEP_CAVERN.z * 0.7
	passage_end.y = deep_centre.y - DEEP_CAVERN.y * 0.3
	var passage_steps := int(ceil(start.distance_to(passage_end) / RING_STEP))
	for step in passage_steps + 1:
		passage.append(start.lerp(passage_end, float(step) / passage_steps))
	return {"tunnel": tunnel, "cavern": centre, "heading": heading, "passage": passage, "deep": deep_centre,
			"deep_heading": turn, "mouth_a": entrance - along * 2.0, "mouth_b": mouth_end,
			"bounds": AABB(Vector3(minf(entrance.x, deep_centre.x) - 400.0, deep_centre.y - 200.0, minf(entrance.y, deep_centre.z) - 400.0),
					Vector3(absf(entrance.x - deep_centre.x) + 800.0, mouth_y - deep_centre.y + 400.0, absf(entrance.y - deep_centre.z) + 800.0))}


func _lowest_ground(middle: Vector2, half: Vector3, heading: float) -> float:
	var lowest := INF
	var along := Vector2(cos(heading), sin(heading))
	var side := Vector2(-along.y, along.x)
	for a in range(0, 360, 20):
		for share in [0.0, 0.5, 1.0, 1.25]:
			var angle := deg_to_rad(float(a))
			var spot: Vector2 = middle + side * cos(angle) * half.x * share + along * sin(angle) * half.z * share
			lowest = minf(lowest, terrain.height_at(spot.x, spot.y))
	return lowest


# --- Building -------------------------------------------------------------------------

func _build(cave: Dictionary, index: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 77 + index
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var random := RandomNumberGenerator.new()
	random.seed = 4242 + index
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var tunnel: PackedVector3Array = cave["tunnel"]
	var passage: PackedVector3Array = cave["passage"]
	var first := [cave["cavern"], CAVERN, cave["heading"]]
	var deep := [cave["deep"], DEEP_CAVERN, cave["deep_heading"]]
	_tube(rock, faces, tunnel, TUNNEL_RADIUS, noise, true, [first])
	_tube(rock, faces, passage, PASSAGE_RADIUS, noise, false, [first, deep])
	_chamber(rock, faces, first, noise, [[_near(tunnel, first), TUNNEL_RADIUS], [_near(passage, first), PASSAGE_RADIUS]])
	_chamber(rock, faces, deep, noise, [[_near(passage, deep), PASSAGE_RADIUS]])
	_spikes(rock, faces, first, random, 30)
	_spikes(rock, faces, deep, random, 45)
	rock.generate_normals()
	var mesh := rock.commit()
	mesh.surface_set_material(0, _rock)
	var shown := MeshInstance3D.new()
	shown.name = "Cave%d" % index
	shown.mesh = mesh
	add_child(shown)
	var body := StaticBody3D.new()
	body.name = "CaveRock%d" % index
	body.collision_layer = Units.LAYER_WORLD
	body.collision_mask = 0
	body.physics_material_override = Units.world_surface()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.add_child(_collar(cave))
	add_child(body)
	_glow(first, random, 3, 18, Color(0.3, 0.9, 0.8))
	_glow(deep, random, 5, 40, Color(0.6, 0.4, 1.0))


## A tunnel along `path`: rings of rock round it, a flat floor to drive on.
## With `open_top`, rings poking out of the hillside are pressed down onto
## the ground and the parts lying on it left out, which opens the mouth.
## Triangles inside any of `chambers` are left out, so it opens into them.
func _tube(rock: SurfaceTool, faces: PackedVector3Array, path: PackedVector3Array, radius: float,
		noise: FastNoiseLite, open_top: bool, chambers: Array) -> void:
	var rings: Array = []
	var pressed: Array = []
	for index in path.size():
		var here := path[index]
		var ahead := path[mini(index + 1, path.size() - 1)]
		var behind := path[maxi(index - 1, 0)]
		var forward := (ahead - behind).normalized()
		var side := forward.cross(Vector3.UP).normalized()
		var up := side.cross(forward).normalized()
		var ring := PackedVector3Array()
		var flags: Array = []
		for step in RING_SIDES:
			var angle := TAU * float(step) / RING_SIDES
			var across := cos(angle) * radius
			var height := sin(angle) * radius * 0.82
			var floor_level := -radius * 0.5
			var on_floor := height < floor_level
			height = maxf(height, floor_level)
			var point := here + side * across + up * height
			var bump := noise.get_noise_3dv(point) * radius * (0.03 if on_floor else 0.16)
			point += (side * cos(angle) + up * sin(angle)) * bump
			var pushed := false
			if open_top:
				var ground: float = terrain.height_at(point.x, point.z)
				if point.y > ground:
					point.y = ground
					pushed = true
			ring.append(point)
			flags.append(pushed)
		rings.append(ring)
		pressed.append(flags)
	for index in rings.size() - 1:
		var a: PackedVector3Array = rings[index]
		var b: PackedVector3Array = rings[index + 1]
		var a_flags: Array = pressed[index]
		var b_flags: Array = pressed[index + 1]
		for step in RING_SIDES:
			var next := (step + 1) % RING_SIDES
			for tri in [[a[step], b[step], b[next], a_flags[step], b_flags[step], b_flags[next]],
					[a[step], b[next], a[next], a_flags[step], b_flags[next], a_flags[next]]]:
				if tri[3] and tri[4] and tri[5]:
					continue   # lies on the ground: this is the open mouth
				var middle: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				if _inside_any(middle, chambers, 0.97):
					continue
				_triangle(rock, faces, tri[0], tri[1], tri[2], middle)


## A cavern: a squashed, lumpy ball with a flat floor, holed where tunnels
## come in. `chamber` is [centre, half-sizes, heading].
func _chamber(rock: SurfaceTool, faces: PackedVector3Array, chamber: Array, noise: FastNoiseLite, tubes: Array) -> void:
	var centre: Vector3 = chamber[0]
	var half: Vector3 = chamber[1]
	var heading: float = chamber[2]
	var along := Vector3(cos(heading), 0.0, sin(heading))
	var side := along.cross(Vector3.UP).normalized()
	var rows := 30
	var columns := 52
	var grid: Array = []
	for row in rows + 1:
		var polar := PI * float(row) / rows   # 0 at the top
		var line := PackedVector3Array()
		for column in columns:
			var azimuth := TAU * float(column) / columns
			var unit := Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
			var local := Vector3(unit.x * half.x, unit.y * half.y, unit.z * half.z)
			var point := centre + side * local.x + Vector3.UP * local.y + along * local.z
			# Lumpy walls, but smooth where a tunnel joins, and a flat floor.
			var calm := 1.0
			for item in tubes:
				var tube: Array = item
				calm = minf(calm, smoothstep(float(tube[1]) * 1.2, float(tube[1]) * 3.0, _distance_to_path(point, tube[0])))
			var lump := 1.0 + noise.get_noise_3dv(point * 0.6) * 0.22 * calm
			point = centre + (point - centre) * lump
			point.y = maxf(point.y, centre.y - half.y * 0.6 + noise.get_noise_3dv(point) * 1.2)
			line.append(point)
		grid.append(line)
	for row in rows:
		var top: PackedVector3Array = grid[row]
		var bottom: PackedVector3Array = grid[row + 1]
		for column in columns:
			var next := (column + 1) % columns
			for tri in [[top[column], bottom[column], bottom[next]], [top[column], bottom[next], top[next]]]:
				var middle: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var holed := false
				for item in tubes:
					var tube: Array = item
					if _distance_to_path(middle, tube[0]) < float(tube[1]) * 0.97:
						holed = true
						break
				if not holed:
					_triangle(rock, faces, tri[0], tri[1], tri[2], middle)


## Stalactites hanging from the roof and stalagmites rising from the floor.
func _spikes(rock: SurfaceTool, faces: PackedVector3Array, chamber: Array, random: RandomNumberGenerator, count: int) -> void:
	var centre: Vector3 = chamber[0]
	var half: Vector3 = chamber[1]
	for index in count:
		var hanging := index % 3 != 0
		var angle := random.randf() * TAU
		var reach := sqrt(random.randf()) * 0.75
		var spot := centre + Vector3(cos(angle) * half.x * reach, 0.0, sin(angle) * half.z * reach)
		var radius := random.randf_range(1.5, 5.0)
		var length := random.randf_range(radius * 2.5, radius * 6.0)
		var base: Vector3
		var tip: Vector3
		if hanging:
			var roof := half.y * sqrt(maxf(1.0 - reach * reach, 0.05)) * 0.9
			base = spot + Vector3(0.0, roof, 0.0)
			tip = base - Vector3(0.0, length, 0.0)
		else:
			base = spot + Vector3(0.0, -half.y * 0.6, 0.0)
			tip = base + Vector3(0.0, length * 0.7, 0.0)
		var sides := 7
		for step in sides:
			var a0 := TAU * float(step) / sides
			var a1 := TAU * float(step + 1) / sides
			var p0 := base + Vector3(cos(a0), 0.0, sin(a0)) * radius
			var p1 := base + Vector3(cos(a1), 0.0, sin(a1)) * radius
			_triangle(rock, faces, p0, p1, tip, (p0 + p1 + tip) / 3.0)


## Glowing crystal clusters on the floor, and lamps among them.
func _glow(chamber: Array, random: RandomNumberGenerator, lamps: int, clusters: int, color: Color) -> void:
	var centre: Vector3 = chamber[0]
	var half: Vector3 = chamber[1]
	var crystals := SurfaceTool.new()
	crystals.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in clusters:
		var angle := random.randf() * TAU
		var reach := random.randf_range(0.3, 0.8)
		var foot := centre + Vector3(cos(angle) * half.x * reach, -half.y * 0.6, sin(angle) * half.z * reach)
		for spike in 5:
			var lean := Vector3(random.randf_range(-0.5, 0.5), 1.0, random.randf_range(-0.5, 0.5)).normalized()
			var size := random.randf_range(0.6, 2.2)
			var tip := foot + lean * size * random.randf_range(3.0, 6.0)
			for step in 6:
				var a0 := TAU * float(step) / 6.0
				var a1 := TAU * float(step + 1) / 6.0
				var p0 := foot + Vector3(cos(a0), 0.0, sin(a0)) * size
				var p1 := foot + Vector3(cos(a1), 0.0, sin(a1)) * size
				crystals.add_vertex(p0)
				crystals.add_vertex(p1)
				crystals.add_vertex(tip)
	crystals.generate_normals()
	var mesh := crystals.commit()
	var look: StandardMaterial3D = _crystal.duplicate()
	look.albedo_color = color.lightened(0.2)
	look.emission = color
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, look)
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shown)
	for index in lamps:
		var angle := TAU * float(index) / lamps + random.randf_range(-0.3, 0.3)
		var lamp := OmniLight3D.new()
		lamp.light_color = color
		lamp.light_energy = 2.5
		lamp.omni_range = maxf(half.x, half.z) * 0.9
		lamp.shadow_enabled = false
		lamp.position = centre + Vector3(cos(angle) * half.x * 0.45, -half.y * 0.25, sin(angle) * half.z * 0.45)
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 1500.0
		lamp.distance_fade_length = 500.0
		add_child(lamp)


## Solid ground round a mouth, where the ground's own collision has gone
## with the hole. Only for collision: the ground is drawn there already.
func _collar(cave: Dictionary) -> CollisionShape3D:
	var a: Vector2 = cave["mouth_a"]
	var b: Vector2 = cave["mouth_b"]
	var hole := TUNNEL_RADIUS * 0.9
	var low := a.min(b) - Vector2.ONE * (hole + COLLAR)
	var high := a.max(b) + Vector2.ONE * (hole + COLLAR)
	var step := 2.0
	var faces := PackedVector3Array()
	var x := low.x
	while x < high.x:
		var z := low.y
		while z < high.y:
			var middle := Vector2(x + step * 0.5, z + step * 0.5)
			var gap := _to_segment(middle, a, b)
			if gap > hole and gap < hole + COLLAR:
				var p00 := Vector3(x, terrain.height_at(x, z), z)
				var p10 := Vector3(x + step, terrain.height_at(x + step, z), z)
				var p01 := Vector3(x, terrain.height_at(x, z + step), z + step)
				var p11 := Vector3(x + step, terrain.height_at(x + step, z + step), z + step)
				faces.append_array(PackedVector3Array([p00, p10, p11, p00, p11, p01]))
			z += step
		x += step
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	return collider


func _triangle(rock: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, middle: Vector3) -> void:
	var shade := 0.55 + 0.25 * fposmod(sin(middle.x * 0.13) * cos(middle.z * 0.11) * 3.0, 1.0)
	rock.set_color(Color(0.42 * shade, 0.38 * shade, 0.34 * shade))
	rock.add_vertex(a)
	rock.add_vertex(b)
	rock.add_vertex(c)
	faces.append(a)
	faces.append(b)
	faces.append(c)


func _inside_any(point: Vector3, chambers: Array, share: float) -> bool:
	for item in chambers:
		var chamber: Array = item
		var centre: Vector3 = chamber[0]
		var half: Vector3 = chamber[1]
		var heading: float = chamber[2]
		var along := Vector3(cos(heading), 0.0, sin(heading))
		var side := along.cross(Vector3.UP).normalized()
		var off := point - centre
		var local := Vector3(off.dot(side) / half.x, off.y / half.y, off.dot(along) / half.z)
		if local.length() < share:
			return true
	return false


## The part of a path that comes near a chamber, which is all a chamber
## needs to know about it.
static func _near(path: PackedVector3Array, chamber: Array) -> PackedVector3Array:
	var centre: Vector3 = chamber[0]
	var half: Vector3 = chamber[1]
	var reach := maxf(maxf(half.x, half.y), half.z) * 1.6
	var kept := PackedVector3Array()
	for index in path.size():
		if path[index].distance_to(centre) < reach:
			if kept.is_empty() and index > 0:
				kept.append(path[index - 1])
			kept.append(path[index])
	return kept


static func _distance_to_path(point: Vector3, path: PackedVector3Array) -> float:
	var best := INF
	if path.size() == 1:
		return point.distance_to(path[0])
	for index in path.size() - 1:
		var a := path[index]
		var b := path[index + 1]
		var along := b - a
		var t := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, point.distance_to(a + along * t))
	return best


static func _to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var along := b - a
	var t := clampf((point - a).dot(along) / maxf(along.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + along * t)


# --- Underground ------------------------------------------------------------------------

## How far underground the camera is: 0 out in the open, 1 deep in a cave.
func underground_amount() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0.0
	var eye := Origin.to_map(camera.global_position)
	for item in caves:
		var cave: Dictionary = item
		var bounds: AABB = cave["bounds"]
		if not bounds.has_point(eye):
			continue
		var ground: float = terrain.height_at(eye.x, eye.z)
		return clampf((ground - eye.y - 3.0) / 25.0, 0.0, 1.0)
	return 0.0


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	var amount := underground_amount()
	var daylight: Node = get_tree().get_first_node_in_group("daylight")
	if daylight != null:
		daylight.underground = amount
	# A headlamp on the camera while underground.
	var camera := get_viewport().get_camera_3d()
	if amount > 0.3 and camera != null:
		if _lamp == null or not is_instance_valid(_lamp) or _lamp.get_parent() != camera:
			if _lamp != null and is_instance_valid(_lamp):
				_lamp.queue_free()
			_lamp = SpotLight3D.new()
			_lamp.spot_range = 80.0
			_lamp.spot_angle = 38.0
			_lamp.light_energy = 2.2
			_lamp.shadow_enabled = false
			camera.add_child(_lamp)
	elif _lamp != null and is_instance_valid(_lamp):
		_lamp.queue_free()
		_lamp = null
