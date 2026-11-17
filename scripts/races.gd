extends Node
## Races, cargo runs and the people at the airports and towns who offer them.
##
## At every airport someone stands on the apron under a sign. Walk up and
## press E: some run air races, all of them have cargo to fly. Beside the
## highway in Polson, Bigfork and Lakeside, others run car races.
##
## Air races, from 100 m/s to 500 m/s: pick one of your saved builds; it is
## put on the runway, you are sat in it, and after a countdown you race three
## computer pilots round a loop of rings in the sky, in order, back to the
## airport. The next ring glows with a beam of light over it. Car races are
## the same on the highway, through gates. Finish in the top three to win
## money (more for harder races); your best time on each is kept. Dying ends
## a race as a loss; F2 gives up.
##
## The computer racers fly (or drive) a smooth line through the rings at
## their own top speed, slowing for turns tighter than they can take. Get
## near one and it shows off: a big boast pops up over it and it speeds up
## by up to 20 m/s for a few seconds.
##
## Cargo: pick a destination airport and a crate (light, medium or heavy).
## The crate appears beside the agent; get it there however you like, in a
## cargo bay, on a magnet or on a winch hook, and set it down in the green
## ring at the other airport. Pay is by distance and weight, with a bonus
## for being quick; drop it too hard and it smashes.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Units = preload("res://scripts/units.gd")
const Roads = preload("res://scripts/roads.gd")
const Sound = preload("res://scripts/sound.gd")
const Profile = preload("res://scripts/profile.gd")
const SaveManager = preload("res://scripts/save_manager.gd")

## [id, name, host airport, top speed m/s, loop radius m, ring radius m, height over the ground m, prize $, rings]
const AIR_RACES := [
	["rookie", "Rookie Loop", "Wild Horse Island", 100.0, 2600.0, 45.0, 150.0, 1000, 9],
	["islands", "Island Hopper", "Polson airport", 200.0, 4500.0, 60.0, 220.0, 3000, 10],
	["circuit", "Lake Circuit", "Bigfork airport", 300.0, 7000.0, 80.0, 300.0, 8000, 11],
	["gauntlet", "Mountain Gauntlet", "Somers Mountain airport", 400.0, 9000.0, 100.0, 380.0, 18000, 12],
	["demon", "Speed Demon", "Lakeside Ridge airport", 500.0, 11000.0, 130.0, 450.0, 40000, 12],
]
## [id, name, town, top speed m/s, length m, prize $]
const CAR_RACES := [
	["polson", "Polson Highway Sprint", "Polson", 34.0, 7000.0, 1500],
	["bigfork", "East Shore Run", "Bigfork", 48.0, 10000.0, 4000],
	["lakeside", "Lakeside Dash", "Lakeside", 65.0, 14000.0, 9000],
]
const RIVALS := [["Ace Vega", Color(0.95, 0.2, 0.15)], ["Duke Mirage", Color(0.2, 0.45, 1.0)],
		["Slick Rourke", Color(0.95, 0.8, 0.1)], ["Nova Kade", Color(0.6, 0.25, 0.9)],
		["Rex Torrent", Color(0.15, 0.8, 0.4)], ["Blaze Okafor", Color(1.0, 0.5, 0.1)]]
const BOASTS := [
	"Eat my exhaust, rookie!", "Is that thing held together with tape?", "I've seen gliders faster than you!",
	"Try to keep up!", "See you at the finish... in an hour!", "You call that flying?",
	"My grandma builds better than that!", "Wave bye-bye!", "Coming through, slowpoke!",
	"Nice paint job. Shame about the engine.", "Was that your top speed? Cute.", "First place is MINE!",
	"Don't blink, you'll miss me!", "Smell that? That's victory.", "Out of my lane!",
	"You're making this too easy!", "Watch and learn!", "I could win this backwards!",
	"Did you build that in the dark?", "Later, loser!", "Too slow! TOO SLOW!", "Catch me if you can!",
	"Is your parking brake on?", "Sorry, did you say something? Couldn't hear you back there.",
]
const TALK_REACH := 7.0
const BOOST := Vector2(8.0, 20.0)       # m/s a boast adds, at least and at most
const BOOST_TIME := 6.0
const BOAST_COOLDOWN := 14.0
const PLANE_G := 7.0                    # how hard the computer pilots will turn
const CAR_G := 1.0
const CRATES := [["Light crate (200 kg)", 200.0, 1.6, 90.0], ["Medium crate (800 kg)", 800.0, 2.2, 180.0],
		["Heavy crate (2,000 kg)", 2000.0, 3.0, 320.0]]   # name, kg, size m, $ per km
const DROP_ZONE := 25.0
const CRATE_SMASH_G := 45.0

var terrain: Node = null        # terrain.gd
var player: Node3D = null       # player.gd
var controller: Node = null     # build_controller.gd
var fleet: Node = null          # fleet.gd
var game_hud: Node = null       # game_hud.gd
var roads: RefCounted = null    # roads.gd

var _hosts: Array = []          # {"name", "at": map position, "airport": name or "", "air": [race], "car": [race], "node"}
var _airports: Dictionary = {}  # name -> {"centre": map Vector3, "start": map Vector3, "heading": radians, "length": m, "apron": map Vector3}
var _near: Dictionary = {}      # the host in reach, or empty
var _check := 0.0
var _window: PanelContainer = null
var _window_column: VBoxContainer = null
var _vehicle_pick: OptionButton = null
var _race: Dictionary = {}      # the race running; see _start_race
var _job: Dictionary = {}       # the cargo run under way; see _take_job
var _status: Label = null
var _random := RandomNumberGenerator.new()
var _plane_meshes: Dictionary = {}
var _car_mesh_cache: Dictionary = {}
var _ring_looks: Array = []


