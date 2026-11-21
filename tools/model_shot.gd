extends SceneTree
## Renders the character in a few poses (run under xvfb with opengl3):
##     xvfb-run godot --path . --rendering-driver opengl3 -s tools/model_shot.gd

const Player = preload("res://scripts/player.gd")

var player: Node3D
var camera: Camera3D
var frame := 0
const POSES := [
	["stand", [0.0, 0.0, -0.05, -0.05, 0.0, 0.0, 0.2, 0.2, 0.0, 0.95]],
	["run", [0.8, -0.8, -0.1, -1.2, -0.7, 0.7, 1.3, 1.3, -0.22, 0.95]],
	["sit", [1.45, 1.45, -1.45, -1.45, 0.45, 0.45, 0.7, 0.7, 0.0, 0.95]],
	["swim", [0.4, 0.0, -0.1, -0.1, 3.4, 0.8, 0.3, 0.3, -1.35, 1.35]],
]


func _initialize() -> void:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, 0.6, 0.0)
	root.add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.55, 0.65, 0.75)
	world.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(world)
	player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.fov = 30.0


func _process(_delta: float) -> bool:
	frame += 1
	var index := frame / 6
	if index >= POSES.size():
		return true
	var pose: Array = POSES[index][1]
	player.callv("_pose", pose)
	camera.make_current()
	player.set_physics_process(false)
	player.set_process(false)
	player.position = Vector3.ZERO
	var angle := 0.7
	camera.look_at_from_position(Vector3(sin(angle) * -4.0, 1.2, cos(angle) * -4.0), Vector3(0, 0.8, 0), Vector3.UP)
	if frame % 6 == 5:
		root.get_viewport().get_texture().get_image().save_png("/tmp/shots/model_%s.png" % POSES[index][0])
		print("SHOT ", POSES[index][0])
	return false
