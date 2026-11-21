extends Node
## Natural disasters: tornadoes, hurricanes, tsunamis, earthquakes and the
## volcano. Each can be started from the Weather window; with "Random
## disasters" on, one strikes now and then on its own (every 20 to 40
## minutes, never in the first 10) and is announced with where it is.
##
## Tornado: see tornado.gd. It forms a few kilometres away, heading roughly
## toward you.
## Hurricane: four minutes of 46 m/s winds, driving rain and 3.5 m waves.
## Tsunami: an earthquake under the lake, then a wave 14 m high spreading
## from it at 55 m/s, which lifts and carries boats and runs up the shore.
## Earthquake: the ground shakes for a few seconds; loose things hop about.
## Volcano: the tallest mountain (terrain.gd hollows its crater). It
## rumbles, blows, throws glowing bombs kilometres that burst where they
## land, sends rivers of lava down the steepest ground, and an ash cloud
## darkens the sky downwind for a few minutes.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Sound = preload("res://scripts/sound.gd")
const Player = preload("res://scripts/player.gd")
const Tornado = preload("res://scripts/tornado.gd")
const Terrain = preload("res://scripts/terrain.gd")

const FIRST_RANDOM := 600.0          # seconds into a game before the first random disaster
const RANDOM_GAP := Vector2(1200.0, 2400.0)
const HURRICANE_TIME := 240.0
const ERUPTION_TIME := 150.0
const FLOWS := 6                     # rivers of lava from one eruption
const FLOW_STEP := 12.0              # metres between points along a lava river
const FLOW_LENGTH := 4000.0
const MAX_BOMBS := 48
const CRATER_HEAT := 25.0           # HP a second inside the crater
const LAVA_BURN := 250.0            # HP a second touching the crater's lava
const CRATER_HEADROOM := 300.0      # metres above the rim the heat reaches
## How fast a part's own health goes in the crater, per second, by material:
## low-melting stuff goes fastest, refractory metals slowest.
const HEAT_SHARE := {"foam": 0.3, "balsa": 0.2, "cork": 0.2, "wood": 0.12, "oak": 0.12, "plastic": 0.2,
		"rubber": 0.2, "nylon": 0.2, "acrylic": 0.2, "ice": 1.0, "lead": 0.15, "magnesium": 0.12,
		"steel": 0.025, "titanium": 0.02, "tungsten": 0.01, "cast_iron": 0.03, "diamond": 0.02, "granite": 0.02,
		"concrete": 0.03, "brick": 0.03}

## Disasters strike on their own now and then. The settings switch it.
static var random_events := true

var weather: Node = null             # weather.gd
var terrain: Node = null             # terrain.gd
var daylight: Node = null            # daylight.gd, for the ash in the sky
var game_hud: Node = null            # game_hud.gd, for warnings
var player: Node3D = null            # player.gd
var noise: Texture2D = null          # for the tornado's swirl

var _random := RandomNumberGenerator.new()
var _clock := 0.0
var _next_random := 0.0
var _tornadoes: Array = []
var _hurricane_left := 0.0
var _quake_left := 0.0
var _quake_strength := 0.0
var _quake_at := Vector3.ZERO        # map position of the quake's middle
var _quake_tick := 0.0
var _tsunami_heard := false
var _eruption := -1.0                # seconds since the eruption began, below 0 when there is none
var _bombs: Array = []               # {"at": map position, "speed": velocity, "node": MeshInstance3D}
var _bomb_timer := 0.0
var _flows: Array = []               # {"points": PackedVector3Array (map), "front": metres, "width", "node", "speed"}
var _flow_timer := 0.0
var _burn_timer := 0.0
var _plume: GPUParticles3D = null
var _embers: GPUParticles3D = null
var _glow: OmniLight3D = null
var _bomb_mesh: Mesh = null
var _lava_look: StandardMaterial3D = null
var _crater_tick := 0.0
var _heat_warned := -100.0


func _ready() -> void:
	_random.randomize()
	_next_random = FIRST_RANDOM + _random.randf_range(0.0, 600.0)


func _structures() -> Array:
	if terrain == null:
		return []
	return [terrain.towns, terrain.towers]


