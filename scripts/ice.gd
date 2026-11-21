extends Node3D
## Ice on the lake in winter. As the cold deepens the shallow edges freeze,
## Polson Bay first and furthest, out to a few hundred metres from shore in
## midwinter, and thaw back as spring comes. The ice is solid: drive on it,
## land on it, skid on it (it has ice's own low friction). Worked out in
## CELL m squares round the player, a few times a minute.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Units = preload("res://scripts/units.gd")

const CELL := 32.0
const REACH := 1500.0
const MAX_EXTENT := 350.0         # m from shore the ice reaches in deep winter
const POLSON_BAY_Z := 13000.0     # south of this (Polson Bay) it freezes further out

var terrain: Node = null
var weather: Node = null
var player: Node3D = null

var _timer := 0.0
var _centre := Vector2.INF
var _extent := -1.0
var _shown: MeshInstance3D = null
var _body: StaticBody3D = null
var _look: StandardMaterial3D = null
var cells := 0


func _ready() -> void:
	_look = StandardMaterial3D.new()
	_look.albedo_color = Color(0.82, 0.9, 0.97, 0.92)
	_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_look.roughness = 0.15
	_look.metallic_specular = 0.8
	_shown = MeshInstance3D.new()
	_shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shown)
	_body = StaticBody3D.new()
	_body.collision_layer = Units.LAYER_WORLD
	_body.collision_mask = 0
	var slick := PhysicsMaterial.new()
	slick.friction = 0.08
	_body.physics_material_override = slick
	add_child(_body)


## How far from shore the ice reaches now, in metres (0 when there is none).
func extent() -> float:
	if weather == null:
		return 0.0
	var cold: float = weather.cold
	return clampf((cold - 0.55) / 0.4, 0.0, 1.0) * MAX_EXTENT


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or terrain == null or player == null:
		return
	_timer = 3.0
	var here := Origin.to_map(player.global_position)
	var spot := Vector2(here.x, here.z)
	var reach := extent()
	if absf(reach - _extent) < 10.0 and _centre != Vector2.INF and _centre.distance_to(spot) < 400.0:
		_place()
		return
	_extent = reach
	_centre = spot
	_rebuild()


func _frozen(x: float, z: float, reach: float) -> bool:
	if not terrain.is_lake(x, z):
		return false
	var here := reach * (2.5 if z > POLSON_BAY_Z else 1.0)
	for ring in [here * 0.35, here * 0.7, here]:
		for index in 8:
			var angle := TAU * index / 8.0
			if not terrain.is_lake(x + cos(angle) * ring, z + sin(angle) * ring):
				return true
	return false


func _rebuild() -> void:
	cells = 0
	for child in _body.get_children():
		child.queue_free()
	if _extent < 20.0:
		_shown.mesh = null
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var y := MapInfo.LAKE_Y + 0.12
	var low := (_centre - Vector2(REACH, REACH)).snapped(Vector2(CELL, CELL))
	var count := int(REACH * 2.0 / CELL)
	for i in count:
		for k in count:
			var x := low.x + i * CELL
			var z := low.y + k * CELL
			if not _frozen(x + CELL * 0.5, z + CELL * 0.5, _extent):
				continue
			cells += 1
			var a := Vector3(x, y, z)
			var b := Vector3(x + CELL, y, z)
			var c := Vector3(x + CELL, y, z + CELL)
			var d := Vector3(x, y, z + CELL)
			for corner in [a, b, c, a, c, d]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(corner)
			faces.append_array(PackedVector3Array([a, c, b, a, d, c]))
	if cells == 0:
		_shown.mesh = null
		return
	var mesh := surface.commit()
	mesh.surface_set_material(0, _look)
	_shown.mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_body.add_child(collider)
	_place()


## The ice is built in map positions: keep it where the world now is.
func _place() -> void:
	_shown.global_position = -Origin.offset
	_body.global_position = -Origin.offset
