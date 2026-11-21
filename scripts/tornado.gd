extends Node
## One tornado: a spinning funnel from the cloud base to the ground that
## wanders across the map for a few minutes. Far bigger than any real one,
## so you can watch it cross the far side of the lake: a funnel three
## kilometres tall and nearly a kilometre wide at the ground. Its winds
## (weather.gd adds them to the wind everywhere) do the damage to anything
## that flies or drives: up to 95 m/s round a 380 m core, air drawn in
## along the ground for kilometres, and a strong updraft in the middle, so
## cars are dragged in and lifted. Over the lake it is a waterspout, pale
## with spray. It smashes buildings and towers in its path, and roars.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Sound = preload("res://scripts/sound.gd")
const SWIRL_SHADER = preload("res://shaders/swirl.gdshader")

const CORE := 380.0           # metres: the radius of the fastest winds
const TOP_SPEED := 95.0       # m/s round the core
const UPDRAFT := 55.0         # m/s up the middle
const REACH := 3500.0         # metres beyond which it does nothing
const HEIGHT := 3000.0        # metres to the cloud base
const SPEED := 18.0           # m/s across the ground
const LIFE := 300.0           # seconds
const FUNNEL_TINT := Color(0.33, 0.33, 0.34)
const DUST_TINT := Color(0.42, 0.36, 0.28)
const SPOUT_TINT := Color(0.55, 0.58, 0.62)
const SPRAY_TINT := Color(0.82, 0.86, 0.9)

var place := Vector2.ZERO     # map x and z of the funnel's foot
var heading := 0.0            # radians, the way it travels
var terrain: Node = null      # terrain.gd
var structures: Array = []    # towns.gd, towers.gd
var age := 0.0
var strength := 0.0
var _ground := 0.0
var _visual: Node3D
var _funnel: MeshInstance3D
var _skirt: MeshInstance3D
var _debris: MultiMeshInstance3D
var _sound: AudioStreamPlayer3D
var _smash := 0.0
var _over_water := false
var _random := RandomNumberGenerator.new()


func setup(at: Vector2, travel: float, the_terrain: Node, the_structures: Array, noise: Texture2D) -> void:
	place = at
	heading = travel
	terrain = the_terrain
	structures = the_structures
	_random.randomize()
	_visual = Node3D.new()
	_visual.name = "Funnel"
	add_child(_visual)
	_funnel = _lathe(func(t: float) -> float: return 320.0 + 1800.0 * pow(t, 1.7), HEIGHT, 48, 30,
			FUNNEL_TINT, 0.7, noise)
	_visual.add_child(_funnel)
	_skirt = _lathe(func(t: float) -> float: return 700.0 + 500.0 * t, 320.0, 48, 6, DUST_TINT, 0.55, noise)
	_visual.add_child(_skirt)
	for shown in [_funnel, _skirt]:
		(shown as MeshInstance3D).extra_cull_margin = HEIGHT
	# Debris whirling round the foot.
	var pieces := MultiMesh.new()
	pieces.transform_format = MultiMesh.TRANSFORM_3D
	var chunk := BoxMesh.new()
	chunk.size = Vector3(7.0, 2.5, 5.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.25, 0.21, 0.17)
	chunk.material = dark
	pieces.mesh = chunk
	pieces.instance_count = 90
	_debris = MultiMeshInstance3D.new()
	_debris.multimesh = pieces
	_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_debris)
	_sound = Sound.make_loop("tornado_loop")
	if _sound != null:
		_sound.unit_size = 700.0
		_sound.max_distance = 20000.0
		_sound.volume_db = 6.0
		_visual.add_child(_sound)
		_sound.play()


## A lathed band, radius by `profile` from bottom (t 0) to top (t 1).
func _lathe(profile: Callable, height: float, sides: int, rings: int, tint: Color, opacity: float,
		noise: Texture2D) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rings:
		var t0 := float(ring) / rings
		var t1 := float(ring + 1) / rings
		var r0: float = profile.call(t0)
		var r1: float = profile.call(t1)
		for side in sides:
			var a0 := float(side) / sides * TAU
			var a1 := float(side + 1) / sides * TAU
			var p00 := Vector3(cos(a0) * r0, t0 * height, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, t0 * height, sin(a1) * r0)
			var p01 := Vector3(cos(a0) * r1, t1 * height, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, t1 * height, sin(a1) * r1)
			var u0 := float(side) / sides
			var u1 := float(side + 1) / sides
			for corner in [[p00, Vector2(u0, t0)], [p10, Vector2(u1, t0)], [p11, Vector2(u1, t1)],
					[p00, Vector2(u0, t0)], [p11, Vector2(u1, t1)], [p01, Vector2(u0, t1)]]:
				surface.set_uv(corner[1])
				surface.add_vertex(corner[0])
	var mesh := surface.commit()
	var look := ShaderMaterial.new()
	look.shader = SWIRL_SHADER
	look.set_shader_parameter("noise_map", noise)
	look.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	look.set_shader_parameter("opacity", opacity)
	mesh.surface_set_material(0, look)
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shown