func _crater_map() -> Vector3:
	var at: Vector2 = Terrain.VOLCANO
	return Vector3(at.x, terrain.height_at(at.x, at.y), at.y)


## Where something is from the character, in words: "3.4 km north-east".
func _where(map_point: Vector2) -> String:
	if player == null:
		return ""
	var here := Origin.to_map(player.global_position)
	var off := map_point - Vector2(here.x, here.z)
	var distance := off.length()
	var bearing := fposmod(rad_to_deg(atan2(off.x, -off.y)), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var word: String = names[int(round(bearing / 45.0)) % 8]
	return "%.1f km %s of you" % [distance / 1000.0, word]


func _warn(title: String, line: String) -> void:
	if game_hud != null:
		game_hud.announce(title, line, 6.0, Color(1.0, 0.55, 0.2))


# --- Starting them ---------------------------------------------------------------------

## A tornado that forms a few kilometres away and heads roughly your way.
func start_tornado() -> void:
	if terrain == null or player == null:
		return
	var here := Origin.to_map(player.global_position)
	var angle := _random.randf() * TAU
	var distance := _random.randf_range(2500.0, 4500.0)
	var at := Vector2(here.x, here.z) + Vector2(cos(angle), sin(angle)) * distance
	var toward := (Vector2(here.x, here.z) - at).angle() + _random.randf_range(-0.35, 0.35)
	var tornado: Node = Tornado.new()
	tornado.name = "Tornado"
	add_child(tornado)
	tornado.setup(at, toward, terrain, _structures(), noise)
	_tornadoes.append(tornado)
	weather.sources.append(tornado)
	if weather.kind == "clear" or weather.kind == "cloudy" or weather.kind == "fog":
		weather.kind = "storm"
	_warn("TORNADO WARNING", "A tornado has touched down %s." % _where(at))


func start_hurricane() -> void:
	_hurricane_left = HURRICANE_TIME
	weather.kind = "hurricane"
	_warn("HURRICANE", "Winds over 45 m/s, driving rain and big waves for four minutes. Land and tie down.")


## An earthquake under the lake far out, and the wave it raises.
func start_tsunami() -> void:
	if terrain == null or player == null:
		return
	var here := Origin.to_map(player.global_position)
	var centre := Vector2(here.x, here.z)
	for attempt in 60:
		var angle := _random.randf() * TAU
		var distance := _random.randf_range(5000.0, 11000.0)
		var spot := Vector2(here.x, here.z) + Vector2(cos(angle), sin(angle)) * distance
		if terrain.is_lake(spot.x, spot.y):
			centre = spot
			break
	_quake(Vector3(centre.x, 0.0, centre.y), 0.8, 7.0)
	weather.start_tsunami(centre, 14.0)
	_tsunami_heard = false
	_warn("TSUNAMI WARNING", "An earthquake under the lake %s. A wave is coming: get to high ground." % _where(centre))


func start_earthquake() -> void:
	var here := Origin.to_map(player.global_position) if player != null else Vector3.ZERO
	_quake(here, 1.0, 9.0)
	_warn("EARTHQUAKE", "")


func start_eruption() -> void:
	if terrain == null or _eruption >= 0.0:
		return
	_eruption = 0.0
	var crater := _crater_map()
	_quake(crater, 1.2, 10.0)
	Sound.play_at("rumble", Origin.to_world(crater), 14.0, 3000.0)
	_warn("VOLCANO", "The volcano is waking up, %s. Stay clear of its slopes." % _where(Vector2(crater.x, crater.z)))


## Ends every disaster at once and clears the sky.
func calm_everything() -> void:
	for item in _tornadoes:
		if is_instance_valid(item):
			item.queue_free()
	_tornadoes.clear()
	weather.sources.clear()
	weather.tsunami = {}
	_hurricane_left = 0.0
	if weather.kind == "hurricane" or weather.kind == "storm":
		weather.kind = "clear"
	_quake_left = 0.0
	Player.camera_shake = 0.0
	_end_eruption(true)


func _quake(map_point: Vector3, strength: float, seconds: float) -> void:
	_quake_at = map_point
	_quake_strength = strength
	_quake_left = seconds
	if player != null:
		Sound.play_at("rumble", player.global_position + Vector3(0.0, -5.0, 0.0), 8.0 * strength, 400.0)


# --- Running them -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if random_events and _clock > _next_random:
		_next_random = _clock + _random.randf_range(RANDOM_GAP.x, RANDOM_GAP.y)
		var roll := _random.randf()
		if roll < 0.35:
			start_tornado()
		elif roll < 0.55:
			start_hurricane()
		elif roll < 0.75:
			start_tsunami()
		else:
			start_eruption()
	_run_tornadoes()
	if _hurricane_left > 0.0:
		_hurricane_left -= delta
		if _hurricane_left <= 0.0 and weather.kind == "hurricane":
			weather.kind = "storm"
	_run_quake(delta)
	_run_tsunami()
	if _eruption >= 0.0:
		_run_eruption(delta)
	_run_bombs(delta)
	_run_flows(delta)
	_crater_tick -= delta
	if _crater_tick <= 0.0:
		_run_crater(0.1 - _crater_tick)
		_crater_tick = 0.1


func _run_tornadoes() -> void:
	for index in range(_tornadoes.size() - 1, -1, -1):
		var tornado: Node = _tornadoes[index]
		if not is_instance_valid(tornado) or tornado.finished():
			weather.sources.erase(tornado)
			if is_instance_valid(tornado):
				tornado.queue_free()
			_tornadoes.remove_at(index)


## The ground shakes: the camera trembles (less the further away), and every
## loose body resting near the ground gets small kicks this way and that.
func _run_quake(delta: float) -> void:
	if _quake_left <= 0.0:
		return
	_quake_left -= delta
	var fade := clampf(_quake_left / 2.0, 0.0, 1.0)
	var distance := 0.0
	if player != null:
		var here := Origin.to_map(player.global_position)
		distance = Vector2(here.x - _quake_at.x, here.z - _quake_at.z).length()
	var felt := _quake_strength * fade * clampf(1.0 - distance / 20000.0, 0.15, 1.0)
	Player.camera_shake = felt * 0.25 if _quake_left > 0.0 else 0.0
	_quake_tick -= delta
	if _quake_tick > 0.0:
		return
	_quake_tick = 0.1
	for node in get_tree().get_nodes_in_group("combat"):
		var spawner: Node = node.spawner
		if spawner == null or not bool(spawner.spawned):
			continue
		for item in spawner.all_bodies():
			var body: RigidBody3D = item
			if not is_instance_valid(body) or body.freeze:
				continue
			if body.global_position.y - terrain.ground_at(body.global_position) > 4.0:
				continue
			var kick := Vector3(_random.randf_range(-1.0, 1.0), _random.randf_range(0.0, 0.6), _random.randf_range(-1.0, 1.0))
			body.sleeping = false
			body.apply_central_impulse(kick * body.mass * felt * 0.6)
	if _quake_left <= 0.0:
		Player.camera_shake = 0.0


func _run_tsunami() -> void:
	var wave: Dictionary = weather.tsunami
	if wave.is_empty() or player == null or _tsunami_heard:
		return
	var here := Origin.to_map(player.global_position)
	var r := Vector2(here.x, here.z).distance_to(wave["centre"])
	if absf(r - float(wave["radius"])) < 300.0 and float(wave["amp"]) > 2.0:
		_tsunami_heard = true
		Sound.play_at("wave_crash", player.global_position, 10.0, 300.0)


# --- The volcano ------------------------------------------------------------------------------

func _run_eruption(delta: float) -> void:
	var before := _eruption
	_eruption += delta
	var crater := _crater_map()
	var crater_world := Origin.to_world(crater)
	# Heat comes up in the first seconds, and dies away after.
	terrain.volcano_heat = clampf(maxf(0.15, minf(_eruption / 8.0, 1.0) * (1.0 - smoothstep(ERUPTION_TIME, ERUPTION_TIME + 60.0, _eruption))), 0.15, 1.0)
	if before < 8.0 and _eruption >= 8.0:
		_blow(crater_world)
	if _plume != null:
		_plume.global_position = crater_world + Vector3(0.0, 40.0, 0.0)
		_embers.global_position = crater_world + Vector3(0.0, 20.0, 0.0)
		_glow.global_position = crater_world + Vector3(0.0, 120.0, 0.0)
		var going := _eruption < ERUPTION_TIME
		_plume.emitting = going
		_embers.emitting = going
		_glow.light_energy = 8.0 * terrain.volcano_heat
	# Bombs while it is going.
	if _eruption > 8.0 and _eruption < ERUPTION_TIME:
		_bomb_timer -= delta
		if _bomb_timer <= 0.0:
			_bomb_timer = _random.randf_range(0.12, 0.45)
			_throw_bomb(crater)
	# The ash cloud, thick near the volcano, over the sky.
	if daylight != null and player != null:
		var here := Origin.to_map(player.global_position)
		var distance := Vector2(here.x - crater.x, here.z - crater.z).length()
		var thick := clampf(1.0 - distance / 22000.0, 0.0, 1.0) * clampf((_eruption - 8.0) / 20.0, 0.0, 1.0) \
				* (1.0 - smoothstep(ERUPTION_TIME, ERUPTION_TIME + 90.0, _eruption))
		daylight.ash_amount = thick * 0.85
		daylight.ash_direction = (crater_world + Vector3(0.0, 3000.0, 0.0) - player.global_position).normalized()
	if _eruption > ERUPTION_TIME + 180.0:
		_end_eruption(false)


## The blast that opens the eruption.
func _blow(crater_world: Vector3) -> void:
	Sound.play_at("eruption", crater_world, 20.0, 4000.0)
	if player != null:
		var distance := player.global_position.distance_to(crater_world)
		get_tree().create_timer(distance / 343.0).timeout.connect(func() -> void:
			_quake(Origin.to_map(crater_world), 0.6, 4.0))
	weather.flash = 0.6
	_plume = _make_plume()
	_embers = _make_embers()
	add_child(_plume)
	add_child(_embers)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.45, 0.15)
	_glow.omni_range = 3000.0
	_glow.omni_attenuation = 1.2
	_glow.shadow_enabled = false
	add_child(_glow)
	_start_flows()