func setup(the_terrain: Node, the_roads: RefCounted) -> void:
	add_to_group("races")
	terrain = the_terrain
	roads = the_roads
	_random.randomize()
	for item in terrain.world.get("runways", []):
		var runway: Dictionary = item
		var airport_name := str(runway.get("name", ""))
		var centre: Array = runway["centre"]
		var middle := Vector2(float(centre[0]), float(centre[1]))
		var heading := deg_to_rad(float(runway.get("heading", 0.0)))
		# Runway headings are compass bearings: 0 north (-Z), 90 east (+X).
		var along := Vector2(sin(heading), -cos(heading))
		var length := float(runway.get("length", 700.0))
		var start := middle - along * (length * 0.5 - 40.0)
		var apron_at := middle + Vector2(-along.y, along.x) * 70.0
		var apron: Variant = runway.get("apron")
		if apron is Dictionary:
			var apron_centre: Array = (apron as Dictionary)["centre"]
			apron_at = Vector2(float(apron_centre[0]), float(apron_centre[1]))
		_airports[airport_name] = {
			"centre": _ground_point(middle), "start": _ground_point(start), "along": along,
			"length": length, "apron": _ground_point(apron_at),
		}
	# A host at every airport: air races where there are some, cargo everywhere.
	for airport_name in _airports:
		var airport: Dictionary = _airports[airport_name]
		var air: Array = []
		for race in AIR_RACES:
			if str(race[2]) == airport_name:
				air.append(race)
		var host_at: Vector3 = (airport["apron"] as Vector3) + Vector3(6.0, 0.0, 6.0)
		host_at.y = terrain.height_at(host_at.x, host_at.z)
		_add_host(str(airport_name), host_at, str(airport_name), air, [])
	# Car race hosts beside the highway in three towns.
	var towns: Dictionary = {}
	for item in terrain.world.get("town_names", []):
		var town: Dictionary = item
		var at: Array = town["at"]
		towns[str(town["name"])] = Vector2(float(at[0]), float(at[1]))
	for race in CAR_RACES:
		if not towns.has(race[2]) or roads.lines.is_empty():
			continue
		var found: Array = roads.nearest(towns[race[2]])
		if found.is_empty():
			continue
		var line: PackedVector3Array = roads.lines[found[0]]
		var point := line[found[1]]
		var next := line[mini(int(found[1]) + 1, line.size() - 1)]
		var prior := line[maxi(int(found[1]) - 1, 0)]
		var direction := (next - prior).normalized()
		var right := direction.cross(Vector3.UP).normalized()
		var host_point := point + right * 12.0
		host_point.y = terrain.height_at(host_point.x, host_point.z)
		_add_host("%s car races" % race[2], host_point, "", [], [race], found)


func _ground_point(spot: Vector2) -> Vector3:
	return Vector3(spot.x, terrain.height_at(spot.x, spot.y), spot.y)


# --- The people ------------------------------------------------------------------------

func _add_host(title: String, at: Vector3, airport: String, air: Array, car: Array, road: Array = []) -> void:
	var node := Node3D.new()
	node.name = "Host"
	node.position = at
	terrain.add_child(node)
	node.add_child(_person(Color(0.2, 0.55, 0.95) if not car.is_empty() else Color(0.95, 0.75, 0.15)))
	var sign_text := "CARGO"
	if not air.is_empty():
		sign_text = "AIR RACES  ·  CARGO"
	if not car.is_empty():
		sign_text = "CAR RACES"
	var sign_label := Label3D.new()
	sign_label.text = sign_text
	sign_label.font_size = 64
	sign_label.pixel_size = 0.01
	sign_label.outline_size = 12
	sign_label.modulate = Color(1.0, 0.92, 0.4)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.position = Vector3(0.0, 3.0, 0.0)
	sign_label.visibility_range_end = 600.0
	node.add_child(sign_label)
	_hosts.append({"name": title, "at": at, "airport": airport, "air": air, "car": car, "road": road, "node": node})
	if not air.is_empty() or not car.is_empty():
		terrain.landmarks.map_points.append([Vector2(at.x, at.z), "Air races" if not air.is_empty() else "Car races"])


## A person: blocky, like the character, in a high-visibility vest.
func _person(vest: Color) -> Node3D:
	var person := Node3D.new()
	var parts := [
		[Vector3(0.22, 0.75, 0.22), Vector3(-0.12, 0.375, 0.0), Color(0.2, 0.22, 0.26)],
		[Vector3(0.22, 0.75, 0.22), Vector3(0.12, 0.375, 0.0), Color(0.2, 0.22, 0.26)],
		[Vector3(0.5, 0.65, 0.28), Vector3(0.0, 1.075, 0.0), vest],
		[Vector3(0.16, 0.6, 0.18), Vector3(-0.34, 1.1, 0.0), vest],
		[Vector3(0.16, 0.6, 0.18), Vector3(0.34, 1.1, 0.0), vest],
		[Vector3(0.34, 0.34, 0.34), Vector3(0.0, 1.6, 0.0), Color(0.85, 0.7, 0.55)],
		[Vector3(0.38, 0.1, 0.38), Vector3(0.0, 1.8, 0.0), Color(0.15, 0.15, 0.18)],
	]
	for item in parts:
		var part: Array = item
		var box := BoxMesh.new()
		box.size = part[0]
		var look := StandardMaterial3D.new()
		look.albedo_color = part[2]
		box.material = look
		var shown := MeshInstance3D.new()
		shown.mesh = box
		shown.position = part[1]
		person.add_child(shown)
	return person


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.2
		_find_near()
		if _status != null and _window != null and _window.visible:
			_status.text = _job_text()
	if not _race.is_empty():
		_run_race(delta)
	if not _job.is_empty():
		_run_job(delta)


