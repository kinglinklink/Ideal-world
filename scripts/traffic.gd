extends Node
## Life on the map: cars driving the highways and light planes flying
## between the airports.
##
## Cars: up to MAX_CARS at a time on the highways within a couple of
## kilometres of you, each on its own long route, in the right-hand lane at
## its own cruising speed. They slow and stop for anything in front of them
## (your vehicles, you, another car) and are solid, so you can hit them, or
## shove them with something big: they are driven, not pushed, so they are
## as hard to move as a wall. Further away they are taken off and new ones
## put on.
##
## Planes: PLANES light aircraft cruising between random airports at a few
## hundred metres, turning gently onto each new heading. Solid too.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Units = preload("res://scripts/units.gd")
const Roads = preload("res://scripts/roads.gd")
const Sound = preload("res://scripts/sound.gd")
const Profiler = preload("res://scripts/profiler.gd")
const MeshKit = preload("res://scripts/mesh_kit.gd")

const MAX_CARS := 18
const CAR_NEAR := 400.0         # metres from you at the closest a new car appears
const CAR_FAR := 2300.0         # and at the furthest
const CAR_DROP := 3000.0        # cars further away than this go
const LANE := 2.2               # metres right of the road's middle
const PLANES := 6
const PLANE_SPEED := Vector2(55.0, 80.0)
const CAR_COLORS := [Color(0.75, 0.1, 0.1), Color(0.1, 0.25, 0.7), Color(0.9, 0.9, 0.88), Color(0.12, 0.12, 0.13),
		Color(0.55, 0.57, 0.6), Color(0.85, 0.65, 0.1), Color(0.15, 0.45, 0.25)]

## Traffic on the roads and in the air. The settings switch it.
static var enabled := true

var terrain: Node = null        # terrain.gd
var player: Node3D = null       # player.gd
var roads: RefCounted = null    # roads.gd

var _cars: Array = []
var _planes: Array = []
var _airports: Array = []       # [map position of the runway's middle, name]
var _random := RandomNumberGenerator.new()
var _spawn_timer := 1.0
var _look_timer := 0.0
var _car_meshes: Array = []
var _plane_mesh: Mesh = null
var _last_offset := Vector3.ZERO
var _nearby: Array = []         # indices of highway stretches near you, found again now and then
var _nearby_timer := 0.0


func setup(the_terrain: Node, the_player: Node3D) -> void:
	terrain = the_terrain
	player = the_player
	_random.randomize()
	roads = Roads.new()
	roads.build(terrain.towns)
	for item in terrain.world.get("runways", []):
		var runway: Dictionary = item
		var centre: Array = runway["centre"]
		var at := Vector2(float(centre[0]), float(centre[1]))
		_airports.append([Vector3(at.x, terrain.height_at(at.x, at.y), at.y), str(runway.get("name", ""))])
	for color in CAR_COLORS:
		_car_meshes.append(_make_car_mesh(color))
	_plane_mesh = _make_plane_mesh()


func _physics_process(delta: float) -> void:
	var started := Profiler.start()
	_physics_tick(delta)
	Profiler.add("traffic", started)


func _physics_tick(delta: float) -> void:
	if terrain == null:
		return
	var shifted := Origin.offset != _last_offset
	_last_offset = Origin.offset
	if not enabled:
		if not _cars.is_empty() or not _planes.is_empty():
			_clear()
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 1.5
		_top_up_cars()
		while _planes.size() < PLANES and _airports.size() >= 2:
			_add_plane()
	_look_timer -= delta
	var look := _look_timer <= 0.0
	if look:
		_look_timer = 0.15
	for index in range(_cars.size() - 1, -1, -1):
		if not _run_car(_cars[index], delta, look, shifted):
			_drop_car(index)
	for item in _planes:
		_run_plane(item, delta, shifted)


func _clear() -> void:
	for index in range(_cars.size() - 1, -1, -1):
		_drop_car(index)
	for item in _planes:
		var plane: Dictionary = item
		(plane["body"] as Node).queue_free()
	_planes.clear()


