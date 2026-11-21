extends SceneTree
## Renders the night sky looking at the moon in a few phases, to check the
## moon's face (run under xvfb with opengl3):
##     xvfb-run godot --path . --rendering-driver opengl3 -s tools/moon_shot.gd

var material: ShaderMaterial
var frame := 0
const PHASES := [0.5, 0.3, 0.12, 0.8]


func _initialize() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var toward := Vector3(0.2, 0.5, -1.0).normalized()
	material.set_shader_parameter("moon_direction", toward)
	material.set_shader_parameter("sun_direction", -toward)
	material.set_shader_parameter("night", 1.0)
	material.set_shader_parameter("top_color", Vector3(0.01, 0.016, 0.045))
	material.set_shader_parameter("horizon_color", Vector3(0.04, 0.06, 0.12))
	material.set_shader_parameter("cloud_cover", 0.0)
	var camera := Camera3D.new()
	camera.fov = 12.0
	root.add_child(camera)
	camera.look_at_from_position(Vector3.ZERO, toward, Vector3.UP)


func _process(_delta: float) -> bool:
	frame += 1
	var index := frame / 6
	if index >= PHASES.size():
		return true
	material.set_shader_parameter("moon_phase", PHASES[index])
	if frame % 6 == 5:
		root.get_viewport().get_texture().get_image().save_png("/tmp/shots/moon_%d.png" % index)
		print("SHOT moon ", PHASES[index])
	return false