func _tint(shown: MeshInstance3D, colour: Color) -> void:
	var look := shown.mesh.surface_get_material(0) as ShaderMaterial
	look.set_shader_parameter("tint", Vector3(colour.r, colour.g, colour.b))


func finished() -> bool:
	return age >= LIFE


## The tornado's own winds at a place in the world, in m/s.
func wind_at(world: Vector3) -> Vector3:
	if strength <= 0.0:
		return Vector3.ZERO
	var map := Origin.to_map(world)
	var away := Vector2(map.x - place.x, map.z - place.y)
	var r := away.length()
	if r > REACH:
		return Vector3.ZERO
	var height := world.y - _ground
	if height > HEIGHT * 1.2:
		return Vector3.ZERO
	var taper := 1.0 - smoothstep(REACH * 0.55, REACH, r)
	var round_speed := TOP_SPEED * strength * taper * (r / CORE if r < CORE else CORE / maxf(r, 1.0))
	var tangent := Vector2(-away.y, away.x) / maxf(r, 0.5)
	var inward := -away / maxf(r, 0.5)
	var drawn := round_speed * (0.45 if r > CORE * 0.5 else 0.1)
	var flat := tangent * round_speed + inward * drawn + Vector2(cos(heading), sin(heading)) * SPEED * strength
	var up := UPDRAFT * strength * exp(-pow(r / (CORE * 1.6), 2.0)) * (1.0 - smoothstep(HEIGHT * 0.8, HEIGHT * 1.2, height))
	return Vector3(flat.x, up, flat.y)


func _process(delta: float) -> void:
	age += delta
	strength = smoothstep(0.0, 15.0, age) * (1.0 - smoothstep(LIFE - 25.0, LIFE, age))
	heading += sin(age * 0.07) * 0.004 + _random.randf_range(-0.003, 0.003)
	place += Vector2(cos(heading), sin(heading)) * SPEED * delta
	if terrain != null:
		_ground = maxf(terrain.height_at(place.x, place.y), MapInfo.LAKE_Y)
	var foot := Origin.to_world(Vector3(place.x, _ground, place.y))
	_visual.global_position = foot
	var water: bool = terrain != null and terrain.is_lake(place.x, place.y)
	if water != _over_water:
		_over_water = water
		_tint(_funnel, SPOUT_TINT if water else FUNNEL_TINT)
		_tint(_skirt, SPRAY_TINT if water else DUST_TINT)
	for shown in [_funnel, _skirt]:
		var look := (shown as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
		look.set_shader_parameter("strength", strength)
	if _sound != null:
		_sound.volume_db = linear_to_db(maxf(strength, 0.001)) + 6.0
	# Debris round the foot.
	var pieces := _debris.multimesh
	for index in pieces.instance_count:
		var spin := age * (1.6 + 0.04 * index) + float(index) * 2.399
		var radius := 220.0 + 600.0 * fmod(float(index) * 0.618, 1.0)
		var lift := fmod(age * (12.0 + 4.0 * float(index % 5)) + index * 31.0, 900.0) * strength
		var turn := Basis(Vector3(0.3, 1.0, 0.2).normalized(), spin * 3.0)
		pieces.set_instance_transform(index, Transform3D(turn, Vector3(cos(spin) * radius, lift, sin(spin) * radius)))
	_debris.visible = strength > 0.05 and not _over_water
	# Smash what is in the way, twice a second.
	_smash -= delta
	if _smash <= 0.0 and strength > 0.3:
		_smash = 0.5
		for item in structures:
			if is_instance_valid(item):
				item.blast(foot + Vector3(0.0, 8.0, 0.0), CORE * 1.4, 900.0 * strength)
