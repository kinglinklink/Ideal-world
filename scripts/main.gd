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
const Stress = preload("res://scripts/stress.gd")
const Rigging = preload("res://scripts/rigging.gd")
const Weather = preload("res://scripts/weather.gd")
const Disasters = preload("res://scripts/disasters.gd")
const WeatherPanel = preload("res://scripts/weather_panel.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Races = preload("res://scripts/races.gd")

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
var _rigging: Node              # rigging.gd: magnets, winches and couplers of the pad's build
var _weather: Node              # weather.gd
var _clock_save := 60.0
var _missions: Node = null      # missions.gd
var _disasters: Node            # disasters.gd
var _weather_panel: RefCounted  # weather_panel.gd
var _panel_timer := 0.0
var _races: Node               # races.gd: races, cargo runs and the people who offer them
var _recent_hurt := 0.0         # health lost in the last second or so, for the crash replay
const CRASH_REPLAY_HURT := 35.0 # lose this much in a moment while riding and the replay plays
const START_HEADING := PI
const Profile = preload("res://scripts/profile.gd")
const Missions = preload("res://scripts/missions.gd")
const Birds = preload("res://scripts/birds.gd")
const BirdGuide = preload("res://scripts/bird_guide.gd")
const PhotoCamera = preload("res://scripts/photo_camera.gd")
const Fuel = preload("res://scripts/fuel.gd")
const Boats = preload("res://scripts/boats.gd")
const Ice = preload("res://scripts/ice.gd")
const Flowers = preload("res://scripts/flowers.gd")
const DamageFx = preload("res://scripts/damage_fx.gd")
const FailureLog = preload("res://scripts/failure_log.gd")
const Inspector = preload("res://scripts/inspector.gd")
const PerfOverlay = preload("res://scripts/perf_overlay.gd")
const TestStand = preload("res://scripts/test_stand.gd")
const FALLEN_OUT_Y := -600.0         # map y below which the character has fallen out of the world


func _ready() -> void:
	_make_sky_and_sun()

	# Weather, wind, waves and the seasons.
	var weather: Node = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.daylight = _daylight
	_weather = weather

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
	map_features.append([Rect2(pad_size.x + 8.0, pad_size.z * 0.5 - TestStand.SIZE * 0.5, TestStand.SIZE, TestStand.SIZE),
			Color(0.5, 0.48, 0.4), "Test stand"])

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

	# Magnets, winches and couplers.
	var rigging: Node = Rigging.new()
	rigging.name = "Rigging"
	add_child(rigging)
	rigging.setup(spawner)
	_rigging = rigging

	# The map: ground, lake, forests, airports and the wall round the edge.
	# Set up before the first physics step, so the ground is solid under the
	# character from the start.
	var terrain: Node3D = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var noise := _grass_noise()
	terrain.setup(player, spawner, noise)
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
	menus.connect("runway_requested", send_build_to_runway)
	menus.connect("slot_chosen", _on_slot_chosen)
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
	player.hurt_taken.connect(_on_hurt)

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

	# Tornadoes, hurricanes, tsunamis, earthquakes and the volcano, and the
	# Weather window that sets the weather and starts them.
	var disasters: Node = Disasters.new()
	disasters.name = "Disasters"
	add_child(disasters)
	disasters.weather = _weather
	disasters.terrain = terrain
	disasters.daylight = _daylight
	disasters.game_hud = game_hud
	disasters.player = player
	disasters.noise = noise
	_disasters = disasters
	_weather.player = player
	_weather_panel = WeatherPanel.new()
	_weather_panel.build(game_hud, _weather, disasters)
	hud.weather_pressed.connect(func() -> void:
		_weather_panel.toggle()
		player.cursor_free = true)

	# Cars on the highways and planes in the sky; races and cargo runs.
	var traffic: Node = Traffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(terrain, player)
	var races: Node = Races.new()
	races.name = "Races"
	add_child(races)
	races.player = player
	races.controller = controller
	races.fleet = _fleet
	races.game_hud = game_hud
	races.minimap = hud.minimap()
	races.setup(terrain, traffic.roads)
	controller.talk_handler = Callable(races, "talk")
	_races = races

	# Birds and their nests, the bird guide (B) and the camera (C).
	var birds: Node3D = Birds.new()
	birds.name = "Birds"
	add_child(birds)
	birds.terrain = terrain
	birds.weather = _weather
	birds.player = player
	birds.game_hud = game_hud
	birds.islands = hud.minimap().islands()
	birds.towns = hud.minimap().towns()
	birds.setup()
	var guide := BirdGuide.new()
	guide.player = player
	game_hud.root.add_child(guide)
	var camera_tool: CanvasLayer = PhotoCamera.new()
	camera_tool.name = "PhotoCamera"
	add_child(camera_tool)
	camera_tool.screens = [hud, game_hud]
	camera_tool.birds = birds
	camera_tool.game_hud = game_hud
	camera_tool.player = player
	hud.birds_pressed.connect(guide.toggle)
	hud.photos_pressed.connect(camera_tool.toggle_photos)

	# The docks, boats on the lake in summer, and boat races at the docks.
	var boats: Node = Boats.new()
	boats.name = "Boats"
	add_child(boats)
	boats.terrain = terrain
	boats.weather = _weather
	boats.player = player
	boats.setup()
	races.add_boat_hosts(boats.docks)
	combat.structures.append(boats)
	var ice: Node3D = Ice.new()
	ice.name = "Ice"
	add_child(ice)
	ice.terrain = terrain
	ice.weather = _weather
	ice.player = player
	var flowers: Node3D = Flowers.new()
	flowers.name = "Flowers"
	add_child(flowers)
	flowers.terrain = terrain
	flowers.weather = _weather
	flowers.player = player

	# Fuel stations, smoke and fire on damaged builds, and the failure log (L).
	var fuel: Node = Fuel.new()
	fuel.name = "Fuel"
	add_child(fuel)
	fuel.terrain = terrain
	fuel.races = races
	fuel.roads = traffic.roads
	fuel.player = player
	fuel.game_hud = game_hud
	fuel.setup()
	for dock in boats.docks:
		fuel.add_dock_station(str(dock["name"]), Vector2((dock["shore"] as Vector3).x, (dock["shore"] as Vector3).z))
	var effects: Node3D = DamageFx.new()
	effects.name = "DamageFx"
	add_child(effects)
	var failures: CanvasLayer = FailureLog.new()
	failures.name = "FailureLog"
	add_child(failures)
	camera_tool.screens.append(failures)
	_replay.screens.append(failures)

	# The Inspector (8), the performance overlay (F3) and the test stand.
	var inspector: Node = Inspector.new()
	inspector.name = "Inspector"
	inspector.spawner = spawner
	inspector.engines = engines
	inspector.game_hud = game_hud
	add_child(inspector)
	var overlay: CanvasLayer = PerfOverlay.new()
	overlay.name = "PerfOverlay"
	overlay.spawner = spawner
	overlay.engines = engines
	add_child(overlay)
	camera_tool.screens.append(overlay)
	var stand: Node3D = TestStand.new()
	stand.name = "TestStand"
	stand.spawner = spawner
	stand.controller = controller
	stand.grid = grid
	stand.terrain = terrain
	stand.game_hud = game_hud
	stand.player = player
	add_child(stand)
	stand.setup(pad_size)
	hud.test_stand_pressed.connect(func() -> void: stand.open_stand())
	hud.runway_pressed.connect(send_build_to_runway)

	# The mission board, and the markers on the full map.
	var missions: Node = Missions.new()
	missions.name = "Missions"
	add_child(missions)
	missions.races = races
	missions.terrain = terrain
	missions.minimap = hud.minimap()
	missions.game_hud = game_hud
	missions.player = player
	missions.birds = birds
	missions.setup()
	camera_tool.missions = missions
	hud.world_map().missions = missions
	_missions = missions


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_P \
			and get_viewport().gui_get_focus_owner() == null:
		_respawn()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == KEY_M \
			and get_viewport().gui_get_focus_owner() == null:
		_hud.toggle_world_map()
	elif key != null and key.pressed and not key.echo and key.physical_keycode == KEY_9 \
			and get_viewport().gui_get_focus_owner() == null and bool(_controller.spawned):
		Stress.view = not Stress.view
		_game_hud.announce("", "Stress view on: blue easy, red at breaking point" if Stress.view else "Stress view off", 2.5)


## A save slot was picked: the year and the day carry on from where that
## slot left them, and the character starts at the hangar.
func _on_slot_chosen(_slot: int) -> void:
	var saved: Dictionary = Profile.clock()
	if not saved.is_empty() and _weather != null and _daylight != null:
		_weather.year_fraction = float(saved.get("year", _weather.year_fraction))
		_weather.day = int(saved.get("day", 0))
		_daylight.set_time(float(saved.get("time", 0.1)))
	_respawn()
	get_tree().call_group("slot_listeners", "slot_changed")


## Notes the year and the time of day in the slot, and saves it.
func _keep_clock() -> void:
	if _weather == null or _daylight == null:
		return
	Profile.set_clock(_weather.year_fraction, _weather.day, _daylight.day_fraction)
	Profile.save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_keep_clock()


# --- To runway ---------------------------------------------------------------

const RUNWAY_MARGIN := 25.0   # metres from the runway's end to the back of the build

## Takes the build (spawning it first if need be) to the start of a runway,
## level, facing down it, standing on its wheels. The nearest asphalt runway
## first; pressed again while still parked at the start, the next one along
## (in order of distance from the hangar). The way the build faces is the
## way its seat faces (or its thrusters push, with no seat).
func send_build_to_runway() -> void:
	if not bool(_controller.spawned):
		_controller.toggle_spawn()
		if not bool(_controller.spawned):
			return
	var main_body: RigidBody3D = _spawner.heaviest_body()
	if main_body == null:
		return
	var runways: Array = []
	for item in _terrain.world.get("runways", []):
		var runway: Dictionary = item
		if str(runway.get("surface", "")) == "asphalt":
			runways.append(runway)
	if runways.is_empty():
		return
	var home := Vector2(_start.x, _start.z)
	runways.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _runway_start(a).distance_to(home) < _runway_start(b).distance_to(home))
	# Nearest to the build, unless it is already parked at one's start.
	var here: Vector3 = Origin.to_map(main_body.global_position)
	var flat_here := Vector2(here.x, here.z)
	var pick := 0
	var best := INF
	for index in runways.size():
		var gap: float = _runway_start(runways[index]).distance_to(flat_here)
		if gap < RUNWAY_MARGIN + 60.0 and main_body.linear_velocity.length() < 5.0:
			pick = (index + 1) % runways.size()
			best = -1.0
			break
		var middle: Array = (runways[index] as Dictionary)["centre"]
		var distance := Vector2(float(middle[0]), float(middle[1])).distance_to(flat_here)
		if distance < best:
			best = distance
			pick = index
	var chosen: Dictionary = runways[pick]
	var heading := deg_to_rad(float(chosen["heading"]))
	var along := Vector3(sin(heading), 0.0, -cos(heading))
	var side := Vector3(-along.z, 0.0, along.x)
	# Level the build as it was built and turn it to face down the runway.
	var now := main_body.global_transform.basis.orthonormalized()
	var built: Basis = _spawner.grid_basis().orthonormalized()
	var forward := _build_forward(main_body)
	var level_forward: Vector3 = built * (now.inverse() * forward)
	level_forward.y = 0.0
	if level_forward.length() < 0.01:
		level_forward = built * Vector3.BACK
	var turn := atan2(along.x, along.z) - atan2(level_forward.x, level_forward.z)
	var rotate: Basis = Basis(Vector3.UP, turn) * built * now.inverse()
	var pivot: Vector3 = main_body.global_position
	# Where its corners end up, turned about the pivot: how far it reaches
	# back, out to each side and down.
	var rear := INF
	var front := -INF
	var left := INF
	var right := -INF
	var low := INF
	for corner in _build_corners():
		var turned: Vector3 = rotate * (corner - pivot)
		rear = minf(rear, turned.dot(along))
		front = maxf(front, turned.dot(along))
		left = minf(left, turned.dot(side))
		right = maxf(right, turned.dot(side))
		low = minf(low, turned.y)
	if low == INF:
		return
	var end := _runway_start(chosen)
	var target := Vector3(end.x, 0.0, end.y) + along * (RUNWAY_MARGIN - rear) - side * ((left + right) * 0.5)
	var ground := -INF
	for share in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var point: Vector3 = target + along * lerpf(rear, front, share)
		ground = maxf(ground, float(_terrain.height_at(point.x, point.z)))
	target.y = ground + 0.3 - low
	var place := Origin.to_world(target)
	_spawner.teleport(Transform3D(rotate, place - rotate * pivot))
	# The character comes too: in the seat it is carried along; on foot it
	# is put on the runway in front of the build, facing it.
	_player.forget_motion()
	if int(_controller.seat_uid) == 0:
		var stand := Vector3(target.x, 0.0, target.z) + along * (front + 6.0)
		stand.y = float(_terrain.height_at(stand.x, stand.z)) + 0.1
		_player.teleport(Origin.to_world(stand), atan2(along.x, along.z))
	_terrain.make_solid_now()
	_game_hud.announce("", "%s runway, %d m. Press To runway again for the next one." % [str(chosen.get("name", "")), int(float(chosen.get("length", 0.0)))], 4.0)


