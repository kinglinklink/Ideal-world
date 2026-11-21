extends Node
## Fuel stations: at every airport, beside the highway in each town, and at
## the docks. Each has a green circle on the ground and a pump with a sign.
## Park inside the circle, get out, walk up to the pump and press F: the
## Fuel window shows the litres needed and the cost to fill, with Fill up
## and "Spend an amount" (if money is short it fills as far as it goes).
## The tanks fill over a few seconds.
##
## Price: $0.25 a litre of petrol (34 MJ/L), scaled by the fuel's energy
## for other fuels; 20 % more at airports. A 1,000 L tank costs $250 to
## fill, a quarter of the Rookie Loop's first prize.
## Ideal-mode engines burn nothing, so they never need it.

const Origin = preload("res://scripts/origin.gd")
const Profile = preload("res://scripts/profile.gd")
const Sound = preload("res://scripts/sound.gd")

const PRICE := 0.25                  # $ per litre of petrol
const PETROL_ENERGY := 34.0e6        # J per litre
const AIRPORT_MARKUP := 1.2
const REACH := 3.5                   # m from the pump to use it
const POUR_RATE := 400.0             # litres a second at the pump

var terrain: Node = null             # terrain.gd
var races: Node = null               # races.gd, for the airports
var roads: RefCounted = null         # roads.gd
var player: Node3D = null            # player.gd
var game_hud: Node = null            # game_hud.gd

var stations: Array = []             # {"name", "at": map Vector3 (circle centre), "pump": map Vector3, "radius", "airport", "node"}
var _near: Dictionary = {}
var _check := 0.0
var _window: PanelContainer = null
var _column: VBoxContainer = null
var _status: Label = null
var _pouring: Dictionary = {}        # {"engines", "litres", "station"}
var _ring_look: StandardMaterial3D = null


func setup() -> void:
	add_to_group("map_markers")
	add_to_group("fuel")
	_ring_look = StandardMaterial3D.new()
	_ring_look.albedo_color = Color(0.2, 1.0, 0.35, 0.35)
	_ring_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	for airport_name in races._airports:
		var airport: Dictionary = races._airports[airport_name]
		var apron: Vector3 = airport["apron"]
		var along: Vector2 = airport["along"]
		var side := Vector2(-along.y, along.x)
		var spot := Vector2(apron.x, apron.z) - along * 45.0 + side * 10.0
		_add("%s fuel" % airport_name, spot, 15.0, true)
	if roads != null and not roads.lines.is_empty():
		for item in terrain.world.get("town_names", []):
			var town: Dictionary = item
			var at: Array = town["at"]
			var middle := Vector2(float(at[0]), float(at[1]))
			var bounds: Array = terrain.world.get("bounds", [-11520.0, -27648.0, 17408.0, 22528.0])
			if middle.x < float(bounds[0]) or middle.y < float(bounds[1]) or middle.x > float(bounds[2]) or middle.y > float(bounds[3]):
				continue
			var found: Array = roads.nearest(middle)
			if found.is_empty():
				continue
			var line: PackedVector3Array = roads.lines[found[0]]
			var point := line[found[1]]
			if Vector2(point.x, point.z).distance_to(middle) > 2500.0:
				continue
			var next := line[mini(int(found[1]) + 1, line.size() - 1)]
			var prior := line[maxi(int(found[1]) - 1, 0)]
			var right := (next - prior).normalized().cross(Vector3.UP).normalized()
			var spot := point - right * 16.0
			_add("%s fuel" % str(town["name"]), Vector2(spot.x, spot.z), 6.0, false)
	for item in terrain.landmarks.map_points:
		var point: Array = item
		if str(point[1]).ends_with("dock"):
			add_dock_station(str(point[1]), point[0])
	var made: Array = game_hud.make_window("Fuel", 460.0)
	_window = made[0]
	_column = made[1]


## A fuel station at a dock (boats.gd adds the docks it makes).
func add_dock_station(dock_name: String, at: Vector2) -> void:
	for station in stations:
		if (station["at"] as Vector3).distance_to(Vector3(at.x, (station["at"] as Vector3).y, at.y)) < 30.0:
			return
	# On the shore beside the dock, not in the water.
	var spot := at
	for step in 12:
		if not terrain.is_lake(spot.x, spot.y):
			break
		var best := spot
		var best_ground := -INF
		for angle in range(0, 360, 45):
			var probe := spot + Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * 10.0
			var ground: float = terrain.height_at(probe.x, probe.y)
			if ground > best_ground:
				best_ground = ground
				best = probe
		spot = best
	_add("%s fuel" % dock_name.trim_suffix(" dock").trim_suffix(" Dock"), spot, 6.0, false)


