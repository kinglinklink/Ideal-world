extends Node
## Weather, wind, waves and the seasons.
##
## The weather is one of: clear, cloudy, rain, storm, snow, fog, or (as a
## disaster) hurricane. Left on Auto it changes every few minutes, likelier
## to rain in spring and snow in winter; the Weather window can set it. Each
## kind sets the cloud cover, the rain or snow, the wind, the haze and how
## dark it gets, and the world eases between them over a minute or so.
##
## Wind blows everywhere with gusts, stronger higher up (the 1/7 power law,
## from 10 m), and adds to anything a disaster stirs up (tornadoes). Every
## aero panel, propeller, body outline and the character feel the air's
## speed relative to them, so a headwind gives lift and a tornado throws
## cars about. Waves on the lake grow with the wind: four swells, heights
## shared between them, travelling with the wind, the same formula in the
## water shader and in the buoyancy, so boats ride what you see.
##
## Seasons: a year lasts YEAR_DAYS days of the day-and-night cycle (10 days,
## 3 h 20 min of play), starting in early summer. The snow line comes down
## from the peaks in autumn to the lake shore in mid-winter and goes back up
## in spring; grass turns gold in autumn and some trees turn yellow.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Sound = preload("res://scripts/sound.gd")

const YEAR_DAYS := 10.0
const KINDS := ["clear", "cloudy", "rain", "storm", "snow", "fog", "hurricane"]
const NAMES := {"clear": "Clear", "cloudy": "Cloudy", "rain": "Rain", "storm": "Thunderstorm",
		"snow": "Snow", "fog": "Fog", "hurricane": "Hurricane"}
const SEASONS := ["spring", "summer", "autumn", "winter"]
## cloud cover, rain or snow (0 to 1), wind (m/s), gustiness, haze (0 to 1), darkness (0 to 1)
const PRESETS := {
	"clear": [0.08, 0.0, 3.0, 0.3, 0.0, 0.0],
	"cloudy": [0.6, 0.0, 6.0, 0.35, 0.1, 0.25],
	"rain": [0.88, 0.6, 8.0, 0.4, 0.3, 0.45],
	"storm": [1.0, 1.0, 15.0, 0.5, 0.4, 0.65],
	"snow": [0.92, 0.7, 5.0, 0.3, 0.5, 0.35],
	"fog": [0.5, 0.0, 1.0, 0.2, 1.0, 0.3],
	"hurricane": [1.0, 1.0, 46.0, 0.35, 0.6, 0.75],
}
const EASE_TIME := 45.0           # seconds for the weather to most of the way change
## The four swells: length (m), turn from the wind (radians), share of the height, phase.
const WAVES := [[41.0, 0.0, 0.45, 0.0], [27.0, 0.45, 0.25, 1.7], [63.0, -0.35, 0.2, 4.1], [19.0, 0.8, 0.1, 2.6]]
const TSUNAMI_WIDTH := 600.0      # metres, the width of the wave's hump: a wall of water, not a swell

static var instance: Node = null

var daylight: Node = null         # daylight.gd: the day count comes from its clock
var player: Node3D = null         # player.gd

var mode := "auto"                # "auto" or one of KINDS
var kind := "clear"               # the weather it is heading for
var season_mode := "auto"         # "auto" or one of SEASONS
var wind_override := -1.0         # m/s from the Weather window, or below 0 for the weather's own
var day := 0
var year_fraction := 0.32         # 0 start of spring, 0.25 summer, 0.5 autumn, 0.75 winter

# The weather as it is now, eased toward the preset of `kind`.
var cloud := 0.08
var precipitation := 0.0
var wind_speed := 3.0
var gust := 0.3
var haze := 0.0
var darkness := 0.0
var wind_angle := 0.8             # the way the wind blows toward, radians from +X toward +Z
var wave_height := 0.1            # metres, crest to trough of the biggest swells
var wave_phase := Vector4.ZERO    # each swell's phase now, for the water shader
var tsunami: Dictionary = {}      # {"centre": Vector2 map, "radius", "amp", "max", "speed"} while one runs
var sources: Array = []           # things that add wind: an object with wind_at(world position) -> Vector3
var flash := 0.0                  # lightning, 1 at a strike, fading fast
var snow_line := 2300.0           # metres above sea level
var autumn := 0.0                 # 0 to 1
var spring := 0.0
var cold := 0.0                   # 0 midsummer to 1 midwinter