func _find_near() -> void:
	_near = {}
	if player == null or bool(player.seated):
		if game_hud != null and game_hud.prompt.text.begins_with("E  Talk"):
			game_hud.prompt.text = ""
		return
	var here := Origin.to_map(player.global_position)
	for item in _hosts:
		var host: Dictionary = item
		if (host["at"] as Vector3).distance_to(here) < TALK_REACH:
			_near = host
			break
	if game_hud != null:
		if not _near.is_empty():
			game_hud.prompt.text = "E  Talk to the %s" % ("race organiser" if not (_near["car"] as Array).is_empty()
					else ("race and cargo agent" if not (_near["air"] as Array).is_empty() else "cargo agent"))
		elif game_hud.prompt.text.begins_with("E  Talk"):
			game_hud.prompt.text = ""


## Called when E is pressed (build_controller.gd). True if someone is there to talk to.
func talk() -> bool:
	if _near.is_empty():
		return false
	_open_window(_near)
	return true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F2:
		if not _race.is_empty():
			_end_race("You gave up the race.", false)
		elif not _job.is_empty():
			_end_job("You gave up the cargo run.", 0)


## Dying ends a race or cargo run as a loss (main.gd calls this through the group).
func player_died() -> void:
	if not _race.is_empty():
		_end_race("You died. Race lost.", false)
	if not _job.is_empty():
		_end_job("You died. The cargo run is off.", 0)


# --- The window ------------------------------------------------------------------------

func _open_window(host: Dictionary) -> void:
	if _window != null:
		_window.queue_free()
	var made: Array = game_hud.make_window(str(host["name"]), 600.0)
	_window = made[0]
	_window_column = made[1]
	var column: VBoxContainer = _window_column
	var races: Array = (host["air"] as Array) + (host["car"] as Array)
	if not races.is_empty():
		var pick_row := HBoxContainer.new()
		column.add_child(pick_row)
		var caption := Label.new()
		caption.text = "Race in"
		pick_row.add_child(caption)
		_vehicle_pick = OptionButton.new()
		_vehicle_pick.focus_mode = Control.FOCUS_NONE
		_vehicle_pick.custom_minimum_size = Vector2(300, 0)
		for save_name in SaveManager.list_saves():
			_vehicle_pick.add_item(str(save_name))
		pick_row.add_child(_vehicle_pick)
		if _vehicle_pick.item_count == 0:
			var none := Label.new()
			none.text = "Save a build first (the Saves button): that is what you race in."
			column.add_child(none)
		for item in races:
			var race: Array = item
			var is_air: bool = (host["air"] as Array).has(race)
			var row := HBoxContainer.new()
			column.add_child(row)
			var about := Label.new()
			about.custom_minimum_size = Vector2(390, 0)
			var best := Profile.best_time(str(race[0]))
			var prize: int = race[7] if is_air else race[5]
			about.text = "%s   rivals at %d m/s   1st %s%s" % [race[1], int(race[3]), Profile.money(prize),
					("   best %s" % _clock_text(best)) if best > 0.0 else ""]
			row.add_child(about)
			var go := Button.new()
			go.text = "Race"
			go.focus_mode = Control.FOCUS_NONE
			go.pressed.connect(func() -> void: _start_race(race, host, is_air))
			row.add_child(go)
	var airport: String = host["airport"]
	if airport != "":
		var heading := Label.new()
		heading.text = "Cargo runs from here"
		heading.add_theme_font_size_override("font_size", 17)
		column.add_child(heading)
		var destination := OptionButton.new()
		destination.focus_mode = Control.FOCUS_NONE
		var names: Array = []
		var here: Vector3 = (_airports[airport] as Dictionary)["apron"]
		for other in _airports:
			if other == airport:
				continue
			var there: Vector3 = (_airports[other] as Dictionary)["apron"]
			names.append([other, Vector2(here.x, here.z).distance_to(Vector2(there.x, there.z))])
		names.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
		for item in names:
			destination.add_item("%s  (%.1f km)" % [item[0], float(item[1]) / 1000.0])
		column.add_child(destination)
		var weight := OptionButton.new()
		weight.focus_mode = Control.FOCUS_NONE
		for crate in CRATES:
			weight.add_item("%s   %s per km" % [crate[0], Profile.money(int(crate[3]))])
		column.add_child(weight)
		var take := Button.new()
		take.text = "Take the job"
		take.focus_mode = Control.FOCUS_NONE
		take.pressed.connect(func() -> void:
			if names.is_empty():
				return
			_take_job(airport, str(names[destination.selected][0]), weight.selected))
		column.add_child(take)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_status.text = _job_text()
	_window.visible = true
	if player != null:
		player.cursor_free = true   # free the mouse in first person, to click


static func _clock_text(seconds: float) -> String:
	return "%d:%04.1f" % [int(seconds / 60.0), fmod(seconds, 60.0)]


# --- Races --------------------------------------------------------------------------------

func _start_race(race: Array, host: Dictionary, is_air: bool) -> void:
	if not _race.is_empty() or _vehicle_pick == null or _vehicle_pick.item_count == 0:
		return
	var save_name := _vehicle_pick.get_item_text(_vehicle_pick.selected)
	var course: Dictionary = _air_course(race, host) if is_air else _car_course(race, host)
	if course.is_empty():
		game_hud.announce("", "No course could be laid out here.", 3.0)
		return
	var start: Vector3 = course["start"]
	var heading: float = course["heading"]
	var made: Array = fleet.spawn_save_at(save_name, Origin.to_world(start + Vector3(0.0, 2.0, 0.0)), heading)
	var vehicle: Node = made[1]
	if vehicle == null:
		game_hud.announce("", str(made[0]), 4.0)
		return
	if not controller.sit_in(vehicle):
		game_hud.announce("", "\"%s\" has no seat to race from." % save_name, 4.0)
	vehicle.race_hold = true
	vehicle.set_parked(true)
	if _window != null:
		_window.visible = false
	var path: PackedVector3Array = course["path"]
	var along := Roads.distances(path)
	var top := float(race[3]) * 1.08 + BOOST.y
	var limits := _speed_limits(path, along, PLANE_G if is_air else CAR_G, top)
	var ring_at := PackedFloat32Array()
	for item in course["rings"]:
		ring_at.append(along[_nearest_index(path, item)])
	var racers: Array = []
	var shares := [0.94, 1.0, 1.05]
	var rivals := RIVALS.duplicate()
	rivals.shuffle()
	for index in 3:
		var rival: Array = rivals[index]
		racers.append(_new_racer(str(rival[0]), rival[1], float(race[3]) * float(shares[index]), is_air,
				float(course.get("grid", 0.0)) + (float(index) * 8.0 if not is_air else float(index) * 30.0 + 30.0),
				(2.2 if index % 2 == 0 else -2.2) if not is_air else 0.0))
	_race = {"race": race, "air": is_air, "path": path, "along": along, "limits": limits, "rings": course["rings"],
			"ring_at": ring_at, "radius": float(course["radius"]), "racers": racers, "vehicle": vehicle,
			"clock": -3.5, "next": 0, "finished": false, "player_time": 0.0, "count": 4, "nodes": []}
	_make_rings()
	_race["label"] = game_hud.make_side_label()
	game_hud.announce(str(race[1]), "Through the rings in order. F2 gives up.", 3.0)


