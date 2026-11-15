extends Node3D
## Entry point. Builds the starting area in code: sky, sun, ground, the build
## pad, the player, the build tools and the interface.
##
## World axes: Y is up, X and Z are the ground plane. Distances are in metres.

const Player = preload("res://scripts/player.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const BuildController = preload("res://scripts/build_controller.gd")
const Hud = preload("res://scripts/hud.gd")
const PAD_SHADER = preload("res://shaders/pad_grid.gdshader")

const GROUND_SIZE := 2000.0   # metres across


func _ready() -> void:
	_make_sky_and_sun()
	_make_ground()

	var grid: Node3D = BuildGrid.new()
	grid.name = "BuildGrid"
	add_child(grid)
	_make_pad_surface(grid)

	var player: CharacterBody3D = Player.new()
	player.name = "Player"
	# Start just outside the pad, looking along +Z across it.
	var pad_size: Vector3 = grid.size_metres()
	player.position = Vector3(pad_size.x * 0.5, 0.1, -4.0)
	player.yaw = PI
	add_child(player)

	var controller: Node3D = BuildController.new()
	controller.name = "BuildController"
	add_child(controller)
	controller.setup(grid, player)

	var hud: CanvasLayer = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(controller, grid, player)


func _make_sky_and_sun() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.47, 0.88)
	sky_material.sky_horizon_color = Color(0.68, 0.82, 0.95)
	sky_material.ground_horizon_color = Color(0.68, 0.82, 0.95)
	sky_material.ground_bottom_color = Color(0.30, 0.42, 0.30)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


## A flat grass slab. Its top face is the ground plane at Y = 0.
func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)

	var slab := Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)

	var shape := BoxShape3D.new()
	shape.size = slab
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ground.add_child(collider)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.62, 0.30)
	material.roughness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = slab
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	ground.add_child(mesh_instance)


## The visible grid on the build pad. Clicks land on the ground collider
## underneath; the grid decides whether a cell is inside the pad.
func _make_pad_surface(grid: Node3D) -> void:
	var pad_size: Vector3 = grid.size_metres()

	var material := ShaderMaterial.new()
	material.shader = PAD_SHADER

	var plane := PlaneMesh.new()
	plane.size = Vector2(pad_size.x, pad_size.z)
	plane.material = material

	var surface := MeshInstance3D.new()
	surface.name = "PadSurface"
	surface.mesh = plane
	# Lifted 2 mm so it never flickers against the ground beneath it.
	surface.position = Vector3(pad_size.x * 0.5, 0.002, pad_size.z * 0.5)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.add_child(surface)
