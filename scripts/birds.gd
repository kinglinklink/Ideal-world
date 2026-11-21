extends Node3D
## Birds and their nests (the species are in bird_data.gd).
##
## The map is cut into AREA m squares. As you come near a square, each
## species in season gets one roll: its chance follows how common it really
## is (60 % for an abundant bird, down to 0.1 % for an accidental stray),
## three times better where its nests are. A hit puts a group of them down
## at a spot in the square that suits them (water, shore, marsh, forest,
## meadow, ridge or town). Squares you leave behind are cleared, and can
## roll again a few minutes later.
##
## Birds are scenery: invincible, with no collision. Each kind moves its
## own way (birds.gd _move_*): songbirds flit between perches, geese float
## and fly round in a V, ospreys circle, hover and dive, herons wade,
## ducks, grebes and swans paddle, eagles and ravens soar, swallows skim
## the water and hummingbirds hover. Explosions and fast vehicles scatter
## them.
##
## Hover the mouse over a bird (or put the crosshair on it in first
## person) and the camera eases in on it, with its name; the bird guide
## (bird_guide.gd) ticks it off as spotted. Move the mouse well away and
## the camera eases back.
##
## Nests sit where each kind really nests (stick nests on snags and tall
## shore trees, a heron colony by the river mouths, goose nests on Goose and
## Douglas Islands, floating grebe nests in the north-shore reeds, holes in
## dead trees), with eggs in spring and chicks in summer. Nests are solid
## scenery too, and cannot be hurt.

const BirdData = preload("res://scripts/bird_data.gd")
const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Profile = preload("res://scripts/profile.gd")
const Sound = preload("res://scripts/sound.gd")
const Profiler = preload("res://scripts/profiler.gd")

const AREA := 800.0              # m, the squares birds are rolled for
const NEAR := 1600.0             # m, squares nearer than this are rolled
const FAR := 2600.0              # m, groups further than this are cleared
const REROLL := 180.0            # s before a cleared square can roll again
const MAX_GROUPS := 40
const MAX_BIRDS := 170
const NEST_NEAR := 1400.0
const NEAR_EVERY_FRAME := 300.0  # m: groups nearer than this move every frame
const WINGS_SEEN := 450.0        # m: past this the wings are not worth flapping
const FAR_DRAWN := 1500.0        # m: past this birds are not drawn
const HOVER_PIXELS := 16.0
const LEAVE_PIXELS := 90.0       # mouse movement that ends a close-up

var terrain: Node = null         # terrain.gd
var weather: Node = null         # weather.gd, for the season and the water
var player: Node3D = null        # player.gd
var game_hud: Node = null        # game_hud.gd
var islands: Array = []          # [Vector2 map, name] from the map data
var towns: Array = []            # [Vector2 map, name]

var _random := RandomNumberGenerator.new()
var _groups: Array = []          # {"species", "home": map Vector3, "birds": [], "area": Vector2i, "state": {...}}
var _rolled: Dictionary = {}     # Vector2i area -> true while rolled
var _cooldown: Dictionary = {}   # Vector2i area -> clock when it may roll again
var _clock := 0.0
var _plan := 0.0
var _scare_check := 0.0
var _materials: Dictionary = {}
var _nests: Array = []           # {"kind", "species": [ids], "at": map Vector3, "node", "season"}
var _nest_areas: Dictionary = {} # Vector2i area -> [species ids nesting there]
var _season := ""
var _frame := 0
# The close-up on a bird.
var _hover_bird: Dictionary = {}
var _hover_time := 0.0
var _zoom: Dictionary = {}       # {"bird", "camera", "from", "mouse", "leaving"}
var _card: Label = null
var _card_layer: CanvasLayer = null


func setup() -> void:
	add_to_group("birds")
	_random.randomize()
	_plan_nests()
	_card_layer = CanvasLayer.new()
	_card_layer.layer = 3
	add_child(_card_layer)
	_card = Label.new()
	_card.add_theme_font_size_override("font_size", 22)
	_card.add_theme_constant_override("outline_size", 8)
	_card.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_card.add_theme_color_override("font_color", Color(1.0, 0.97, 0.85))
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card.position.y = 90.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_card_layer.add_child(_card)


func species_count() -> int:
	return BirdData.SPECIES.size()


## Names of the species not yet photographed, commonest first.
func unphotographed() -> Array:
	var list: Array = []
	for species in BirdData.ids():
		if not bool(str(Profile.bird(species).get("photo", "")) != ""):
			list.append("%s (%s)" % [BirdData.SPECIES[species]["name"], str(BirdData.SPECIES[species]["status"]).to_lower()])
	return list


func _here() -> Vector3:
	return Origin.to_map(player.global_position) if player != null else Vector3.ZERO


# --- Where birds live ---------------------------------------------------------------------

## What kind of place a map point is, for birds.
func habitat_at(x: float, z: float) -> String:
	if terrain.is_lake(x, z):
		var shallow := false
		for angle in [0.0, 1.57, 3.14, 4.71]:
			if not terrain.is_lake(x + cos(angle) * 90.0, z + sin(angle) * 90.0):
				shallow = true
		if shallow and (z < -19000.0 or z > 13000.0):
			return "marsh"
		return "water"
	var near_water := false
	for angle in [0.0, 1.57, 3.14, 4.71]:
		if terrain.is_lake(x + cos(angle) * 70.0, z + sin(angle) * 70.0):
			near_water = true
	if near_water:
		return "marsh" if (z < -19000.0 or z > 13000.0) else "shore"
	for item in towns:
		if (item[0] as Vector2).distance_to(Vector2(x, z)) < 1300.0:
			return "town"
	var above: float = terrain.height_at(x, z) - MapInfo.LAKE_Y
	if above > 420.0:
		return "ridge"
	var slope: float = absf(terrain.height_at(x + 20.0, z) - terrain.height_at(x - 20.0, z)) \
			+ absf(terrain.height_at(x, z + 20.0) - terrain.height_at(x, z - 20.0))
	if slope < 6.0 and above < 220.0:
		return "meadow"
	return "forest"


func _on_island(x: float, z: float) -> bool:
	for item in islands:
		if (item[0] as Vector2).distance_to(Vector2(x, z)) < 1200.0:
			return true
	return false