func _end_eruption(at_once: bool) -> void:
	_eruption = -1.0
	if terrain != null:
		terrain.volcano_heat = 0.15
	if daylight != null:
		daylight.ash_amount = 0.0
	for node in [_plume, _embers, _glow]:
		if is_instance_valid(node):
			(node as Node).queue_free()
	_plume = null
	_embers = null
	_glow = null
	if at_once:
		for item in _bombs:
			var bomb: Dictionary = item
			if is_instance_valid(bomb["node"]):
				(bomb["node"] as Node).queue_free()
		_bombs.clear()
	for item in _flows:
		var flow: Dictionary = item
		if is_instance_valid(flow["node"]):
			(flow["node"] as Node).queue_free()
	_flows.clear()


func _make_plume() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 500
	particles.lifetime = 45.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-4000, -500, -4000), Vector3(8000, 6000, 8000))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 120.0
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 12.0
	process.initial_velocity_min = 60.0
	process.initial_velocity_max = 110.0
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 0.6
	process.scale_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.5))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	particles.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(260.0, 260.0)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_color = Color(0.2, 0.18, 0.17, 0.55)
	if noise != null:
		look.albedo_texture = noise
	puff.material = look
	particles.draw_pass_1 = puff
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


func _make_embers() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 400
	particles.lifetime = 6.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-1500, -500, -1500), Vector3(3000, 2000, 3000))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 60.0
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 35.0
	process.initial_velocity_min = 40.0
	process.initial_velocity_max = 120.0
	process.gravity = Vector3(0.0, -9.8, 0.0)
	particles.process_material = process
	var spark := QuadMesh.new()
	spark.size = Vector2(4.0, 4.0)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_color = Color(1.0, 0.55, 0.15)
	look.emission_enabled = true
	look.emission = Color(1.0, 0.45, 0.1)
	look.emission_energy_multiplier = 3.0
	spark.material = look
	particles.draw_pass_1 = spark
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


