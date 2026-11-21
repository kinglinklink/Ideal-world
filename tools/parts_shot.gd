extends SceneTree
## Renders a lineup of the mechanical, fluid and other machine parts at their
## default sizes, to check their models (run under xvfb with opengl3).

const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const Units = preload("res://scripts/units.gd")

const GROUPS := ["Mechanical", "Fluid and Engine", "Combat", "Misc", "Logic", "Aero"]
var camera: Camera3D
var frame := 0
var shots: Array = []


func _initialize() -> void:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.6, 0)
	root.add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.55, 0.62, 0.7)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	root.add_child(world)
	var row := 0
	for group in GROUPS:
		var column := 0
		for id in PartLibrary.part_ids():
			if PartLibrary.category(id) != group:
				continue
			var shown := MeshInstance3D.new()
			shown.mesh = PartLibrary.get_mesh(id)
			shown.scale = PartLibrary.default_size_cells(id) * Units.CELL
			shown.position = Vector3(column * 0.9, 0.0, row * 1.4)
			shown.set_surface_override_material(0, MaterialLibrary.surface("steel", Color(0.55, 0.57, 0.6)))
			root.add_child(shown)
			var label := Label3D.new()
			label.text = id
			label.font_size = 18
			label.pixel_size = 0.004
			label.position = shown.position + Vector3(0, -0.35, 0.3)
			label.rotation = Vector3(-0.6, 0, 0)
			root.add_child(label)
			column += 1
		row += 1
	camera = Camera3D.new()
	camera.fov = 40
	root.add_child(camera)


func _process(_delta: float) -> bool:
	frame += 1
	camera.make_current()
	var half := frame / 8
	camera.look_at_from_position(Vector3(4.5 + half * 9.0, 4.0, -2.5), Vector3(4.5 + half * 9.0, 0.0, 3.5), Vector3.UP)
	if frame % 8 == 7:
		root.get_viewport().get_texture().get_image().save_png("/tmp/shots/parts_%d.png" % half)
	return frame >= 24