func _add(title: String, spot: Vector2, radius: float, airport: bool) -> void:
	var ground: float = terrain.height_at(spot.x, spot.y)
	var centre := Vector3(spot.x, ground, spot.y)
	var pump := centre + Vector3(radius + 2.5, 0.0, 0.0)
	pump.y = terrain.height_at(pump.x, pump.z)
	var node := Node3D.new()
	node.name = "FuelStation"
	terrain.add_child(node)
	node.position = centre
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.1
	mesh.radial_segments = 40
	mesh.rings = 1
	disc.mesh = mesh
	disc.material_override = _ring_look
	disc.position = Vector3(0.0, 0.12, 0.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(disc)
	var pump_node := Node3D.new()
	pump_node.position = pump - centre
	node.add_child(pump_node)
	_box(pump_node, Vector3(0.0, 0.9, 0.0), Vector3(0.8, 1.8, 0.55), Color(0.85, 0.12, 0.1))
	_box(pump_node, Vector3(0.0, 1.35, -0.29), Vector3(0.6, 0.45, 0.04), Color(0.1, 0.12, 0.14))
	_box(pump_node, Vector3(0.0, 1.9, 0.0), Vector3(0.9, 0.2, 0.65), Color(0.95, 0.95, 0.92))
	_box(pump_node, Vector3(-0.45, 0.9, 0.0), Vector3(0.08, 0.08, 0.08), Color(0.1, 0.1, 0.1))
	_box(pump_node, Vector3(-0.5, 0.5, 0.0), Vector3(0.05, 0.8, 0.05), Color(0.1, 0.1, 0.1))
	var pump_body := StaticBody3D.new()
	var pump_shape := CollisionShape3D.new()
	var pump_box := BoxShape3D.new()
	pump_box.size = Vector3(0.8, 2.0, 0.55)
	pump_shape.shape = pump_box
	pump_shape.position = Vector3(0.0, 1.0, 0.0)
	pump_body.add_child(pump_shape)
	pump_node.add_child(pump_body)
	var sign_label := Label3D.new()
	var price := PRICE * (AIRPORT_MARKUP if airport else 1.0)
	sign_label.text = "FUEL   $%.2f / L\n[F]  Refuel at the pump" % price
	sign_label.font_size = 48
	sign_label.pixel_size = 0.01
	sign_label.outline_size = 10
	sign_label.modulate = Color(0.55, 1.0, 0.6)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.position = Vector3(0.0, 3.0, 0.0)
	sign_label.visibility_range_end = 250.0
	pump_node.add_child(sign_label)
	stations.append({"name": title, "at": centre, "pump": pump, "radius": radius, "airport": airport, "node": node})


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var shown := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	shown.mesh = box
	var look := StandardMaterial3D.new()
	look.albedo_color = color
	shown.material_override = look
	shown.position = at
	parent.add_child(shown)


func map_markers() -> Array:
	var list: Array = []
	for station in stations:
		var at: Vector3 = station["at"]
		list.append({"at": Vector2(at.x, at.z), "kind": "fuel", "name": station["name"],
				"info": "$%.2f a litre of petrol. Park in the green circle, get out and press F at the pump." % (
					PRICE * (AIRPORT_MARKUP if bool(station["airport"]) else 1.0)), "done": false})
	return list


# --- Using a pump ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _pouring.is_empty():
		_pour(delta)
	_check -= delta
	if _check > 0.0 or player == null:
		return
	_check = 0.2
	var was_near := not _near.is_empty()
	_near = {}
	if not bool(player.seated):
		var here := Origin.to_map(player.global_position)
		for station in stations:
			if (station["pump"] as Vector3).distance_to(here) < REACH:
				_near = station
				break
	if game_hud == null:
		return
	if not _near.is_empty():
		game_hud.prompt.text = "F  Refuel (park in the green circle first)"
	elif was_near and game_hud.prompt.text.begins_with("F  Refuel"):
		game_hud.prompt.text = ""


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F and not _near.is_empty() \
			and get_viewport().gui_get_focus_owner() == null:
		_open(_near)
		get_viewport().set_input_as_handled()


## Every spawned build with a body in the station's circle: [name, spawner].
func _vehicles_in(station: Dictionary) -> Array:
	var found: Array = []
	var centre: Vector3 = station["at"]
	for node in get_tree().get_nodes_in_group("combat"):
		var spawner: Node = node.spawner
		if spawner == null or not bool(spawner.spawned) or spawner.engines == null:
			continue
		for item in spawner.all_bodies():
			var body := item as RigidBody3D
			if body == null or not is_instance_valid(body):
				continue
			var at := Origin.to_map(body.global_position)
			if Vector2(at.x, at.z).distance_to(Vector2(centre.x, centre.z)) < float(station["radius"]) and absf(at.y - centre.y) < 12.0:
				found.append([_vehicle_name(spawner), spawner])
				break
	return found


func _vehicle_name(spawner: Node) -> String:
	var fleet: Node = get_tree().get_first_node_in_group("fleet")
	if fleet != null:
		for item in fleet.vehicles:
			if (item as Dictionary)["spawner"] == spawner:
				return str(item["name"])
	return "Your build (from the pad)"


func price_per_litre(station: Dictionary, engines: Node) -> float:
	var energy: float = engines.energy_per_litre() if engines != null else PETROL_ENERGY
	return PRICE * energy / PETROL_ENERGY * (AIRPORT_MARKUP if bool(station["airport"]) else 1.0)


func _open(station: Dictionary) -> void:
	for index in range(1, _column.get_child_count()):
		_column.get_child(index).queue_free()
	var vehicles := _vehicles_in(station)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(430, 0)
	if vehicles.is_empty():
		_status.text = "Nothing is parked in the green circle. Drive or fly in, stop inside it, get out and press F again."
		_column.add_child(_status)
	for item in vehicles:
		var pair: Array = item
		var engines: Node = (pair[1] as Node).engines
		var capacity: float = engines.total_capacity()
		var held: float = engines.total_fuel()
		var needed := maxf(capacity - held, 0.0)
		var price := price_per_litre(station, engines)
		var title := Label.new()
		title.text = str(pair[0])
		title.add_theme_font_size_override("font_size", 17)
		_column.add_child(title)
		var facts := Label.new()
		if capacity <= 0.0:
			facts.text = "No fuel tanks."
		else:
			facts.text = "%.0f L of %.0f L   ·   needs %.0f L   ·   $%.2f a litre\nCost to fill: %s" % [
				held, capacity, needed, price, Profile.money(int(ceil(needed * price)))]
		_column.add_child(facts)
		if capacity <= 0.0:
			continue
		var row := HBoxContainer.new()
		_column.add_child(row)
		var fill := Button.new()
		fill.text = "Fill up"
		fill.focus_mode = Control.FOCUS_NONE
		fill.pressed.connect(func() -> void: _buy(station, engines, needed * price))
		row.add_child(fill)
		var amount := LineEdit.new()
		amount.placeholder_text = "$ amount"
		amount.custom_minimum_size = Vector2(110, 0)
		row.add_child(amount)
		var spend := Button.new()
		spend.text = "Spend"
		spend.focus_mode = Control.FOCUS_NONE
		spend.pressed.connect(func() -> void:
			_buy(station, engines, maxf(amount.text.replace("$", "").replace(",", "").to_float(), 0.0)))
		row.add_child(spend)
	if not vehicles.is_empty():
		_column.add_child(_status)
		_status.text = "You have %s." % Profile.money(Profile.cash())
	_window.visible = true
	if player != null:
		player.cursor_free = true


## Buys `dollars` of fuel (no more than fits, no more than you have).
func _buy(station: Dictionary, engines: Node, dollars: float) -> void:
	var price := price_per_litre(station, engines)
	var needed := maxf(engines.total_capacity() - engines.total_fuel(), 0.0)
	var litres := minf(needed, dollars / maxf(price, 0.0001))
	litres = minf(litres, float(Profile.cash()) / maxf(price, 0.0001))
	var cost := int(ceil(litres * price))
	if litres < 0.5 or cost <= 0:
		_status.text = "The tanks are full." if needed < 0.5 else "Not enough money (%s)." % Profile.money(Profile.cash())
		return
	if not Profile.spend(cost):
		_status.text = "Not enough money."
		return
	_pouring = {"engines": engines, "litres": litres}
	Sound.play_ui("cash")
	_status.text = "Filling %.0f L for %s..." % [litres, Profile.money(cost)]


func _pour(delta: float) -> void:
	var engines: Node = _pouring["engines"]
	if not is_instance_valid(engines):
		_pouring = {}
		return
	var step := minf(float(_pouring["litres"]), POUR_RATE * delta)
	engines.add_fuel(step)
	_pouring["litres"] = float(_pouring["litres"]) - step
	if float(_pouring["litres"]) <= 0.01:
		_pouring = {}
		if _status != null and is_instance_valid(_status):
			_status.text = "Done: %.0f L in the tanks. You have %s." % [engines.total_fuel(), Profile.money(Profile.cash())]
		Sound.play_ui("click")