func _suits(species: Dictionary, x: float, z: float) -> bool:
	var habitats: Array = species["habitats"]
	var here := habitat_at(x, z)
	if habitats.has(here):
		return true
	return habitats.has("islands") and here != "water" and _on_island(x, z)


func _water_y(map_point: Vector3) -> float:
	if weather != null and weather.has_method("water_height"):
		return float(weather.water_height(Origin.to_world(map_point))) + Origin.offset.y
	return MapInfo.LAKE_Y


func _ground_y(x: float, z: float) -> float:
	var ground: float = terrain.height_at(x, z)
	return maxf(ground, MapInfo.LAKE_Y) if terrain.is_lake(x, z) else ground


# --- Spawning ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var started := Profiler.start()
	_tick(delta)
	Profiler.add("birds", started)


func _tick(delta: float) -> void:
	if terrain == null or player == null:
		return
	_clock += delta
	_plan -= delta
	if _plan <= 0.0:
		_plan = 2.0
		_plan_areas()
		_plan_nest_nodes()
	_scare_check -= delta
	if _scare_check <= 0.0:
		_scare_check = 0.5
		_scare_by_vehicles()
	# Near birds move every frame; further off, every few frames with the
	# time saved up, and past FAR_DRAWN they are too small to see and not drawn.
	_frame += 1
	var eye := _here()
	for index in _groups.size():
		var group: Dictionary = _groups[index]
		var home: Vector3 = group["home"]
		var distance := Vector2(home.x - eye.x, home.z - eye.z).length()
		var every := 1 if distance < NEAR_EVERY_FRAME else (3 if distance < 900.0 else 6)
		group["owed"] = float(group.get("owed", 0.0)) + delta
		if (_frame + index) % every != 0:
			continue
		group["distance"] = distance
		_run_group(group, float(group["owed"]))
		group["owed"] = 0.0
	_run_hover(delta)


func _plan_areas() -> void:
	var here := _here()
	var season: String = weather.season_name() if weather != null else "summer"
	# Clear groups far away.
	for index in range(_groups.size() - 1, -1, -1):
		var group: Dictionary = _groups[index]
		var home: Vector3 = group["home"]
		if Vector2(home.x, home.z).distance_to(Vector2(here.x, here.z)) > FAR or not (BirdData.SPECIES[group["species"]]["seasons"] as Array).has(season):
			_free_group(group)
			_groups.remove_at(index)
	for key in _rolled.keys():
		var area: Vector2i = key
		var middle := (Vector2(area) + Vector2(0.5, 0.5)) * AREA
		if middle.distance_to(Vector2(here.x, here.z)) > FAR:
			_rolled.erase(area)
			_cooldown[area] = _clock + REROLL
	# Roll squares close by.
	var low := Vector2i(floori((here.x - NEAR) / AREA), floori((here.z - NEAR) / AREA))
	var high := Vector2i(floori((here.x + NEAR) / AREA), floori((here.z + NEAR) / AREA))
	for i in range(low.x, high.x + 1):
		for k in range(low.y, high.y + 1):
			var area := Vector2i(i, k)
			if _rolled.has(area) or float(_cooldown.get(area, 0.0)) > _clock:
				continue
			var middle := (Vector2(area) + Vector2(0.5, 0.5)) * AREA
			if middle.distance_to(Vector2(here.x, here.z)) > NEAR:
				continue
			_rolled[area] = true
			_roll(area, season)


func _bird_count() -> int:
	var count := 0
	for group in _groups:
		count += (group["birds"] as Array).size()
	return count


func _roll(area: Vector2i, season: String) -> void:
	var nesting: Array = _nest_areas.get(area, [])
	for key in BirdData.SPECIES:
		var species: Dictionary = BirdData.SPECIES[key]
		if not (species["seasons"] as Array).has(season):
			continue
		var chance: float = BirdData.STATUS_CHANCE[species["status"]]
		if nesting.has(key):
			chance *= 3.0
		if season == "winter":
			chance *= float(species.get("winter_extra", 1.0))
		if _random.randf() >= chance:
			continue
		if _groups.size() >= MAX_GROUPS or _bird_count() >= MAX_BIRDS:
			return
		for attempt in 16:
			var x := (float(area.x) + _random.randf()) * AREA
			var z := (float(area.y) + _random.randf()) * AREA
			if _suits(species, x, z):
				spawn_group(str(key), Vector3(x, _ground_y(x, z), z))
				break


## Puts a group of `species` down at a map point.
func spawn_group(species_id: String, home: Vector3) -> Dictionary:
	var species: Dictionary = BirdData.SPECIES[species_id]
	var flock: Array = species["flock"]
	var count := _random.randi_range(int(flock[0]), int(flock[1]))
	var group := {"species": species_id, "home": home, "birds": [], "state": {"timer": _random.randf_range(5.0, 20.0), "flying": false, "angle": 0.0}}
	for index in count:
		var bird := _make_bird(species_id, home, index)
		(group["birds"] as Array).append(bird)
	_groups.append(group)
	if str(species["status"]) == "Accidental" and game_hud != null and _distance_to_player(home) < 1200.0:
		game_hud.announce("Rare sighting!", "%s somewhere nearby" % species["name"], 4.0, Color(1.0, 0.6, 0.9))
	return group


func _distance_to_player(map_point: Vector3) -> float:
	return map_point.distance_to(_here())


func _free_group(group: Dictionary) -> void:
	for item in group["birds"]:
		var bird: Dictionary = item
		if is_instance_valid(bird["node"]):
			(bird["node"] as Node).queue_free()
		if not _zoom.is_empty() and _zoom.get("bird") == bird:
			_end_zoom(true)


# --- Models -------------------------------------------------------------------------

func _look(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		_materials[key] = material
	return _materials[key]


func _part(parent: Node3D, mesh: Mesh, color: Color, at: Vector3, size: Vector3, turn := Vector3.ZERO) -> MeshInstance3D:
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	shown.material_override = _look(color)
	shown.position = at
	shown.rotation = turn
	shown.scale = size
	shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shown)
	return shown