## An air course: a loop of rings round the airport, over the lake where it
## can, at the race's height over whatever is below, from a takeoff down the
## runway to a last ring over the airport.
func _air_course(race: Array, host: Dictionary) -> Dictionary:
	var airport: Dictionary = _airports.get(host["airport"], {})
	if airport.is_empty():
		return {}
	var start: Vector3 = airport["start"]
	var along: Vector2 = airport["along"]
	var length: float = airport["length"]
	var radius: float = race[4]
	var ring_count: int = race[8]
	var bounds: Array = terrain.world.get("bounds", [-11520.0, -27648.0, 17408.0, 22528.0])
	var low := Vector2(float(bounds[0]) + 2500.0, float(bounds[1]) + 2500.0)
	var high := Vector2(float(bounds[2]) - 2500.0, float(bounds[3]) - 2500.0)
	var home := Vector2(start.x, start.z) + along * length * 0.5
	# The loop's middle: the side of the airport with the most lake.
	var best_side := Vector2.ZERO
	var best_wet := -1
	for trial in 12:
		var angle := TAU * float(trial) / 12.0
		var middle := home + Vector2(cos(angle), sin(angle)) * radius
		var wet := 0
		for step in 16:
			var around := middle + Vector2(cos(TAU * step / 16.0), sin(TAU * step / 16.0)) * radius
			if terrain.is_lake(around.x, around.y):
				wet += 1
			if around.x < low.x or around.y < low.y or around.x > high.x or around.y > high.y:
				wet -= 4
		if wet > best_wet:
			best_wet = wet
			best_side = middle
	var to_home := (home - best_side).angle()
	var rings: Array = []
	for index in range(1, ring_count + 1):
		var angle := to_home + TAU * float(index) / (ring_count + 1)
		var reach := radius * _random.randf_range(0.82, 1.15)
		var spot := best_side + Vector2(cos(angle), sin(angle)) * reach
		spot = spot.clamp(low, high)
		var under := MapInfo.LAKE_Y
		for look in 9:
			var probe := spot + Vector2(cos(TAU * look / 9.0), sin(TAU * look / 9.0)) * 250.0 * float(look > 0)
			under = maxf(under, terrain.height_at(probe.x, probe.y))
		rings.append(Vector3(spot.x, under + float(race[6]) * _random.randf_range(0.85, 1.15), spot.y))
	var finish := Vector3(home.x, start.y + 120.0, home.y)
	rings.append(finish)
	# The line the computer pilots fly: down the runway, up, and through the rings.
	var control: Array = [start + Vector3(0.0, 1.5, 0.0)]
	control.append(Vector3(start.x + along.x * length * 0.55, start.y + 2.0, start.z + along.y * length * 0.55))
	control.append(Vector3(start.x + along.x * (length + 600.0), start.y + 80.0, start.z + along.y * (length + 600.0)))
	control.append_array(rings)
	control.append(finish + Vector3(along.x, 0.0, along.y) * 1500.0)
	return {"start": start, "heading": atan2(-along.x, -along.y), "rings": rings, "path": _spline(control, 20.0),
			"radius": float(race[5]), "grid": 0.0}


## A car course: along the highway from the organiser's spot, through gates.
func _car_course(race: Array, host: Dictionary) -> Dictionary:
	var road: Array = host.get("road", [])
	if road.is_empty():
		return {}
	var forward: PackedVector3Array = roads.route_from(road[0], road[1], true, float(race[4]))
	var backward: PackedVector3Array = roads.route_from(road[0], road[1], false, float(race[4]))
	var route := forward if Roads.distances(forward)[forward.size() - 1] >= Roads.distances(backward)[backward.size() - 1] else backward
	if route.size() < 10:
		return {}
	var along := Roads.distances(route)
	var total := along[along.size() - 1]
	var rings: Array = []
	var gap := 600.0
	var at := gap
	while at < total - 100.0:
		rings.append((Roads.sample(route, along, at)[0] as Vector3) + Vector3(0.0, 3.0, 0.0))
		at += gap
	rings.append(route[route.size() - 1] + Vector3(0.0, 3.0, 0.0))
	var first: Array = Roads.sample(route, along, 30.0)
	var direction: Vector3 = first[1]
	var right := direction.cross(Vector3.UP).normalized()
	var start: Vector3 = (first[0] as Vector3) + right * 2.2
	var path := PackedVector3Array()
	for point in route:
		path.append(point + Vector3(0.0, 0.05, 0.0))
	return {"start": start, "heading": atan2(-direction.x, -direction.z), "rings": rings, "path": path,
			"radius": 16.0, "grid": 30.0}


