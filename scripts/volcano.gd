extends Node3D
## The volcano's great cone, built on top of the tallest peak inside the
## wall: from its old summit (2,063 m) up to a crater rim about 4,500 m above
## sea level, towering over the Salish and Mission ridgelines. The crater is
## 1.5 km across and 450 m deep with a lake of lava at the bottom. The cone
## is one mesh, drawn and solid, and sinks into the mountain where its
## slopes meet the ground. disasters.gd makes it erupt and makes the crater
## deadly.

const MapInfo = preload("res://scripts/map_info.gd")
const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")

const RIM_ASL := 4500.0           # m above sea level
const CRATER_RADIUS := 750.0      # m, to the rim
const FLOOR_RADIUS := 340.0       # m, the flat floor and its lava lake
const DEPTH := 450.0              # m, rim to floor
const REACH := 4600.0             # m, the furthest the cone can spread
const SECTORS := 96
const OUTER_RINGS := 40
const CONE_SHADER := """
shader_type spatial;
uniform sampler2D noise_map : repeat_enable, filter_linear_mipmap;
uniform float snow_line = 2300.0;   // metres above sea level
uniform float base_elevation = 901.0;
uniform float heat = 0.15;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 xz = world.xz;
	float fine = texture(noise_map, xz / 9.0).r;
	float broad = texture(noise_map, xz / 170.0 + vec2(0.3, 0.6)).r;
	vec3 basalt = mix(vec3(0.16, 0.145, 0.14), vec3(0.3, 0.26, 0.22), broad);
	vec3 color = basalt * (0.8 + 0.4 * fine) * COLOR.rgb;
	float steep = 1.0 - normalize(NORMAL).y;
	float height = world.y + base_elevation;
	float snowy = smoothstep(snow_line - 120.0, snow_line + 60.0, height + broad * 200.0) * (1.0 - smoothstep(0.5, 0.8, steep));
	color = mix(color, vec3(0.92, 0.94, 0.97), snowy * 0.95);
	ALBEDO = color;
	ROUGHNESS = 0.95;
	EMISSION = vec3(1.0, 0.3, 0.05) * COLOR.a * heat * 2.5;
}
"""

var terrain: Node = null           # terrain.gd
var rim_y := 0.0                   # map y of the crater rim
var floor_y := 0.0                 # map y of the crater floor
var _material: ShaderMaterial = null
var _lava: MeshInstance3D = null
var _lava_look: StandardMaterial3D = null
var _glow: OmniLight3D = null
var _clock := 0.0


func setup(the_terrain: Node, noise: Texture2D) -> void:
	terrain = the_terrain
	rim_y = RIM_ASL - MapInfo.BASE_ELEVATION
	floor_y = rim_y - DEPTH
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = CONE_SHADER
	_material.shader = shader
	_material.set_shader_parameter("noise_map", noise)
	_material.set_shader_parameter("base_elevation", MapInfo.BASE_ELEVATION)
	_build()
	_build_lava()


func centre() -> Vector2:
	return terrain.VOLCANO


## The cone's height at a distance `r` from the middle, in direction `angle`,
## before it meets the ground. Concave outside like a stratovolcano, steep
## inside the crater.
func _profile(r: float, angle: float, noise: FastNoiseLite) -> float:
	if r <= FLOOR_RADIUS:
		return floor_y
	if r <= CRATER_RADIUS:
		var t := (r - FLOOR_RADIUS) / (CRATER_RADIUS - FLOOR_RADIUS)
		return floor_y + DEPTH * pow(t, 1.6) + noise.get_noise_2d(angle * 40.0, r) * 12.0 * t
	var u := (r - CRATER_RADIUS) / (REACH - CRATER_RADIUS)
	var gully := noise.get_noise_2d(angle * 180.0, r * 0.02) * 60.0 * smoothstep(0.02, 0.2, u)
	return rim_y + 15.0 * (1.0 - smoothstep(0.0, 0.03, u)) - (rim_y + 250.0) * pow(u, 0.72) + gully