static var _ball: SphereMesh = null
static var _cube: BoxMesh = null
static var _rod: CylinderMesh = null
static var _cone: CylinderMesh = null


static func _meshes() -> void:
	if _ball != null:
		return
	_ball = SphereMesh.new()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 10
	_ball.rings = 6
	_cube = BoxMesh.new()
	_rod = CylinderMesh.new()
	_rod.top_radius = 0.5
	_rod.bottom_radius = 0.5
	_rod.height = 1.0
	_rod.radial_segments = 6
	_rod.rings = 1
	_cone = CylinderMesh.new()
	_cone.top_radius = 0.0
	_cone.bottom_radius = 0.5
	_cone.height = 1.0
	_cone.radial_segments = 6
	_cone.rings = 1


## A low-poly bird `length` m long, facing -Z, coloured as the species:
## body, head, beak, tail, two wings on pivots that flap, and legs and a
## long neck for the long-legged and long-necked kinds.
func _make_model(species: Dictionary) -> Dictionary:
	_meshes()
	var look: Array = species["look"]
	var shape := str(species["shape"])
	var root := Node3D.new()
	var model := Node3D.new()
	root.add_child(model)
	var length: float = species["length"]
	model.scale = Vector3.ONE * length
	var body_size := Vector3(0.34, 0.3, 0.6)
	var head_at := Vector3(0.0, 0.14, -0.34)
	var head_size := 0.2
	var beak_length := 0.12
	var neck := false
	var legs := 0.0
	match shape:
		"duck":
			body_size = Vector3(0.4, 0.3, 0.62)
			head_at = Vector3(0.0, 0.24, -0.33)
			beak_length = 0.14
		"goose", "swan":
			body_size = Vector3(0.36, 0.3, 0.6)
			head_at = Vector3(0.0, 0.55 if shape == "goose" else 0.62, -0.46)
			head_size = 0.14
			neck = true
		"wader":
			body_size = Vector3(0.24, 0.24, 0.42)
			head_at = Vector3(0.0, 0.55, -0.28)
			head_size = 0.11
			beak_length = 0.28
			neck = true
			legs = 0.55
		"grebe":
			body_size = Vector3(0.3, 0.24, 0.6)
			head_at = Vector3(0.0, 0.48, -0.36)
			head_size = 0.13
			beak_length = 0.16
			neck = true
		"raptor":
			body_size = Vector3(0.32, 0.3, 0.56)
			head_size = 0.18
			beak_length = 0.08
		"hummer":
			body_size = Vector3(0.28, 0.28, 0.5)
			head_size = 0.24
			beak_length = 0.32
		"woodpecker":
			beak_length = 0.16
	_part(model, _ball, look[0], Vector3.ZERO, body_size)
	_part(model, _ball, look[3], Vector3(0.0, -0.05, -0.04), body_size * Vector3(0.85, 0.75, 0.8))
	if neck:
		var base := Vector3(0.0, 0.08, -0.26)
		var middle := (base + head_at) * 0.5
		var neck_part := _part(model, _rod, look[2] if shape != "wader" else look[0], middle,
				Vector3(0.08, base.distance_to(head_at), 0.08))
		neck_part.look_at_from_position(neck_part.position, head_at, Vector3.FORWARD)
		neck_part.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		neck_part.scale = Vector3(0.08, base.distance_to(head_at), 0.08)
	_part(model, _ball, look[2], head_at, Vector3.ONE * head_size)
	_part(model, _cone, look[4], head_at + Vector3(0.0, 0.0, -head_size * 0.5 - beak_length * 0.5),
			Vector3(0.05 if shape != "duck" else 0.09, beak_length, 0.05), Vector3(-PI * 0.5, 0.0, 0.0))
	_part(model, _cube, look[1], Vector3(0.0, 0.04, 0.36), Vector3(0.18 if shape != "raptor" else 0.28, 0.03, 0.26))
	if legs > 0.0:
		for side in [-1.0, 1.0]:
			_part(model, _rod, Color(0.2, 0.2, 0.18), Vector3(0.05 * side, -0.12 - legs * 0.5, 0.0), Vector3(0.025, legs, 0.025))
	var span: float = float(species["wings"]) / length * 0.5
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.14 * side, 0.08, -0.04)
		model.add_child(pivot)
		_part(pivot, _cube, look[1], Vector3(span * 0.5 * side, 0.0, 0.02), Vector3(span, 0.025, 0.26 if shape != "hummer" else 0.16))
		wings.append(pivot)
	add_child(root)
	return {"node": root, "wings": wings}


func _make_bird(species_id: String, home: Vector3, index: int) -> Dictionary:
	var species: Dictionary = BirdData.SPECIES[species_id]
	var made := _make_model(species)
	var start := home + Vector3(_random.randf_range(-8.0, 8.0), 0.0, _random.randf_range(-8.0, 8.0))
	start.y = _ground_y(start.x, start.z)
	var motion := str(species["motion"])
	if motion == "soar" or motion == "dive":
		start.y += _random.randf_range(60.0, 140.0)
	var bird := {"species": species_id, "node": made["node"], "wings": made["wings"], "at": start, "velocity": Vector3.ZERO,
			"mode": "perch", "target": start, "timer": _random.randf_range(0.5, 6.0), "phase": _random.randf() * TAU,
			"index": index, "length": float(species["length"]), "motion": motion, "flee": 0.0,
			"angle": _random.randf() * TAU, "height": _random.randf_range(60.0, 180.0), "hidden": 0.0}
	if motion == "float":
		bird["at"] = Vector3(start.x, _water_y(start), start.z)
	return bird


# --- Moving -------------------------------------------------------------------------

func _run_group(group: Dictionary, delta: float) -> void:
	var species: Dictionary = BirdData.SPECIES[group["species"]]
	var state: Dictionary = group["state"]
	state["timer"] = float(state["timer"]) - delta
	for item in group["birds"]:
		var bird: Dictionary = item
		bird["phase"] = float(bird["phase"]) + delta
		if float(bird["flee"]) > 0.0:
			_move_flee(bird, delta)
		else:
			match str(bird["motion"]):
				"flit", "flock":
					_move_flit(bird, group, delta)
				"goose":
					_move_goose(bird, group, delta)
				"float":
					_move_float(bird, group, delta)
				"soar":
					_move_soar(bird, group, delta, false)
				"dive":
					_move_soar(bird, group, delta, true)
				"wade":
					_move_wade(bird, group, delta)
				"swoop":
					_move_swoop(bird, group, delta)
				"hover":
					_move_hover(bird, group, delta)
		_place(bird, species, delta, float(group.get("distance", 0.0)))