## A smooth line through control points (Catmull-Rom), a point every `step` metres.
static func _spline(control: Array, step: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in control.size() - 1:
		var p0: Vector3 = control[maxi(index - 1, 0)]
		var p1: Vector3 = control[index]
		var p2: Vector3 = control[index + 1]
		var p3: Vector3 = control[mini(index + 2, control.size() - 1)]
		var pieces := maxi(2, int(ceil(p1.distance_to(p2) / step)))
		for piece in pieces:
			var t := float(piece) / pieces
			var t2 := t * t
			var t3 := t2 * t
			points.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	points.append(control[control.size() - 1])
	return points


## The fastest each point of a line can be taken: no harder than `g` round
## its bends, and slowing in time for them (braking at 1.5 x that g).
static func _speed_limits(path: PackedVector3Array, along: PackedFloat32Array, g: float, top: float) -> PackedFloat32Array:
	var limits := PackedFloat32Array()
	limits.resize(path.size())
	for index in path.size():
		var limit := top
		if index > 0 and index < path.size() - 1:
			var a := path[index - 1]
			var b := path[index]
			var c := path[index + 1]
			var turn := (b - a).normalized().angle_to((c - b).normalized())
			var span := (a.distance_to(b) + b.distance_to(c)) * 0.5
			if turn > 0.0001:
				var radius := span / turn
				limit = minf(limit, sqrt(g * 9.81 * radius))
		limits[index] = limit
	for index in range(path.size() - 2, -1, -1):
		var gap := along[index + 1] - along[index]
		limits[index] = minf(limits[index], sqrt(limits[index + 1] * limits[index + 1] + 2.0 * g * 1.5 * 9.81 * gap))
	return limits


static func _nearest_index(path: PackedVector3Array, point: Vector3) -> int:
	var best := INF
	var found := 0
	for index in path.size():
		var distance := path[index].distance_squared_to(point)
		if distance < best:
			best = distance
			found = index
	return found


func _new_racer(rival_name: String, color: Color, top: float, is_air: bool, start_at: float, lane: float) -> Dictionary:
	var node := Node3D.new()
	node.name = "Racer"
	add_child(node)
	var shown := MeshInstance3D.new()
	shown.mesh = _racer_mesh(color, is_air)
	node.add_child(shown)
	var tag := Label3D.new()
	tag.text = rival_name
	tag.font_size = 40
	tag.pixel_size = 0.0015
	tag.fixed_size = true
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.outline_size = 10
	tag.modulate = color.lightened(0.3)
	tag.position = Vector3(0.0, 4.0 if is_air else 3.0, 0.0)
	node.add_child(tag)
	var bubble := Label3D.new()
	bubble.font_size = 72
	bubble.pixel_size = 0.0022
	bubble.fixed_size = true
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.outline_size = 16
	bubble.modulate = Color(1.0, 1.0, 0.85)
	bubble.outline_modulate = Color(0.1, 0.05, 0.0)
	bubble.position = Vector3(0.0, 9.0 if is_air else 6.0, 0.0)
	bubble.visible = false
	node.add_child(bubble)
	var sound := Sound.make_loop("jet_loop" if is_air else "car_loop", "Machines")
	if sound != null:
		sound.unit_size = 30.0 if is_air else 10.0
		sound.max_distance = 4000.0 if is_air else 400.0
		node.add_child(sound)
		sound.play()
	return {"node": node, "name": rival_name, "top": top, "speed": 0.0, "at": start_at, "lane": lane,
			"boost": 0.0, "boost_time": 0.0, "cooldown": _random.randf_range(2.0, 6.0), "bubble": bubble,
			"bubble_time": 0.0, "finish": 0.0, "bank": 0.0}


func _racer_mesh(color: Color, is_air: bool) -> Mesh:
	var cache: Dictionary = _plane_meshes if is_air else _car_mesh_cache
	var key := color.to_html()
	if cache.has(key):
		return cache[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := color.darkened(0.5)
	if is_air:
		# A small racer: slim fuselage, short swept wings, tall tail, bubble canopy.
		_box(surface, Vector3(0.0, 0.0, 0.0), Vector3(1.1, 1.1, 7.5), color)
		_box(surface, Vector3(0.0, 0.0, -0.8), Vector3(8.0, 0.2, 1.8), color)
		_box(surface, Vector3(0.0, 0.0, 3.2), Vector3(3.2, 0.15, 0.9), dark)
		_box(surface, Vector3(0.0, 0.9, 3.3), Vector3(0.12, 1.6, 1.0), dark)
		_box(surface, Vector3(0.0, 0.65, -1.6), Vector3(0.8, 0.45, 1.6), Color(0.1, 0.15, 0.2))
		_box(surface, Vector3(0.0, 0.0, -3.85), Vector3(0.5, 0.5, 0.3), Color(0.15, 0.15, 0.15))
	else:
		_box(surface, Vector3(0.0, 0.6, 0.0), Vector3(1.9, 0.6, 4.6), color)
		_box(surface, Vector3(0.0, 1.1, 0.4), Vector3(1.5, 0.5, 1.8), dark)
		_box(surface, Vector3(0.0, 1.0, 2.2), Vector3(1.9, 0.12, 0.5), dark)
		for corner in [Vector3(-0.9, 0.35, -1.45), Vector3(0.9, 0.35, -1.45), Vector3(-0.9, 0.35, 1.45), Vector3(0.9, 0.35, 1.45)]:
			_box(surface, corner, Vector3(0.32, 0.7, 0.7), Color(0.07, 0.07, 0.07))
	surface.generate_normals()
	var mesh := surface.commit()
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.metallic = 0.4
	look.roughness = 0.35
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, look)
	cache[key] = mesh
	return mesh


static func _box(surface: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var corners := []
	for corner in [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
		corners.append(centre + (corner as Vector3) * h)
	surface.set_color(color)
	for face in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		var f: Array = face
		for index in [0, 1, 2, 0, 2, 3]:
			surface.add_vertex(corners[f[index]])


func _make_rings() -> void:
	if _ring_looks.is_empty():
		for color in [Color(1.0, 0.85, 0.1), Color(1.0, 1.0, 1.0, 0.35), Color(0.2, 1.0, 0.35)]:
			var look := StandardMaterial3D.new()
			look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			look.albedo_color = color
			if color.a < 1.0:
				look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ring_looks.append(look)
	var rings: Array = _race["rings"]
	var path: PackedVector3Array = _race["path"]
	var radius: float = _race["radius"]
	var nodes: Array = []
	for index in rings.size():
		var centre: Vector3 = rings[index]
		var near := _nearest_index(path, centre)
		var tangent := (path[mini(near + 1, path.size() - 1)] - path[maxi(near - 1, 0)]).normalized()
		var torus := TorusMesh.new()
		torus.inner_radius = radius * 0.88
		torus.outer_radius = radius
		torus.rings = 48
		torus.ring_segments = 8
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The torus lies flat (its hole along Y); stand it across the line.
		var up := tangent
		var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
		var third := side.cross(up).normalized()
		ring.transform = Transform3D(Basis(side, up, third), centre)
		terrain.add_child(ring)
		var beam := MeshInstance3D.new()
		var pillar := CylinderMesh.new()
		pillar.top_radius = 2.5
		pillar.bottom_radius = 2.5
		pillar.height = 1200.0
		pillar.radial_segments = 8
		pillar.rings = 1
		beam.mesh = pillar
		beam.material_override = _ring_looks[1]
		beam.position = centre + Vector3(0.0, 600.0 + radius, 0.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		terrain.add_child(beam)
		nodes.append([ring, beam])
	_race["nodes"] = nodes
	_show_rings()


func _show_rings() -> void:
	var next: int = _race["next"]
	var nodes: Array = _race["nodes"]
	for index in nodes.size():
		var pair: Array = nodes[index]
		var ring: MeshInstance3D = pair[0]
		var beam: MeshInstance3D = pair[1]
		ring.visible = index >= next
		beam.visible = index == next
		var last := index == nodes.size() - 1
		ring.material_override = _ring_looks[2] if last else (_ring_looks[0] if index == next else _ring_looks[1])


func _run_race(delta: float) -> void:
	var before: float = _race["clock"]
	_race["clock"] = before + delta
	var clock: float = _race["clock"]
	# The countdown.
	if before < 0.0:
		for mark in [-3.0, -2.0, -1.0]:
			if before < mark and clock >= mark:
				game_hud.announce(str(int(-mark)), "", 0.9)
				Sound.play_ui("beep")
		if clock >= 0.0:
			game_hud.announce("GO!", "", 1.0, Color(0.4, 1.0, 0.4))
			Sound.play_ui("go")
			var vehicle: Node = _race["vehicle"]
			if is_instance_valid(vehicle):
				vehicle.race_hold = false
				vehicle.set_parked(false)
	var path: PackedVector3Array = _race["path"]
	var along: PackedFloat32Array = _race["along"]
	var total: float = along[along.size() - 1]
	var is_air: bool = _race["air"]
	var here := Origin.to_map(player.global_position) if player != null else Vector3.ZERO
	# The computer racers.
	for item in _race["racers"]:
		var racer: Dictionary = item
		if clock > 0.0:
			_run_racer(racer, delta, path, along, here, is_air)
		_place_racer(racer, path, along, is_air)
		if float(racer["finish"]) <= 0.0 and float(racer["at"]) >= total - 5.0:
			racer["finish"] = clock
	# The player through the rings.
	var rings: Array = _race["rings"]
	var next: int = _race["next"]
	if clock > 0.0 and next < rings.size() and not bool(_race["finished"]):
		var centre: Vector3 = rings[next]
		if here.distance_to(centre) < float(_race["radius"]):
			next += 1
			_race["next"] = next
			Sound.play_ui("checkpoint")
			_show_rings()
			if next >= rings.size():
				_finish_race(clock)
				return
	# Out of time: four times as long as the fastest rival would take.
	if clock > total / float((_race["racers"][0] as Dictionary)["top"]) * 4.0 + 60.0 and not bool(_race["finished"]):
		_end_race("Out of time.", false)
		return
	_update_race_label()


func _run_racer(racer: Dictionary, delta: float, _path: PackedVector3Array, along: PackedFloat32Array,
		here: Vector3, is_air: bool) -> void:
	var at: float = racer["at"]
	var limits: PackedFloat32Array = _race["limits"]
	var index := clampi(_index_at(along, at), 0, limits.size() - 1)
	racer["boost_time"] = maxf(float(racer["boost_time"]) - delta, 0.0)
	if float(racer["boost_time"]) <= 0.0:
		racer["boost"] = 0.0
	var wanted := minf(float(racer["top"]) + float(racer["boost"]), limits[index])
	var push := 25.0 if is_air else 7.0
	racer["speed"] = move_toward(float(racer["speed"]), wanted, (push if wanted > float(racer["speed"]) else 30.0) * delta)
	racer["at"] = at + float(racer["speed"]) * delta
	# Showing off when you come close.
	racer["cooldown"] = float(racer["cooldown"]) - delta
	racer["bubble_time"] = float(racer["bubble_time"]) - delta
	var bubble: Label3D = racer["bubble"]
	bubble.visible = float(racer["bubble_time"]) > 0.0
	var node: Node3D = racer["node"]
	var reach := maxf(120.0, float(racer["speed"]) * 2.5)
	if float(racer["cooldown"]) <= 0.0 and Origin.to_map(node.global_position).distance_to(here) < reach:
		racer["cooldown"] = BOAST_COOLDOWN + _random.randf_range(0.0, 6.0)
		racer["bubble_time"] = 4.0
		bubble.text = BOASTS[_random.randi() % BOASTS.size()]
		racer["boost"] = _random.randf_range(BOOST.x, BOOST.y)
		racer["boost_time"] = BOOST_TIME


static func _index_at(along: PackedFloat32Array, distance: float) -> int:
	var low := 0
	var high := along.size() - 1
	while high - low > 1:
		var middle := (low + high) >> 1
		if along[middle] <= distance:
			low = middle
		else:
			high = middle
	return low


func _place_racer(racer: Dictionary, path: PackedVector3Array, along: PackedFloat32Array, is_air: bool) -> void:
	var at: float = racer["at"]
	var picked: Array = Roads.sample(path, along, at)
	var ahead: Array = Roads.sample(path, along, at + 10.0)
	var point: Vector3 = picked[0]
	var direction: Vector3 = ((ahead[0] as Vector3) - point)
	if direction.length() < 0.01:
		direction = picked[1]
	direction = direction.normalized()
	var right := direction.cross(Vector3.UP).normalized()
	point += right * float(racer["lane"])
	var basis := Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.98 else Vector3.FORWARD)
	if is_air:
		# Bank into the turn.
		var further: Array = Roads.sample(path, along, at + 60.0)
		var bend := ((further[1] as Vector3) - direction)
		var lateral := bend.dot(right) * float(racer["speed"]) * float(racer["speed"]) / 60.0
		racer["bank"] = lerpf(float(racer["bank"]), clampf(atan2(lateral, 9.81), -1.3, 1.3), 0.1)
		basis = basis * Basis(Vector3.FORWARD, -float(racer["bank"]))
	else:
		point.y += 0.05
	var node: Node3D = racer["node"]
	node.global_transform = Transform3D(basis, Origin.to_world(point))


## Where everyone is, as distance along the racing line: the rivals' own,
## and the player's from the nearest point of the line (looked for near
## where it was last), but never past the next ring not yet flown through.
func _places() -> Array:
	var ring_at: PackedFloat32Array = _race["ring_at"]
	var next: int = _race["next"]
	var path: PackedVector3Array = _race["path"]
	var along: PackedFloat32Array = _race["along"]
	var here := Origin.to_map(player.global_position)
	var last: int = _race.get("player_index", 0)
	var best := INF
	for index in range(maxi(last - 30, 0), mini(last + 60, path.size())):
		var distance := path[index].distance_squared_to(here)
		if distance < best:
			best = distance
			last = index
	_race["player_index"] = last
	var mine := along[last]
	if next < ring_at.size():
		mine = minf(mine, ring_at[next])
	var ahead := 0
	for item in _race["racers"]:
		var racer: Dictionary = item
		if float(racer["at"]) > mine:
			ahead += 1
	return [ahead + 1, mine]


func _update_race_label() -> void:
	var label: Label = _race.get("label")
	if label == null:
		return
	var clock: float = maxf(float(_race["clock"]), 0.0)
	var rings: Array = _race["rings"]
	var next: int = _race["next"]
	var place: Array = _places()
	var distance := 0.0
	if next < rings.size():
		distance = Origin.to_map(player.global_position).distance_to(rings[next])
	label.text = "%s\nPosition %d of 4   Ring %d of %d   %s\nNext ring %s   F2 gives up" % [
		str((_race["race"] as Array)[1]), int(place[0]), mini(next + 1, rings.size()), rings.size(), _clock_text(clock),
		("%.1f km" % (distance / 1000.0)) if distance > 1000.0 else ("%d m" % int(distance))]


func _finish_race(clock: float) -> void:
	_race["finished"] = true
	var ahead := 0
	for item in _race["racers"]:
		var racer: Dictionary = item
		if float(racer["finish"]) > 0.0 and float(racer["finish"]) < clock:
			ahead += 1
	var place := ahead + 1
	var race: Array = _race["race"]
	var prize: int = race[7] if bool(_race["air"]) else race[5]
	var won := 0
	if place == 1:
		won = prize
	elif place == 2:
		won = int(prize * 0.5)
	elif place == 3:
		won = int(prize * 0.25)
	var record := Profile.record_time(str(race[0]), clock)
	var words: String = ["1st!", "2nd", "3rd", "4th"][place - 1]
	if won > 0:
		Profile.add_cash(won)
		Sound.play_ui("cash")
	_end_race("%s   %s%s%s" % [words, _clock_text(clock), "   new best time!" if record else "",
			("   won " + Profile.money(won)) if won > 0 else ""], place == 1)


func _end_race(message: String, won: bool) -> void:
	game_hud.announce("RACE WON" if won else ("FINISHED" if message.begins_with("2nd") or message.begins_with("3rd")
			or message.begins_with("4th") else "RACE OVER"), message, 6.0,
			Color(0.4, 1.0, 0.4) if won else Color(1.0, 0.75, 0.3))
	var vehicle: Node = _race.get("vehicle")
	if is_instance_valid(vehicle) and bool(vehicle.race_hold):
		vehicle.race_hold = false
		vehicle.set_parked(false)
	for item in _race.get("nodes", []):
		for node in (item as Array):
			if is_instance_valid(node):
				(node as Node).queue_free()
	for item in _race.get("racers", []):
		var racer: Dictionary = item
		if is_instance_valid(racer["node"]):
			(racer["node"] as Node).queue_free()
	var label: Label = _race.get("label")
	if label != null and is_instance_valid(label):
		label.queue_free()
	_race = {}


# --- Cargo ----------------------------------------------------------------------------------

func _take_job(from: String, to: String, crate_index: int) -> void:
	if not _job.is_empty():
		_status.text = "You already have a crate to deliver (F2 gives it up)."
		return
	var crate: Array = CRATES[clampi(crate_index, 0, CRATES.size() - 1)]
	var start: Vector3 = (_airports[from] as Dictionary)["apron"]
	var target: Vector3 = (_airports[to] as Dictionary)["apron"]
	var distance := Vector2(start.x, start.z).distance_to(Vector2(target.x, target.z))
	var body := RigidBody3D.new()
	body.name = "Crate"
	body.mass = float(crate[1])
	body.collision_layer = Units.LAYER_BODIES
	body.collision_mask = Units.LAYER_WORLD | Units.LAYER_BODIES
	var size: float = crate[2]
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var look := StandardMaterial3D.new()
	look.albedo_color = Color(0.62, 0.45, 0.25)
	look.roughness = 0.9
	box.material = look
	var shown := MeshInstance3D.new()
	shown.mesh = box
	body.add_child(shown)
	var tag := Label3D.new()
	tag.text = "CARGO for %s" % to
	tag.font_size = 48
	tag.pixel_size = 0.0018
	tag.fixed_size = true
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.outline_size = 10
	tag.position = Vector3(0.0, size * 0.5 + 0.8, 0.0)
	body.add_child(tag)
	add_child(body)
	var here := Origin.to_map(player.global_position)
	var spot := Vector3(here.x, 0.0, here.z) + (Vector3(start.x, 0.0, start.z) - Vector3(here.x, 0.0, here.z)).normalized() * 8.0
	spot.y = terrain.height_at(spot.x, spot.z) + size * 0.5 + 0.3
	body.global_position = Origin.to_world(spot)
	# The drop zone: a green ring on the ground and a beam over it.
	var zone := Node3D.new()
	zone.position = target + Vector3(0.0, 0.3, 0.0)
	terrain.add_child(zone)
	var torus := TorusMesh.new()
	torus.inner_radius = DROP_ZONE - 1.2
	torus.outer_radius = DROP_ZONE
	var zone_look := StandardMaterial3D.new()
	zone_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zone_look.albedo_color = Color(0.2, 1.0, 0.35)
	torus.material = zone_look
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	zone.add_child(ring)
	var pillar := CylinderMesh.new()
	pillar.top_radius = 2.0
	pillar.bottom_radius = 2.0
	pillar.height = 900.0
	var beam_look := StandardMaterial3D.new()
	beam_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_look.albedo_color = Color(0.2, 1.0, 0.35, 0.3)
	pillar.material = beam_look
	var beam := MeshInstance3D.new()
	beam.mesh = pillar
	beam.position = Vector3(0.0, 450.0, 0.0)
	zone.add_child(beam)
	var pay := int(round(distance / 1000.0 * float(crate[3]))) + 200
	_job = {"crate": body, "to": to, "target": target, "pay": pay, "clock": 0.0,
			"par": distance / 45.0 + 120.0, "zone": zone, "settled": 0.0, "speeds": [], "name": crate[0]}
	terrain.extra_sources.append(self)
	if _window != null:
		_window.visible = false
	game_hud.announce("CARGO", "%s to %s, %.1f km: %s (more if you are quick). F2 gives up." % [
		str(crate[0]), to, distance / 1000.0, Profile.money(pay)], 6.0)


func _run_job(delta: float) -> void:
	var crate: RigidBody3D = _job["crate"]
	if not is_instance_valid(crate):
		_end_job("The crate is gone.", 0)
		return
	_job["clock"] = float(_job["clock"]) + delta
	# Smashed by a hard knock: its change of speed over 50 ms.
	var speeds: Array = _job["speeds"]
	speeds.append(crate.linear_velocity)
	if speeds.size() > 6:
		speeds.pop_front()
	if speeds.size() == 6 and float(_job["clock"]) > 1.0:
		var knock := ((speeds[5] as Vector3) - (speeds[0] as Vector3)).length() / (5.0 * delta) / 9.81
		if knock > CRATE_SMASH_G:
			Sound.play_at("collapse", crate.global_position, 0.0, 30.0, 1.4)
			_end_job("The crate smashed.", 0)
			return
	var at := Origin.to_map(crate.global_position)
	var target: Vector3 = _job["target"]
	var flat := Vector2(at.x - target.x, at.z - target.z).length()
	var low: bool = at.y - terrain.height_at(at.x, at.z) < 4.0
	if flat < DROP_ZONE and low and crate.linear_velocity.length() < 1.5:
		_job["settled"] = float(_job["settled"]) + delta
		if float(_job["settled"]) > 1.5:
			var pay: int = _job["pay"]
			var quick := float(_job["clock"]) < float(_job["par"])
			if quick:
				pay = int(pay * 1.5)
			Profile.add_cash(pay)
			Sound.play_ui("cash")
			_end_job("Delivered to %s%s: %s" % [_job["to"], " fast" if quick else "", Profile.money(pay)], pay)
	else:
		_job["settled"] = 0.0


func _end_job(message: String, paid: int) -> void:
	game_hud.announce("DELIVERED" if paid > 0 else "CARGO", message, 5.0,
			Color(0.4, 1.0, 0.4) if paid > 0 else Color(1.0, 0.75, 0.3))
	var crate: Node = _job.get("crate")
	if is_instance_valid(crate):
		crate.queue_free()
	var zone: Node = _job.get("zone")
	if is_instance_valid(zone):
		zone.queue_free()
	terrain.extra_sources.erase(self)
	_job = {}


func _job_text() -> String:
	if _job.is_empty():
		return "Cash %s" % Profile.money(Profile.cash())
	var crate: RigidBody3D = _job["crate"]
	var away := 0.0
	if is_instance_valid(crate):
		var at := Origin.to_map(crate.global_position)
		var target: Vector3 = _job["target"]
		away = Vector2(at.x - target.x, at.z - target.z).length()
	return "Delivering a %s to %s: %.1f km to go, %s on the clock." % [
		str(_job["name"]).to_lower(), _job["to"], away / 1000.0, _clock_text(float(_job["clock"]))]


## The crate's place and speed, so the ground stays solid under it (terrain.gd).
func body_motions() -> Array:
	if _job.is_empty() or not is_instance_valid(_job.get("crate")):
		return []
	var crate: RigidBody3D = _job["crate"]
	return [[crate.global_position, crate.linear_velocity]]


## Moves the crate with the world when main.gd re-centres it.
func shift_origin(shift: Vector3) -> void:
	if not _job.is_empty() and is_instance_valid(_job.get("crate")):
		var crate: RigidBody3D = _job["crate"]
		crate.global_position -= shift