func _build() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1980
	noise.frequency = 0.05
	var middle: Vector2 = centre()
	var radii := PackedFloat32Array()
	for ring in 9:
		radii.append(FLOOR_RADIUS * float(ring) / 8.0)
	for ring in range(1, 13):
		radii.append(FLOOR_RADIUS + (CRATER_RADIUS - FLOOR_RADIUS) * float(ring) / 12.0)
	for ring in range(1, OUTER_RINGS + 1):
		var t := float(ring) / OUTER_RINGS
		radii.append(CRATER_RADIUS + (REACH - CRATER_RADIUS) * t * t)
	var points: Array = []        # [ring][sector] -> Vector3 map
	var buried: Array = []        # [ring][sector] -> true where under the ground
	for ring in radii.size():
		var line: Array = []
		var under: Array = []
		for sector in SECTORS:
			var angle := TAU * float(sector) / SECTORS
			var r: float = radii[ring]
			var spot := middle + Vector2(cos(angle), sin(angle)) * r
			var y := _profile(r, angle, noise)
			var ground: float = terrain.height_at(spot.x, spot.y)
			var is_buried := r > CRATER_RADIUS and y < ground - 8.0
			if r > CRATER_RADIUS and y < ground - 30.0:
				y = ground - 30.0
			line.append(Vector3(spot.x, y, spot.y))
			under.append(is_buried)
		points.append(line)
		buried.append(under)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for ring in radii.size() - 1:
		for sector in SECTORS:
			var next := (sector + 1) % SECTORS
			# Rings deep under the mountain on all four corners are left out.
			if bool(buried[ring][sector]) and bool(buried[ring][next]) and bool(buried[ring + 1][sector]) and bool(buried[ring + 1][next]):
				continue
			var a: Vector3 = points[ring][sector]
			var b: Vector3 = points[ring][next]
			var c: Vector3 = points[ring + 1][next]
			var d: Vector3 = points[ring + 1][sector]
			for tri in [[a, c, b], [a, d, c]]:
				for corner in tri:
					var p: Vector3 = corner
					var r := Vector2(p.x, p.z).distance_to(middle)
					# Alpha marks the hot crater walls for the glow.
					var hot := 1.0 - smoothstep(FLOOR_RADIUS, FLOOR_RADIUS + 140.0, r)
					surface.set_color(Color(1.0, 1.0, 1.0, hot))
					surface.add_vertex(p)
				faces.append_array(PackedVector3Array([tri[0], tri[1], tri[2]]))
	surface.generate_normals()
	var mesh := surface.commit()
	mesh.surface_set_material(0, _material)
	var shown := MeshInstance3D.new()
	shown.name = "Cone"
	shown.mesh = mesh
	add_child(shown)
	var body := StaticBody3D.new()
	body.name = "ConeRock"
	body.collision_layer = Units.LAYER_WORLD
	body.collision_mask = 0
	body.physics_material_override = Units.world_surface()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _build_lava() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = FLOOR_RADIUS - 5.0
	disc.bottom_radius = FLOOR_RADIUS - 5.0
	disc.height = 1.0
	disc.radial_segments = 48
	disc.rings = 1
	_lava_look = StandardMaterial3D.new()
	_lava_look.albedo_color = Color(0.25, 0.06, 0.02)
	_lava_look.emission_enabled = true
	_lava_look.emission = Color(1.0, 0.38, 0.06)
	_lava_look.emission_energy_multiplier = 3.0
	_lava_look.roughness = 0.6
	var cracks := NoiseTexture2D.new()
	var pattern := FastNoiseLite.new()
	pattern.noise_type = FastNoiseLite.TYPE_CELLULAR
	pattern.frequency = 0.03
	cracks.noise = pattern
	cracks.seamless = true
	_lava_look.emission_texture = cracks
	_lava_look.albedo_texture = cracks
	_lava_look.uv1_scale = Vector3(6.0, 6.0, 6.0)
	disc.material = _lava_look
	_lava = MeshInstance3D.new()
	_lava.mesh = disc
	_lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var middle: Vector2 = centre()
	_lava.position = Vector3(middle.x, floor_y + 2.0, middle.y)
	add_child(_lava)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.45, 0.15)
	_glow.omni_range = 1400.0
	_glow.light_energy = 3.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(middle.x, floor_y + 150.0, middle.y)
	add_child(_glow)


func _process(delta: float) -> void:
	_clock += delta
	if _lava_look != null:
		_lava_look.uv1_offset = Vector3(_clock * 0.004, _clock * 0.003, 0.0)
	var heat: float = terrain.volcano_heat if terrain != null else 0.15
	if _material != null:
		_material.set_shader_parameter("heat", heat)
		var weather: Node = get_tree().get_first_node_in_group("weather")
		if weather != null:
			_material.set_shader_parameter("snow_line", weather.snow_line)
	if _glow != null:
		_glow.light_energy = 2.0 + 10.0 * heat
		_lava_look.emission_energy_multiplier = 2.5 + 4.0 * heat


# --- The crater, for disasters.gd ---------------------------------------------------

## Distance from the middle, flat (m).
func off_centre(map_point: Vector3) -> float:
	return Vector2(map_point.x, map_point.z).distance_to(centre())


## True inside the crater's bowl, up to `headroom` m over the rim.
func in_crater(map_point: Vector3, headroom: float, widen := 1.0) -> bool:
	return off_centre(map_point) < CRATER_RADIUS * 0.96 * widen and map_point.y < rim_y + headroom


## True touching the lava lake.
func in_lava(map_point: Vector3) -> bool:
	return off_centre(map_point) < FLOOR_RADIUS and map_point.y < floor_y + 4.0