func _fly_to(bird: Dictionary, target: Vector3, speed: float, delta: float) -> bool:
	var at: Vector3 = bird["at"]
	var off := target - at
	var step := speed * delta
	if off.length() <= step:
		bird["velocity"] = off / maxf(delta, 0.0001)
		bird["at"] = target
		return true
	var wanted := off.normalized() * speed
	bird["velocity"] = (bird["velocity"] as Vector3).lerp(wanted, clampf(delta * 3.0, 0.0, 1.0))
	bird["at"] = at + (bird["velocity"] as Vector3) * delta
	return false


func _move_flit(bird: Dictionary, group: Dictionary, delta: float) -> void:
	var home: Vector3 = group["home"]
	var reach := 50.0 if bird["motion"] == "flit" else 120.0
	var speed := clampf(float(bird["length"]) * 40.0, 6.0, 12.0)
	if bird["mode"] == "perch":
		bird["velocity"] = Vector3.ZERO
		bird["timer"] = float(bird["timer"]) - delta
		if float(bird["timer"]) <= 0.0:
			var target := home + Vector3(_random.randf_range(-reach, reach), 0.0, _random.randf_range(-reach, reach))
			if bird["motion"] == "flock":
				var shared: Dictionary = group["state"]
				if float(shared["timer"]) <= 0.0 or not shared.has("target"):
					shared["target"] = target
					shared["timer"] = _random.randf_range(6.0, 14.0)
				target = (shared["target"] as Vector3) + Vector3(_random.randf_range(-6.0, 6.0), 0.0, _random.randf_range(-6.0, 6.0))
			var ground := _ground_y(target.x, target.z)
			var perch_high := _random.randf() < 0.55 and habitat_at(target.x, target.z) != "water"
			target.y = ground + (_random.randf_range(4.0, 16.0) if perch_high else 0.05)
			if terrain.is_lake(target.x, target.z):
				target.y = maxf(target.y, MapInfo.LAKE_Y + 2.0)
			bird["target"] = target
			bird["mode"] = "fly"
	else:
		var target: Vector3 = bird["target"]
		var at: Vector3 = bird["at"]
		var lift := minf(at.distance_to(target) * 0.25, 10.0)
		if _fly_to(bird, target + Vector3(0.0, lift * 0.3, 0.0), speed, delta):
			bird["mode"] = "perch"
			bird["timer"] = _random.randf_range(2.0, 9.0)


func _move_goose(bird: Dictionary, group: Dictionary, delta: float) -> void:
	var state: Dictionary = group["state"]
	var home: Vector3 = group["home"]
	if not bool(state["flying"]) and float(state["timer"]) <= 0.0:
		state["flying"] = true
		state["timer"] = _random.randf_range(20.0, 35.0)
		state["angle"] = _random.randf() * TAU
	elif bool(state["flying"]) and float(state["timer"]) <= 0.0:
		state["flying"] = false
		state["timer"] = _random.randf_range(30.0, 70.0)
	if bool(state["flying"]):
		state["angle"] = float(state["angle"]) + delta * 0.05 / maxf(float((group["birds"] as Array).size()), 1.0)
		var angle: float = state["angle"]
		var radius := 400.0
		var lead := home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		lead.y = maxf(_ground_y(lead.x, lead.z), MapInfo.LAKE_Y) + 60.0
		var heading := Vector3(-sin(angle), 0.0, cos(angle))
		var side := heading.cross(Vector3.UP)
		var index: int = bird["index"]
		var rank := float((index + 1) >> 1)
		var flank := -1.0 if index % 2 == 0 else 1.0
		var place := lead - heading * rank * 3.0 + side * flank * rank * 2.6
		_fly_to(bird, place, 18.0, delta)
		bird["mode"] = "fly"
	else:
		_move_float(bird, group, delta)


func _move_float(bird: Dictionary, group: Dictionary, delta: float) -> void:
	var home: Vector3 = group["home"]
	var at: Vector3 = bird["at"]
	if bird["mode"] == "fly" and not terrain.is_lake(at.x, at.z):
		# Back to the water to land.
		_fly_to(bird, Vector3(home.x, _water_y(home) + 1.0, home.z), 14.0, delta)
		if Vector2(at.x, at.z).distance_to(Vector2(home.x, home.z)) < 6.0:
			bird["mode"] = "swim"
		return
	bird["mode"] = "swim"
	bird["timer"] = float(bird["timer"]) - delta
	if float(bird["timer"]) <= 0.0:
		bird["timer"] = _random.randf_range(4.0, 12.0)
		var target := home + Vector3(_random.randf_range(-30.0, 30.0), 0.0, _random.randf_range(-30.0, 30.0))
		if terrain.is_lake(target.x, target.z):
			bird["target"] = target
		if bird["species"] == "western_grebe" and _random.randf() < 0.3:
			bird["hidden"] = _random.randf_range(4.0, 9.0)   # a dive after fish
	var target: Vector3 = bird["target"]
	var flat := Vector3(target.x - at.x, 0.0, target.z - at.z)
	var velocity := flat.normalized() * minf(flat.length(), 0.7) if flat.length() > 0.3 else Vector3.ZERO
	bird["velocity"] = velocity
	at += velocity * delta
	at.y = _water_y(at) - float(bird["length"]) * 0.05
	bird["at"] = at
	bird["hidden"] = maxf(float(bird["hidden"]) - delta, 0.0)