var _time := 0.0
var _change := 300.0              # seconds to the next change on Auto
var _last_fraction := -1.0
var _strike := 6.0
var _rain: GPUParticles3D = null
var _snow: GPUParticles3D = null
var _bolt: MeshInstance3D = null
var _bolt_time := 0.0
var _random := RandomNumberGenerator.new()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	add_to_group("weather")
	_random.randomize()
	wind_angle = _random.randf() * TAU
	_rain = _make_rain()
	_snow = _make_snow()
	add_child(_rain)
	add_child(_snow)
	_bolt = MeshInstance3D.new()
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	_update_season()


# --- What other scripts ask --------------------------------------------------------

## The wind at a place in the world, in m/s: where the air is going.
static func wind_at(world: Vector3) -> Vector3:
	if instance == null:
		return Vector3.ZERO
	return instance._wind_at(world)


## The height of the lake's surface at a place in the world (game metres),
## with the waves and any tsunami.
static func water_height(world: Vector3) -> float:
	if instance == null:
		return MapInfo.LAKE_Y
	var map := Origin.to_map(world)
	return MapInfo.LAKE_Y + instance._wave_at(Vector2(map.x, map.z))


## How the water moves at a place: a tsunami's rush, outward from its middle.
static func water_velocity(world: Vector3) -> Vector3:
	if instance == null or instance.tsunami.is_empty():
		return Vector3.ZERO
	var map := Origin.to_map(world)
	return instance._tsunami_flow(Vector2(map.x, map.z))


## True where a tsunami has pushed the water up over the land.
static func flooded(world: Vector3, ground: float) -> bool:
	if instance == null or instance.tsunami.is_empty():
		return false
	var map := Origin.to_map(world)
	var rise: float = instance._tsunami_height(Vector2(map.x, map.z))
	return rise > 0.3 and MapInfo.LAKE_Y + rise > ground + 0.2


func season_name() -> String:
	return SEASONS[clampi(int(fposmod(year_fraction, 1.0) * 4.0), 0, 3)]


func _wind_at(world: Vector3) -> Vector3:
	var height := maxf(world.y - MapInfo.LAKE_Y, 2.0)
	var rise := clampf(pow(height / 10.0, 1.0 / 7.0), 0.6, 2.0)
	var map := Origin.to_map(world)
	var gusting := 1.0 + gust * (0.6 * sin(0.31 * _time + map.x * 0.0021) + 0.4 * sin(0.83 * _time + 1.7 + map.z * 0.0033))
	var speed := (wind_override if wind_override >= 0.0 else wind_speed) * gusting * rise
	var wind := Vector3(cos(wind_angle), 0.0, sin(wind_angle)) * speed
	for item in sources:
		if is_instance_valid(item):
			wind += item.wind_at(world)
	return wind


func _wave_at(xz: Vector2) -> float:
	var height := 0.0
	for index in 4:
		var wave: Array = WAVES[index]
		var angle: float = wind_angle + float(wave[1])
		var along := Vector2(cos(angle), sin(angle))
		var k: float = TAU / float(wave[0])
		height += wave_height * 0.5 * float(wave[2]) * sin(k * along.dot(xz) - wave_phase[index] + float(wave[3]))
	if not tsunami.is_empty():
		height += _tsunami_height(xz)
	return height


func _tsunami_height(xz: Vector2) -> float:
	if tsunami.is_empty():
		return 0.0
	var r: float = xz.distance_to(tsunami["centre"])
	var front: float = tsunami["radius"]
	var u := (r - front) / TSUNAMI_WIDTH
	var behind := (r - front + 2.2 * TSUNAMI_WIDTH) / TSUNAMI_WIDTH
	return float(tsunami["amp"]) * (exp(-u * u) - 0.35 * exp(-behind * behind))


func _tsunami_flow(xz: Vector2) -> Vector3:
	var away: Vector2 = xz - (tsunami["centre"] as Vector2)
	var r := away.length()
	if r < 1.0:
		return Vector3.ZERO
	var rise := maxf(_tsunami_height(xz), 0.0)
	# Water in a wave of height h on depth d moves at about c h / d; d taken as
	# 40 m. Capped at the wave's own speed, as a wall this tall would break.
	var flow: float = minf(float(tsunami["speed"]) * rise / 40.0, float(tsunami["speed"]))
	return Vector3(away.x / r, 0.0, away.y / r) * flow


# --- Changing it ---------------------------------------------------------------------

