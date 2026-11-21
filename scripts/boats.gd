extends Node
## Life on the lake: the docks, and boats out on the water in summer.
##
## Docks: the Melita camp dock and Cromwell's five-slip dock are built by
## landmarks.gd; this adds the landing at Skeeko Bay (Wild Horse Island,
## below the hangar), a dock on Shelter Island and the town dock in Polson
## Bay. Every dock has boat races (races.gd) and a fuel pump (fuel.gd).
##
## Boats, in summer only: up to MAX_BOATS within a few kilometres of you.
## Sailboats sail by the real wind (they cannot point closer than 45° to
## it, so they tack), speedboats race about leaving a wake, and fishing
## boats motor to a spot and sit there a while. They ride the waves, are
## solid, and can be shot or blown up and sunk.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Units = preload("res://scripts/units.gd")
const Sound = preload("res://scripts/sound.gd")
const Weather = preload("res://scripts/weather.gd")
const Profiler = preload("res://scripts/profiler.gd")

const MAX_BOATS := 10
const NEAR := 3500.0
const DROP := 5000.0
## kind: [length m, width m, health, top speed m/s, colour of the hull]
const KINDS := {
	"sail": [9.0, 3.0, 300.0, 6.0, Color(0.95, 0.95, 0.93)],
	"speed": [6.5, 2.4, 200.0, 18.0, Color(0.85, 0.15, 0.12)],
	"fishing": [7.0, 2.6, 400.0, 4.0, Color(0.25, 0.45, 0.65)],
}

static var enabled := true

var terrain: Node = null           # terrain.gd
var weather: Node = null           # weather.gd
var player: Node3D = null          # player.gd
var docks: Array = []              # {"name", "shore": map Vector3, "water": map Vector3, "heading"}

var _boats: Array = []             # see _add_boat
var _random := RandomNumberGenerator.new()
var _timer := 1.0
var _wake_mesh: QuadMesh = null


func setup() -> void:
	add_to_group("map_markers")
	_random.randomize()
	for item in terrain.landmarks.map_points:
		var point: Array = item
		if str(point[1]) == "Melita dock" or str(point[1]) == "Cromwell dock":
			_note_dock(str(point[1]), point[0], false)
	# Skeeko Bay: the shore below the hangar, to its north-west.
	var skeeko := _shore_near(Vector2(-350.0, -350.0), 1800.0, Vector2(-1.0, -1.0))
	if skeeko != Vector2.INF:
		_note_dock("Skeeko Bay landing", skeeko, true)
	for item in terrain.landmarks.map_points:
		var point: Array = item
		if str(point[1]) == "Shelter mansion":
			var spot := _shore_near(point[0], 400.0, Vector2.ZERO)
			if spot != Vector2.INF:
				_note_dock("Shelter Island dock", spot, true)
	for item in terrain.world.get("town_names", []):
		var town: Dictionary = item
		if str(town["name"]) == "Polson":
			var at: Array = town["at"]
			var spot := _shore_near(Vector2(float(at[0]), float(at[1])), 3000.0, Vector2(0.0, -1.0))
			if spot != Vector2.INF:
				_note_dock("Polson dock", spot, true)