func _move_soar(bird: Dictionary, group: Dictionary, delta: float, dives: bool) -> void:
	var home: Vector3 = group["home"]
	var at: Vector3 = bird["at"]
	if bird["mode"] == "dive":
		var surface := maxf(_water_y(at), _ground_y(at.x, at.z))
		if _fly_to(bird, Vector3(at.x, surface + 0.3, at.z), 26.0, delta):
			bird["mode"] = "climb"
		return
	if bird["mode"] == "hover":
		bird["velocity"] = Vector3.ZERO
		bird["timer"] = float(bird["timer"]) - delta
		if float(bird["timer"]) <= 0.0:
			bird["mode"] = "dive"
		return
	if bird["mode"] == "climb":
		var up := at + Vector3(0.0, 2.0, 0.0)
		_fly_to(bird, up, 8.0, delta)
		if at.y > _ground_y(at.x, at.z) + float(bird["height"]) * 0.6:
			bird["mode"] = "circle"
		return
	bird["mode"] = "circle"
	var radius := 140.0 if not dives else 70.0
	var height: float = bird["height"] if not dives else 35.0 + float(bird["index"]) * 8.0
	bird["angle"] = float(bird["angle"]) + delta * 11.0 / radius
	var angle: float = bird["angle"]
	var centre := home + Vector3(sin(_clock * 0.01 + float(bird["index"])) * 80.0, 0.0, cos(_clock * 0.013) * 80.0)
	var target := centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	target.y = maxf(_ground_y(target.x, target.z), MapInfo.LAKE_Y) + height
	_fly_to(bird, target, 13.0, delta)
	if dives:
		bird["timer"] = float(bird["timer"]) - delta
		if float(bird["timer"]) <= 0.0:
			bird["timer"] = _random.randf_range(18.0, 40.0)
			var below_water: bool = terrain.is_lake(at.x, at.z) or bird["species"] == "rough_legged_hawk"
			if below_water:
				bird["mode"] = "hover"
				bird["timer"] = 2.5


func _move_wade(bird: Dictionary, group: Dictionary, delta: float) -> void:
	var home: Vector3 = group["home"]
	var at: Vector3 = bird["at"]
	bird["timer"] = float(bird["timer"]) - delta
	if bird["mode"] == "fly":
		if _fly_to(bird, bird["target"], 9.0, delta):
			bird["mode"] = "stand"
			group["home"] = bird["target"]
		return
	bird["mode"] = "stand"
	if float(bird["timer"]) <= 0.0:
		bird["timer"] = _random.randf_range(40.0, 90.0)
		for attempt in 8:
			var spot := home + Vector3(_random.randf_range(-150.0, 150.0), 0.0, _random.randf_range(-150.0, 150.0))
			if _suits(BirdData.SPECIES[bird["species"]], spot.x, spot.z):
				spot.y = _ground_y(spot.x, spot.z) + 0.02
				bird["target"] = spot
				bird["mode"] = "fly"
				return
	# A slow step now and then.
	var step := Vector3(sin(float(bird["phase"]) * 0.2), 0.0, cos(float(bird["phase"]) * 0.17)) * 0.15
	at += step * delta
	at.y = _ground_y(at.x, at.z) + 0.02
	bird["velocity"] = step
	bird["at"] = at


func _move_swoop(bird: Dictionary, group: Dictionary, delta: float) -> void:
	var home: Vector3 = group["home"]
	var phase: float = bird["phase"]
	var index: float = float(bird["index"])
	var target := home + Vector3(sin(phase * 0.6 + index) * 60.0 + sin(phase * 1.7 + index * 2.0) * 15.0, 0.0,
			cos(phase * 0.5 + index * 1.3) * 60.0)
	target.y = maxf(_water_y(target), _ground_y(target.x, target.z)) + 2.0 + sin(phase * 2.3 + index) * 1.5
	bird["mode"] = "fly"
	_fly_to(bird, target, 11.0, delta)


func _move_hover(bird: Dictionary, group: Dictionary, delta: float) -> void:
	var home: Vector3 = group["home"]
	bird["timer"] = float(bird["timer"]) - delta
	if float(bird["timer"]) <= 0.0:
		bird["timer"] = _random.randf_range(0.6, 2.5)
		var spot := home + Vector3(_random.randf_range(-4.0, 4.0), 0.0, _random.randf_range(-4.0, 4.0))
		spot.y = _ground_y(spot.x, spot.z) + _random.randf_range(1.0, 3.0)
		bird["target"] = spot
	bird["mode"] = "fly"
	_fly_to(bird, bird["target"], 9.0, delta)


func _move_flee(bird: Dictionary, delta: float) -> void:
	bird["flee"] = float(bird["flee"]) - delta
	var away: Vector3 = bird["flee_dir"]
	bird["mode"] = "fly"
	bird["velocity"] = (bird["velocity"] as Vector3).lerp(away * 16.0, clampf(delta * 4.0, 0.0, 1.0))
	bird["at"] = (bird["at"] as Vector3) + (bird["velocity"] as Vector3) * delta
	bird["hidden"] = 0.0
	if float(bird["flee"]) <= 0.0:
		bird["mode"] = "perch" if bird["motion"] in ["flit", "flock"] else "circle"
		bird["timer"] = _random.randf_range(1.0, 4.0)


## Sets a bird's node from its state, turned to face where it goes, wings
## flapping, gliding or folded.
func _place(bird: Dictionary, species: Dictionary, _delta: float, distance: float = 0.0) -> void:
	var node: Node3D = bird["node"]
	if not is_instance_valid(node):
		return
	var at: Vector3 = bird["at"]
	var velocity: Vector3 = bird["velocity"]
	var mode := str(bird["mode"])
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() > 0.05:
		bird["yaw"] = atan2(-flat.x, -flat.z)
	var yaw: float = bird.get("yaw", 0.0)
	var pitch := 0.0
	if velocity.length() > 0.5 and mode != "swim":
		pitch = clampf(atan2(velocity.y, maxf(flat.length(), 0.1)), -0.9, 0.9) * 0.6
	node.visible = float(bird["hidden"]) <= 0.0 and distance < FAR_DRAWN
	if not node.visible:
		return
	node.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), Origin.to_world(at))
	if distance > WINGS_SEEN:
		return
	var wings: Array = bird["wings"]
	var phase: float = bird["phase"]
	var beat := 0.0
	var fold := false
	match mode:
		"perch", "swim", "stand":
			fold = true
		"circle":
			beat = 0.15 + 0.1 * sin(phase * 1.1) if species["shape"] == "raptor" or species["shape"] == "crow" else sin(phase * 8.0) * 0.6
		"hover":
			beat = sin(phase * (60.0 if species["shape"] == "hummer" else 14.0)) * 0.7
		_:
			var rate := clampf(2.5 / sqrt(float(bird["length"])), 3.0, 60.0)
			if species["shape"] == "hummer":
				rate = 60.0
			beat = sin(phase * rate) * 0.75
	for index in wings.size():
		var pivot: Node3D = wings[index]
		var side := -1.0 if index == 0 else 1.0
		if fold:
			pivot.rotation = Vector3(0.0, -side * 1.35, side * 0.35)
			pivot.scale = Vector3(0.55, 1.0, 1.0)
		else:
			pivot.rotation = Vector3(0.0, 0.0, side * beat)
			pivot.scale = Vector3.ONE


