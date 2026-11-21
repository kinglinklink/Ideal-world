extends Node
## The mission board (J, or the Missions button) and the markers on the
## full map.
##
## The board lists everything left to do: races not yet won (with the
## prize, the rivals' speed and your best time), cargo runs, photo jobs and
## birds not yet photographed. Won races and finished jobs move to a Done
## list. Each line has a Waypoint button that marks it on the mini map.
##
## Photo jobs pay for a photo (the camera tool, C) of a landmark: it has to
## be in the frame and near enough to fill some of it.

const Origin = preload("res://scripts/origin.gd")
const Profile = preload("res://scripts/profile.gd")
const Sound = preload("res://scripts/sound.gd")

## [id, title, the map point's name, pay $, nearer than this many metres]
const PHOTO_JOBS := [
	["photo_cromwell", "The Cromwell villa", "Cromwell villa", 1500, 600.0],
	["photo_lodge", "Camp Melita's lodge", "Camp Melita lodge", 800, 300.0],
	["photo_shelter", "The Shelter Island mansion", "Shelter mansion", 1200, 400.0],
	["photo_carrier", "The aircraft carrier", "Carrier", 2000, 2500.0],
	["photo_volcano", "The volcano", "Volcano", 2500, 9000.0],
	["photo_tower", "A wizard tower", "Wizard tower", 1500, 1500.0],
	["photo_cave", "A cave mouth", "Wild Horse Cavern", 1000, 150.0],
]

var races: Node = null          # races.gd
var terrain: Node = null        # terrain.gd, for the landmarks
var minimap: Control = null     # minimap.gd, for waypoints
var game_hud: Node = null       # game_hud.gd
var player: Node3D = null       # player.gd
var birds: Node = null          # birds.gd, if there are birds

var _window: PanelContainer = null
var _column: VBoxContainer = null


func setup() -> void:
	add_to_group("missions")
	var made: Array = game_hud.make_window("Missions", 640.0)
	_window = made[0]
	_column = made[1]


func toggle() -> void:
	if _window == null:
		return
	_window.visible = not _window.visible
	if _window.visible:
		refresh()
		if player != null:
			player.cursor_free = true


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_J \
			and get_viewport().gui_get_focus_owner() == null:
		toggle()


# --- The board ------------------------------------------------------------------

func refresh() -> void:
	# Keep the heading row; rebuild the rest.
	var children := _column.get_children()
	for index in range(1, children.size()):
		children[index].queue_free()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var done: Array = []

	_heading(list, "Races to win")
	for item in races.race_list():
		var race: Dictionary = item
		var line := "%s  (%s, %s)   1st %s   rivals %d m/s%s" % [race["name"], "air" if race["kind"] == "air" else "car",
				race["host"], Profile.money(int(race["prize"])), int(race["speed"]),
				("   best " + _clock(float(race["best"]))) if float(race["best"]) > 0.0 else ""]
		if bool(race["won"]):
			done.append(["✓  " + race["name"] + ("   best " + _clock(float(race["best"])) if float(race["best"]) > 0.0 else ""), race["where"]])
		else:
			_row(list, line, race["where"])

	_heading(list, "Cargo runs")
	var agents: Array = races.cargo_agents()
	_note(list, "%d delivered so far. Any airport's agent has crates for every other airport, paid by distance and weight." % Profile.cargo_runs())
	var here := _here()
	agents.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).distance_to(here) < (b[0] as Vector2).distance_to(here))
	for index in mini(agents.size(), 3):
		_row(list, "Cargo agent at %s  (%.1f km)" % [agents[index][1], (agents[index][0] as Vector2).distance_to(here) / 1000.0], agents[index][0])

	_heading(list, "Photo jobs   (C takes photos)")
	for job in PHOTO_JOBS:
		var where := _landmark(str(job[2]))
		var line := "%s   pays %s" % [job[1], Profile.money(int(job[3]))]
		if Profile.mission_done(str(job[0])):
			done.append(["✓  " + str(job[1]), where])
		elif where != Vector2.INF:
			_row(list, line, where)

	if birds != null:
		_heading(list, "Birds to photograph")
		var missing: Array = birds.unphotographed()
		if missing.is_empty():
			_note(list, "Every bird photographed!")
		else:
			_note(list, "%d of %d still to photograph. Open the bird guide (B) for where to look." % [missing.size(), birds.species_count()])
			for index in mini(missing.size(), 6):
				_note(list, "   " + str(missing[index]))

	_heading(list, "Done")
	if done.is_empty():
		_note(list, "Nothing yet.")
	for item in done:
		_row(list, str(item[0]), item[1], Color(1.0, 0.85, 0.3))