func _throw_bomb(crater: Vector3) -> void:
	if _bombs.size() >= MAX_BOMBS:
		return
	var angle := _random.randf() * TAU
	var tilt := deg_to_rad(_random.randf_range(8.0, 40.0))
	var speed := _random.randf_range(60.0, 170.0)
	var velocity := Vector3(cos(angle) * sin(tilt), cos(tilt), sin(angle) * sin(tilt)) * speed
	var size := _random.randf_range(1.0, 3.0)
	if _bomb_mesh == null:
		var ball := SphereMesh.new()
		ball.radius = 0.5
		ball.height = 1.0
		ball.radial_segments = 10
		ball.rings = 6
		var look := StandardMaterial3D.new()
		look.albedo_color = Color(0.3, 0.12, 0.05)
		look.emission_enabled = true
		look.emission = Color(1.0, 0.35, 0.05)
		look.emission_energy_multiplier = 2.5
		ball.material = look
		_bomb_mesh = ball
	var node := MeshInstance3D.new()
	node.mesh = _bomb_mesh
	node.scale = Vector3.ONE * size
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var start := crater + Vector3(0.0, 30.0, 0.0)
	node.global_position = Origin.to_world(start)
	_bombs.append({"at": start, "speed": velocity, "node": node, "size": size})