# --- Scaring them off ----------------------------------------------------------------------

## Birds within `radius` m of a world point fly off (an explosion, a crash).
func startle(world_point: Vector3, radius: float) -> void:
	var map_point := Origin.to_map(world_point)
	for group in _groups:
		for item in group["birds"]:
			var bird: Dictionary = item
			var off: Vector3 = (bird["at"] as Vector3) - map_point
			if off.length() < radius:
				bird["flee"] = _random.randf_range(5.0, 9.0)
				bird["flee_dir"] = (Vector3(off.x, 0.0, off.z).normalized() + Vector3(0.0, 0.7, 0.0)).normalized()


static func startle_all(tree: SceneTree, world_point: Vector3, radius: float) -> void:
	for node in tree.get_nodes_in_group("birds"):
		node.startle(world_point, radius)


func _scare_by_vehicles() -> void:
	for node in get_tree().get_nodes_in_group("combat"):
		var spawner: Node = node.spawner
		if spawner == null or not bool(spawner.spawned):
			continue
		for item in spawner.all_bodies():
			var body := item as RigidBody3D
			if body != null and is_instance_valid(body) and body.linear_velocity.length() > 25.0:
				startle(body.global_position, 70.0)
				break


# --- Close-ups ---------------------------------------------------------------------------

