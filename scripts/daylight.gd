extends Node3D
## Day and night. A whole day lasts CYCLE seconds of play: ten minutes of
## daylight from sunrise to sunset, then ten minutes of night under the moon
## and stars. The sun rises in the east, crosses the southern sky (at most 60°
## up, about right for a Montana summer) and sets in the west; the moon
## follows the opposite path.
##
## This node owns the sky, the sun, the moon and the haze. It also turns on
## everything in the "night_lights" group (runway lights) after dusk.
##
## Settings can hold it at day or at night, and jump to a time.

const SKY_SHADER = preload("res://shaders/sky.gdshader")
const Weather = preload("res://scripts/weather.gd")

const CYCLE := 1200.0            # seconds in a whole day and night
const START := 0.08              # where in the day a new game starts: 08:00
const MAX_SUN_HEIGHT := 60.0     # degrees above the southern horizon at noon
const FIXED_DAY := 0.2           # the time held by "Always day": 10:48
const FIXED_NIGHT := 0.75        # the time held by "Always night": midnight
const SKY_EVERY := 0.5           # seconds between updates of the sky's colours
const MOON_MONTH := 8.0          # game days from one full moon to the next

const DAY_TOP := Color(0.22, 0.47, 0.88)
const DAY_HORIZON := Color(0.68, 0.82, 0.95)
const DAY_GROUND := Color(0.30, 0.42, 0.30)
const DUSK_TOP := Color(0.24, 0.32, 0.62)
const DUSK_HORIZON := Color(0.96, 0.62, 0.38)
const NIGHT_TOP := Color(0.010, 0.016, 0.045)
const NIGHT_HORIZON := Color(0.04, 0.06, 0.12)
const NIGHT_GROUND := Color(0.02, 0.03, 0.03)
const DAY_AMBIENT := Color(0.62, 0.70, 0.82)
const NIGHT_AMBIENT := Color(0.10, 0.12, 0.21)
const DAY_FOG := Color(0.70, 0.80, 0.90)
const DUSK_FOG := Color(0.85, 0.62, 0.48)
const NIGHT_FOG := Color(0.03, 0.04, 0.08)

var mode := "cycle"              # "cycle", "day" or "night"
var day_fraction := START        # 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight

var environment: Environment
var _sky_material: ShaderMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky_timer := 0.0
var _lights_on := false
var _cloud_shift := Vector2.ZERO
var _last_flash := 0.0
## Set by disasters.gd while a volcano erupts: [direction toward the ash in
## the world, how thick it is here, 0 to 1].
var ash_direction := Vector3.ZERO
var ash_amount := 0.0
## Set by caves.gd: 1 deep in a cave, where no daylight reaches.
var underground := 0.0


func _ready() -> void:
	add_to_group("daylight")
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Haze, so the far mountains fade into the sky.
	environment.fog_enabled = true
	environment.fog_density = 0.00005
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.4

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 250.0
	add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.62, 0.72, 1.0)
	_moon.shadow_enabled = false
	add_child(_moon)
	_apply(true)


func set_shadows(on: bool) -> void:
	_sun.shadow_enabled = on


func set_mode(new_mode: String) -> void:
	mode = new_mode if ["cycle", "day", "night"].has(new_mode) else "cycle"
	if mode == "day":
		day_fraction = FIXED_DAY
	elif mode == "night":
		day_fraction = FIXED_NIGHT
	_apply(true)


## Jumps to a time of day: 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight.
func set_time(fraction: float) -> void:
	day_fraction = fposmod(fraction, 1.0)
	_apply(true)


## The time as a 24-hour clock, sunrise at 06:00.
func clock_text() -> String:
	var hours := fposmod(6.0 + day_fraction * 24.0, 24.0)
	return "%02d:%02d" % [int(hours), int(fposmod(hours * 60.0, 60.0))]


## 0 in daylight, 1 at full night, between at dusk and dawn.
func night_amount() -> float:
	return 1.0 - smoothstep(-0.16, 0.02, _sun_direction().y)


func is_night() -> bool:
	return _sun_direction().y < -0.02


func _process(delta: float) -> void:
	if mode == "cycle":
		day_fraction = fposmod(day_fraction + delta / CYCLE, 1.0)
	var weather: Node = Weather.instance
	if weather != null:
		var blowing: Vector3 = Weather.wind_at(Vector3(0.0, 300.0, 0.0))
		_cloud_shift += Vector2(blowing.x, blowing.z) * delta * 0.00025
		if absf(float(weather.flash) - _last_flash) > 0.002:
			_last_flash = float(weather.flash)
			_sky_material.set_shader_parameter("flash", _last_flash)
	_sky_timer -= delta
	_apply(_sky_timer <= 0.0)


## Toward the sun, as a direction in the world: east at sunrise, south and
## high at noon, west at sunset, below the horizon at night.
func _sun_direction() -> Vector3:
	var angle := day_fraction * TAU
	var tilt := deg_to_rad(MAX_SUN_HEIGHT)
	return Vector3(cos(angle), sin(angle) * sin(tilt), sin(angle) * cos(tilt)).normalized()


