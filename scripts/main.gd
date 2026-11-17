extends Node3D
## Entry point. Builds the world in code: sky, sun, the Flathead Lake map,
## the build pad on Wild Horse Island, the player, the build tools and the
## interface.
##
## World axes: Y is up, X and Z are the ground plane, north is -Z. Distances
## are in metres. Y = 0 is the level of the build pad; see map_info.gd.
##
## This script also keeps the world centred on the player (see origin.gd):
## when the player strays more than 1.5 km from the origin, everything is
## moved back by whole kilometres, so positions stay small and precise.

const Units = preload("res://scripts/units.gd")
const Player = preload("res://scripts/player.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const BuildController = preload("res://scripts/build_controller.gd")
const Hud = preload("res://scripts/hud.gd")
const Scenery = preload("res://scripts/scenery.gd")
const PAD_SHADER = preload("res://shaders/pad_grid.gdshader")
const Terrain = preload("res://scripts/terrain.gd")
const Spawner = preload("res://scripts/spawner.gd")
const Combat = preload("res://scripts/combat.gd")
const Logic = preload("res://scripts/logic.gd")
const Engines = preload("res://scripts/engines.gd")
const Origin = preload("res://scripts/origin.gd")
const Daylight = preload("res://scripts/daylight.gd")
const Sound = preload("res://scripts/sound.gd")
const Menus = preload("res://scripts/menus.gd")
const Fleet = preload("res://scripts/fleet.gd")
const Replay = preload("res://scripts/replay.gd")
const GameHud = preload("res://scripts/game_hud.gd")

# The hangar sits behind the start point, with its door facing the build pad.
const GARAGE_SIZE := Vector3(56.0, 15.0, 40.0)  # width, height at the eaves, depth in metres
const RIDGE_RISE := 5.0                         # the roof's peak above the eaves
const GARAGE_GAP := 12.0                        # from the hangar door to the pad
const DOOR_SIZE := Vector2(44.0, 12.5)          # width, height in metres
const WALL_THICKNESS := 0.5

# Grass keeps clear of the pad and garage by this distance, in metres.
const GRASS_MARGIN := 45.0

var _garage_door: StaticBody3D
var _garage_door_collider: CollisionShape3D
var _garage_open := false
var _garage_door_parts: Array = []   # [MeshInstance3D, its shut transform]
var _door_shut := 1.0
var _door_tween: Tween = null
var _hud: CanvasLayer
var _player: CharacterBody3D
var _spawner: Node3D
var _combat: Node3D
var _terrain: Node3D
var _controller: Node3D
var _daylight: Node3D          # daylight.gd: sun, moon, sky and the time of day
var _fleet: Node3D             # fleet.gd: saved builds spawned out as vehicles
var _start := Vector3.ZERO     # where the character starts and respawns, in map positions
var _replay: Node               # replay.gd: the last 30 seconds, played back
var _game_hud: CanvasLayer      # game_hud.gd: health, cash, announcements
var _respawn_after_replay := false
const START_HEADING := PI


func _ready() -> void:
	_make_sky_and_sun()

	# Sound: effects, machines, wind and the birds and crickets.
	var sound: Node = Sound.new()
	sound.name = "Sound"
	add_child(sound)

	var grid: Node3D = BuildGrid.new()
	grid.name = "BuildGrid"
	add_child(grid)
	_make_pad_surface(grid)

	var pad_size: Vector3 = grid.size_metres()
	var map_features: Array = _make_garage(pad_size)
	map_features.append([Rect2(0.0, 0.0, pad_size.x, pad_size.z), Color(0.20, 0.26, 0.36), "Build pad"])

	var player: CharacterBody3D = Player.new()
	player.name = "Player"
	# Start between the garage door and the pad, looking along +Z across the pad.
	_start = Vector3(pad_size.x * 0.5, 0.1, -GARAGE_GAP * 0.5)
	player.position = _start
	player.yaw = START_HEADING
	add_child(player)
	_player = player

	var spawner: Node3D = Spawner.new()
	spawner.name = "Spawner"
	add_child(spawner)
	_spawner = spawner

	# Guns, shells and explosives. Added after the spawner, so each tick it
	# runs once the machines have moved.
	var combat: Node3D = Combat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(spawner)
	_combat = combat

	# Logic blocks, sensors, lights, vanish blocks, propellers and lift gas.
	var logic: Node3D = Logic.new()
	logic.name = "Logic"
	add_child(logic)
	logic.setup(spawner)

	# Fuel, pumps, cylinders, jet engines and rockets.
	var engines: Node3D = Engines.new()
	engines.name = "Engines"
	add_child(engines)
	engines.setup(spawner)

	# The map: ground, lake, forests, airports and the wall round the edge.
	# Set up before the first physics step, so the ground is solid under the
	# character from the start.
	var terrain: Node3D = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(player, spawner, _grass_noise())
	player.terrain = terrain
	spawner.terrain = terrain
	combat.terrain = terrain
	combat.structures = [terrain.towns, terrain.towers]

	# Saved builds spawned out into the world as vehicles of their own.
	var fleet: Node3D = Fleet.new()
	fleet.name = "Fleet"
	add_child(fleet)
	fleet.terrain = terrain
	fleet.player = player
	fleet.main_spawner = spawner
	fleet.structures = combat.structures
	terrain.fleet = fleet
	_fleet = fleet
	logic.terrain = terrain
	_terrain = terrain

	# Grass round the pad and garage.
	var home_depth := GARAGE_GAP + GARAGE_SIZE.z
	var home := Rect2(0.0, -home_depth, pad_size.x, pad_size.z + home_depth)
	var scenery: Node3D = Scenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	scenery.build(home, GRASS_MARGIN, terrain)

	var controller: Node3D = BuildController.new()
	controller.name = "BuildController"
	add_child(controller)
	controller.setup(grid, player, spawner)
	controller.fleet = _fleet
	_controller = controller

	var hud: CanvasLayer = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(controller, grid, player)
	hud.set_map_features(map_features)
	hud.set_world_map(terrain.world, terrain.landmarks.map_points)
	_hud = hud
	hud.connect("garage_button_pressed", _on_garage_button)
	hud.connect("respawn_pressed", _respawn)
	# Title screen, pause menu, settings and the parts guide, over everything.
	var menus: CanvasLayer = Menus.new()
	menus.name = "Menus"
	add_child(menus)
	menus.player = player
	menus.hud = hud
	menus.version = "Ideal World  %s" % Hud.VERSION
	menus.connect("respawn_requested", _respawn)
	hud.menus = menus
	hud.setup_settings(terrain.forest, _daylight, menus.settings_panel)
	menus.show_title()
	sound.spawner = spawner
	sound.fleet = _fleet
	hud.set_fleet(_fleet)
	sound.player = player
	sound.daylight = _daylight

	# Health, cash and announcements.
	var game_hud: CanvasLayer = GameHud.new()
	game_hud.name = "GameHud"
	add_child(game_hud)
	game_hud.player = player
	_game_hud = game_hud
	player.died.connect(_on_player_died)
	player.hurt_taken.connect(func(amount: float) -> void: game_hud.flash_hurt(amount))

	# The replay: key 0 once something is spawned, and after dying.
	var replay: Node = Replay.new()
	replay.name = "Replay"
	add_child(replay)
	replay.spawner = spawner
	replay.fleet = _fleet
	replay.player = player
	replay.controller = controller
	replay.screens = [hud, game_hud]
	replay.finished.connect(_on_replay_finished)
	_replay = replay


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_P \
			and get_viewport().gui_get_focus_owner() == null:
		_respawn()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M \
			and get_viewport().gui_get_focus_owner() == null:
		_hud.toggle_world_map()


## Sends the character back to the hangar, in front of its door. The world
## is first shifted back to where it started, so the spawn point is always
## the same fixed map position however far away the character was.
func _respawn() -> void:
	if Origin.offset != Vector3.ZERO:
		_shift_world(-Origin.offset)
	_controller.respawn(Origin.to_world(_start), START_HEADING)
	_player.heal_full()


## Dying: whatever race was on is lost, the replay shows how it happened,
## and the character comes back at the hangar when it ends.
func _on_player_died(cause: String) -> void:
	_game_hud.announce("YOU DIED", "Killed by %s" % cause, 3.0, Color(1.0, 0.3, 0.25))
	get_tree().call_group("races", "player_died")
	_respawn_after_replay = true
	if not _replay.start("You died: %s" % cause):
		_respawn_after_replay = false
		get_tree().create_timer(2.0).timeout.connect(_respawn)


func _on_replay_finished(_reason: String) -> void:
	if _respawn_after_replay:
		_respawn_after_replay = false
		_respawn()


# --- Keeping the world centred on the player ------------------------------------

func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var at := _player.global_position
	if absf(at.x) > Origin.SHIFT_DISTANCE or absf(at.z) > Origin.SHIFT_DISTANCE:
		var shift := Vector3(snappedf(at.x, Origin.SHIFT_STEP), 0.0, snappedf(at.z, Origin.SHIFT_STEP))
		_shift_world(shift)


## Moves everything in the world by -`shift`, so the player is back near the
## origin. Velocities, joints and contacts are untouched: the whole world moves
## together, so nothing can tell it happened. Shifts are whole multiples of
## 1,024 m, which floats hold exactly, so nothing drifts.
func _shift_world(shift: Vector3) -> void:
	Origin.offset += shift
	for child in get_children():
		if child == _player:
			_player.global_position -= shift
		elif child == _spawner:
			_spawner.shift_origin(shift)   # moves each body itself
		elif child == _fleet:
			_fleet.shift_origin(shift)     # likewise, vehicle by vehicle
		elif child is DirectionalLight3D:
			continue
		elif child is Node3D:
			var node: Node3D = child
			node.position -= shift
	_combat.shift_origin(shift)
	_terrain.origin_shifted()


func _make_sky_and_sun() -> void:
	var daylight: Node3D = Daylight.new()
	daylight.name = "Daylight"
	add_child(daylight)
	_daylight = daylight


## The noise picture the ground and water shaders read for grass mottling
## and ripples.
func _grass_noise() -> NoiseTexture2D:
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
	return noise_map


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


## The hangar: a steel portal-frame building with a pitched roof and a big
## roller door facing the pad, and a concrete apron between the two. Inside,
## the frames stand bare: I-beam columns, Warren roof trusses, purlins, knee
## braces and yellow cross-bracing on the walls and roof. Returns its
## footprints for the map.
func _make_garage(pad_size: Vector3) -> Array:
	var width := GARAGE_SIZE.x
	var height := GARAGE_SIZE.y      # at the eaves
	var depth := GARAGE_SIZE.z
	var half_width := width * 0.5
	var half_depth := depth * 0.5
	var thick := WALL_THICKNESS
	var ridge := height + RIDGE_RISE
	var centre := Vector3(pad_size.x * 0.5, 0.0, -GARAGE_GAP - half_depth)

	var garage := StaticBody3D.new()
	garage.physics_material_override = Units.world_surface()
	garage.name = "Hangar"
	garage.position = centre
	add_child(garage)

	var cladding := Color(0.60, 0.63, 0.66)
	var roof_color := Color(0.26, 0.30, 0.35)
	var steel := Color(0.16, 0.18, 0.21)
	var bracing := Color(0.95, 0.72, 0.10)
	var door_color := Color(0.40, 0.44, 0.48)
	var seam := Color(0.22, 0.25, 0.29)
	var front := half_depth - thick * 0.5   # the middle of the front wall, in Z
	var back := -half_depth + thick * 0.5

	# --- The shell: walls, gables and roof, all solid ---
	_wall(garage, Vector3(thick, height, depth), Vector3(-half_width + thick * 0.5, height * 0.5, 0.0), cladding)
	_wall(garage, Vector3(thick, height, depth), Vector3(half_width - thick * 0.5, height * 0.5, 0.0), cladding)
	_wall(garage, Vector3(width, height, thick), Vector3(0.0, height * 0.5, back), cladding)
	var side_width := (width - DOOR_SIZE.x) * 0.5
	var above_door := height - DOOR_SIZE.y
	_wall(garage, Vector3(side_width, height, thick), Vector3(-half_width + side_width * 0.5, height * 0.5, front), cladding)
	_wall(garage, Vector3(side_width, height, thick), Vector3(half_width - side_width * 0.5, height * 0.5, front), cladding)
	_wall(garage, Vector3(DOOR_SIZE.x, above_door, thick), Vector3(0.0, DOOR_SIZE.y + above_door * 0.5, front), cladding)
	for z in [front, back]:
		_gable(garage, half_width, height, ridge, float(z), thick, cladding)
	var slope := atan2(RIDGE_RISE, half_width)
	var rafter := sqrt(half_width * half_width + RIDGE_RISE * RIDGE_RISE) + 1.2
	for side in [-1.0, 1.0]:
		var s: float = side
		var tilt := Basis(Vector3.BACK, s * slope)
		var middle := Vector3(-s * half_width * 0.5, (height + ridge) * 0.5 + 0.15, 0.0)
		_tilted_wall(garage, Vector3(rafter, 0.35, depth + 1.2), Transform3D(tilt, middle), roof_color)

	# --- The steel, merged into one mesh so it costs one draw ---
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bays := 5
	var inset := half_width - 0.9      # columns stand just inside the side walls
	for bay in bays + 1:
		var z := -half_depth + 1.0 + (depth - 2.0) * float(bay) / bays
		for side in [-1.0, 1.0]:
			var x: float = float(side) * inset
			_i_beam(frame, Vector3(x, 0.0, z), Vector3(x, height - 0.2, z), 0.7, 0.5, steel)
			# Knee brace from the column up to the truss.
			_member(frame, Vector3(x, height - 3.2, z), Vector3(x - float(side) * 3.0, height - 0.45, z), 0.18, 0.18, steel)
			# Base plate.
			_box(frame, Transform3D(Basis.IDENTITY, Vector3(x, 0.03, z)), Vector3(1.0, 0.06, 1.0), steel)
		_truss(frame, z, inset, height, ridge, steel)
	# Purlins along the roof, and an eave beam each side.
	var purlins := 7
	for index in purlins + 1:
		var t := float(index) / purlins
		for side in [-1.0, 1.0]:
			var s: float = side
			var x := s * inset * (1.0 - t)
			var y := lerpf(height - 0.05, ridge - 0.45, t)
			_member(frame, Vector3(x, y, -half_depth + 0.6), Vector3(x, y, half_depth - 0.6), 0.16, 0.22, steel)
	# Yellow cross-bracing: an X in the end bays of each side wall and of the roof.
	var bay_length := (depth - 2.0) / bays
	for bay_index in [0, bays - 1]:
		var z0 := -half_depth + 1.0 + bay_length * float(bay_index)
		var z1 := z0 + bay_length
		for side in [-1.0, 1.0]:
			var x: float = float(side) * (inset + 0.38)
			_member(frame, Vector3(x, 0.4, z0), Vector3(x, height - 0.6, z1), 0.08, 0.08, bracing)
			_member(frame, Vector3(x, 0.4, z1), Vector3(x, height - 0.6, z0), 0.08, 0.08, bracing)
			var low_y := height - 0.2
			var high_y := ridge - 0.6
			_member(frame, Vector3(float(side) * inset, low_y, z0), Vector3(0.0, high_y, z1), 0.08, 0.08, bracing)
			_member(frame, Vector3(float(side) * inset, low_y, z1), Vector3(0.0, high_y, z0), 0.08, 0.08, bracing)
	# Vertical ribs on the outside of the cladding, every metre.
	var rib := Color(0.50, 0.53, 0.56)
	var x_rib := -half_width + 0.5
	while x_rib < half_width:
		for z in [half_depth + 0.04, -half_depth - 0.04]:
			var in_door: bool = float(z) > 0.0 and absf(x_rib) < DOOR_SIZE.x * 0.5 + 0.4
			var bottom := DOOR_SIZE.y + 0.1 if in_door else 0.0
			var top := height + RIDGE_RISE * (1.0 - absf(x_rib) / half_width) - 0.1
			_box(frame, Transform3D(Basis.IDENTITY, Vector3(x_rib, (bottom + top) * 0.5, float(z))),
					Vector3(0.08, top - bottom, 0.08), rib)
		x_rib += 1.0
	var z_rib := -half_depth + 0.5
	while z_rib < half_depth:
		for x in [-half_width - 0.04, half_width + 0.04]:
			_box(frame, Transform3D(Basis.IDENTITY, Vector3(float(x), height * 0.5, z_rib)), Vector3(0.08, height, 0.08), rib)
		z_rib += 1.0
	# The door's frame: a heavy steel header and jambs, with hazard stripes.
	_box(frame, Transform3D(Basis.IDENTITY, Vector3(0.0, DOOR_SIZE.y + 0.35, half_depth + 0.2)),
			Vector3(DOOR_SIZE.x + 1.6, 0.7, 0.5), steel)
	for side in [-1.0, 1.0]:
		var jamb_x: float = float(side) * (DOOR_SIZE.x * 0.5 + 0.4)
		_box(frame, Transform3D(Basis.IDENTITY, Vector3(jamb_x, DOOR_SIZE.y * 0.5, half_depth + 0.2)),
				Vector3(0.8, DOOR_SIZE.y, 0.5), steel)
		for stripe in 8:
			var y := 0.3 + float(stripe) * 0.6
			var tilt := Basis(Vector3.FORWARD, deg_to_rad(35.0))
			_box(frame, Transform3D(tilt, Vector3(jamb_x, y, half_depth + 0.47)), Vector3(0.75, 0.22, 0.02),
					bracing if stripe % 2 == 0 else Color(0.08, 0.08, 0.08))
	frame.generate_normals()
	var steelwork := MeshInstance3D.new()
	steelwork.name = "Steelwork"
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.6
	look.metallic = 0.35
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := frame.commit()
	mesh.surface_set_material(0, look)
	steelwork.mesh = mesh
	garage.add_child(steelwork)

	# A sign over the door.
	var sign_label := Label3D.new()
	sign_label.text = "HANGAR 1"
	sign_label.font_size = 260
	sign_label.pixel_size = 0.01
	sign_label.modulate = Color(0.96, 0.96, 0.92)
	sign_label.outline_size = 24
	sign_label.outline_modulate = Color(0.1, 0.1, 0.12)
	sign_label.position = Vector3(0.0, height + RIDGE_RISE * 0.35, half_depth + 0.12)
	garage.add_child(sign_label)

	# Floor: polished concrete with yellow lines marking the bays.
	_solid(garage, Vector3(width - thick * 2.0, 0.02, depth - thick * 2.0), Vector3(0.0, 0.011, 0.0), Color(0.55, 0.56, 0.58))
	for side in [-1.0, 1.0]:
		_solid(garage, Vector3(0.25, 0.022, depth - 3.0), Vector3(float(side) * (DOOR_SIZE.x * 0.5 - 0.5), 0.012, 0.0), bracing)
	_solid(garage, Vector3(DOOR_SIZE.x - 1.0, 0.022, 0.25), Vector3(0.0, 0.012, -half_depth + 1.5), bracing)

	# High-bay lamps hung from the trusses, and two lights that cast shadows.
	for row in 3:
		for column in 4:
			var lamp_at := Vector3(-half_width * 0.6 + half_width * 0.4 * float(column), height - 1.4,
					-half_depth * 0.6 + half_depth * 0.6 * float(row))
			_solid(garage, Vector3(0.9, 0.25, 0.9), lamp_at, Color(1.0, 0.97, 0.88) * 1.4)
	for lamp_side in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(float(lamp_side) * width * 0.22, height - 2.0, 0.0)
		lamp.omni_range = 34.0
		lamp.light_energy = 2.2
		lamp.shadow_enabled = true   # so the walls keep the light indoors
		garage.add_child(lamp)

	# --- The roller door: its own body, so it can roll up out of the way ---
	_garage_door = StaticBody3D.new()
	_garage_door.physics_material_override = Units.world_surface()
	_garage_door.name = "HangarDoor"
	garage.add_child(_garage_door)
	_garage_door_collider = _wall(_garage_door, Vector3(DOOR_SIZE.x, DOOR_SIZE.y, 0.2),
			Vector3(0.0, DOOR_SIZE.y * 0.5, front), door_color)
	for panel in range(1, 12):
		var seam_height := DOOR_SIZE.y * float(panel) / 12.0
		_solid(_garage_door, Vector3(DOOR_SIZE.x, 0.07, 0.26), Vector3(0.0, seam_height, front), seam)

	# A concrete apron from the door to the pad. It is too thin to trip on.
	var apron_width := DOOR_SIZE.x + 6.0
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
		[Rect2(centre.x - half_width, centre.z - half_depth, width, depth), Color(0.42, 0.46, 0.52), "Hangar"],
	]