# --- Cars --------------------------------------------------------------------------

func _top_up_cars() -> void:
	if player == null or roads.lines.is_empty():
		return
	var here := Origin.to_map(player.global_position)
	var spot := Vector2(here.x, here.z)
	_nearby_timer -= 1.0
	if _nearby_timer <= 0.0:
		_nearby_timer = 4.0
		_nearby.clear()
		for index in roads.lines.size():
			var stretch: PackedVector3Array = roads.lines[index]
			for probe in [stretch[0], stretch[stretch.size() >> 1], stretch[stretch.size() - 1]]:
				if Vector2(probe.x, probe.z).distance_to(spot) < CAR_FAR + 500.0:
					_nearby.append(index)
					break
	if _nearby.is_empty():
		return
	for attempt in 4:
		if _cars.size() >= MAX_CARS:
			return
		# A random highway point a fair way off.
		var line_index: int = _nearby[_random.randi() % _nearby.size()]
		var line: PackedVector3Array = roads.lines[line_index]
		var index: int = _random.randi() % line.size()
		var distance := Vector2(line[index].x, line[index].z).distance_to(spot)
		if distance < CAR_NEAR or distance > CAR_FAR:
			continue
		var route: PackedVector3Array = roads.route_from(line_index, index, _random.randf() < 0.5, 7000.0)
		if route.size() < 4:
			continue
		_add_car(route)


func _add_car(route: PackedVector3Array) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = Units.LAYER_BODIES
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 1.5, 4.5)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, 0.85, 0.0)
	body.add_child(collider)
	var shown := MeshInstance3D.new()
	shown.mesh = _car_meshes[_random.randi() % _car_meshes.size()]
	body.add_child(shown)
	var sound := Sound.make_loop("car_loop", "Machines")
	if sound != null:
		sound.unit_size = 6.0
		sound.max_distance = 180.0
		sound.volume_db = -6.0
		sound.pitch_scale = _random.randf_range(0.85, 1.2)
		body.add_child(sound)
	add_child(body)
	if sound != null:
		sound.play()
	var cruise := _random.randf_range(20.0, 29.0)
	var car := {"body": body, "route": route, "along": Roads.distances(route), "at": 0.0,
			"speed": cruise, "cruise": cruise, "blocked": false}
	_place_car(car, true)
	_cars.append(car)


func _drop_car(index: int) -> void:
	var car: Dictionary = _cars[index]
	if is_instance_valid(car["body"]):
		(car["body"] as Node).queue_free()
	_cars.remove_at(index)


## Drives one car on. False when it should go (the road ended, or it is far away).
func _run_car(car: Dictionary, delta: float, look: bool, shifted: bool) -> bool:
	var body: AnimatableBody3D = car["body"]
	if not is_instance_valid(body):
		return false
	var along: PackedFloat32Array = car["along"]
	if float(car["at"]) >= along[along.size() - 1] - 1.0:
		return false
	if player != null and body.global_position.distance_to(player.global_position) > CAR_DROP:
		return false
	if look:
		car["blocked"] = _blocked(body)
	var wanted: float = 0.0 if bool(car["blocked"]) else float(car["cruise"])
	var rate := 7.0 if wanted < float(car["speed"]) else 2.5
	car["speed"] = move_toward(float(car["speed"]), wanted, rate * delta)
	car["at"] = float(car["at"]) + float(car["speed"]) * delta
	body.sync_to_physics = not shifted
	_place_car(car, false)
	return true


func _place_car(car: Dictionary, first: bool) -> void:
	var picked: Array = Roads.sample(car["route"], car["along"], float(car["at"]))
	var point: Vector3 = picked[0]
	var ahead: Array = Roads.sample(car["route"], car["along"], float(car["at"]) + 4.0)
	var direction: Vector3 = ((ahead[0] as Vector3) - point)
	if direction.length() < 0.01:
		direction = picked[1]
	direction = direction.normalized()
	var right := direction.cross(Vector3.UP).normalized()
	var place := Origin.to_world(point + right * LANE + Vector3(0.0, 0.05, 0.0))
	var turn := Basis.looking_at(direction, Vector3.UP)
	var body: AnimatableBody3D = car["body"]
	if first:
		body.global_transform = Transform3D(turn, place)
	else:
		body.global_transform = Transform3D(turn, place)