func _apply(colours_too: bool) -> void:
	var toward_sun := _sun_direction()
	var height := toward_sun.y
	var day := smoothstep(-0.10, 0.15, height)          # 1 in full day
	var night := 1.0 - smoothstep(-0.16, 0.02, height)  # 1 in full night
	var dusk := (1.0 - smoothstep(0.0, 0.32, absf(height))) * (1.0 - night)   # 1 at sunrise and sunset

	# The sun shines while it is up; the moon at night. Each points along -Z.
	_sun.visible = height > -0.06
	if _sun.visible:
		_sun.basis = Basis.looking_at(-toward_sun, Vector3.UP if absf(height) < 0.99 else Vector3.FORWARD)
		_sun.light_energy = 1.2 * smoothstep(-0.04, 0.22, height) * _shade()
		_sun.light_color = Color(1.0, 0.68, 0.42).lerp(Color(1.0, 0.98, 0.95), smoothstep(0.02, 0.35, height))
	var toward_moon := -toward_sun
	_moon.visible = night > 0.01
	if _moon.visible:
		_moon.basis = Basis.looking_at(-toward_moon, Vector3.UP if absf(toward_moon.y) < 0.99 else Vector3.FORWARD)
		_moon.light_energy = 0.14 * night * _shade() * (0.25 + 0.75 * moon_lit())

	var lights := night > 0.3
	if lights != _lights_on:
		_lights_on = lights
		for node in get_tree().get_nodes_in_group("night_lights"):
			(node as Node3D).visible = lights

	if not colours_too:
		return
	_sky_timer = SKY_EVERY
	var top := NIGHT_TOP.lerp(DAY_TOP, day).lerp(DUSK_TOP, dusk * 0.6)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.8)
	var ground := NIGHT_GROUND.lerp(DAY_GROUND, day)
	_sky_material.set_shader_parameter("top_color", Vector3(top.r, top.g, top.b))
	_sky_material.set_shader_parameter("horizon_color", Vector3(horizon.r, horizon.g, horizon.b))
	_sky_material.set_shader_parameter("ground_color", Vector3(ground.r, ground.g, ground.b))
	_sky_material.set_shader_parameter("sun_direction", toward_sun)
	_sky_material.set_shader_parameter("moon_direction", toward_moon)
	_sky_material.set_shader_parameter("moon_phase", moon_phase())
	_sky_material.set_shader_parameter("night", night)
	environment.ambient_light_color = NIGHT_AMBIENT.lerp(DAY_AMBIENT, day)
	environment.ambient_light_energy = 1.0
	environment.fog_light_color = NIGHT_FOG.lerp(DAY_FOG, day).lerp(DUSK_FOG, dusk * 0.5)
	_apply_weather(day)


## Where the moon is in its month: 0 new, 0.5 full. A full moon on the first
## night of a new game.
func moon_phase() -> float:
	var weather: Node = Weather.instance
	var days := float(weather.day) if weather != null else 0.0
	return fposmod(0.5 + (days + day_fraction) / MOON_MONTH, 1.0)


## How much of the moon's face is lit, 0 to 1.
func moon_lit() -> float:
	return 0.5 - 0.5 * cos(moon_phase() * TAU)


## How much the weather (cloud, ash) and being underground cut the light.
func _shade() -> float:
	var weather: Node = Weather.instance
	var dark := 0.0
	if weather != null:
		dark = float(weather.darkness)
	return (1.0 - dark * 0.75) * (1.0 - ash_amount * 0.7) * (1.0 - underground)


func _apply_weather(day: float) -> void:
	var weather: Node = Weather.instance
	var cover := 0.1
	var dark := 0.0
	var haze := 0.0
	var rain := 0.0
	if weather != null:
		cover = weather.cloud
		dark = weather.darkness
		haze = weather.haze
		rain = weather.precipitation
	_sky_material.set_shader_parameter("cloud_cover", cover)
	_sky_material.set_shader_parameter("overcast", clampf(dark + ash_amount * 0.5, 0.0, 1.0))
	_sky_material.set_shader_parameter("cloud_shift", _cloud_shift)
	_sky_material.set_shader_parameter("ash", ash_direction * ash_amount)
	environment.ambient_light_energy = (1.0 - dark * 0.45) * (1.0 - ash_amount * 0.5) * (1.0 - underground * 0.85)
	environment.fog_density = 0.00005 + haze * 0.0028 + rain * 0.0004 + ash_amount * 0.002
	var grey := Color(0.5, 0.53, 0.57).lerp(NIGHT_FOG, 1.0 - day)
	environment.fog_light_color = environment.fog_light_color.lerp(grey, clampf(dark + haze * 0.6, 0.0, 1.0))
	if ash_amount > 0.0:
		environment.fog_light_color = environment.fog_light_color.lerp(Color(0.22, 0.18, 0.15), ash_amount)