## The map point (x, z) of a runway's start: the end its heading leads away from.
static func _runway_start(runway: Dictionary) -> Vector2:
	var middle: Array = runway["centre"]
	var heading := deg_to_rad(float(runway["heading"]))
	var along := Vector2(sin(heading), -cos(heading))
	return Vector2(float(middle[0]), float(middle[1])) - along * (float(runway["length"]) * 0.5)


## The way the build faces, in the world: its first seat's forward, or the
## way its thrusters push, or failing both its body's own forward (-Z).
func _build_forward(main_body: RigidBody3D) -> Vector3:
	var records: Dictionary = _spawner.all_records()
	var push := Vector3.ZERO
	for key in records:
		var uid: int = key
		var type := str((records[uid] as Dictionary).get("type", ""))
		if type == "seat":
			var frame: Array = _spawner.seat_frame(uid)
			if not frame.is_empty():
				return -(frame[0] as Transform3D).basis.z.normalized()
		elif type == "thruster":
			var place: Array = _spawner.part_frame(uid)
			if not place.is_empty():
				push += -(place[0] as Transform3D).basis.z.normalized()
	if push.length() > 0.01:
		return push.normalized()
	return -main_body.global_transform.basis.z.normalized()


## Every corner of every solid shape in the spawned build, in the world:
## a box's own corners, and the corners of the box round anything else.
func _build_corners() -> PackedVector3Array:
	var corners := PackedVector3Array()
	for item in _spawner.all_bodies():
		var body := item as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		for child in body.get_children():
			var collider := child as CollisionShape3D
			if collider == null or collider.disabled or collider.shape == null:
				continue
			var box := _shape_box(collider.shape)
			var to_world: Transform3D = collider.global_transform
			for index in 8:
				corners.append(to_world * box.get_endpoint(index))
	return corners