## The shore point nearest `centre` (within `reach` m) with open water off
## it, preferring the side `toward` if given.
func _shore_near(centre: Vector2, reach: float, toward: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_score := INF
	var step := 20.0
	var ring := 0.0
	while ring <= reach:
		var around := maxi(1, int(TAU * ring / step))
		for index in around:
			var angle := TAU * float(index) / float(around)
			var spot := centre + Vector2(cos(angle), sin(angle)) * ring
			if terrain.is_lake(spot.x, spot.y):
				continue
			var out := _water_direction(spot)
			if out == Vector2.ZERO:
				continue
			var score := ring - (toward.normalized().dot(spot - centre) * 0.5 if toward != Vector2.ZERO else 0.0)
			if score < best_score:
				best_score = score
				best = spot
		if best != Vector2.INF and ring > 60.0:
			break
		ring += step
	return best


## Which way open water lies from a shore point: water at 15 m and 80 m.
func _water_direction(spot: Vector2) -> Vector2:
	var total := Vector2.ZERO
	for index in 16:
		var direction := Vector2(cos(TAU * index / 16.0), sin(TAU * index / 16.0))
		if terrain.is_lake(spot.x + direction.x * 15.0, spot.y + direction.y * 15.0) \
				and terrain.is_lake(spot.x + direction.x * 80.0, spot.y + direction.y * 80.0):
			total += direction
	return total.normalized() if total.length() > 0.5 else Vector2.ZERO


func _note_dock(dock_name: String, spot: Vector2, build: bool) -> void:
	var out := _water_direction(spot)
	if out == Vector2.ZERO:
		out = Vector2(0.0, -1.0)
	var heading := atan2(out.x, -out.y)
	var length := 40.0
	# Walk the shore point to the water's edge.
	var edge := spot
	for step in 20:
		if terrain.is_lake(edge.x + out.x * 2.0, edge.y + out.y * 2.0):
			break
		edge += out * 2.0
	var shore := Vector3(edge.x, terrain.height_at(edge.x, edge.y), edge.y)
	var water := Vector3(edge.x + out.x * length, MapInfo.LAKE_Y, edge.y + out.y * length)
	docks.append({"name": dock_name, "shore": shore, "water": water, "heading": heading})
	if build:
		_build_dock(shore, out, length)


func _build_dock(shore: Vector3, out: Vector2, length: float) -> void:
	var node := StaticBody3D.new()
	node.name = "Dock"
	node.collision_layer = Units.LAYER_WORLD
	node.collision_mask = 0
	terrain.add_child(node)
	var deck_y := MapInfo.LAKE_Y + 1.0
	node.position = Vector3(shore.x, deck_y, shore.z)
	node.rotation.y = atan2(-out.x, -out.y)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.42, 0.28)
	wood.roughness = 0.9
	var reach := length + 6.0
	_piece(node, Vector3(0.0, 0.0, -reach * 0.5 + 6.0), Vector3(3.0, 0.3, reach), wood, true)
	_piece(node, Vector3(0.0, 0.0, -length - 2.0), Vector3(14.0, 0.3, 4.0), wood, true)
	var z := 0.0
	while z <= length:
		for side in [-1.0, 1.0]:
			_piece(node, Vector3(1.3 * side, -2.5, -z), Vector3(0.3, 5.0, 0.3), wood, false)
		z += 5.0
	# A ramp up the bank if the shore is higher than the deck.
	var climb: float = shore.y - deck_y
	if climb > 0.3:
		var ramp := MeshInstance3D.new()
		var box := BoxMesh.new()
		var run := maxf(climb * 4.0, 4.0)
		box.size = Vector3(3.0, 0.3, sqrt(run * run + climb * climb))
		ramp.mesh = box
		ramp.material_override = wood
		ramp.position = Vector3(0.0, climb * 0.5, run * 0.5)
		ramp.rotation.x = atan2(climb, run)
		node.add_child(ramp)
		var ramp_shape := CollisionShape3D.new()
		var ramp_box := BoxShape3D.new()
		ramp_box.size = box.size
		ramp_shape.shape = ramp_box
		ramp_shape.position = ramp.position
		ramp_shape.rotation = ramp.rotation
		node.add_child(ramp_shape)


func _piece(body: StaticBody3D, at: Vector3, size: Vector3, look: Material, solid: bool) -> void:
	var shown := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	shown.mesh = box
	shown.material_override = look
	shown.position = at
	body.add_child(shown)
	if solid:
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		shape.position = at
		body.add_child(shape)