## Lava bombs fly as cannon shells do, in map positions, and burst where
## they come down: a blast of a few metres, and buildings, parts and the
## character near it hurt.
func _run_bombs(delta: float) -> void:
	for index in range(_bombs.size() - 1, -1, -1):
		var bomb: Dictionary = _bombs[index]
		var speed: Vector3 = bomb["speed"]
		speed += Vector3(0.0, -9.81, 0.0) * delta
		speed *= 1.0 - 0.002 * delta * speed.length()
		var at: Vector3 = (bomb["at"] as Vector3) + speed * delta
		bomb["speed"] = speed
		bomb["at"] = at
		var node: MeshInstance3D = bomb["node"]
		if is_instance_valid(node):
			node.global_position = Origin.to_world(at)
		var ground: float = maxf(terrain.height_at(at.x, at.z), MapInfo.LAKE_Y)
		if at.y <= ground or at.y < -500.0:
			_burst(Origin.to_world(Vector3(at.x, ground + 0.5, at.z)), float(bomb["size"]))
			if is_instance_valid(node):
				node.queue_free()
			_bombs.remove_at(index)


func _burst(world: Vector3, size: float) -> void:
	var radius := 6.0 + size * 3.0
	Sound.play_at("explosion", world, clampf(size * 3.0, 0.0, 9.0), 250.0, _random.randf_range(0.7, 1.0))
	for node in get_tree().get_nodes_in_group("combat"):
		node.damage_near(world, radius, 1200.0 * size)
	for item in _structures():
		if is_instance_valid(item):
			item.blast(world, radius, 1500.0 * size)
	if player != null:
		var distance := player.global_position.distance_to(world)
		if distance < radius * 1.5:
			player.hurt(90.0 * (1.0 - distance / (radius * 1.5)), "a lava bomb")