func set_mode(new_mode: String) -> void:
	mode = new_mode
	if mode != "auto" and PRESETS.has(mode):
		kind = mode
	else:
		mode = "auto"
		_change = 5.0


func set_season(new_mode: String) -> void:
	season_mode = new_mode if SEASONS.has(new_mode) else "auto"
	if season_mode != "auto":
		year_fraction = SEASONS.find(season_mode) * 0.25 + 0.12
	_update_season()


## Starts a tsunami from a map point, `amp` metres high.
func start_tsunami(centre: Vector2, amp: float) -> void:
	tsunami = {"centre": centre, "radius": 0.0, "amp": amp, "max": 26000.0, "speed": 70.0, "full": amp}


func _process(delta: float) -> void:
	_time += delta
	# The day count and the season, from the day-and-night clock.
	if daylight != null:
		var fraction: float = daylight.day_fraction
		if _last_fraction >= 0.0 and fraction < _last_fraction - 0.5:
			day += 1
		if season_mode == "auto" and _last_fraction >= 0.0:
			var moved := fposmod(fraction - _last_fraction, 1.0)
			if moved < 0.5:
				year_fraction = fposmod(year_fraction + moved / YEAR_DAYS, 1.0)
		_last_fraction = fraction
	_update_season()

	# On Auto, a new kind of weather now and then.
	if mode == "auto":
		_change -= delta
		if _change <= 0.0:
			_change = _random.randf_range(180.0, 480.0)
			kind = _pick_kind()
	elif kind != mode and kind != "hurricane":
		kind = mode
	var target: Array = PRESETS.get(kind, PRESETS["clear"])
	var step := 1.0 - exp(-delta / EASE_TIME * 2.0)
	var precip_target: float = target[1]
	cloud = lerpf(cloud, target[0], step)
	precipitation = lerpf(precipitation, precip_target, step)
	wind_speed = lerpf(wind_speed, target[2], step)
	gust = lerpf(gust, target[3], step)
	haze = lerpf(haze, target[4], step)
	darkness = lerpf(darkness, target[5], step)
	wind_angle = fposmod(wind_angle + sin(_time * 0.01) * 0.002 * delta, TAU)

	# Waves grow with the wind: about 1.2 m at 10 m/s, 3.5 m at most.
	var blowing := wind_override if wind_override >= 0.0 else wind_speed
	wave_height = lerpf(wave_height, clampf(0.012 * blowing * blowing, 0.06, 3.5), 1.0 - exp(-delta / 20.0))
	for index in 4:
		var length: float = WAVES[index][0]
		var omega := sqrt(9.81 * TAU / length)
		wave_phase[index] = fposmod(omega * _time, TAU)
	if not tsunami.is_empty():
		tsunami["radius"] = float(tsunami["radius"]) + float(tsunami["speed"]) * delta
		# Full height until it has run most of its way, then it dies down.
		var reach: float = tsunami["max"]
		tsunami["amp"] = float(tsunami["full"]) * (1.0 - smoothstep(0.8 * reach, reach, float(tsunami["radius"])))
		if float(tsunami["radius"]) >= float(tsunami["max"]):
			tsunami = {}

	Sound.rain_amount = precipitation if cold < 0.6 else precipitation * 0.25
	Sound.wind_speed = blowing
	_run_precipitation()
	_run_lightning(delta)


func _pick_kind() -> String:
	var roll := _random.randf()
	var wet := 0.25 + spring * 0.2 + autumn * 0.15
	if cold > 0.65:
		if roll < 0.35:
			return "snow"
		if roll < 0.5:
			return "fog"
		return "cloudy" if roll < 0.75 else "clear"
	if roll < 0.4:
		return "clear"
	if roll < 0.62:
		return "cloudy"
	if roll < 0.62 + wet * 0.6:
		return "rain"
	if roll < 0.62 + wet * 0.6 + 0.08:
		return "storm"
	return "fog" if roll > 0.95 else "cloudy"


func _update_season() -> void:
	var fraction := fposmod(year_fraction, 1.0)
	cold = 0.5 + 0.5 * cos(TAU * (fraction - 0.875))
	autumn = exp(-pow((fraction - 0.62) / 0.09, 2.0))
	spring = exp(-pow((fraction - 0.12) / 0.09, 2.0))
	snow_line = lerpf(2350.0, 650.0, smoothstep(0.3, 0.92, cold))


# --- Rain, snow and lightning -----------------------------------------------------------