func map_markers() -> Array:
	var list: Array = []
	for item in docks:
		var dock: Dictionary = item
		var shore: Vector3 = dock["shore"]
		list.append({"at": Vector2(shore.x, shore.z), "kind": "dock", "name": dock["name"],
				"info": "A dock with boat races and a fuel pump.", "done": false})
	return list


# --- Boats -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var started := Profiler.start()
	_physics_tick(delta)
	Profiler.add("traffic", started)


func _physics_tick(delta: float) -> void:
	if terrain == null or player == null:
		return
	var summer: bool = weather == null or weather.season_name() == "summer"
	_timer -= delta
	if _timer <= 0.0:
		_timer = 2.0
		var here := Origin.to_map(player.global_position)
		for index in range(_boats.size() - 1, -1, -1):
			var boat: Dictionary = _boats[index]
			var at: Vector3 = boat["at"]
			if Vector2(at.x, at.z).distance_to(Vector2(here.x, here.z)) > DROP or (not summer and not bool(boat["sinking"])):
				_drop(index)
		if enabled and summer and _boats.size() < MAX_BOATS:
			_top_up(here)
	for index in range(_boats.size() - 1, -1, -1):
		if not _run(_boats[index], delta):
			_drop(index)


func _top_up(here: Vector3) -> void:
	for attempt in 6:
		var spot: Vector2
		if not docks.is_empty() and _random.randf() < 0.3:
			var dock: Dictionary = docks[_random.randi() % docks.size()]
			var water: Vector3 = dock["water"]
			spot = Vector2(water.x, water.z)
		else:
			var angle := _random.randf() * TAU
			spot = Vector2(here.x, here.z) + Vector2(cos(angle), sin(angle)) * _random.randf_range(500.0, NEAR)
		if Vector2(here.x, here.z).distance_to(spot) > NEAR or not terrain.is_lake(spot.x, spot.y):
			continue
		if not _open_water(spot, 25.0):
			continue
		var roll := _random.randf()
		_add_boat("sail" if roll < 0.4 else ("speed" if roll < 0.7 else "fishing"), spot)
		return


func _open_water(spot: Vector2, margin: float) -> bool:
	for index in 8:
		var angle := TAU * index / 8.0
		if not terrain.is_lake(spot.x + cos(angle) * margin, spot.y + sin(angle) * margin):
			return false
	return true


func _add_boat(kind: String, spot: Vector2) -> void:
	var spec: Array = KINDS[kind]
	var length: float = spec[0]
	var width: float = spec[1]
	var body := AnimatableBody3D.new()
	body.name = "Boat"
	body.collision_layer = Units.LAYER_BODIES
	body.collision_mask = 0
	body.sync_to_physics = false
	body.set_meta("structure", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 1.4, length)
	shape.shape = box
	shape.position = Vector3(0.0, 0.3, 0.0)
	body.add_child(shape)
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh(kind)
	body.add_child(hull)
	var sail: Node3D = null
	if kind == "sail":
		sail = Node3D.new()
		sail.position = Vector3(0.0, 1.0, -0.6)
		body.add_child(sail)
		var mast := MeshInstance3D.new()
		var pole := CylinderMesh.new()
		pole.top_radius = 0.08
		pole.bottom_radius = 0.1
		pole.height = 11.0
		mast.mesh = pole
		mast.position = Vector3(0.0, 5.5, 0.0)
		sail.add_child(mast)
		var cloth := MeshInstance3D.new()
		cloth.mesh = _sail_mesh()
		sail.add_child(cloth)
	add_child(body)
	var at := Vector3(spot.x, MapInfo.LAKE_Y, spot.y)
	body.global_position = Origin.to_world(at)
	var boat := {"kind": kind, "body": body, "at": at, "heading": _random.randf() * TAU, "speed": 0.0,
			"target": at, "wait": 0.0, "health": float(spec[2]), "sinking": false, "sink": 0.0, "sail": sail,
			"tack": 1.0, "tack_time": 0.0, "sound": null, "wake": null}
	_pick_target(boat)
	if kind == "speed" or kind == "fishing":
		var sound := Sound.make_loop("boat_loop", "Machines")
		if sound != null:
			sound.unit_size = 8.0 if kind == "speed" else 4.0
			sound.max_distance = 600.0
			sound.pitch_scale = 1.3 if kind == "speed" else 0.8
			body.add_child(sound)
			sound.play()
			boat["sound"] = sound
	if kind == "speed":
		var wake := _make_wake()
		body.add_child(wake)
		wake.position = Vector3(0.0, -0.2, length * 0.5)
		boat["wake"] = wake
	_boats.append(boat)