## Something in the way, up to 25 m ahead in its lane.
func _blocked(body: AnimatableBody3D) -> bool:
	var front := body.global_transform.basis.z * -1.0
	var from := body.global_position + Vector3(0.0, 1.0, 0.0) + front * 2.6
	var query := PhysicsRayQueryParameters3D.create(from, from + front * 25.0, Units.LAYER_BODIES | Units.LAYER_PLAYER)
	query.exclude = [body.get_rid()]
	return not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Planes --------------------------------------------------------------------------------

func _add_plane() -> void:
	var from: Array = _airports[_random.randi() % _airports.size()]
	var start: Vector3 = from[0]
	var heading := _random.randf() * TAU
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = Units.LAYER_BODIES
	body.collision_mask = 0
	for box in [[Vector3(1.6, 1.6, 9.0), Vector3.ZERO], [Vector3(12.0, 0.3, 1.8), Vector3(0.0, 0.3, -0.5)]]:
		var shape := BoxShape3D.new()
		shape.size = box[0]
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = box[1]
		body.add_child(collider)
	var shown := MeshInstance3D.new()
	shown.mesh = _plane_mesh
	body.add_child(shown)
	var sound := Sound.make_loop("plane_loop", "Machines")
	if sound != null:
		sound.unit_size = 25.0
		sound.max_distance = 3500.0
		sound.pitch_scale = _random.randf_range(0.9, 1.15)
		body.add_child(sound)
	add_child(body)
	if sound != null:
		sound.play()
	var plane := {"body": body, "at": start + Vector3(0.0, _random.randf_range(250.0, 500.0), 0.0),
			"heading": heading, "speed": _random.randf_range(PLANE_SPEED.x, PLANE_SPEED.y), "bank": 0.0}
	_next_destination(plane)
	_planes.append(plane)


func _next_destination(plane: Dictionary) -> void:
	var here: Vector3 = plane["at"]
	for attempt in 8:
		var to: Array = _airports[_random.randi() % _airports.size()]
		var target: Vector3 = to[0]
		if Vector2(target.x, target.z).distance_to(Vector2(here.x, here.z)) > 3000.0:
			# Cruise high enough to clear the ground on the way.
			var highest := maxf(here.y - 300.0, target.y)
			for step in 12:
				var spot := here.lerp(target, float(step) / 11.0)
				highest = maxf(highest, terrain.height_at(spot.x, spot.z))
			plane["target"] = Vector3(target.x, highest + _random.randf_range(250.0, 450.0), target.z)
			return
	plane["target"] = here + Vector3(cos(float(plane["heading"])), 0.0, sin(float(plane["heading"]))) * 5000.0


func _run_plane(plane: Dictionary, delta: float, shifted: bool) -> void:
	var at: Vector3 = plane["at"]
	var target: Vector3 = plane["target"]
	var flat := Vector2(target.x - at.x, target.z - at.z)
	if flat.length() < 900.0:
		_next_destination(plane)
		return
	var wanted := flat.angle()
	var heading: float = plane["heading"]
	var turn := clampf(wrapf(wanted - heading, -PI, PI), -deg_to_rad(4.0) * delta, deg_to_rad(4.0) * delta)
	heading += turn
	plane["heading"] = heading
	plane["bank"] = lerpf(float(plane["bank"]), clampf(turn / maxf(delta, 0.0001) * 6.0, -0.6, 0.6), 1.0 - exp(-delta * 2.0))
	var speed: float = plane["speed"]
	var forward := Vector3(cos(heading), 0.0, sin(heading))
	var climb := clampf(target.y - at.y, -6.0, 6.0)
	at += forward * speed * delta + Vector3(0.0, climb * delta, 0.0)
	# Never into the ground.
	var ground: float = terrain.height_at(at.x, at.z)
	at.y = maxf(at.y, maxf(ground, MapInfo.LAKE_Y) + 120.0)
	plane["at"] = at
	var body: AnimatableBody3D = plane["body"]
	body.sync_to_physics = not shifted
	var pitch_dir := (forward * speed + Vector3(0.0, climb, 0.0)).normalized()
	var basis := Basis.looking_at(pitch_dir, Vector3.UP) * Basis(Vector3.FORWARD, float(plane["bank"]))
	body.global_transform = Transform3D(basis, Origin.to_world(at))