static func _shape_box(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if not points.is_empty():
			var box := AABB(points[0], Vector3.ZERO)
			for point in points:
				box = box.expand(point)
			return box
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return AABB(Vector3(-cylinder.radius, -cylinder.height * 0.5, -cylinder.radius),
				Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0))
	if shape is SphereShape3D:
		var radius: float = (shape as SphereShape3D).radius
		return AABB(-Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	var mesh: ArrayMesh = shape.get_debug_mesh()
	return mesh.get_aabb() if mesh != null else AABB()


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


## A big crash you live through plays the replay too.
func _on_hurt(amount: float) -> void:
	_game_hud.flash_hurt(amount)
	_recent_hurt += amount
	if _recent_hurt >= CRASH_REPLAY_HURT and not _player.dead and bool(_player.seated) and not _replay.active:
		_recent_hurt = 0.0
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if not _player.dead and not _replay.active:
				_replay.start("Big crash!"))


func _on_replay_finished(_reason: String) -> void:
	if _respawn_after_replay:
		_respawn_after_replay = false
		_respawn()


func _process(delta: float) -> void:
	_recent_hurt = maxf(_recent_hurt - delta * 30.0, 0.0)
	_clock_save -= delta
	if _clock_save <= 0.0:
		_clock_save = 60.0
		_keep_clock()
	_panel_timer -= delta
	if _panel_timer <= 0.0 and _weather_panel != null:
		_panel_timer = 0.5
		_weather_panel.refresh()


# --- Keeping the world centred on the player ------------------------------------

func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var at := _player.global_position
	if absf(at.x) > Origin.SHIFT_DISTANCE or absf(at.z) > Origin.SHIFT_DISTANCE:
		var shift := Vector3(snappedf(at.x, Origin.SHIFT_STEP), 0.0, snappedf(at.z, Origin.SHIFT_STEP))
		_shift_world(shift)
	# Far below anything there is (the deepest cavern floor is about 160 m
	# under the pad): fallen out of the world, so back to the hangar.
	if Origin.to_map(at).y < FALLEN_OUT_Y and not bool(_player.seated):
		_game_hud.announce("", "You fell out of the world. Back to the hangar.", 3.0)
		_respawn()


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
	_rigging.shift_origin(shift)
	if _disasters != null:
		_disasters.shift_origin(shift)
	if _races != null:
		_races.shift_origin(shift)
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