## A triangular gable end above the eaves, solid.
func _gable(body: StaticBody3D, half_width: float, eave: float, ridge: float, z: float, thick: float, color: Color) -> void:
	var points := PackedVector3Array()
	for dz in [-thick * 0.5, thick * 0.5]:
		points.append(Vector3(-half_width, eave, z + float(dz)))
		points.append(Vector3(half_width, eave, z + float(dz)))
		points.append(Vector3(0.0, ridge, z + float(dz)))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(color)
	for index in [0, 1, 2, 3, 5, 4, 0, 3, 4, 0, 4, 1, 1, 4, 5, 1, 5, 2, 2, 5, 3, 2, 3, 0]:
		surface.add_vertex(points[index])
	surface.generate_normals()
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.roughness = 0.85
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := surface.commit()
	mesh.surface_set_material(0, look)
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	body.add_child(shown)


## A box wall turned by `place`: something to see and something to walk into.
func _tilted_wall(body: StaticBody3D, size: Vector3, place: Transform3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	material.metallic = 0.3
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	shown.transform = place
	body.add_child(shown)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = place
	body.add_child(collider)


## One roof truss across the hangar at `z`: a bottom chord at the eaves, top
## chords up to the ridge, and a Warren web of diagonals between them.
func _truss(surface: SurfaceTool, z: float, inset: float, eave: float, ridge: float, color: Color) -> void:
	var bottom := eave - 0.45
	_member(surface, Vector3(-inset, bottom, z), Vector3(inset, bottom, z), 0.3, 0.3, color)
	for side in [-1.0, 1.0]:
		var s: float = side
		_member(surface, Vector3(s * inset, eave - 0.05, z), Vector3(0.0, ridge - 0.45, z), 0.3, 0.32, color)
	var panels := 12
	var previous := Vector3(-inset, bottom, z)
	for index in range(1, panels + 1):
		var x := -inset + 2.0 * inset * float(index) / panels
		var top_y := lerpf(eave - 0.05, ridge - 0.45, 1.0 - absf(x) / inset)
		var top := Vector3(x, top_y - 0.1, z)
		var low := Vector3(x, bottom, z)
		_member(surface, low, top, 0.12, 0.12, color)   # vertical
		if index % 2 == 1:
			_member(surface, previous, top, 0.14, 0.14, color)
		else:
			var previous_top_y := lerpf(eave - 0.05, ridge - 0.45, 1.0 - absf(previous.x) / inset)
			_member(surface, Vector3(previous.x, previous_top_y - 0.1, z), low, 0.14, 0.14, color)
		previous = low


## An I-beam from `a` to `b`: a web and two flanges. `section` is the depth
## of the beam (across the hangar) and `flange` the width of its flanges.
func _i_beam(surface: SurfaceTool, a: Vector3, b: Vector3, section: float, flange: float, color: Color) -> void:
	var length := a.distance_to(b)
	var middle := (a + b) * 0.5
	var place := Transform3D(Basis.IDENTITY, middle)
	_box(surface, place, Vector3(section, length, 0.06), color)                                   # web
	_box(surface, place.translated_local(Vector3(section * 0.5 - 0.04, 0.0, 0.0)), Vector3(0.08, length, flange), color)
	_box(surface, place.translated_local(Vector3(-section * 0.5 + 0.04, 0.0, 0.0)), Vector3(0.08, length, flange), color)


## A straight member from `a` to `b` with a `w` × `h` section.
func _member(surface: SurfaceTool, a: Vector3, b: Vector3, w: float, h: float, color: Color) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.001:
		return
	var forward := along / length
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := up.cross(forward).normalized()
	var top := forward.cross(side).normalized()
	_box(surface, Transform3D(Basis(side, top, forward), (a + b) * 0.5), Vector3(w, h, length), color)


## A box into a merged mesh.
func _box(surface: SurfaceTool, place: Transform3D, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var c: Array = []
	for corner in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		c.append(place * ((corner as Vector3) * h))
	surface.set_color(color)
	for face in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		var f: Array = face
		for index in [0, 1, 2, 0, 2, 3]:
			surface.add_vertex(c[f[index]])


## Rolls the hangar door up into its top, or back down, over a second and a
## half. It stops being solid as it starts to open and is solid again once
## it has closed.
func _on_garage_button() -> void:
	_garage_open = not _garage_open
	_hud.set_garage_open(_garage_open)
	if _garage_door_parts.is_empty():
		for child in _garage_door.get_children():
			if child is MeshInstance3D:
				_garage_door_parts.append([child, (child as MeshInstance3D).transform])
	if _garage_open:
		_garage_door_collider.set_deferred("disabled", true)
	_garage_door.visible = true
	if _door_tween != null and _door_tween.is_valid():
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.tween_method(_set_door_shut, _door_shut, 0.0 if _garage_open else 1.0, 1.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_door_tween.tween_callback(func() -> void:
		_garage_door.visible = not _garage_open
		if not _garage_open:
			_garage_door_collider.set_deferred("disabled", false))


## How far down the door is: 1 shut, 0 rolled up. Squeezes its panels up
## toward the top of the opening.
func _set_door_shut(amount: float) -> void:
	_door_shut = amount
	var shown := maxf(amount, 0.02)
	for item in _garage_door_parts:
		var part: MeshInstance3D = item[0]
		var original: Transform3D = item[1]
		var place := original
		place.basis = Basis.from_scale(Vector3(1.0, shown, 1.0)) * original.basis
		place.origin.y = original.origin.y * shown + DOOR_SIZE.y * (1.0 - shown)
		part.transform = place


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