# --- Models --------------------------------------------------------------------------------

## A saloon car, 4.4 m long, front toward -Z: a body with a sloping bonnet
## and boot, a cabin with dark glass all round, four wheels with hubs, and
## lights.
func _make_car_mesh(paint: Color) -> Mesh:
	var surface := MeshKit.new_surface()
	var glass := Color(0.08, 0.11, 0.14)
	surface.set_color(paint)
	_side_shape(surface, [Vector2(-2.2, 0.3), Vector2(2.2, 0.3), Vector2(2.2, 1.0), Vector2(1.95, 1.1),
			Vector2(-1.95, 1.08), Vector2(-2.2, 0.85)], 1.84)
	surface.set_color(paint.darkened(0.1))
	_side_shape(surface, [Vector2(-0.95, 1.07), Vector2(1.55, 1.07), Vector2(0.95, 1.62), Vector2(-0.4, 1.62)], 1.56)
	surface.set_color(glass)
	_side_shape(surface, [Vector2(-0.86, 1.12), Vector2(1.45, 1.12), Vector2(0.9, 1.56), Vector2(-0.37, 1.56)], 1.6)
	for corner in [Vector3(-0.86, 0.36, -1.38), Vector3(0.86, 0.36, -1.38), Vector3(-0.86, 0.36, 1.38), Vector3(0.86, 0.36, 1.38)]:
		surface.set_color(Color(0.06, 0.06, 0.06))
		MeshKit.add_cylinder(surface, corner, 0, 0.36, 0.26, 14)
		surface.set_color(Color(0.6, 0.6, 0.62))
		MeshKit.add_cylinder(surface, corner + Vector3(signf(corner.x) * 0.02, 0.0, 0.0), 0, 0.2, 0.26, 10)
	for side in [-1.0, 1.0]:
		surface.set_color(Color(1.0, 0.95, 0.8))
		MeshKit.add_box(surface, Vector3(0.6 * side, 0.8, -2.21), Vector3(0.38, 0.14, 0.03))
		surface.set_color(Color(0.9, 0.1, 0.05))
		MeshKit.add_box(surface, Vector3(0.62 * side, 0.85, 2.21), Vector3(0.35, 0.12, 0.03))
	surface.set_color(Color(0.15, 0.15, 0.16))
	MeshKit.add_box(surface, Vector3(0.0, 0.45, -2.22), Vector3(1.7, 0.18, 0.06))   # bumpers
	MeshKit.add_box(surface, Vector3(0.0, 0.45, 2.22), Vector3(1.7, 0.18, 0.06))
	return _finish(surface)