func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	parent.add_child(label)


func _note(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(580, 0)
	parent.add_child(label)


func _row(parent: Control, text: String, where: Vector2, color: Color = Color(1, 1, 1)) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	if where != Vector2.INF:
		var mark := Button.new()
		mark.text = "Waypoint"
		mark.focus_mode = Control.FOCUS_NONE
		mark.pressed.connect(func() -> void:
			set_waypoint(where)
			game_hud.announce("", "Waypoint set: %s" % text.get_slice("   ", 0).trim_prefix("✓  "), 2.0))
		row.add_child(mark)


func set_waypoint(where: Vector2) -> void:
	if minimap != null:
		minimap.waypoint = where
		minimap.has_waypoint = true


static func _clock(seconds: float) -> String:
	return "%d:%04.1f" % [int(seconds / 60.0), fmod(seconds, 60.0)]


func _here() -> Vector2:
	if player == null:
		return Vector2.ZERO
	var at := Origin.to_map(player.global_position)
	return Vector2(at.x, at.z)


## The nearest map point with this name, or Vector2.INF.
func _landmark(point_name: String) -> Vector2:
	var best := Vector2.INF
	var here := _here()
	if terrain == null:
		return best
	for item in terrain.landmarks.map_points:
		var point: Array = item
		if str(point[1]) == point_name:
			var at: Vector2 = point[0]
			if best == Vector2.INF or at.distance_to(here) < best.distance_to(here):
				best = at
	return best


# --- The map ----------------------------------------------------------------------

## Markers for the full map: {"at": Vector2, "kind", "name", "info", "done"}.
func markers() -> Array:
	var list: Array = []
	var by_place: Dictionary = {}
	for item in races.race_list():
		var race: Dictionary = item
		var key := str(race["where"])
		if not by_place.has(key):
			by_place[key] = {"at": race["where"], "kind": "race", "name": "%s races at %s" % [
					"Air" if race["kind"] == "air" else "Car", race["host"]], "lines": [], "done": true}
		var entry: Dictionary = by_place[key]
		(entry["lines"] as Array).append("%s%s   1st %s   rivals %d m/s%s" % ["✓ " if race["won"] else "", race["name"],
				Profile.money(int(race["prize"])), int(race["speed"]),
				("   best " + _clock(float(race["best"]))) if float(race["best"]) > 0.0 else ""])
		if not bool(race["won"]):
			entry["done"] = false
	for key in by_place:
		var entry: Dictionary = by_place[key]
		entry["info"] = "\n".join(entry["lines"] as Array) + "\nTalk to the organiser (E) to race."
		list.append(entry)
	for item in races.cargo_agents():
		var agent: Array = item
		if by_place.has(str(agent[0])):
			continue
		list.append({"at": agent[0], "kind": "cargo", "name": "Cargo agent, %s" % agent[1],
				"info": "Crates to every other airport, paid by distance and weight.", "done": false})
	for job in PHOTO_JOBS:
		var where := _landmark(str(job[2]))
		if where == Vector2.INF:
			continue
		list.append({"at": where, "kind": "photo", "name": "Photo job: %s" % job[1],
				"info": "Pays %s for a photo (C) with it in the frame, from within %d m." % [Profile.money(int(job[3])), int(job[4])],
				"done": Profile.mission_done(str(job[0]))})
	for node in get_tree().get_nodes_in_group("map_markers"):
		list.append_array(node.map_markers())
	return list


# --- Photo jobs ---------------------------------------------------------------------

## A photo was just taken with `camera`: pays any photo job whose landmark
## is in it. Returns what was paid for, as lines to announce.
func photo_taken(camera: Camera3D) -> Array:
	var paid: Array = []
	if camera == null or terrain == null:
		return paid
	var eye := Origin.to_map(camera.global_position)
	for job in PHOTO_JOBS:
		if Profile.mission_done(str(job[0])):
			continue
		for item in terrain.landmarks.map_points:
			var point: Array = item
			if str(point[1]) != str(job[2]):
				continue
			var at: Vector2 = point[0]
			var ground: float = terrain.height_at(at.x, at.y)
			var target := Vector3(at.x, ground + 15.0, at.y)
			if Vector2(eye.x, eye.z).distance_to(at) > float(job[4]):
				continue
			if not camera.is_position_in_frustum(Origin.to_world(target)):
				continue
			Profile.mark_mission(str(job[0]))
			Profile.add_cash(int(job[3]))
			Sound.play_ui("cash")
			paid.append("Photo job done: %s, %s" % [job[1], Profile.money(int(job[3]))])
			break
	return paid