func _make_rain() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Rain"
	particles.amount = 5000
	particles.lifetime = 2.6
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-90, -90, -90), Vector3(180, 180, 180))
	particles.emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(55.0, 2.0, 55.0)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 2.0
	process.initial_velocity_min = 17.0
	process.initial_velocity_max = 21.0
	process.gravity = Vector3.ZERO
	particles.process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.018, 0.8)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	look.billboard_keep_scale = true
	streak.material = look
	particles.draw_pass_1 = streak
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


func _make_snow() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Snow"
	particles.amount = 4000
	particles.lifetime = 14.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-70, -70, -70), Vector3(140, 140, 140))
	particles.emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(45.0, 2.0, 45.0)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 25.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.0
	process.gravity = Vector3(0.0, -0.4, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	particles.process_material = process
	var flake := QuadMesh.new()
	flake.size = Vector2(0.07, 0.07)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.material = look
	particles.draw_pass_1 = flake
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


func _run_precipitation() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var snowing := cold > 0.6 or Origin.to_map(eye).y + MapInfo.BASE_ELEVATION > snow_line
	var amount := clampf(precipitation, 0.0, 1.0)
	var wind := _wind_at(eye) if amount > 0.01 else Vector3.ZERO
	_rain.emitting = amount > 0.02 and not snowing
	_snow.emitting = amount > 0.02 and snowing
	if _rain.emitting:
		_rain.amount_ratio = amount
		_rain.global_position = eye + Vector3(0.0, 35.0, 0.0) - wind * 0.9
		var process: ParticleProcessMaterial = _rain.process_material
		process.direction = (Vector3(wind.x, -19.0, wind.z)).normalized()
	if _snow.emitting:
		_snow.amount_ratio = amount
		_snow.global_position = eye + Vector3(0.0, 18.0, 0.0) - wind * 5.0
		var snow_process: ParticleProcessMaterial = _snow.process_material
		snow_process.gravity = Vector3(wind.x * 0.25, -0.4, wind.z * 0.25)


## Thunderstorms and hurricanes: a strike every few seconds somewhere within
## a few kilometres, a flash, and thunder heard after the light, at the
## speed of sound.
func _run_lightning(delta: float) -> void:
	flash = maxf(flash - delta * 6.0, 0.0)
	if _bolt_time > 0.0:
		_bolt_time -= delta
		if _bolt_time <= 0.0:
			_bolt.visible = false
	if kind != "storm" and kind != "hurricane":
		return
	if precipitation < 0.7:
		return
	_strike -= delta
	if _strike > 0.0:
		return
	_strike = _random.randf_range(4.0, 16.0)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var angle := _random.randf() * TAU
	var distance := _random.randf_range(400.0, 5000.0)
	var ground := camera.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	ground.y = terrain.ground_at(ground) if terrain != null else MapInfo.LAKE_Y
	ground.y = maxf(ground.y, MapInfo.LAKE_Y)
	flash = clampf(1.6 - distance / 4000.0, 0.3, 1.0)
	_draw_bolt(ground)
	var delay := ground.distance_to(camera.global_position) / 343.0
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		Sound.play_at("thunder", ground, clampf(12.0 - distance / 500.0, -6.0, 10.0), 800.0, _random.randf_range(0.8, 1.1)))


func _draw_bolt(ground: Vector3) -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var top := ground + Vector3(_random.randf_range(-200, 200), 1500.0, _random.randf_range(-200, 200))
	var steps := 24
	for step in steps + 1:
		var t := float(step) / steps
		var at := top.lerp(ground, t)
		if step > 0 and step < steps:
			at += Vector3(_random.randf_range(-40, 40), 0.0, _random.randf_range(-40, 40)) * (1.0 - t * 0.5)
		lines.surface_add_vertex(at)
	lines.surface_end()
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(0.9, 0.92, 1.0)
	look.emission_enabled = true
	look.emission = Color(0.8, 0.85, 1.0)
	look.emission_energy_multiplier = 4.0
	lines.surface_set_material(0, look)
	_bolt.mesh = lines
	_bolt.visible = true
	_bolt_time = 0.18


## The weather written out for the Weather window and the readouts.
func describe() -> String:
	var blowing := wind_override if wind_override >= 0.0 else wind_speed
	var heading := fposmod(rad_to_deg(atan2(cos(wind_angle), -sin(wind_angle))) + 180.0, 360.0)
	return "Day %d   %s   %s   wind %.0f m/s from %03d°   waves %.1f m" % [
		day + 1, season_name().capitalize(), NAMES.get(kind, kind), blowing, int(heading), wave_height]