func _pick_target(boat: Dictionary) -> void:
	var at: Vector3 = boat["at"]
	for attempt in 12:
		var reach := 1500.0 if boat["kind"] == "speed" else 700.0
		var angle := _random.randf() * TAU
		var spot := Vector2(at.x, at.z) + Vector2(cos(angle), sin(angle)) * _random.randf_range(reach * 0.3, reach)
		if not terrain.is_lake(spot.x, spot.y) or not _open_water(spot, 20.0):
			continue
		var clear := true
		for step in 12:
			var probe := Vector2(at.x, at.z).lerp(spot, float(step) / 12.0)
			if not terrain.is_lake(probe.x, probe.y):
				clear = false
				break
		if clear:
			boat["target"] = Vector3(spot.x, MapInfo.LAKE_Y, spot.y)
			return
	boat["target"] = at


## Moves one boat a tick. False when it is gone.
func _run(boat: Dictionary, delta: float) -> bool:
	var body: AnimatableBody3D = boat["body"]
	if not is_instance_valid(body):
		return false
	var at: Vector3 = boat["at"]
	if bool(boat["sinking"]):
		boat["sink"] = float(boat["sink"]) + delta
		at.y -= delta * 0.6
		boat["at"] = at
		body.global_transform = Transform3D(Basis.from_euler(Vector3(float(boat["sink"]) * 0.08, float(boat["heading"]), float(boat["sink"]) * 0.05)),
				Origin.to_world(at))
		return float(boat["sink"]) < 12.0
	var spec: Array = KINDS[boat["kind"]]
	var top: float = spec[3]
	var target: Vector3 = boat["target"]
	var to_target := Vector2(target.x - at.x, target.z - at.z)
	var wanted_speed := top
	if float(boat["wait"]) > 0.0:
		boat["wait"] = float(boat["wait"]) - delta
		wanted_speed = 0.0
	elif to_target.length() < 25.0:
		if boat["kind"] == "fishing":
			boat["wait"] = _random.randf_range(30.0, 90.0)
		_pick_target(boat)
	var want_heading := atan2(to_target.x, -to_target.y)
	if boat["kind"] == "sail" and weather != null:
		# The wind blows toward wind_angle; a boat cannot point within 45° of where it comes from.
		var from_wind := float(weather.wind_angle) + PI
		var wind_heading := _compass(from_wind)
		var off := wrapf(want_heading - wind_heading, -PI, PI)
		boat["tack_time"] = float(boat["tack_time"]) - delta
		if absf(off) < deg_to_rad(45.0):
			if float(boat["tack_time"]) <= 0.0:
				boat["tack"] = -float(boat["tack"])
				boat["tack_time"] = _random.randf_range(40.0, 80.0)
			want_heading = wind_heading + deg_to_rad(50.0) * float(boat["tack"])
			off = deg_to_rad(50.0)
		var wind: float = weather.wind_speed
		wanted_speed = clampf(wind * 0.55, 1.0, top) * clampf(sin(absf(off)) * 1.1, 0.25, 1.0) if float(boat["wait"]) <= 0.0 else 0.0
	# Don't run into things in front.
	if _blocked(boat):
		wanted_speed = 0.0
	var turn := wrapf(want_heading - float(boat["heading"]), -PI, PI)
	var turn_rate := 0.35 if boat["kind"] == "speed" else 0.15
	boat["heading"] = float(boat["heading"]) + clampf(turn, -turn_rate * delta, turn_rate * delta)
	boat["speed"] = move_toward(float(boat["speed"]), wanted_speed, (3.0 if boat["kind"] == "speed" else 0.8) * delta)
	var heading: float = boat["heading"]
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	var next := at + forward * float(boat["speed"]) * delta
	if not terrain.is_lake(next.x, next.z):
		boat["speed"] = 0.0
		_pick_target(boat)
		next = at
	# Ride the waves: height and tilt from the water at bow, stern and sides.
	var length: float = spec[0]
	var width: float = spec[1]
	var world := Origin.to_world(next)
	var bow := Weather.water_height(world + forward * length * 0.4)
	var stern := Weather.water_height(world - forward * length * 0.4)
	var side_vector := forward.cross(Vector3.UP)
	var port := Weather.water_height(world - side_vector * width * 0.5)
	var starboard := Weather.water_height(world + side_vector * width * 0.5)
	next.y = (bow + stern + port + starboard) * 0.25 - 0.15
	var pitch := atan2(bow - stern, length * 0.8)
	if boat["kind"] == "speed":
		pitch += clampf(float(boat["speed"]) / 18.0, 0.0, 1.0) * 0.12
	var roll := atan2(starboard - port, width)
	boat["at"] = next
	body.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, -heading, roll)), Origin.to_world(next))
	var sail: Node3D = boat["sail"]
	if sail != null and weather != null:
		var across := wrapf(_compass(float(weather.wind_angle)) - heading, -PI, PI)
		sail.rotation.y = clampf(-across * 0.5, -1.2, 1.2)
	var wake: GPUParticles3D = boat["wake"]
	if wake != null:
		wake.emitting = float(boat["speed"]) > 4.0
	return true


