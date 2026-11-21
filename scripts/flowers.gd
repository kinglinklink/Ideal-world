extends Node3D
## Wildflowers in spring: yellows, blues, purples and white, dotted through
## the open grass round the player (the ground shader paints them further
## off). Not under the trees, not on steep ground, not on the beach.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")

const REACH := 220.0
const COUNT := 5000
const COLORS := [Color(0.98, 0.85, 0.15), Color(0.45, 0.55, 0.95), Color(0.72, 0.42, 0.88), Color(0.97, 0.97, 0.94),
		Color(0.95, 0.55, 0.2)]

var terrain: Node = null
var weather: Node = null
var player: Node3D = null

var _field: MultiMeshInstance3D = null
var _centre := Vector2.INF
var _timer := 0.0
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_field = MultiMeshInstance3D.new()
	_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_field)


func _flower_mesh() -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for turn in [0.0, PI * 0.5]:
		var across := Vector3(cos(turn), 0.0, sin(turn))
		# The stem.
		surface.set_color(Color(0.25, 0.45, 0.18))
		for corner in [-across * 0.015, across * 0.015 + Vector3(0, 0.22, 0), -across * 0.015 + Vector3(0, 0.22, 0),
				-across * 0.015, across * 0.015, across * 0.015 + Vector3(0, 0.22, 0)]:
			surface.add_vertex(corner)
		# The head, in the instance's colour (white here, tinted per flower).
		surface.set_color(Color(1, 1, 1))
		var top := Vector3(0.0, 0.24, 0.0)
		for corner in [top - across * 0.06 - Vector3(0, 0.04, 0), top + across * 0.06 + Vector3(0, 0.04, 0), top - across * 0.06 + Vector3(0, 0.04, 0),
				top - across * 0.06 - Vector3(0, 0.04, 0), top + across * 0.06 - Vector3(0, 0.04, 0), top + across * 0.06 + Vector3(0, 0.04, 0)]:
			surface.add_vertex(corner)
	surface.generate_normals()
	var mesh := surface.commit()
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, look)
	return mesh


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or terrain == null or player == null:
		return
	_timer = 2.0
	var spring: float = weather.spring if weather != null else 0.0
	if spring < 0.25:
		_field.visible = false
		_centre = Vector2.INF
		return
	var here := Origin.to_map(player.global_position)
	var spot := Vector2(here.x, here.z)
	if _centre == Vector2.INF or _centre.distance_to(spot) > REACH * 0.5:
		_centre = spot
		_plant(spring)
	_field.visible = true
	_field.global_position = -Origin.offset


func _plant(spring: float) -> void:
	_random.seed = hash(Vector2i(int(_centre.x / 50.0), int(_centre.y / 50.0)))
	var points: Array = []
	var wanted := int(COUNT * clampf(spring, 0.0, 1.0))
	var tries := 0
	while points.size() < wanted and tries < wanted * 3:
		tries += 1
		var at := _centre + Vector2(_random.randf_range(-REACH, REACH), _random.randf_range(-REACH, REACH))
		if terrain.is_lake(at.x, at.y):
			continue
		var y: float = terrain.height_at(at.x, at.y)
		if y - MapInfo.LAKE_Y < 1.5 or y - MapInfo.LAKE_Y > 600.0:
			continue
		var slope: float = absf(terrain.height_at(at.x + 3.0, at.y) - y) + absf(terrain.height_at(at.x, at.y + 3.0) - y)
		if slope > 1.2:
			continue
		# Flowers grow in drifts: keep the ones where a slow noise is high.
		if sin(at.x * 0.021) * cos(at.y * 0.017) + sin(at.x * 0.007 + at.y * 0.009) < 0.2:
			continue
		points.append(Vector3(at.x, y, at.y))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _flower_mesh()
	multimesh.instance_count = points.size()
	for index in points.size():
		var size := _random.randf_range(0.7, 1.4)
		multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, _random.randf() * TAU).scaled(Vector3.ONE * size), points[index]))
		multimesh.set_instance_color(index, COLORS[_random.randi() % COLORS.size()])
	_field.multimesh = multimesh
