extends Node
## The flight replay: the last LENGTH seconds of every spawned body and of
## the character, played back from a camera that orbits whatever the
## character was riding in.
##
## Recording runs all the time, RATE snapshots a second. A snapshot holds
## where each body was (in map positions, so it survives the world
## re-centring) and, whenever a body's set of parts changes (a part shot off,
## a chunk breaking away), what the body looked like from then on. So a crash
## replays with the plane whole until the moment it came apart.
##
## Playing pauses the game, hides the live bodies and shows copies of their
## meshes in their recorded places. Space, Esc or the Skip button ends it;
## dragging with either mouse button turns the camera and the wheel zooms.
## Key 0 plays a replay once something has been spawned; dying plays one too
## (main.gd), and the character comes back at the hangar when it ends.

const Origin = preload("res://scripts/origin.gd")

const RATE := 30.0              # snapshots per second
const LENGTH := 30.0            # seconds kept
const MAX_FRAMES := 900         # RATE x LENGTH
const PRUNE_EVERY := 150        # snapshots between clearing out looks no longer needed

signal finished(reason: String)

## True while a replay is playing, so menus.gd leaves Esc alone.
static var playing := false

var spawner: Node3D = null      # spawner.gd: the build on the pad
var fleet: Node3D = null        # fleet.gd
var player: Node3D = null       # player.gd
var controller: Node = null     # build_controller.gd: is the build spawned?
var screens: Array = []         # CanvasLayers hidden while a replay plays (the interface)
var active := false

var _frames: Array = []         # {"n": number, "t": seconds, "bodies": {id: Transform3D in map}, "player": Transform3D, "focus": id}
var _looks: Dictionary = {}     # body id -> Array of [first snapshot number, parts]; parts: [mesh, surface material, override, transform]
var _counts: Dictionary = {}    # body id -> its child count when last looked at
var _number := 0                # snapshots taken so far
var _clock := 0.0
var _timer := 0.0

var _time := 0.0                # seconds into the replay
var _speed := 1.0
var _ghost_root: Node3D = null
var _ghosts: Dictionary = {}    # "id/version" -> Node3D
var _shown: Dictionary = {}     # body id -> the key of its ghost on show
var _player_ghost: Node3D = null
var _camera: Camera3D = null
var _old_camera: Camera3D = null
var _yaw := 0.6
var _pitch := -0.25
var _distance := 18.0
var _dragging := false
var _ui: CanvasLayer = null
var _bar: ProgressBar = null
var _speed_button: Button = null
var _hidden: Array = []         # [Node3D, was visible]
var _was_paused := false
var _reason := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# --- Recording ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if active or get_tree().paused:
		return
	_clock += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / RATE
	_record()


func _record() -> void:
	var bodies: Dictionary = {}
	var focus := 0
	var nearest := INF
	var here: Vector3 = player.global_position if player != null else Vector3.ZERO
	var seated: bool = player != null and bool(player.seated)
	for source in _sources():
		for child in (source as Node).get_children():
			var body := child as RigidBody3D
			if body == null or not body.is_inside_tree():
				continue
			var id := body.get_instance_id()
			var count := body.get_child_count()
			if int(_counts.get(id, -1)) != count:
				_counts[id] = count
				_capture(id, body)
			var place := body.global_transform
			if seated:
				var distance := place.origin.distance_to(here)
				if distance < nearest:
					nearest = distance
					focus = id
			place.origin += Origin.offset
			bodies[id] = place
	var frame := {"n": _number, "t": _clock, "bodies": bodies, "focus": focus}
	if player != null:
		var body_place: Transform3D = player.model_transform()
		body_place.origin += Origin.offset
		frame["player"] = body_place
	_frames.append(frame)
	_number += 1
	while _frames.size() > MAX_FRAMES:
		_frames.pop_front()
	if _number % PRUNE_EVERY == 0:
		_prune()


func _sources() -> Array:
	var list: Array = []
	if spawner != null and bool(spawner.spawned):
		list.append(spawner)
	if fleet != null:
		list.append_array(fleet.spawners())
	return list


## Notes what a body looks like from this snapshot on: each mesh it shows,
## with its materials and its place in the body.
func _capture(id: int, body: RigidBody3D) -> void:
	var parts: Array = []
	for child in body.get_children():
		var shown := child as MeshInstance3D
		if shown == null or not shown.visible or shown.mesh == null or shown.is_queued_for_deletion():
			continue
		parts.append([shown.mesh, shown.get_surface_override_material(0), shown.material_override, shown.transform])
	if not _looks.has(id):
		_looks[id] = []
	(_looks[id] as Array).append([_number, parts])