## A heading measured like a compass (0 north, -Z) from an angle measured
## from +X toward +Z.
static func _compass(angle: float) -> float:
	return atan2(cos(angle), -sin(angle))


func _blocked(boat: Dictionary) -> bool:
	var body: AnimatableBody3D = boat["body"]
	var heading: float = boat["heading"]
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	var from := body.global_position + Vector3(0.0, 0.5, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * (12.0 + float(boat["speed"]) * 2.0),
			Units.LAYER_BODIES | Units.LAYER_PLAYER)
	query.exclude = [body.get_rid()]
	return not body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _drop(index: int) -> void:
	var boat: Dictionary = _boats[index]
	if is_instance_valid(boat["body"]):
		(boat["body"] as Node).queue_free()
	_boats.remove_at(index)


func boat_count() -> int:
	return _boats.size()


# --- Damage (combat.gd treats boats like buildings) --------------------------------------

func _boat_of(collider: Object) -> Dictionary:
	for boat in _boats:
		if boat["body"] == collider:
			return boat
	return {}


func damage_piece(collider: Object, _shape: int, amount: float) -> Array:
	var boat := _boat_of(collider)
	if boat.is_empty() or bool(boat["sinking"]):
		return []
	boat["health"] = float(boat["health"]) - amount
	if float(boat["health"]) <= 0.0:
		_sink(boat)
	return []


func blast(centre: Vector3, radius: float, peak: float) -> Array:
	for boat in _boats:
		var body: AnimatableBody3D = boat["body"]
		if not is_instance_valid(body) or bool(boat["sinking"]):
			continue
		var distance := body.global_position.distance_to(centre)
		if distance < radius + 4.0:
			boat["health"] = float(boat["health"]) - peak * (1.0 - clampf(distance / (radius + 4.0), 0.0, 1.0))
			if float(boat["health"]) <= 0.0:
				_sink(boat)
	return []


func _sink(boat: Dictionary) -> void:
	boat["sinking"] = true
	boat["speed"] = 0.0
	var sound: Node = boat["sound"]
	if sound != null and is_instance_valid(sound):
		sound.queue_free()
	var body: AnimatableBody3D = boat["body"]
	if is_instance_valid(body):
		Sound.play_at("splash", body.global_position, 4.0, 200.0)


