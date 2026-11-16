extends Node3D
## Entry point. Builds the starting area in code: sky, sun, ground, the build
## pad, the player, the build tools and the interface.
##
## World axes: Y is up, X and Z are the ground plane. Distances are in metres.

const Units = preload("res://scripts/units.gd")
const Player = preload("res://scripts/player.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const BuildController = preload("res://scripts/build_controller.gd")
const Hud = preload("res://scripts/hud.gd")
const Scenery = preload("res://scripts/scenery.gd")
const PAD_SHADER = preload("res://shaders/pad_grid.gdshader")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")
const Spawner = preload("res://scripts/spawner.gd")
const Combat = preload("res://scripts/combat.gd")

const GROUND_SIZE := 6000.0   # metres across

# The garage sits behind the start point, with its door facing the build pad.
const GARAGE_SIZE := Vector3(24.0, 7.0, 16.0)   # width, height, depth in metres
const GARAGE_GAP := 12.0                        # from the garage door to the pad
const DOOR_SIZE := Vector2(16.0, 5.5)           # width, height in metres
const WALL_THICKNESS := 0.4

# Plants keep clear of the pad and garage by these distances, in metres.
const GRASS_MARGIN := 45.0
const TREE_MARGIN := 80.0

var _garage_door: StaticBody3D
var _garage_door_collider: CollisionShape3D
var _garage_open := false
var _hud: CanvasLayer


func _ready() -> void:
	_make_sky_and_sun()
	_make_ground()

	var grid: Node3D = BuildGrid.new()
	grid.name = "BuildGrid"
	add_child(grid)
	_make_pad_surface(grid)

	var pad_size: Vector3 = grid.size_metres()
	var map_features: Array = _make_garage(pad_size)
	map_features.append([Rect2(0.0, 0.0, pad_size.x, pad_size.z), Color(0.20, 0.26, 0.36), "Build pad"])

	# Grass and trees, kept well back from the pad and the garage.
	var home_depth := GARAGE_GAP + GARAGE_SIZE.z
	var home := Rect2(0.0, -home_depth, pad_size.x, pad_size.z + home_depth)
	var scenery: Node3D = Scenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	scenery.build(home, GRASS_MARGIN, TREE_MARGIN)

	var player: CharacterBody3D = Player.new()
	player.name = "Player"
	# Start between the garage door and the pad, looking along +Z across the pad.
	player.position = Vector3(pad_size.x * 0.5, 0.1, -GARAGE_GAP * 0.5)
	player.yaw = PI
	add_child(player)

	var spawner: Node3D = Spawner.new()
	spawner.name = "Spawner"
	add_child(spawner)

	# Guns, shells and explosives. Added after the spawner, so each tick it
	# runs once the machines have moved.
	var combat: Node3D = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(spawner)

	var controller: Node3D = BuildController.new()
	controller.name = "BuildController"
	add_child(controller)
	controller.setup(grid, player, spawner)

	var hud: CanvasLayer = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(controller, grid, player)
	hud.set_map_features(map_features)
	hud.set_map_trees(scenery.tree_spots)
	_hud = hud
	hud.connect("garage_button_pressed", _on_garage_button)


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
	sun.directional_shadow_max_distance = 150.0
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

	# Grass: one seamless noise picture, mixed at three sizes by the shader.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 7
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var noise_map := NoiseTexture2D.new()
	noise_map.width = 512
	noise_map.height = 512
	noise_map.seamless = true
	noise_map.generate_mipmaps = true
	noise_map.noise = noise
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("noise_map", noise_map)
	var mesh := BoxMesh.new()
	mesh.size = slab
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	ground.add_child(mesh_instance)


func _solid(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = at
	parent.add_child(mesh_instance)


## A wall section: something to see and something to walk into.
func _wall(body: StaticBody3D, size: Vector3, at: Vector3, color: Color) -> CollisionShape3D:
	_solid(body, size, at, color)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = at
	body.add_child(collider)
	return collider


## The garage: a hollow building with a large sectional door facing the pad,
## and a concrete apron between the two. Returns its footprints for the map.
func _make_garage(pad_size: Vector3) -> Array:
	var width := GARAGE_SIZE.x
	var height := GARAGE_SIZE.y
	var depth := GARAGE_SIZE.z
	var half_depth := depth * 0.5
	var thick := WALL_THICKNESS
	var centre := Vector3(pad_size.x * 0.5, 0.0, -GARAGE_GAP - half_depth)

	var garage := StaticBody3D.new()
	garage.name = "Garage"
	garage.position = centre
	add_child(garage)

	var wall := Color(0.74, 0.78, 0.84)
	var roof := Color(0.86, 0.42, 0.24)
	var trim := Color(0.94, 0.95, 0.97)
	var door_color := Color(0.32, 0.36, 0.42)
	var seam := Color(0.20, 0.23, 0.28)
	var front := half_depth - thick * 0.5   # the middle of the front wall, in Z

	# Back and side walls, and the roof.
	_wall(garage, Vector3(width, height, thick), Vector3(0.0, height * 0.5, -half_depth + thick * 0.5), wall)
	_wall(garage, Vector3(thick, height, depth), Vector3(-width * 0.5 + thick * 0.5, height * 0.5, 0.0), wall)
	_wall(garage, Vector3(thick, height, depth), Vector3(width * 0.5 - thick * 0.5, height * 0.5, 0.0), wall)
	_wall(garage, Vector3(width + 1.0, 0.5, depth + 1.0), Vector3(0.0, height + 0.25, 0.0), roof)

	# The front wall, built around the door opening.
	var side_width := (width - DOOR_SIZE.x) * 0.5
	var above_door := height - DOOR_SIZE.y
	_wall(garage, Vector3(side_width, height, thick),
			Vector3(-width * 0.5 + side_width * 0.5, height * 0.5, front), wall)
	_wall(garage, Vector3(side_width, height, thick),
			Vector3(width * 0.5 - side_width * 0.5, height * 0.5, front), wall)
	_wall(garage, Vector3(DOOR_SIZE.x, above_door, thick),
			Vector3(0.0, DOOR_SIZE.y + above_door * 0.5, front), wall)

	# White trim round the opening, on the outside.
	_solid(garage, Vector3(DOOR_SIZE.x + 0.8, 0.4, 0.3), Vector3(0.0, DOOR_SIZE.y + 0.2, half_depth + 0.05), trim)
	_solid(garage, Vector3(0.4, DOOR_SIZE.y, 0.3), Vector3(-DOOR_SIZE.x * 0.5 - 0.2, DOOR_SIZE.y * 0.5, half_depth + 0.05), trim)
	_solid(garage, Vector3(0.4, DOOR_SIZE.y, 0.3), Vector3(DOOR_SIZE.x * 0.5 + 0.2, DOOR_SIZE.y * 0.5, half_depth + 0.05), trim)

	# A concrete floor and two lamps inside.
	_solid(garage, Vector3(width - thick * 2.0, 0.02, depth - thick * 2.0), Vector3(0.0, 0.011, 0.0), Color(0.58, 0.58, 0.60))
	for lamp_side in [-1.0, 1.0]:
		var side: float = lamp_side
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(side * width * 0.25, height - 1.0, 0.0)
		lamp.omni_range = 16.0
		lamp.light_energy = 1.5
		lamp.shadow_enabled = true   # so the walls keep the light indoors
		garage.add_child(lamp)

	# The door is its own body, so it can be taken away and put back.
	_garage_door = StaticBody3D.new()
	_garage_door.name = "GarageDoor"
	garage.add_child(_garage_door)
	_garage_door_collider = _wall(_garage_door, Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.2),
			Vector3(0.0, DOOR_SIZE.y * 0.5, front), door_color)
	for panel in range(1, 5):
		var seam_height := DOOR_SIZE.y * float(panel) / 5.0
		_solid(_garage_door, Vector3(DOOR_SIZE.x, 0.06, 0.26), Vector3(0.0, seam_height, front), seam)

	# A concrete apron from the door to the pad. It is too thin to trip on.
	var apron_width := DOOR_SIZE.x + 4.0
	var apron := MeshInstance3D.new()
	var apron_mesh := BoxMesh.new()
	apron_mesh.size = Vector3(apron_width, 0.02, GARAGE_GAP)
	var apron_material := StandardMaterial3D.new()
	apron_material.albedo_color = Color(0.62, 0.62, 0.64)
	apron_material.roughness = 1.0
	apron_mesh.material = apron_material
	apron.mesh = apron_mesh
	apron.position = Vector3(pad_size.x * 0.5, 0.011, -GARAGE_GAP * 0.5)
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(apron)

	return [
		[Rect2(centre.x - apron_width * 0.5, -GARAGE_GAP, apron_width, GARAGE_GAP), Color(0.34, 0.34, 0.36), ""],
		[Rect2(centre.x - width * 0.5, centre.z - half_depth, width, depth),
				Color(0.62, 0.34, 0.22), "Garage"],
	]


## Opens or closes the garage. There is no animation yet: the door simply
## goes away and comes back, along with its collision.
func _on_garage_button() -> void:
	_garage_open = not _garage_open
	_garage_door.visible = not _garage_open
	_garage_door_collider.set_deferred("disabled", _garage_open)
	_hud.set_garage_open(_garage_open)


## The visible grid on the build pad. Clicks land on the ground collider
## underneath; the grid decides whether a part is inside the pad.
func _make_pad_surface(grid: Node3D) -> void:
	var pad_size: Vector3 = grid.size_metres()

	var material := ShaderMaterial.new()
	material.shader = PAD_SHADER
	material.set_shader_parameter("cell_size", Units.CELL)

	var plane := PlaneMesh.new()
	plane.size = Vector2(pad_size.x, pad_size.z)
	plane.material = material

	var surface := MeshInstance3D.new()
	surface.name = "PadSurface"
	surface.mesh = plane
	# Lifted slightly so it never flickers against the ground beneath it.
	surface.position = Vector3(pad_size.x * 0.5, 0.01, pad_size.z * 0.5)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.add_child(surface)
