extends SceneTree
## Renders a block of every building material, and panes of tinted glass in
## front of a striped wall, to check the material textures and glass (run
## under xvfb with opengl3):
##     xvfb-run godot --path . --rendering-driver opengl3 -s tools/material_shot.gd

const MaterialLibrary = preload("res://scripts/material_library.gd")

var camera: Camera3D
var frame := 0


func _initialize() -> void:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.7, 0.0)
	light.shadow_enabled = true
	root.add_child(light)
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var ids: Array = MaterialLibrary.ids()
	for index in ids.size():
		var id: String = ids[index]
		var column := index % 10
		var row := index / 10
		var size := Vector3(0.6, 0.6, 0.6) if row != 1 else Vector3(0.6, 0.6, 0.6)
		_block(id, MaterialLibrary.default_color(id), Vector3(column * 0.85 - 3.8, 0.3, row * 1.0), size)
	# Glass in front of a striped wall: plain, dark and red tints, and painted steel beside.
	for stripe in 8:
		_block("plastic", Color(1, 1, 1) if stripe % 2 == 0 else Color(0.1, 0.3, 0.8), Vector3(-2.8 + stripe * 0.5, 1.2, 4.2), Vector3(0.5, 2.4, 0.1))
	_block("glass", MaterialLibrary.default_color("glass"), Vector3(-1.6, 1.2, 3.4), Vector3(1.0, 1.6, 0.05))
	_block("glass", Color(0.25, 0.27, 0.3), Vector3(-0.4, 1.2, 3.4), Vector3(1.0, 1.6, 0.05))
	_block("glass", Color(0.95, 0.35, 0.3), Vector3(0.8, 1.2, 3.4), Vector3(1.0, 1.6, 0.05))
	_block("steel", Color(0.15, 0.45, 0.2), Vector3(2.2, 0.3, 3.4), Vector3(0.6, 0.6, 0.6))
	_block("wood", MaterialLibrary.default_color("wood"), Vector3(2.0, 1.4, 3.4), Vector3(0.25, 0.25, 2.0))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var ground_look := StandardMaterial3D.new()
	ground_look.albedo_color = Color(0.4, 0.45, 0.35)
	ground.material_override = ground_look
	root.add_child(ground)
	camera = Camera3D.new()
	camera.fov = 50.0
	root.add_child(camera)


func _block(id: String, color: Color, at: Vector3, size: Vector3) -> void:
	var shown := MeshInstance3D.new()
	shown.mesh = BoxMesh.new()
	shown.scale = size
	shown.position = at
	shown.set_surface_override_material(0, MaterialLibrary.surface(id, color))
	root.add_child(shown)


func _process(_delta: float) -> bool:
	frame += 1
	camera.make_current()
	if frame == 1:
		camera.look_at_from_position(Vector3(0.0, 3.2, -4.2), Vector3(0.0, 0.2, 1.2), Vector3.UP)
	if frame == 8:
		root.get_viewport().get_texture().get_image().save_png("/tmp/shots/materials_a.png")
	if frame == 9:
		camera.look_at_from_position(Vector3(3.2, 1.9, 2.0), Vector3(2.0, 1.2, 3.4), Vector3.UP)
	if frame == 16:
		root.get_viewport().get_texture().get_image().save_png("/tmp/shots/materials_b.png")
		return true
	return false