## The crater is always deadly: inside the bowl, up to CRATER_HEADROOM over
## its rim (much further while it erupts), the heat burns the character and
## every part of a build, and its lava kills or melts at a touch. Near the
## rim the screen glows and a warning comes first.
func _run_crater(delta: float) -> void:
	if terrain == null:
		return
	var centre: Vector2 = Terrain.VOLCANO
	var erupting := _eruption >= 0.0
	var reach: float = Terrain.CRATER_RADIUS * (2.2 if erupting else 1.0)
	var rim: float = terrain.height_at(centre.x + Terrain.CRATER_RADIUS, centre.y)
	var ceiling: float = rim + (1500.0 if erupting else CRATER_HEADROOM)
	var hot := 0.0
	if player != null and not bool(player.dead):
		var here := Origin.to_map(player.global_position)
		var off := Vector2(here.x, here.z).distance_to(centre)
		hot = clampf(1.0 - (off - reach) / (reach * 0.5), 0.0, 1.0) if here.y < ceiling + 100.0 else 0.0
		if off < reach * 0.95 and here.y < ceiling:
			var above: float = here.y - terrain.height_at(here.x, here.z)
			if above < 2.5 and off < Terrain.CRATER_RADIUS * 0.8:
				player.hurt(LAVA_BURN * delta, "the volcano's lava")
			else:
				player.hurt(CRATER_HEAT * delta, "the volcano's heat")
			hot = 1.0
		if hot > 0.2 and _clock - _heat_warned > 8.0:
			_heat_warned = _clock
			if game_hud != null:
				game_hud.announce("EXTREME HEAT", "Get out of the crater!", 3.0, Color(1.0, 0.45, 0.15))
	if game_hud != null:
		game_hud.heat = hot
	# Every build in or over the crater.
	for node in get_tree().get_nodes_in_group("combat"):
		var spawner: Node = node.spawner
		if spawner == null or not bool(spawner.spawned):
			continue
		var where: Variant = spawner.where()
		if where == null:
			continue
		var spot := Origin.to_map(where as Vector3)
		if Vector2(spot.x, spot.z).distance_to(centre) > reach + 200.0:
			continue
		var burns: Dictionary = {}
		var records: Dictionary = spawner.all_records()
		for key in spawner.live_parts():
			var uid := int(key)
			var place: Array = spawner.part_place(uid)
			if place.is_empty():
				continue
			var at := Origin.to_map(place[0] as Vector3)
			var off := Vector2(at.x, at.z).distance_to(centre)
			if off > reach * 0.95 or at.y > ceiling:
				continue
			var health: float = spawner.health_of(uid)
			var above: float = at.y - terrain.height_at(at.x, at.z)
			if above < 3.0 and off < Terrain.CRATER_RADIUS * 0.8:
				burns[uid] = health + 1.0e6      # lava: gone
			else:
				var material := str((records.get(uid, {}) as Dictionary).get("material", "steel"))
				var full: float = spawner.full_health_of(uid)
				if is_inf(full):
					continue
				burns[uid] = maxf(full, 50.0) * float(HEAT_SHARE.get(material, 0.05)) * delta
		if not burns.is_empty():
			spawner.damage_parts(burns)


## Rivers of lava down the steepest ground from the crater's rim.
func _start_flows() -> void:
	var crater := _crater_map()
	for index in FLOWS:
		var angle := TAU * float(index) / FLOWS + _random.randf_range(-0.4, 0.4)
		var rim: float = Terrain.CRATER_RADIUS * 0.95
		var at := Vector2(crater.x, crater.z) + Vector2(cos(angle), sin(angle)) * rim
		var points := PackedVector3Array()
		var travelled := 0.0
		var last := Vector2(cos(angle), sin(angle))
		while travelled < FLOW_LENGTH:
			var here: float = terrain.height_at(at.x, at.y)
			points.append(Vector3(at.x, here, at.y))
			if terrain.is_lake(at.x, at.y):
				break
			# Downhill, a little loath to turn sharply.
			var best := Vector2.ZERO
			var best_drop := -INF
			for step in 12:
				var turn := TAU * float(step) / 12.0
				var way := Vector2(cos(turn), sin(turn))
				var next: Vector2 = at + way * FLOW_STEP
				var drop: float = here - terrain.height_at(next.x, next.y) + way.dot(last) * 0.6
				if drop > best_drop:
					best_drop = drop
					best = way
			if best_drop < -0.5 and points.size() > 3:
				break   # a hollow: the lava pools here
			last = best
			at += best * FLOW_STEP
			travelled += FLOW_STEP
		var node := MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for point in points:
			low = low.min(Vector2(point.x, point.z))
			high = high.max(Vector2(point.x, point.z))
		_flows.append({"points": points, "front": 0.0, "width": _random.randf_range(14.0, 26.0),
				"node": node, "speed": _random.randf_range(3.0, 7.0), "bounds": Rect2(low, high - low).grow(40.0)})


func _lava_material() -> StandardMaterial3D:
	if _lava_look == null:
		_lava_look = StandardMaterial3D.new()
		_lava_look.albedo_color = Color(0.25, 0.08, 0.03)
		_lava_look.emission_enabled = true
		_lava_look.emission = Color(1.0, 0.32, 0.05)
		_lava_look.emission_energy_multiplier = 3.0
		_lava_look.roughness = 0.9
		_lava_look.cull_mode = BaseMaterial3D.CULL_DISABLED
		if noise != null:
			_lava_look.emission_texture = noise
			_lava_look.uv1_scale = Vector3(0.05, 0.05, 0.05)
			_lava_look.uv1_triplanar = true
	return _lava_look