## Forgets the looks of bodies no snapshot still holds, and older looks of
## a body that a newer one replaced before the oldest snapshot.
func _prune() -> void:
	if _frames.is_empty():
		_looks.clear()
		_counts.clear()
		return
	var oldest: int = int(_frames[0]["n"])
	var seen: Dictionary = {}
	for frame in _frames:
		for id in (frame["bodies"] as Dictionary):
			seen[id] = true
	for id in _looks.keys():
		if not seen.has(id):
			_looks.erase(id)
			_counts.erase(id)
			continue
		var versions: Array = _looks[id]
		while versions.size() > 1 and int(versions[1][0]) <= oldest:
			versions.pop_front()


## True if there is something worth replaying: anything spawned.
func can_play() -> bool:
	return _frames.size() > int(RATE) and (not _sources().is_empty()
			or (controller != null and bool(controller.spawned)))


# --- Playing -----------------------------------------------------------------

## Plays the replay. `reason` is shown at the top ("You crashed"). Returns
## false if there is nothing to play.
func start(reason: String = "") -> bool:
	if active or _frames.size() < 10:
		return false
	active = true
	playing = true
	_reason = reason
	_was_paused = get_tree().paused
	get_tree().paused = true
	_time = 0.0
	_speed = 1.0
	_ghost_root = Node3D.new()
	_ghost_root.name = "ReplayGhosts"
	get_parent().add_child(_ghost_root)
	_hidden.clear()
	for node in [spawner, fleet, player]:
		var hidden_node := node as Node3D
		if hidden_node != null:
			_hidden.append([hidden_node, hidden_node.visible])
			hidden_node.visible = false
	for item in screens:
		var screen := item as CanvasLayer
		if screen != null:
			_hidden.append([screen, screen.visible])
			screen.visible = false
	if player != null:
		_player_ghost = player.model_copy()
		_ghost_root.add_child(_player_ghost)
	_old_camera = get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.far = 60000.0
	_camera.near = 0.1
	_camera.fov = 70.0
	_ghost_root.add_child(_camera)
	_camera.make_current()
	_build_ui()
	_show(0.0)
	return true


func stop() -> void:
	if not active:
		return
	active = false
	playing = false
	for item in _hidden:
		var pair: Array = item
		var node: Object = pair[0]
		if is_instance_valid(node):
			node.set("visible", pair[1])
	_hidden.clear()
	if is_instance_valid(_old_camera):
		_old_camera.make_current()
	if is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
	_ghosts.clear()
	_shown.clear()
	_player_ghost = null
	_camera = null
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
	get_tree().paused = _was_paused
	finished.emit(_reason)


func _length() -> float:
	if _frames.size() < 2:
		return 0.0
	return float(_frames[_frames.size() - 1]["t"]) - float(_frames[0]["t"])


func _process(delta: float) -> void:
	if not active:
		return
	_time += delta * _speed
	var length := _length()
	if _time >= length:
		_time = length
		stop()
		return
	_show(_time)
	if _bar != null and length > 0.0:
		_bar.value = _time / length * 100.0


## Puts every ghost where it was `time` seconds into the replay.
func _show(time: float) -> void:
	if _frames.size() < 2:
		return
	var start_t: float = float(_frames[0]["t"])
	var wanted := start_t + time
	# The snapshot at or just before the time, and the one after.
	var low := 0
	var high := _frames.size() - 1
	while high - low > 1:
		var middle: int = (low + high) >> 1
		if float(_frames[middle]["t"]) <= wanted:
			low = middle
		else:
			high = middle
	var a: Dictionary = _frames[low]
	var b: Dictionary = _frames[high]
	var span: float = maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var blend := clampf((wanted - float(a["t"])) / span, 0.0, 1.0)
	var offset := Origin.offset
	var a_bodies: Dictionary = a["bodies"]
	var b_bodies: Dictionary = b["bodies"]
	var still_shown: Dictionary = {}
	var focus_point := Vector3.ZERO
	var have_focus := false
	for id in a_bodies:
		var place: Transform3D = a_bodies[id]
		if b_bodies.has(id):
			place = _blend(place, b_bodies[id], blend)
		place.origin -= offset
		var ghost := _ghost_for(int(id), int(a["n"]))
		if ghost == null:
			continue
		ghost.global_transform = place
		ghost.visible = true
		still_shown[id] = true
		if int(id) == int(a["focus"]):
			focus_point = place.origin
			have_focus = true
	# Hide the ghosts of bodies that are not in this snapshot.
	for id in _shown.keys():
		if not still_shown.has(id):
			var key: String = _shown[id]
			var old: Node3D = _ghosts.get(key)
			if old != null:
				old.visible = false
			_shown.erase(id)
	if _player_ghost != null and a.has("player"):
		var body_place: Transform3D = a["player"]
		if b.has("player"):
			body_place = _blend(body_place, b["player"], blend)
		body_place.origin -= offset
		_player_ghost.global_transform = body_place
		if not have_focus:
			focus_point = body_place.origin + Vector3(0.0, 1.0, 0.0)
	_place_camera(focus_point)


