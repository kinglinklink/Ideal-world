extends Node3D
## The fleet: saved builds spawned out into the world as vehicles of their
## own, from the Fleet window. Each stays where it is, working, until it is
## despawned on its own or with all the others, so whole fleets can be left
## parked round the map. The build on the pad is separate and carries on as
## before.
##
## A vehicle is spawned a few metres in front of the character, facing the
## way the character faces, resting on the ground (or floating on the lake).
## Each has its own spawner, logic, engines and guns; you can sit in any of
## their seats.

const Spawner = preload("res://scripts/spawner.gd")
const Logic = preload("res://scripts/logic.gd")
const Engines = preload("res://scripts/engines.gd")
const Combat = preload("res://scripts/combat.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const MapInfo = preload("res://scripts/map_info.gd")

const MAX_VEHICLES := 8
const GAP := 6.0    # metres between the character and the near end of a new vehicle

var terrain: Node3D = null    # terrain.gd
var structures: Array = []    # what guns can damage: towns.gd, towers.gd
var vehicles: Array = []      # {"name", "spawner", "logic", "engines", "combat", "parts", "mass"}
var player: Node3D = null     # player.gd: vehicles far from it are parked
var main_spawner: Node = null # the pad's build, parked the same way

const PARK_DISTANCE := 3000.0     # metres from the player at which a vehicle is frozen where it is
const WAKE_DISTANCE := 2500.0     # and set going again
var _park_check := 0.0


## Spawns a saved build in front of `near` (the player). Returns a message to show.
func spawn_save(save_name: String, near: Node3D) -> String:
	_forget_gone()
	if vehicles.size() >= MAX_VEHICLES:
		return "The fleet is full (%d vehicles). Despawn one first." % MAX_VEHICLES
	var grid: Node3D = BuildGrid.new()
	grid.visible = false
	add_child(grid)
	var loaded: Dictionary = SaveManager.load_build(grid, save_name)
	if str(loaded.get("error", "")) != "" or grid.part_count() == 0:
		grid.queue_free()
		var error := str(loaded.get("error", ""))
		return error if error != "" else "\"%s\" has no parts." % save_name
	grid.set_active(false)

	# Where it goes: in front of the character, its forward (a seat's −Z)
	# the way the character faces.
	var bounds := AABB()
	var first := true
	for uid in grid.all_uids():
		var box: AABB = BuildGrid.bounds_of(grid.get_part(uid))
		bounds = box if first else bounds.merge(box)
		first = false
	var heading: float = near.get_heading()
	var turn := Basis(Vector3.UP, heading)
	var forward := turn * Vector3.FORWARD
	var reach := maxf(bounds.size.x, bounds.size.z) * 0.5
	var middle_world: Vector3 = near.global_position + forward * (GAP + reach)
	# Rest it on the highest ground under it, or on the water.
	var floor_y := -INF
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		var spot: Vector2 = corner
		var probe := middle_world + turn * Vector3(spot.x * bounds.size.x * 0.5, 0.0, spot.y * bounds.size.z * 0.5)
		var ground: float = terrain.ground_at(probe) if terrain != null else near.global_position.y
		floor_y = maxf(floor_y, maxf(ground, MapInfo.LAKE_Y))
	var centre_local := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var origin := Vector3(middle_world.x, floor_y + 0.4, middle_world.z) - turn * centre_local
	origin.y = floor_y + 0.4 - bounds.position.y
	grid.global_transform = Transform3D(turn, origin)

	var spawner: Node3D = Spawner.new()
	spawner.name = "Vehicle%d" % Time.get_ticks_msec()
	add_child(spawner)
	spawner.terrain = terrain
	var report: Dictionary = spawner.spawn(grid)
	grid.queue_free()
	var logic: Node3D = Logic.new()
	add_child(logic)
	logic.setup(spawner)
	logic.terrain = terrain
	var engines: Node3D = Engines.new()
	add_child(engines)
	engines.setup(spawner)
	var combat: Node3D = Combat.new()
	add_child(combat)
	combat.resets_world = false   # only Build on the pad puts the world back
	combat.setup(spawner)
	combat.terrain = terrain
	combat.structures = structures
	vehicles.append({"name": save_name, "spawner": spawner, "logic": logic, "engines": engines, "combat": combat,
			"parts": int(report.get("parts", 0)), "mass": float(report.get("mass", 0.0))})
	return "Spawned \"%s\": %d parts, %.0f kg." % [save_name, int(report.get("parts", 0)), float(report.get("mass", 0.0))]


func despawn(index: int) -> void:
	if index < 0 or index >= vehicles.size():
		return
	var vehicle: Dictionary = vehicles[index]
	if is_instance_valid(vehicle["spawner"]):
		vehicle["spawner"].despawn()
	for key in ["logic", "engines", "combat", "spawner"]:
		if is_instance_valid(vehicle[key]):
			(vehicle[key] as Node).queue_free()
	vehicles.remove_at(index)


func despawn_all() -> void:
	while not vehicles.is_empty():
		despawn(vehicles.size() - 1)


func _forget_gone() -> void:
	for index in range(vehicles.size() - 1, -1, -1):
		if not is_instance_valid(vehicles[index]["spawner"]):
			vehicles.remove_at(index)


## The spawners of every vehicle in the fleet.
func spawners() -> Array:
	var list: Array = []
	for item in vehicles:
		if is_instance_valid(item["spawner"]):
			list.append(item["spawner"])
	return list


## Every fleet body's place and speed, for the ground to stay solid under them.
func body_motions() -> Array:
	var motions: Array = []
	for spawner in spawners():
		motions.append_array(spawner.body_motions())
	return motions


## Where each vehicle is: [world position, name], for the maps.
func positions() -> Array:
	var list: Array = []
	for item in vehicles:
		if not is_instance_valid(item["spawner"]):
			continue
		var spawner: Node = item["spawner"]
		var motions: Array = spawner.body_motions()
		if motions.is_empty():
			continue
		var first_motion: Array = motions[0]
		list.append([first_motion[0], str(item["name"])])
	return list


## Vehicles far from the player freeze where they are, keeping their speed,
## and carry on as they were when the player comes back: so a fleet parked
## round the map costs nothing while you are away.
func _physics_process(delta: float) -> void:
	_park_check -= delta
	if _park_check > 0.0 or player == null:
		return
	_park_check = 0.5
	var all: Array = spawners()
	if main_spawner != null and bool(main_spawner.spawned):
		all.append(main_spawner)
	for item in all:
		var spawner: Node = item
		var at: Variant = spawner.where()
		if at == null:
			continue
		var distance: float = (at as Vector3).distance_to(player.global_position)
		if not bool(spawner.parked) and distance > PARK_DISTANCE:
			spawner.set_parked(true)
		elif bool(spawner.parked) and distance < WAKE_DISTANCE:
			spawner.set_parked(false)


## Moves every vehicle with the rest of the world when main.gd re-centres it.
func shift_origin(shift: Vector3) -> void:
	for item in vehicles:
		if is_instance_valid(item["spawner"]):
			item["spawner"].shift_origin(shift)
		if is_instance_valid(item["combat"]):
			var combat: Node3D = item["combat"]
			combat.position -= shift
			combat.shift_origin(shift)