func _run_hover(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not _zoom.is_empty():
		_run_zoom(delta)
		return
	if camera == null or get_tree().paused or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			or get_viewport().gui_get_hovered_control() != null:
		_hover_bird = {}
		return
	var mouse := get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse = get_viewport().get_visible_rect().size * 0.5
	var bird := bird_under(camera, mouse)
	if bird.is_empty() or bird != _hover_bird:
		_hover_bird = bird
		_hover_time = 0.0
		return
	_hover_time += delta
	if _hover_time > 0.2:
		_begin_zoom(bird, camera, mouse)


## The bird nearest the screen point, within its size or HOVER_PIXELS.
func bird_under(camera: Camera3D, screen_point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_gap := INF
	var height := get_viewport().get_visible_rect().size.y
	var per_radian := height / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	for group in _groups:
		for item in group["birds"]:
			var bird: Dictionary = item
			var node: Node3D = bird["node"]
			if not is_instance_valid(node) or not node.visible:
				continue
			var world := node.global_position
			var distance := camera.global_position.distance_to(world)
			if distance > 900.0 or camera.is_position_behind(world):
				continue
			var spot := camera.unproject_position(world)
			var reach := maxf(HOVER_PIXELS, float(bird["length"]) * per_radian / maxf(distance, 0.1))
			var gap := spot.distance_to(screen_point)
			if gap < reach and gap < best_gap:
				best_gap = gap
				best = bird
	return best


## Every species in view and near enough to make out in a photo.
func birds_in_frame(camera: Camera3D) -> Array:
	var found: Array = []
	var height := get_viewport().get_visible_rect().size.y
	var per_radian := height / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	for group in _groups:
		for item in group["birds"]:
			var bird: Dictionary = item
			var node: Node3D = bird["node"]
			if not is_instance_valid(node) or not node.visible:
				continue
			var world := node.global_position
			if not camera.is_position_in_frustum(world):
				continue
			var pixels := float(bird["length"]) * per_radian / maxf(camera.global_position.distance_to(world), 0.1)
			if pixels >= 8.0 and not found.has(bird["species"]):
				found.append(bird["species"])
	return found


func _begin_zoom(bird: Dictionary, camera: Camera3D, mouse: Vector2) -> void:
	var close := Camera3D.new()
	close.name = "BirdCloseUp"
	close.near = camera.near
	close.far = camera.far
	close.fov = camera.fov
	add_child(close)
	close.global_transform = camera.global_transform
	close.make_current()
	_zoom = {"bird": bird, "camera": close, "from": camera, "mouse": mouse, "leaving": false, "time": 0.0}
	var species: Dictionary = BirdData.SPECIES[bird["species"]]
	var first := Profile.spot_bird(str(bird["species"]))
	_card.text = "%s\n%s   ·   %s" % [species["name"], species["latin"], str(species["status"]).to_lower()]
	_card.visible = true
	if first and game_hud != null:
		game_hud.announce("New bird!", "%s added to the bird guide (B)" % species["name"], 3.5, Color(0.6, 1.0, 0.7))
		Sound.play_ui("checkpoint")


func _run_zoom(delta: float) -> void:
	var close: Camera3D = _zoom["camera"]
	var from: Camera3D = _zoom["from"]
	var bird: Dictionary = _zoom["bird"]
	if not is_instance_valid(close) or not is_instance_valid(from):
		_end_zoom(true)
		return
	_zoom["time"] = float(_zoom["time"]) + delta
	var mouse := get_viewport().get_mouse_position()
	var node: Node3D = bird.get("node")
	var gone := node == null or not is_instance_valid(node)
	if not bool(_zoom["leaving"]):
		var moved := mouse.distance_to(_zoom["mouse"]) > LEAVE_PIXELS
		if gone or moved or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or get_tree().paused \
				or from.global_position.distance_to(node.global_position) > 1000.0:
			_zoom["leaving"] = true
	var blend := clampf(delta * 4.0, 0.0, 1.0)
	if bool(_zoom["leaving"]):
		close.global_transform = close.global_transform.interpolate_with(from.global_transform, clampf(delta * 6.0, 0.0, 1.0))
		close.fov = lerpf(close.fov, from.fov, clampf(delta * 6.0, 0.0, 1.0))
		if absf(close.fov - from.fov) < 0.5:
			_end_zoom(false)
		return
	var target := node.global_position
	var eye := from.global_position
	var distance := eye.distance_to(target)
	var wanted := Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	close.global_transform = Transform3D(close.global_transform.basis.slerp(wanted.basis, blend), eye)
	var fov := clampf(rad_to_deg(2.0 * atan(float(bird["length"]) * 3.0 / maxf(distance, 0.1))), 1.0, from.fov)
	close.fov = lerpf(close.fov, fov, blend)


func _end_zoom(at_once: bool) -> void:
	if _zoom.is_empty():
		return
	var close: Camera3D = _zoom["camera"]
	var from: Camera3D = _zoom["from"]
	if is_instance_valid(from):
		from.make_current()
	if is_instance_valid(close):
		close.queue_free()
	_zoom = {}
	_hover_bird = {}
	_card.visible = false
	if at_once:
		_hover_time = 0.0


## True while the camera is on a close-up of a bird (the photo camera asks).
func zoomed_camera() -> Camera3D:
	return _zoom.get("camera") if not _zoom.is_empty() else null


# --- Nests -----------------------------------------------------------------------------

## Where nests go, worked out once from a fixed seed so they are always in
## the same places: [kind, species that use it, how many, habitats].
const NEST_PLAN := [
	["stick_snag", ["osprey"], 26, ["shore", "marsh"]],
	["stick_tree", ["bald_eagle"], 12, ["shore"]],
	["stick_tree", ["crow", "raven"], 14, ["forest", "town", "meadow"]],
	["ground_cup", ["mallard"], 14, ["marsh", "shore"]],
	["ground_cup", ["junco"], 12, ["forest"]],
	["ground_cup", ["harlequin_duck"], 3, ["shore"]],
	["floating", ["western_grebe"], 10, ["marsh"]],
	["cavity", ["chickadee", "pileated_woodpecker", "tree_swallow", "mountain_bluebird"], 26, ["forest", "meadow", "shore"]],
	["mound", ["trumpeter_swan"], 5, ["marsh"]],
	["mound", ["sandhill_crane"], 6, ["meadow", "marsh"]],
]


func _plan_nests() -> void:
	if terrain == null:
		return
	var random := RandomNumberGenerator.new()
	random.seed = 31337
	var bounds: Array = terrain.world.get("bounds", [-11520.0, -27648.0, 17408.0, 22528.0])
	for plan in NEST_PLAN:
		var kind: String = plan[0]
		var habitats: Array = plan[3]
		var placed := 0
		var tries := 0
		while placed < int(plan[2]) and tries < 4000:
			tries += 1
			var x := random.randf_range(float(bounds[0]) + 1500.0, float(bounds[2]) - 1500.0)
			var z := random.randf_range(float(bounds[1]) + 1500.0, float(bounds[3]) - 1500.0)
			if not habitats.has(habitat_at(x, z)):
				continue
			if kind == "floating" and not terrain.is_lake(x, z):
				continue
			if kind != "floating" and terrain.is_lake(x, z):
				continue
			_add_nest(kind, plan[1], Vector3(x, _ground_y(x, z), z))
			placed += 1
	# Geese on Goose and Douglas Islands, a heron colony at each river mouth.
	var random_geese := RandomNumberGenerator.new()
	random_geese.seed = 4747
	for item in islands:
		var island_name := str(item[1])
		if island_name.begins_with("Goose") or island_name.begins_with("Douglas") or island_name.begins_with("Bird"):
			var centre: Vector2 = item[0]
			for count in 5:
				var spot := centre + Vector2(random_geese.randf_range(-40.0, 40.0), random_geese.randf_range(-40.0, 40.0))
				if not terrain.is_lake(spot.x, spot.y):
					_add_nest("ground_island", ["canada_goose"], Vector3(spot.x, _ground_y(spot.x, spot.y), spot.y))
	for mouth: Vector2 in [Vector2(-1500.0, -24800.0), Vector2(5200.0, 16500.0)]:
		var colony_random := RandomNumberGenerator.new()
		colony_random.seed = int(mouth.x)
		var found := 0
		var tries := 0
		while found < 3 and tries < 400:
			tries += 1
			var spot: Vector2 = mouth + Vector2(colony_random.randf_range(-1500.0, 1500.0), colony_random.randf_range(-1500.0, 1500.0))
			if habitat_at(spot.x, spot.y) == "marsh" and not terrain.is_lake(spot.x, spot.y):
				_add_nest("colony", ["great_blue_heron"], Vector3(spot.x, _ground_y(spot.x, spot.y), spot.y))
				found += 1


func _add_nest(kind: String, species: Array, at: Vector3) -> void:
	_nests.append({"kind": kind, "species": species, "at": at, "node": null, "season": ""})
	var area := Vector2i(floori(at.x / AREA), floori(at.z / AREA))
	if not _nest_areas.has(area):
		_nest_areas[area] = []
	for item in species:
		if not (_nest_areas[area] as Array).has(item):
			(_nest_areas[area] as Array).append(item)


## Nests near the player are built; far ones are freed. A change of season
## rebuilds them with eggs, chicks or empty.
func _plan_nest_nodes() -> void:
	var here := _here()
	var season: String = weather.season_name() if weather != null else "summer"
	for item in _nests:
		var nest: Dictionary = item
		var at: Vector3 = nest["at"]
		var distance := Vector2(at.x, at.z).distance_to(Vector2(here.x, here.z))
		var node: Node3D = nest["node"]
		if distance < NEST_NEAR and (node == null or str(nest["season"]) != season):
			if node != null and is_instance_valid(node):
				node.queue_free()
			nest["node"] = _build_nest(nest, season)
			nest["season"] = season
		elif distance > NEST_NEAR + 400.0 and node != null:
			if is_instance_valid(node):
				node.queue_free()
			nest["node"] = null


func nest_count() -> int:
	return _nests.size()


func _build_nest(nest: Dictionary, season: String) -> Node3D:
	_meshes()
	var root := Node3D.new()
	root.name = "Nest"
	var kind := str(nest["kind"])
	var at: Vector3 = nest["at"]
	var sticks := Color(0.36, 0.27, 0.17)
	var grey_wood := Color(0.52, 0.5, 0.47)
	var top := Vector3.ZERO
	var cup := 0.5
	match kind:
		"stick_snag":
			_part(root, _rod, grey_wood, Vector3(0.0, 6.0, 0.0), Vector3(0.45, 12.0, 0.45))
			_part(root, _rod, grey_wood, Vector3(0.6, 9.0, 0.0), Vector3(0.15, 1.6, 0.15), Vector3(0.0, 0.0, 0.9))
			top = Vector3(0.0, 12.2, 0.0)
			cup = 0.8
		"stick_tree":
			var tall := 18.0 if nest["species"].has("bald_eagle") else 13.0
			_part(root, _rod, Color(0.33, 0.24, 0.16), Vector3(0.0, tall * 0.5, 0.0), Vector3(0.7, tall, 0.7))
			_part(root, _cone, Color(0.16, 0.32, 0.18), Vector3(0.0, tall * 0.55, 0.0), Vector3(4.5, tall * 0.7, 4.5))
			top = Vector3(0.0, tall + 0.2, 0.0)
			cup = 1.0 if nest["species"].has("bald_eagle") else 0.45
		"colony":
			for tree in 3:
				var spot := Vector3(cos(tree * 2.1) * 6.0, 0.0, sin(tree * 2.1) * 6.0)
				_part(root, _rod, Color(0.55, 0.5, 0.42), spot + Vector3(0.0, 9.0, 0.0), Vector3(0.6, 18.0, 0.6))
				for branch in 3:
					var branch_at := spot + Vector3(cos(branch * 2.0) * 1.4, 12.0 + branch * 2.0, sin(branch * 2.0) * 1.4)
					_stick_nest(root, branch_at, 0.55, sticks)
					_contents(root, branch_at + Vector3(0.0, 0.15, 0.0), 0.55, "great_blue_heron", season)
			root.position = Origin.to_world(at)
			add_child(root)
			return root
		"cavity":
			_part(root, _rod, grey_wood, Vector3(0.0, 4.0, 0.0), Vector3(0.6, 8.0, 0.6))
			_part(root, _rod, Color(0.05, 0.04, 0.03), Vector3(0.0, 5.5, -0.29), Vector3(0.14, 0.04, 0.14), Vector3(PI * 0.5, 0.0, 0.0))
			_part(root, _rod, Color(0.05, 0.04, 0.03), Vector3(0.29, 3.2, 0.0), Vector3(0.22, 0.04, 0.32), Vector3(0.0, 0.0, PI * 0.5))
			root.position = Origin.to_world(at)
			add_child(root)
			return root
		"ground_cup", "ground_island":
			top = Vector3(0.0, 0.05, 0.0)
			cup = 0.35 if kind == "ground_cup" else 0.6
		"floating":
			at.y = MapInfo.LAKE_Y
			_part(root, _rod, Color(0.35, 0.42, 0.22), Vector3(0.0, 0.05, 0.0), Vector3(1.4, 0.2, 1.4))
			for reed in 10:
				var reed_at := Vector3(cos(reed * 0.7) * 1.6, 0.8, sin(reed * 1.3) * 1.6)
				_part(root, _rod, Color(0.45, 0.55, 0.25), reed_at, Vector3(0.05, 1.6, 0.05))
			top = Vector3(0.0, 0.15, 0.0)
			cup = 0.45
		"mound":
			_part(root, _cone, Color(0.4, 0.42, 0.25), Vector3(0.0, 0.25, 0.0), Vector3(2.4, 0.5, 2.4))
			top = Vector3(0.0, 0.5, 0.0)
			cup = 0.55
	if kind != "floating" and kind != "mound":
		_stick_nest(root, top, cup, sticks if kind != "ground_cup" else Color(0.5, 0.45, 0.3))
	_contents(root, top + Vector3(0.0, cup * 0.3, 0.0), cup, str(nest["species"][0]), season)
	root.position = Origin.to_world(at)
	add_child(root)
	return root


func _stick_nest(root: Node3D, at: Vector3, radius: float, color: Color) -> void:
	_part(root, _rod, color, at, Vector3(radius * 2.0, radius * 0.6, radius * 2.0))
	_part(root, _rod, color.darkened(0.45), at + Vector3(0.0, radius * 0.31, 0.0), Vector3(radius * 1.4, 0.02, radius * 1.4))
	for stick in 6:
		var angle := stick * 1.05
		_part(root, _cube, color.lightened(0.1), at + Vector3(cos(angle) * radius * 0.8, radius * 0.2, sin(angle) * radius * 0.8),
				Vector3(radius * 1.2, 0.05, 0.05), Vector3(0.0, angle + 0.6, 0.15))


## Eggs in spring, chicks in summer, nothing the rest of the year.
func _contents(root: Node3D, at: Vector3, radius: float, species_id: String, season: String) -> void:
	var species: Dictionary = BirdData.SPECIES.get(species_id, {})
	var size: float = clampf(float(species.get("length", 0.3)) * 0.12, 0.02, 0.12)
	if season == "spring":
		for egg in 3:
			var angle := egg * 2.1
			_part(root, _ball, Color(0.88, 0.9, 0.82) if species_id != "bald_eagle" else Color(0.95, 0.95, 0.93),
					at + Vector3(cos(angle) * radius * 0.25, size * 0.4, sin(angle) * radius * 0.25), Vector3(size, size * 1.3, size))
	elif season == "summer":
		for chick in 2:
			var angle := chick * 3.0
			var spot := at + Vector3(cos(angle) * radius * 0.25, size * 1.2, sin(angle) * radius * 0.25)
			_part(root, _ball, Color(0.75, 0.72, 0.6), spot, Vector3.ONE * size * 2.2)
			_part(root, _ball, Color(0.7, 0.68, 0.58), spot + Vector3(0.0, size * 1.4, -size * 0.4), Vector3.ONE * size * 1.3)