static func _blend(a: Transform3D, b: Transform3D, amount: float) -> Transform3D:
	var turn := Quaternion(a.basis.orthonormalized()).slerp(Quaternion(b.basis.orthonormalized()), amount)
	return Transform3D(Basis(turn), a.origin.lerp(b.origin, amount))


## The ghost of a body as it looked at snapshot `number`, made the first
## time it is needed.
func _ghost_for(id: int, number: int) -> Node3D:
	var versions: Array = _looks.get(id, [])
	if versions.is_empty():
		return null
	var pick := 0
	for index in versions.size():
		if int(versions[index][0]) <= number:
			pick = index
	var key := "%d/%d" % [id, pick]
	if _shown.has(id) and _shown[id] != key:
		var old: Node3D = _ghosts.get(_shown[id])
		if old != null:
			old.visible = false
	_shown[id] = key
	if _ghosts.has(key):
		return _ghosts[key]
	var ghost := Node3D.new()
	for item in versions[pick][1]:
		var part: Array = item
		var shown := MeshInstance3D.new()
		shown.mesh = part[0]
		if part[1] != null:
			shown.set_surface_override_material(0, part[1])
		shown.material_override = part[2]
		shown.transform = part[3]
		ghost.add_child(shown)
	_ghost_root.add_child(ghost)
	_ghosts[key] = ghost
	return ghost


func _place_camera(focus: Vector3) -> void:
	if _camera == null:
		return
	var turn := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	_camera.global_position = focus + turn * Vector3(0.0, 0.0, _distance)
	_camera.look_at(focus, Vector3.UP)


func _input(event: InputEvent) -> void:
	if not active:
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.pressed and not key.echo and key.physical_keycode == KEY_0 \
					and get_viewport().gui_get_focus_owner() == null and not get_tree().paused:
				if can_play():
					start("Replay")
		return
	if event is InputEventKey:
		var pressed := event as InputEventKey
		if pressed.pressed and not pressed.echo and pressed.physical_keycode in [KEY_SPACE, KEY_ESCAPE, KEY_0]:
			stop()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance = maxf(_distance / 1.15, 3.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = minf(_distance * 1.15, 400.0)
		elif button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.005
		_pitch = clampf(_pitch - motion.relative.y * 0.005, -1.45, 1.45)


# --- The replay's own interface ---------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 30
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(margin_name, 24)
	_ui.add_child(root)

	var title := Label.new()
	title.text = "REPLAY" if _reason == "" or _reason == "Replay" else "REPLAY  ·  %s" % _reason
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(title)

	var bottom := VBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.show_percentage = false
	bottom.add_child(_bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(row)
	var restart := Button.new()
	restart.text = "Restart"
	restart.custom_minimum_size = Vector2(110, 40)
	restart.pressed.connect(func() -> void: _time = 0.0)
	row.add_child(restart)
	_speed_button = Button.new()
	_speed_button.text = "Speed 1x"
	_speed_button.custom_minimum_size = Vector2(120, 40)
	_speed_button.pressed.connect(_cycle_speed)
	row.add_child(_speed_button)
	var skip := Button.new()
	skip.text = "Skip (Space)"
	skip.custom_minimum_size = Vector2(140, 40)
	skip.pressed.connect(stop)
	row.add_child(skip)
	var hint := Label.new()
	hint.text = "Drag to turn the camera   Wheel to zoom"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_constant_override("outline_size", 6)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	bottom.add_child(hint)


func _cycle_speed() -> void:
	if _speed > 0.9:
		_speed = 0.25 if _speed > 1.5 else 2.0
	else:
		_speed = 1.0 if _speed > 0.4 else 0.5
	# 1 -> 2 -> 0.25 -> 0.5 -> 1
	if _speed_button != null:
		_speed_button.text = "Speed %sx" % str(_speed)