func reset_damage() -> void:
	pass


# --- Looks ------------------------------------------------------------------------------

var _hulls: Dictionary = {}
var _sail_cloth: Mesh = null


func _hull_mesh(kind: String) -> Mesh:
	if _hulls.has(kind):
		return _hulls[kind]
	var spec: Array = KINDS[kind]
	var length: float = spec[0]
	var width: float = spec[1]
	var color: Color = spec[4]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(surface, Vector3(0.0, 0.1, length * 0.08), Vector3(width, 0.9, length * 0.84), color)
	_box(surface, Vector3(0.0, 0.05, -length * 0.42), Vector3(width * 0.55, 0.8, length * 0.16), color)
	_box(surface, Vector3(0.0, -0.32, 0.0), Vector3(width * 0.9, 0.12, length * 0.95), Color(0.15, 0.15, 0.18))
	_box(surface, Vector3(0.0, 0.58, length * 0.1), Vector3(width * 0.92, 0.08, length * 0.7), Color(0.7, 0.6, 0.45))
	match kind:
		"speed":
			_box(surface, Vector3(0.0, 0.85, -0.3), Vector3(width * 0.7, 0.45, 1.0), Color(0.15, 0.2, 0.3))
			_box(surface, Vector3(0.0, 0.5, length * 0.47), Vector3(0.5, 0.9, 0.5), Color(0.1, 0.1, 0.1))
		"fishing":
			_box(surface, Vector3(0.0, 1.3, 0.4), Vector3(width * 0.7, 1.4, 2.0), Color(0.95, 0.95, 0.92))
			_box(surface, Vector3(0.0, 0.5, length * 0.47), Vector3(0.4, 0.7, 0.4), Color(0.1, 0.1, 0.1))
			_box(surface, Vector3(0.6, 1.8, length * 0.35), Vector3(0.05, 2.6, 0.05), Color(0.3, 0.3, 0.3))
		"sail":
			_box(surface, Vector3(0.0, 0.85, 0.9), Vector3(width * 0.6, 0.5, 2.0), Color(0.85, 0.85, 0.82))
	surface.generate_normals()
	var mesh := surface.commit()
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.5
	mesh.surface_set_material(0, look)
	_hulls[kind] = mesh
	return mesh


func _sail_mesh() -> Mesh:
	if _sail_cloth != null:
		return _sail_cloth
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color(0.97, 0.97, 0.94))
	for point in [Vector3(0.0, 0.6, 0.0), Vector3(0.0, 10.8, 0.0), Vector3(0.0, 0.6, 3.6)]:
		surface.add_vertex(point)
	surface.generate_normals()
	var mesh := surface.commit()
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, look)
	_sail_cloth = mesh
	return mesh


func _make_wake() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 60
	particles.lifetime = 4.0
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.0, 1.0)
	process.spread = 30.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.5
	process.gravity = Vector3.ZERO
	process.scale_min = 1.0
	process.scale_max = 2.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 3.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.7))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	particles.process_material = process
	if _wake_mesh == null:
		_wake_mesh = QuadMesh.new()
		_wake_mesh.size = Vector2(1.5, 1.5)
		_wake_mesh.orientation = PlaneMesh.FACE_Y
		var look := StandardMaterial3D.new()
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.vertex_color_use_as_albedo = true
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wake_mesh.material = look
	particles.draw_pass_1 = _wake_mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


static func _box(surface: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var half := size * 0.5
	var corners := []
	for index in 8:
		corners.append(centre + Vector3(half.x if index & 1 else -half.x, half.y if index & 2 else -half.y, half.z if index & 4 else -half.z))
	surface.set_color(color)
	for face in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		var f: Array = face
		for index in [0, 2, 1, 0, 3, 2]:
			surface.add_vertex(corners[f[index]])