## The lava creeps down at its own speed; its ribbon is drawn again twice a
## second. It cools (stops glowing) once the eruption is over. Anything in
## it burns.
func _run_flows(delta: float) -> void:
	if _flows.is_empty():
		return
	var cooling := 1.0
	if _eruption > ERUPTION_TIME:
		cooling = 1.0 - smoothstep(ERUPTION_TIME, ERUPTION_TIME + 150.0, _eruption)
	_lava_material().emission_energy_multiplier = 3.0 * cooling
	_flow_timer -= delta
	var redraw := _flow_timer <= 0.0
	if redraw:
		_flow_timer = 0.5
	for item in _flows:
		var flow: Dictionary = item
		if _eruption < ERUPTION_TIME:
			flow["front"] = float(flow["front"]) + float(flow["speed"]) * delta
		if redraw:
			_draw_flow(flow)
	_burn_timer -= delta
	if _burn_timer <= 0.0 and cooling > 0.2:
		_burn_timer = 0.25
		_burn_things()


func _draw_flow(flow: Dictionary) -> void:
	var points: PackedVector3Array = flow["points"]
	var shown := mini(int(float(flow["front"]) / FLOW_STEP) + 1, points.size())
	var node: MeshInstance3D = flow["node"]
	if shown < 2 or not is_instance_valid(node):
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width: float = flow["width"]
	var offset := Origin.offset
	for index in shown - 1:
		var a := points[index]
		var b := points[index + 1]
		var along := Vector2(b.x - a.x, b.z - a.z).normalized()
		var side := Vector3(-along.y, 0.0, along.x)
		var wa := width * 0.5 * (1.0 if index < shown - 4 else 0.6)
		var wb := width * 0.5 * (1.0 if index + 1 < shown - 4 else 0.4)
		var lift := Vector3(0.0, 1.0, 0.0)
		var corners := [a - side * wa + lift - offset, a + side * wa + lift - offset,
				b + side * wb + lift - offset, b - side * wb + lift - offset]
		for corner in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(corners[corner])
	var mesh := surface.commit()
	mesh.surface_set_material(0, _lava_material())
	node.mesh = mesh
	node.global_transform = Transform3D.IDENTITY


## Parts and the character in a river of lava burn.
func _burn_things() -> void:
	var targets: Array = []   # [world position, what]
	var lava_area := Rect2()
	for flow_item in _flows:
		var area: Rect2 = (flow_item as Dictionary)["bounds"]
		lava_area = area if lava_area.size == Vector2.ZERO else lava_area.merge(area)
	lava_area = lava_area.grow(300.0)
	for node in get_tree().get_nodes_in_group("combat"):
		var spawner: Node = node.spawner
		if spawner == null or not bool(spawner.spawned):
			continue
		var where: Variant = spawner.where()
		if where == null:
			continue
		var spot := Origin.to_map(where as Vector3)
		if not lava_area.has_point(Vector2(spot.x, spot.z)):
			continue
		for key in spawner.live_parts():
			var place: Array = spawner.part_place(int(key))
			if not place.is_empty():
				targets.append([place[0], [spawner, int(key)]])
	if player != null:
		targets.append([player.global_position, null])
	if targets.is_empty():
		return
	var burns: Dictionary = {}
	for flow_item in _flows:
		var flow: Dictionary = flow_item
		var points: PackedVector3Array = flow["points"]
		var shown := mini(int(float(flow["front"]) / FLOW_STEP) + 1, points.size())
		var reach: float = float(flow["width"]) * 0.5 + 1.0
		var bounds: Rect2 = flow["bounds"]
		for target in targets:
			var map := Origin.to_map(target[0])
			if not bounds.has_point(Vector2(map.x, map.z)):
				continue
			for index in range(0, shown, 2):
				var point := points[index]
				if absf(map.x - point.x) < reach and absf(map.z - point.z) < reach and map.y - point.y < 3.0:
					var what: Variant = target[1]
					if what == null:
						player.hurt(12.0, "lava")
					else:
						var pair: Array = what
						var spawner: Node = pair[0]
						if not burns.has(spawner):
							burns[spawner] = {}
						(burns[spawner] as Dictionary)[pair[1]] = 40.0
					break
	for spawner in burns:
		spawner.damage_parts(burns[spawner])