## A light high-wing plane, nose toward -Z: a round fuselage tapering to the
## tail, tapered wings, tailplane and fin, a windscreen, a propeller and
## a stripe.
func _make_plane_mesh() -> Mesh:
	var surface := MeshKit.new_surface()
	var white := Color(0.93, 0.93, 0.92)
	var stripe := Color(0.8, 0.15, 0.1)
	surface.set_color(white)
	MeshKit.add_frustum(surface, Vector3(0.0, 0.0, -3.95), 2, 0.2, 0.7, 0.9, 14)
	MeshKit.add_cylinder(surface, Vector3(0.0, 0.0, -1.0), 2, 0.72, 5.0, 14)
	MeshKit.add_frustum(surface, Vector3(0.0, 0.1, 3.2), 2, 0.72, 0.2, 3.4, 14)
	surface.set_color(stripe)
	MeshKit.add_cylinder(surface, Vector3(0.0, 0.0, -0.4), 2, 0.735, 0.5, 14)
	surface.set_color(Color(0.15, 0.2, 0.25))
	MeshKit.add_extruded_polygon(surface, [Vector3(-0.62, 0.35, -2.6), Vector3(0.62, 0.35, -2.6),
			Vector3(0.55, 0.75, -2.0), Vector3(-0.55, 0.75, -2.0)], Vector3(0.0, 0.0, 0.05))
	surface.set_color(white)
	for side in [-1.0, 1.0]:
		# A wing, root chord 2 m, tip 1.1 m, 6 m long, on top of the cabin.
		MeshKit.add_extruded_polygon(surface, [Vector3(0.0, 0.8, -1.9), Vector3(0.0, 0.8, 0.1),
				Vector3(6.0 * side, 0.9, -0.1), Vector3(6.0 * side, 0.9, -1.2)], Vector3(0.0, 0.16, 0.0))
		MeshKit.add_extruded_polygon(surface, [Vector3(0.0, 0.25, 3.3), Vector3(0.0, 0.25, 4.3),
				Vector3(2.0 * side, 0.25, 4.3), Vector3(2.0 * side, 0.25, 3.7)], Vector3(0.0, 0.1, 0.0))
		surface.set_color(stripe)
		MeshKit.add_box(surface, Vector3(5.6 * side, 0.98, -0.65), Vector3(0.8, 0.18, 1.12))   # wing tips
		surface.set_color(white)
	surface.set_color(stripe)
	MeshKit.add_extruded_polygon(surface, [Vector3(-0.06, 0.4, 3.0), Vector3(-0.06, 0.4, 4.35),
			Vector3(-0.06, 2.0, 4.45), Vector3(-0.06, 1.9, 3.85)], Vector3(0.12, 0.0, 0.0))
	surface.set_color(Color(0.2, 0.2, 0.2))
	MeshKit.add_frustum(surface, Vector3(0.0, 0.0, -4.5), 2, 0.05, 0.2, 0.3, 10)   # spinner
	MeshKit.add_box(surface, Vector3(0.0, 0.0, -4.42), Vector3(2.2, 0.15, 0.06))
	surface.set_color(Color(0.1, 0.1, 0.1))
	for at in [Vector3(-1.1, -1.05, -1.2), Vector3(1.1, -1.05, -1.2), Vector3(0.0, -1.0, -3.3)]:
		MeshKit.add_cylinder(surface, at, 0, 0.25, 0.15, 10)
	surface.set_color(Color(0.5, 0.5, 0.52))
	MeshKit.add_box(surface, Vector3(-0.6, -0.65, -1.2), Vector3(0.06, 0.8, 0.12))   # gear legs
	MeshKit.add_box(surface, Vector3(0.6, -0.65, -1.2), Vector3(0.06, 0.8, 0.12))
	MeshKit.add_box(surface, Vector3(0.0, -0.6, -3.3), Vector3(0.06, 0.7, 0.1))
	return _finish(surface)


## A side outline (z along, y up) made solid `width` across, centred on x = 0.
static func _side_shape(surface: SurfaceTool, outline: Array, width: float) -> void:
	var points: Array = []
	for corner in outline:
		points.append(Vector3(-width * 0.5, (corner as Vector2).y, (corner as Vector2).x))
	MeshKit.add_extruded_polygon(surface, points, Vector3(width, 0.0, 0.0))


static func _box(surface: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var corners := []
	for corner in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		corners.append(centre + (corner as Vector3) * h)
	surface.set_color(color)
	for face in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		var f: Array = face
		for index in [0, 1, 2, 0, 2, 3]:
			surface.add_vertex(corners[f[index]])


static func _finish(surface: SurfaceTool) -> Mesh:
	surface.generate_normals()
	var mesh := surface.commit()
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.5
	look.metallic = 0.2
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, look)
	return mesh


## Where the traffic is, for the minimap: map positions of cars and planes.
func positions() -> Array:
	var list: Array = []
	for item in _planes:
		list.append((item as Dictionary)["at"])
	return list
