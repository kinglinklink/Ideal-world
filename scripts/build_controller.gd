extends Node3D
## The build-mode tools: Place, Delete, Config, Transform, Paint and Scale,
## plus grabbing a selection (G) and carrying it onto another part.

signal tool_changed(new_tool: int)
signal part_type_changed(type: String)
signal brush_changed
signal selection_changed
signal snap_changed(units: int)
signal message(text: String)
signal spawn_changed(is_spawned: bool)
signal assemblies_requested

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const PartSettings = preload("res://scripts/part_settings.gd")
const Gamepad = preload("res://scripts/gamepad.gd")
const PartPorts = preload("res://scripts/part_ports.gd")
const Player = preload("res://scripts/player.gd")
const SaveManager = preload("res://scripts/save_manager.gd")

## NONE means every tool is put away: nothing is aimed, placed or selected.
enum Tool { NONE = -1, PLACE, DELETE, CONFIG, TRANSFORM, PAINT, SCALE }

const TOOL_NAMES := ["Place", "Delete", "Config", "Transform", "Paint", "Scale"]
const HANDLE_COLORS := [Color(0.95, 0.25, 0.2), Color(0.3, 0.9, 0.3), Color(0.3, 0.5, 1.0)]
const HANDLE_BLOCKED := Color(1.0, 0.15, 0.1)
const REACH := 400.0         # metres the tools can reach from the camera
const AIM_EVERY_TICKS := 4   # the aim ray runs at 60 Hz, a quarter of the physics rate
const PASTE_PREVIEW_LIMIT := 200   # most parts drawn in the paste preview
const AXIS_WIDTH := 0.03       # metres; thickness of the axis lines on the placement ghost
const AXIS_OVERHANG := 0.2     # metres the axis lines reach past the part
const AXIS_COLORS := [Color(0.95, 0.2, 0.2), Color(0.3, 0.85, 0.3), Color(0.25, 0.45, 1.0)]   # X, Y, Z
const SEAT_REACH := 2.5        # metres from the character to a seat it can sit in
const SEAT_EVERY_TICKS := 16   # the search for a seat within reach runs at 15 Hz

const PREVIEW_OK := Color(0.35, 0.75, 1.0, 0.45)
const PREVIEW_BLOCKED := Color(1.0, 0.25, 0.2, 0.45)
const HOVER_DELETE := Color(1.0, 0.25, 0.2, 0.5)
const HOVER_OTHER := Color(1.0, 0.95, 0.5, 0.3)
const SELECTED := Color(0.3, 1.0, 0.55, 0.4)
const MASS_MARKER := Color(1.0, 0.85, 0.1, 0.95)
const LIFT_MARKER := Color(0.25, 0.75, 1.0, 0.95)
const LINK_IN := Color(0.3, 1.0, 0.4)     # lines from the parts this one listens to
const LINK_OUT := Color(0.35, 0.65, 1.0)  # lines to the parts that listen to this one

var grid: Node3D = null              # build_grid.gd
var player: CharacterBody3D = null   # player.gd
var spawner: Node3D = null           # spawner.gd
var spawned := false                 # true while the build is spawned and the tools are put away

var current_tool: int = Tool.NONE
var part_type: String = "block"
var place_rotation: Basis = Basis.IDENTITY
var brush_material: String = MaterialLibrary.DEFAULT_ID
var brush_color: Color = MaterialLibrary.default_color(MaterialLibrary.DEFAULT_ID)
var snap_units: int = Units.UNITS_PER_CELL
var selection: Array = []      # part uids. Transform: any number. Config: at most one.
var eyedropper: String = ""    # "", "material" or "color"
var paste_armed := false       # the next click in the Transform tool pastes the clipboard
var link_input: String = ""    # Config: the input waiting for the user to click a source part
var link_source_uid := 0       # Config: the source part clicked, waiting for an output choice
var seat_uid := 0              # the seat the character is sitting in, 0 for none
var near_seat_uid := 0         # the nearest seat within reach, 0 for none
var fleet: Node3D = null       # fleet.gd: vehicles spawned from saves, whose seats can be sat in too
var talk_handler: Callable = Callable()   # races.gd: E talks to someone nearby instead of sitting, if it says so
var _seat_owner: Node = null   # the spawner of the seat sat in; null for a seat on the build grid
var _near_owner: Node = null   # likewise for the seat in reach

var _clipboard: Array = []     # records whose "pos" is relative to an anchor cell centre
var _tick := 0
var _seat_request := false     # E was pressed to sit; acted on in the next physics tick
var _pad_stand := false        # View (Create) was pressed on a controller to stand up
var _clipboard_anchor := Vector3i.ZERO   # where the copy was taken from, for Paste in place
var _clipboard_low := Vector3.ZERO       # the copy's bounding box, in units from its anchor
var _clipboard_high := Vector3.ZERO
var _config_clipboard: Dictionary = {}   # a copied config: {"type", "size", "props"}; kept until Spawn
var _hit_uid := 0              # part under the cursor, 0 for none
var _has_target := false       # the cursor is on some surface
var _target_cell := Vector3i.ZERO
var _target_axis := 1          # axis the clicked surface faces along
var _target_sign := 1

var _preview: MeshInstance3D
var _hover: MeshInstance3D
var _mass_marker: MeshInstance3D
var _lift_marker: MeshInstance3D
var _selection_markers: Array = []
var _paste_markers: Array = []
var _axis_markers: Array = []  # three bars showing the placement ghost's own X, Y and Z
var _link_lines: MeshInstance3D
var _link_mesh: ImmediateMesh
var _handles: Array = []       # Scale tool: six handles, [-X, +X, -Y, +Y, -Z, +Z]
var _handle_label: Label3D
var _drag: Dictionary = {}     # Scale tool: the handle being pulled; see _begin_scale_drag
var _grabbed: Array = []       # G: records lifted to be carried somewhere, to put back if cancelled
var _grab_listeners: Array = []   # [listener uid, input id, grabbed uid, output id] for links into the grabbed parts


func setup(p_grid: Node3D, p_player: CharacterBody3D, p_spawner: Node3D) -> void:
	grid = p_grid
	player = p_player
	spawner = p_spawner
	grid.connect("parts_changed", _on_parts_changed)


func _ready() -> void:
	_preview = _new_marker("Preview")
	_hover = _new_marker("Hover")

	# Three thin bars for the ghost's axes: red X, green Y, blue Z.
	for axis in 3:
		var bar := _new_marker("GhostAxis%d" % axis)
		bar.mesh = BoxMesh.new()
		var bar_material := StandardMaterial3D.new()
		bar_material.albedo_color = AXIS_COLORS[axis]
		bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bar_material.no_depth_test = true   # seen through the part they belong to
		bar_material.render_priority = 2
		bar.material_override = bar_material
		_axis_markers.append(bar)

	# Balls for the centre of mass and the centre of lift, each with a label,
	# and both visible through the build.
	_mass_marker = _new_ball_marker("CentreOfMass", "Center of mass", MASS_MARKER)
	_lift_marker = _new_ball_marker("CentreOfLift", "Center of lift", LIFT_MARKER)

	# Thin lines that show the selected part's signal links.
	_link_lines = _new_marker("SignalLinks")
	_link_mesh = ImmediateMesh.new()
	_link_lines.mesh = _link_mesh
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	_link_lines.material_override = line_material

	# The Scale tool's handles: a cube on each face of the selection.
	for index in 6:
		var handle := _new_marker("ScaleHandle%d" % index)
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		handle.mesh = cube
		var handle_look := StandardMaterial3D.new()
		handle_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		handle_look.albedo_color = HANDLE_COLORS[index >> 1]
		handle_look.no_depth_test = true
		handle_look.render_priority = 3
		handle.material_override = handle_look
		_handles.append(handle)
	_handle_label = Label3D.new()
	_handle_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_handle_label.no_depth_test = true
	_handle_label.render_priority = 4
	_handle_label.font_size = 40
	_handle_label.outline_size = 10
	_handle_label.pixel_size = 0.003
	_handle_label.visible = false
	add_child(_handle_label)


## A ball with a name floating over it, drawn on top of everything.
func _new_ball_marker(marker_name: String, caption: String, color: Color) -> MeshInstance3D:
	var marker := _new_marker(marker_name)
	var ball := SphereMesh.new()
	ball.radius = 0.6 * Units.CELL
	ball.height = 1.2 * Units.CELL
	marker.mesh = ball
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = color
	ball_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball_material.no_depth_test = true   # visible through the build
	ball_material.render_priority = 3
	marker.material_override = ball_material
	var label := Label3D.new()
	label.text = caption
	label.font_size = 48
	label.pixel_size = 0.004
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 4
	label.outline_render_priority = 3
	label.position = Vector3(0.0, 1.4 * Units.CELL, 0.0)
	marker.add_child(label)
	return marker


func _new_marker(marker_name: String) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	add_child(marker)
	return marker


# --- State changes -----------------------------------------------------------

## Picks a tool, or puts it away again if it is already the one in hand.
## This is what the number keys and the tool bar buttons do.
func toggle_tool(tool_index: int) -> void:
	if tool_index == current_tool:
		set_tool(Tool.NONE)
	else:
		set_tool(tool_index)


func set_tool(new_tool: int) -> void:
	if new_tool < Tool.NONE or new_tool >= TOOL_NAMES.size() or new_tool == current_tool:
		return
	if not _grabbed.is_empty():
		_drop_grab_back()
	current_tool = new_tool
	eyedropper = ""
	paste_armed = false
	_drag = {}
	link_input = ""
	link_source_uid = 0
	selection = []
	tool_changed.emit(current_tool)
	selection_changed.emit()
	_refresh_markers()


## Picking a part from the menu also resets the placement rotation.
func set_part_type(type: String) -> void:
	part_type = type
	place_rotation = Basis.IDENTITY
	part_type_changed.emit(part_type)


## Choosing a material also loads that material's own colour into the brush.
func set_brush_material(material: String) -> void:
	brush_material = material
	brush_color = MaterialLibrary.default_color(material)
	brush_changed.emit()


func set_brush_color(color: Color) -> void:
	brush_color = color
	brush_changed.emit()


func set_eyedropper(mode: String) -> void:
	eyedropper = mode
	brush_changed.emit()


func set_snap(units: int) -> void:
	snap_units = maxi(1, units)
	snap_changed.emit(snap_units)


func _say(text: String) -> void:
	message.emit(text)


func _on_parts_changed() -> void:
	var kept: Array = []
	for uid in selection:
		if grid.has_part(uid):
			kept.append(uid)
	if link_source_uid != 0 and not grid.has_part(link_source_uid):
		link_source_uid = 0
	if kept.size() != selection.size():
		selection = kept
		link_input = ""
		link_source_uid = 0
		selection_changed.emit()
	if seat_uid != 0 and not spawned and _seat_owner == null:
		var frame: Array = _seat_frame(seat_uid)
		if frame.is_empty():
			_leave_seat()
		else:
			# The seat may have been moved, turned or resized: stay on it.
			var place: Array = _seat_place(frame)
			player.hold_seat(place[0], place[1])
	_refresh_markers()


# --- Input -------------------------------------------------------------------

## Seated, a key the build's input blocks use belongs to the build: the
## game's shortcuts on the same key (M opens the map, P respawns, J ...) don't
## also go off. Space and Escape keep their jobs.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or seat_uid == 0 or get_viewport().gui_get_focus_owner() != null:
		return
	if key.keycode == KEY_SPACE or key.keycode == KEY_ESCAPE:
		return
	var owner_node: Node = _seat_owner if _seat_owner != null and is_instance_valid(_seat_owner) else spawner
	if owner_node != null and owner_node.has_method("binds_key") and bool(owner_node.binds_key(key.keycode)):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_on_key(key)
		elif key.pressed and current_tool == Tool.TRANSFORM and not spawned:
			_on_move_key(key.physical_keycode)   # held arrows keep nudging
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			get_viewport().gui_release_focus()
			_use_tool()
		elif button.button_index == MOUSE_BUTTON_LEFT and not button.pressed and not _drag.is_empty():
			_end_scale_drag()
	elif event is InputEventJoypadButton:
		_on_pad_button(event as InputEventJoypadButton)
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_update_scale_drag()


## A controller's own buttons for getting about: Y (Triangle) sits down or
## talks, like E; View (Create) stands up from a seat, like Space, and on foot
## spawns or puts away the build, like Enter. Seated, every other button is
## free for the build's Controller input blocks.
func _on_pad_button(button: InputEventJoypadButton) -> void:
	if not button.pressed:
		return
	if button.button_index == JOY_BUTTON_Y and seat_uid == 0:
		if talk_handler.is_valid() and bool(talk_handler.call()):
			return
		if spawned:
			_seat_request = true
	elif button.button_index == JOY_BUTTON_BACK:
		if seat_uid != 0:
			_pad_stand = true
		else:
			toggle_spawn()


func _on_key(key: InputEventKey) -> void:
	var code: int = key.physical_keycode
	if (code == KEY_ENTER or code == KEY_KP_ENTER) and not key.ctrl_pressed:
		toggle_spawn()   # Enter does the same as the Spawn button
		return
	if code == KEY_E and not key.ctrl_pressed and seat_uid == 0 and talk_handler.is_valid() and bool(talk_handler.call()):
		return   # talked to someone
	if spawned:
		# The build tools are put away. Only sitting down still works.
		if code == KEY_E and not key.ctrl_pressed:
			_seat_request = true
		return
	if key.ctrl_pressed:
		# Ctrl shortcuts. Undo and redo work in every tool.
		if code == KEY_Z:
			if key.shift_pressed:
				redo()
			else:
				undo()
		elif code == KEY_Y:
			redo()
		elif current_tool == Tool.TRANSFORM:
			if code == KEY_C:
				copy_selection()
			elif code == KEY_X:
				cut_selection()
			elif code == KEY_V:
				if key.shift_pressed:
					paste_in_place()
				else:
					paste()
			elif code == KEY_A:
				select_all()
		return
	if key.shift_pressed and current_tool == Tool.CONFIG and (code == KEY_C or code == KEY_V):
		if code == KEY_C:
			copy_config()
		else:
			paste_config()
		return
	if code == KEY_1:
		toggle_tool(Tool.PLACE)
	elif code == KEY_2:
		toggle_tool(Tool.DELETE)
	elif code == KEY_3:
		toggle_tool(Tool.CONFIG)
	elif code == KEY_4:
		toggle_tool(Tool.TRANSFORM)
	elif code == KEY_5:
		toggle_tool(Tool.PAINT)
	elif code == KEY_6:
		toggle_tool(Tool.SCALE)
	elif code == KEY_7:
		assemblies_requested.emit()
	elif code == KEY_G:
		grab_selection()
	elif code == KEY_ESCAPE and not _grabbed.is_empty():
		_drop_grab_back()
	elif code == KEY_R:
		_on_rotate_key(Vector3(1.0, 0.0, 0.0))
	elif code == KEY_T:
		_on_rotate_key(Vector3(0.0, 1.0, 0.0))
	elif code == KEY_Y:
		_on_rotate_key(Vector3(0.0, 0.0, 1.0))
	elif code == KEY_E:
		_seat_request = true
	elif current_tool == Tool.TRANSFORM:
		if code == KEY_DELETE or code == KEY_BACKSPACE:
			delete_selection()
		else:
			_on_move_key(code)


## Turns things 90 degrees about world X (0), Y (1) or Z (2), like R, T and Y.
func turn(axis_index: int) -> void:
	var axis := Vector3.ZERO
	axis[clampi(axis_index, 0, 2)] = 1.0
	_on_rotate_key(axis)


## R, T and Y turn things 90 degrees about the world X, Y and Z axes:
## the armed part in the Place tool, the selection in the Transform tool.
func _on_rotate_key(axis: Vector3) -> void:
	if spawned:
		return
	if current_tool == Tool.PLACE:
		place_rotation = _quarter_turn(axis) * place_rotation
	elif current_tool == Tool.TRANSFORM and paste_armed:
		_rotate_clipboard(axis)
	elif current_tool == Tool.TRANSFORM:
		rotate_selection(axis)


## Turns the copy waiting to be put down (a paste, a sub-assembly or a grab)
## a quarter turn about its anchor.
func _rotate_clipboard(axis: Vector3) -> void:
	var quarter: Basis = _quarter_turn(axis)
	_clipboard_low = Vector3(INF, INF, INF)
	_clipboard_high = Vector3(-INF, -INF, -INF)
	for item in _clipboard:
		var record: Dictionary = item
		var pos: Vector3i = record["pos"]
		record["pos"] = Vector3i((quarter * Vector3(pos)).round())
		var turned: Basis = quarter * (record["rot"] as Basis)
		record["rot"] = Basis(turned.x.round(), turned.y.round(), turned.z.round())
		var half: Vector3 = BuildGrid.half_extent_units(record)
		var middle := Vector3(record["pos"] as Vector3i)
		_clipboard_low = _clipboard_low.min(middle - half)
		_clipboard_high = _clipboard_high.max(middle + half)


## A rotation matrix with exact 0 / +1 / -1 entries, so quarter turns never drift.
static func _quarter_turn(axis: Vector3) -> Basis:
	var quarter := Basis(axis, PI * 0.5)
	return Basis(quarter.x.round(), quarter.y.round(), quarter.z.round())


## Arrow keys move along the ground relative to the camera; Page Up / Down move vertically.
func _on_move_key(code: int) -> void:
	var step := Vector3i.ZERO
	if code == KEY_PAGEUP:
		step = Vector3i(0, 1, 0)
	elif code == KEY_PAGEDOWN:
		step = Vector3i(0, -1, 0)
	elif code == KEY_UP:
		step = _ground_axis(-_camera_basis().z)
	elif code == KEY_DOWN:
		step = _ground_axis(_camera_basis().z)
	elif code == KEY_RIGHT:
		step = _ground_axis(_camera_basis().x)
	elif code == KEY_LEFT:
		step = _ground_axis(-_camera_basis().x)
	else:
		return
	move_selection(step * snap_units)


func _camera_basis() -> Basis:
	if player == null:
		return Basis.IDENTITY
	return player.get_camera_basis()


## The world X or Z direction closest to a camera direction.
static func _ground_axis(direction: Vector3) -> Vector3i:
	if absf(direction.x) >= absf(direction.z):
		return Vector3i(1 if direction.x >= 0.0 else -1, 0, 0)
	return Vector3i(0, 0, 1 if direction.z >= 0.0 else -1)


# --- Tool actions ------------------------------------------------------------

func _use_tool() -> void:
	if grid == null or spawned:
		return
	if current_tool == Tool.PLACE:
		_use_place()
	elif current_tool == Tool.DELETE:
		if _hit_uid != 0:
			grid.remove_part(_hit_uid)
			_hit_uid = 0
	elif current_tool == Tool.SCALE:
		if _begin_scale_drag():
			return
		_select_hit()
	elif current_tool == Tool.TRANSFORM:
		if paste_armed:
			paste()
			return
		if _hit_uid == 0:
			selection = []
		elif Input.is_physical_key_pressed(KEY_SHIFT):
			if selection.has(_hit_uid):
				selection.erase(_hit_uid)
			else:
				selection.append(_hit_uid)
		else:
			selection = [_hit_uid]
		selection_changed.emit()
		_refresh_markers()
	elif current_tool == Tool.CONFIG:
		if link_input != "":
			_pick_link_source()
			return
		link_source_uid = 0
		selection = [] if _hit_uid == 0 else [_hit_uid]
		selection_changed.emit()
		_refresh_markers()
	elif current_tool == Tool.PAINT:
		_use_paint()


## Click selects, Shift+click adds or removes (Transform and Scale).
func _select_hit() -> void:
	if _hit_uid == 0:
		selection = []
	elif Input.is_physical_key_pressed(KEY_SHIFT):
		if selection.has(_hit_uid):
			selection.erase(_hit_uid)
		else:
			selection.append(_hit_uid)
	else:
		selection = [_hit_uid]
	selection_changed.emit()
	_refresh_markers()


# --- Scale tool ------------------------------------------------------------------

## The box round the selection, in the grid's own space (metres).
func _selection_bounds() -> AABB:
	var bounds := AABB()
	var first := true
	for uid in selection:
		if not grid.has_part(uid):
			continue
		var part_bounds: AABB = BuildGrid.bounds_of(grid.get_part(uid))
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	return bounds


func _handle_size(bounds: AABB) -> float:
	return clampf(bounds.get_longest_axis_size() * 0.08, 0.06, 0.8)


## Where handle `index` sits (grid space): on the middle of its face, just off it.
func _handle_point(bounds: AABB, index: int) -> Vector3:
	var axis := index >> 1
	var outward := 1.0 if index % 2 == 1 else -1.0
	var point := bounds.get_center()
	point[axis] = (bounds.end[axis] if outward > 0.0 else bounds.position[axis]) + outward * _handle_size(bounds) * 1.2
	return point


func _update_handles() -> void:
	var showing := current_tool == Tool.SCALE and not selection.is_empty() and not spawned
	if not showing:
		for handle in _handles:
			(handle as MeshInstance3D).visible = false
		if _drag.is_empty():
			_handle_label.visible = false
		return
	var bounds: AABB = _drag.get("shown", _selection_bounds())
	var size := _handle_size(bounds)
	for index in 6:
		var handle: MeshInstance3D = _handles[index]
		var dragging := not _drag.is_empty() and int(_drag["index"]) == index
		handle.visible = _drag.is_empty() or dragging
		var scale_by := size * (1.35 if dragging else 1.0)
		handle.global_transform = grid.global_transform * Transform3D(Basis.from_scale(Vector3.ONE * scale_by), _handle_point(bounds, index))
		var look: StandardMaterial3D = handle.material_override
		look.albedo_color = HANDLE_BLOCKED if dragging and str(_drag.get("problem", "")) != "" else HANDLE_COLORS[index >> 1]


## Starts pulling a handle if one is under the cursor. True if it did.
func _begin_scale_drag() -> bool:
	if selection.is_empty() or player == null:
		return false
	var bounds := _selection_bounds()
	var ray: Array = player.get_pick_ray()
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	var size := _handle_size(bounds)
	var best := -1
	var best_along := INF
	for index in 6:
		var centre: Vector3 = grid.global_transform * _handle_point(bounds, index)
		var along := (centre - origin).dot(direction)
		if along <= 0.0:
			continue
		var miss := (origin + direction * along).distance_to(centre)
		if miss < size * 1.1 and along < best_along:
			best = index
			best_along = along
	if best < 0:
		return false
	var records: Dictionary = {}
	for uid in selection:
		records[uid] = grid.get_part(uid)
	_drag = {"index": best, "bounds": bounds, "records": records, "start": _drag_param(best, bounds),
			"delta": 0, "problem": "", "updates": {}, "shown": bounds}
	return true


## How far along its own axis (metres, grid space) the cursor's ray passes
## the line through handle `index`.
func _drag_param(index: int, bounds: AABB) -> float:
	var axis := index >> 1
	var line_origin: Vector3 = grid.global_transform * _handle_point(bounds, index)
	var along := Vector3.ZERO
	along[axis] = 1.0
	var line_direction: Vector3 = (grid.global_transform.basis * along).normalized()
	var ray: Array = player.get_pick_ray()
	var ray_origin: Vector3 = ray[0]
	var ray_direction: Vector3 = ray[1]
	var w := line_origin - ray_origin
	var b := line_direction.dot(ray_direction)
	var d := line_direction.dot(w)
	var e := ray_direction.dot(w)
	var denominator := 1.0 - b * b
	if denominator < 0.0001:
		return 0.0
	return (b * e - d) / denominator


func _update_scale_drag() -> void:
	var index: int = _drag["index"]
	var bounds: AABB = _drag["bounds"]
	var axis := index >> 1
	var outward := 1 if index % 2 == 1 else -1
	var moved: float = (_drag_param(index, bounds) - float(_drag["start"])) * outward
	var step := Units.UNITS_PER_CELL if Input.is_physical_key_pressed(KEY_SHIFT) else 2
	var delta := int(round(moved / Units.UNIT / step)) * step
	var both := Input.is_physical_key_pressed(KEY_ALT)
	var updates := _scaled(delta, axis, outward, both)
	var problem := ""
	for uid in updates:
		problem = grid.check(updates[uid], updates.keys())
		if problem != "":
			break
	_drag["delta"] = delta
	_drag["updates"] = updates
	_drag["problem"] = problem
	var shown := AABB()
	var first := true
	for uid in updates:
		var box: AABB = BuildGrid.bounds_of(updates[uid])
		shown = box if first else shown.merge(box)
		first = false
	_drag["shown"] = shown
	# The selection's highlight takes the new shape as it is pulled.
	for i in selection.size():
		if i < _selection_markers.size() and updates.has(selection[i]):
			_fit_marker(_selection_markers[i], updates[selection[i]], PREVIEW_BLOCKED if problem != "" else SELECTED, 1.02)
	var total_mass := 0.0
	for uid in updates:
		total_mass += BuildGrid.mass_of(updates[uid])
	var length := shown.size[axis]
	_handle_label.text = "%s %.3f m (%s blocks)\n%s%s" % [["X", "Y", "Z"][axis], length,
			str(snappedf(length / Units.CELL, 0.01)), _kilograms(total_mass),
			("\n" + problem) if problem != "" else ""]
	_handle_label.modulate = Color(1.0, 0.5, 0.45) if problem != "" else Color(1, 1, 1)
	_handle_label.global_position = grid.global_transform * (_handle_point(shown, index) + Vector3.UP * _handle_size(shown) * 2.0)
	_handle_label.visible = true
	_update_handles()


static func _kilograms(mass: float) -> String:
	return "%.1f t" % (mass / 1000.0) if mass >= 1000.0 else "%.2f kg" % mass


## The selection stretched by `delta` units along grid axis `axis`, pulled
## from its `outward` face (the opposite face stays put), or from both faces
## about its middle with `both`. Parts keep their places in proportion.
func _scaled(delta: int, axis: int, outward: int, both: bool) -> Dictionary:
	var bounds: AABB = _drag["bounds"]
	var records: Dictionary = _drag["records"]
	var length_units := bounds.size[axis] / Units.UNIT
	var grow := float(delta) * (2.0 if both else 1.0)
	var new_length := maxf(length_units + grow, 1.0)
	var factor := new_length / maxf(length_units, 0.001)
	var fixed: float
	if both:
		fixed = bounds.get_center()[axis] / Units.UNIT
	else:
		fixed = (bounds.position[axis] if outward > 0 else bounds.end[axis]) / Units.UNIT
	var updates: Dictionary = {}
	for key in records:
		var record: Dictionary = (records[key] as Dictionary).duplicate(true)
		var rot: Basis = record["rot"]
		var own := 0
		for k in 3:
			if absf(rot[k][axis]) > 0.5:
				own = k
		var size: Vector3i = record["size"]
		var new_size := clampi(int(round(float(size[own]) * factor)), 1, BuildGrid.MAX_SIZE_UNITS)
		if records.size() == 1:
			new_size = clampi(size[own] + int(grow), 1, BuildGrid.MAX_SIZE_UNITS)
		size[own] = new_size
		record["size"] = size
		var pos: Vector3i = record["pos"]
		var half_before := BuildGrid.half_extent_units(records[key])
		var half_after := BuildGrid.half_extent_units(record)
		if records.size() == 1 and not both:
			# Keep the far face exactly where it was.
			var face := float(pos[axis]) - float(outward) * half_before[axis]
			pos[axis] = int(round(face + float(outward) * half_after[axis]))
		else:
			pos[axis] = int(round(fixed + (float(pos[axis]) - fixed) * factor))
		record["pos"] = pos
		updates[key] = record
	return updates


func _end_scale_drag() -> void:
	var updates: Dictionary = _drag.get("updates", {})
	var problem: String = _drag.get("problem", "")
	_drag = {}
	_handle_label.visible = false
	if not updates.is_empty() and problem == "":
		_apply(updates)
	elif problem != "":
		_say(problem)
	_refresh_markers()


# --- Grab --------------------------------------------------------------------------

## G in the Transform tool: picks the selection up and carries it with the
## cursor; a click puts it down on whatever it touches, joined there, with
## the Transform tool still holding it to nudge into place. Esc or G again
## puts it back where it was.
func grab_selection() -> void:
	if not _grabbed.is_empty():
		_drop_grab_back()
		return
	if current_tool != Tool.TRANSFORM and current_tool != Tool.SCALE:
		_say("Select parts with the Transform tool (4), then press G to grab them.")
		return
	if selection.is_empty():
		_say("Select what to grab first.")
		return
	var chosen: Array = selection.duplicate()
	var lifted: Array = []
	for uid in chosen:
		lifted.append(grid.get_part(uid))
	if current_tool != Tool.TRANSFORM:
		set_tool(Tool.TRANSFORM)
	selection = chosen
	_grab_listeners = []
	for other in grid.all_uids():
		if chosen.has(other):
			continue
		var other_links: Dictionary = (grid.get_part(other) as Dictionary).get("links", {})
		for input_id in other_links:
			var link: Dictionary = other_links[input_id]
			if chosen.has(int(link.get("uid", 0))):
				_grab_listeners.append([other, str(input_id), int(link["uid"]), str(link.get("output", ""))])
	copy_selection()
	_grabbed = lifted
	delete_selection()
	paste_armed = true
	selection_changed.emit()
	_say("Carrying %d part(s): click where they go. Esc or G puts them back." % lifted.size())


func _drop_grab_back() -> void:
	var lifted: Array = _grabbed
	_grabbed = []
	paste_armed = false
	if lifted.is_empty():
		return
	_grab_listeners = []
	grid.undo()   # the lift was one step: undoing it puts every part back as it was, links and all
	selection_changed.emit()
	_refresh_markers()
	_say("Put back.")


func _use_place() -> void:
	if not _has_target:
		return
	var record := _placement_record()
	var problem: String = grid.check(record)
	if problem == "":
		grid.add_part(record)
	else:
		_say(problem)


func _use_paint() -> void:
	if _hit_uid == 0:
		return
	var hit_record: Dictionary = grid.get_part(_hit_uid)
	if eyedropper == "material":
		brush_material = hit_record["material"]
		eyedropper = ""
		brush_changed.emit()
	elif eyedropper == "color":
		brush_color = hit_record["color"]
		eyedropper = ""
		brush_changed.emit()
	else:
		grid.paint(_hit_uid, brush_material, brush_color)


## The part the Place tool would add right now: the armed part, in the brush's
## material and colour, pushed up against the surface under the cursor.
func _placement_record() -> Dictionary:
	var size: Vector3i = BuildGrid.default_size_units(part_type)
	var center: Vector3i = grid.cell_center_units(_target_cell)
	var color: Color = PartLibrary.placement_color(part_type, brush_color)
	var record: Dictionary = BuildGrid.make_record(part_type, center, place_rotation, size, brush_material, color)
	var half: Vector3 = BuildGrid.half_extent_units(record)
	for axis in 3:
		if axis == _target_axis:
			if PartLibrary.sits_mid_cell(part_type):
				continue   # an aero panel stays on the cell's centre line
			# Push the part up against the surface under the cursor.
			var gap: int = Units.HALF_CELL_UNITS - int(round(half[axis]))
			center[axis] -= _target_sign * gap
			continue
		# A part a whole number of cells wide lines its edges up with the grid.
		# Odd widths already do; even widths need a half-cell nudge.
		var extent: int = int(round(half[axis] * 2.0))
		if extent % Units.UNITS_PER_CELL != 0:
			continue
		var low: int = center[axis] - int(round(half[axis]))
		var offset: int = posmod(low, Units.UNITS_PER_CELL)
		if offset != 0:
			center[axis] += Units.UNITS_PER_CELL - offset
	record["pos"] = center
	return record


func move_selection(step_units: Vector3i) -> void:
	if selection.is_empty() or step_units == Vector3i.ZERO:
		return
	var updates: Dictionary = {}
	for uid in selection:
		var record: Dictionary = grid.get_part(uid)
		var pos: Vector3i = record["pos"]
		record["pos"] = pos + step_units
		updates[uid] = record
	_apply(updates)


func rotate_selection(axis: Vector3) -> void:
	if selection.is_empty():
		return
	var quarter: Basis = _quarter_turn(axis)
	var pivot: Vector3i = _selection_pivot()
	var updates: Dictionary = {}
	for uid in selection:
		var record: Dictionary = grid.get_part(uid)
		var pos: Vector3i = record["pos"]
		var rot: Basis = record["rot"]
		var arm: Vector3 = quarter * Vector3(pos - pivot)
		record["pos"] = pivot + Vector3i(arm.round())
		var turned: Basis = quarter * rot
		record["rot"] = Basis(turned.x.round(), turned.y.round(), turned.z.round())
		updates[uid] = record
	_apply(updates)


## One part turns about its own centre. A group turns about the cell centre
## nearest the middle of the group, which keeps on-grid parts on the grid.
func _selection_pivot() -> Vector3i:
	if selection.size() == 1:
		var only: Dictionary = grid.get_part(selection[0])
		var only_pos: Vector3i = only["pos"]
		return only_pos
	var bounds := AABB()
	var first := true
	for uid in selection:
		var part: Dictionary = grid.get_part(uid)
		var part_bounds: AABB = BuildGrid.bounds_of(part)
		if first:
			bounds = part_bounds
			first = false
		else:
			bounds = bounds.merge(part_bounds)
	var middle_cell := Vector3i((bounds.get_center() / Units.CELL).floor())
	var pivot: Vector3i = grid.cell_center_units(middle_cell)
	return pivot


func _apply(updates: Dictionary) -> bool:
	var problem: String = grid.update_parts(updates)
	if problem != "":
		_say(problem)
		return false
	return true


func delete_selection() -> void:
	if selection.is_empty():
		return
	var doomed: Array = selection.duplicate()
	selection = []
	grid.remove_parts(doomed)
	selection_changed.emit()
	_refresh_markers()


func select_all() -> void:
	selection = grid.all_uids()
	selection_changed.emit()
	_refresh_markers()


func copy_selection() -> void:
	if selection.is_empty():
		_say("Select something to copy first.")
		return
	_clipboard = []
	var first: Dictionary = grid.get_part(selection[0])
	var first_pos: Vector3i = first["pos"]
	@warning_ignore("integer_division")
	var anchor: Vector3i = grid.cell_center_units(first_pos / Units.UNITS_PER_CELL)
	_clipboard_anchor = anchor
	_clipboard_low = Vector3(INF, INF, INF)
	_clipboard_high = Vector3(-INF, -INF, -INF)
	for uid in selection:
		var record: Dictionary = grid.get_part(uid)
		var pos: Vector3i = record["pos"]
		record["pos"] = pos - anchor
		record["copied_from"] = uid   # lets a paste re-point links between the copies
		_clipboard.append(record)
		# The box that holds the whole copy, so a paste can rest it on a surface.
		var half: Vector3 = BuildGrid.half_extent_units(record)
		var middle := Vector3(record["pos"] as Vector3i)
		_clipboard_low = _clipboard_low.min(middle - half)
		_clipboard_high = _clipboard_high.max(middle + half)
	_say("Copied %d part(s). Ctrl+V pastes where you point; Ctrl+Shift+V pastes in place." % _clipboard.size())


func cut_selection() -> void:
	if selection.is_empty():
		return
	copy_selection()
	delete_selection()


## Where the copy goes for the surface under the cursor: the position, in
## units, that its anchor takes. Across the surface the copy's first part is
## centred on the cell under the cursor. Along the surface's normal the whole
## copy rests on the surface, however large it is, instead of sinking into it.
func _paste_base() -> Vector3i:
	var base: Vector3i = grid.cell_center_units(_target_cell)
	var axis: int = _target_axis
	var surface: float = float(base[axis] - _target_sign * Units.HALF_CELL_UNITS)
	if _target_sign > 0:
		base[axis] = int(ceil(surface - _clipboard_low[axis] - 0.001))
	else:
		base[axis] = int(floor(surface - _clipboard_high[axis] + 0.001))
	return base


## Pastes the copy onto the surface under the cursor.
func paste() -> void:
	if _clipboard.is_empty():
		_say("Nothing copied yet.")
		return
	if not _has_target:
		_say("Point at a surface to paste onto.")
		return
	_paste_at(_paste_base())


## Pastes the copy exactly where it was copied from, and selects it, so it
## can be stepped into place with the arrow keys, Page Up and Page Down, or
## the Move buttons, one snap step at a time.
func paste_in_place() -> void:
	if _clipboard.is_empty():
		_say("Nothing copied yet.")
		return
	if _paste_at(_clipboard_anchor):
		_say("Pasted in place. Step it with the arrow keys, Page Up / Page Down or the Move buttons.")


## Adds the copied parts with their anchor at `base`. True if it worked.
func _paste_at(base: Vector3i) -> bool:
	var records: Array = []
	for stored in _clipboard:
		var record: Dictionary = (stored as Dictionary).duplicate(true)
		var offset: Vector3i = record["pos"]
		record["pos"] = base + offset
		var problem: String = grid.check(record)
		if problem != "":
			_say("Cannot paste here. " + problem)
			return false
		records.append(record)
	var pasted: Array = []
	var new_uid_of: Dictionary = {}   # original uid -> the uid of its pasted copy
	grid.begin_batch()   # the whole paste is one step for Undo
	for record in records:
		var original: int = record.get("copied_from", 0)
		record.erase("copied_from")
		var uid: int = grid.add_part(record)
		if uid != 0:
			pasted.append(uid)
			new_uid_of[original] = uid
	# Links between copied parts follow the copies. Links to parts that were
	# not copied keep pointing at the originals, if those still exist.
	for uid in pasted:
		var copy: Dictionary = grid.get_part(uid)
		var links: Dictionary = copy.get("links", {})
		if links.is_empty():
			continue
		for input_id in links.keys():
			var link: Dictionary = links[input_id]
			var source: int = int(link.get("uid", 0))
			if new_uid_of.has(source):
				link["uid"] = new_uid_of[source]
			elif not grid.has_part(source):
				links.erase(input_id)
		grid.set_links(uid, links)
	# Parts left behind that listened to grabbed parts listen to them again
	# where they have been put down.
	for item in _grab_listeners:
		var entry: Array = item
		var listener: int = entry[0]
		if not grid.has_part(listener) or not new_uid_of.has(int(entry[2])):
			continue
		var listener_links: Dictionary = (grid.get_part(listener) as Dictionary).get("links", {})
		listener_links[entry[1]] = {"uid": new_uid_of[int(entry[2])], "output": entry[3]}
		grid.set_links(listener, listener_links)
	_grab_listeners = []
	grid.end_batch()
	paste_armed = false
	_grabbed = []
	selection = pasted
	selection_changed.emit()
	_refresh_markers()
	return true


## Saves the selected parts as a module. Returns "" or the problem.
func save_selection_as_module(module_name: String) -> String:
	if selection.is_empty():
		return "Select the parts for the module first, with the Transform tool."
	copy_selection()
	return SaveManager.save_module(_clipboard, module_name)


## Loads a module in place of the copy, and arms the Transform tool to place
## it with the next click. Returns "" or the problem.
func place_module(module_name: String) -> String:
	var records: Array = SaveManager.load_module(module_name)
	if records.is_empty():
		return "Could not read the module \"%s\"." % module_name
	_clipboard = records
	_clipboard_anchor = grid.cell_center_units(Vector3i(10, 1, 10))
	_clipboard_low = Vector3(INF, INF, INF)
	_clipboard_high = Vector3(-INF, -INF, -INF)
	for item in records:
		var record: Dictionary = item
		var half: Vector3 = BuildGrid.half_extent_units(record)
		var middle := Vector3(record["pos"] as Vector3i)
		_clipboard_low = _clipboard_low.min(middle - half)
		_clipboard_high = _clipboard_high.max(middle + half)
	set_tool(Tool.TRANSFORM)
	paste_armed = true
	selection_changed.emit()
	_say("Module \"%s\" (%d parts): click where it should go. R / T / Y do not turn it; turn it after with the Transform tool." % [module_name, records.size()])
	return ""


## Used by the Paste button: the next click in the world pastes there.
func arm_paste() -> void:
	if _clipboard.is_empty():
		_say("Nothing copied yet.")
		return
	paste_armed = true
	selection_changed.emit()
	_say("Click where the copy should go.")


func undo() -> void:
	if spawned:
		return
	if grid != null and not grid.undo():
		_say("Nothing to undo.")


func redo() -> void:
	if spawned:
		return
	if grid != null and not grid.redo():
		_say("Nothing to redo.")


## Config tool: the part being configured, or an empty dictionary.
func config_record() -> Dictionary:
	if current_tool != Tool.CONFIG or selection.is_empty():
		return {}
	var record: Dictionary = grid.get_part(selection[0])
	return record


## Config tool: sets one dimension of the selected part, in cells.
## Returns false, with nothing changed, if the new size does not fit.
func set_config_size(axis: int, cells: float) -> bool:
	var record: Dictionary = config_record()
	if record.is_empty():
		return false
	var old_pos: Vector3i = record["pos"]
	var old_low: Vector3 = Vector3(old_pos) - BuildGrid.half_extent_units(record)
	var size: Vector3i = record["size"]
	size[axis] = clampi(int(round(cells * Units.UNITS_PER_CELL)), 1, BuildGrid.MAX_SIZE_UNITS)
	record["size"] = size
	# Keep the part's low corner where it was, so a part resting on the pad or
	# on another part grows away from it instead of sinking into it.
	var new_half: Vector3 = BuildGrid.half_extent_units(record)
	record["pos"] = Vector3i((old_low + new_half - Vector3(0.001, 0.001, 0.001)).ceil())
	var updates: Dictionary = {}
	updates[selection[0]] = record
	return _apply(updates)


## Config tool, Shift+C: remembers the selected part's size and settings.
## The copy is kept until another is taken or the build is spawned.
func copy_config() -> void:
	var record: Dictionary = config_record()
	if record.is_empty():
		_say("Click a part with the Config tool first, then Shift+C copies its config.")
		return
	var props: Dictionary = record.get("props", {})
	_config_clipboard = {"type": record["type"], "size": record["size"], "props": props.duplicate(true)}
	_say("Config copied from %s. Shift+V pastes it onto the part you have selected." % PartLibrary.part_name(record["type"]))


## Config tool, Shift+V: gives the selected part the copied size and settings.
## A part of another kind takes the size and whichever settings it shares.
func paste_config() -> bool:
	if _config_clipboard.is_empty():
		_say("No config copied yet. Shift+C copies the selected part's config.")
		return false
	var record: Dictionary = config_record()
	if record.is_empty():
		_say("Click the part to paste the config onto first.")
		return false
	var type: String = record["type"]
	# Size, keeping the part's low corner where it is, as resizing by hand does.
	var old_pos: Vector3i = record["pos"]
	var old_low: Vector3 = Vector3(old_pos) - BuildGrid.half_extent_units(record)
	record["size"] = _config_clipboard["size"]
	var new_half: Vector3 = BuildGrid.half_extent_units(record)
	record["pos"] = Vector3i((old_low + new_half - Vector3(0.001, 0.001, 0.001)).ceil())
	# Settings: every copied setting that this kind of part also has.
	var props: Dictionary = record.get("props", {})
	var copied: Dictionary = _config_clipboard["props"]
	for setting in PartSettings.for_type(type):
		var id: String = setting["id"]
		if copied.has(id):
			props[id] = copied[id]
	record["props"] = PartSettings.sanitize(type, props)
	var updates: Dictionary = {}
	updates[selection[0]] = record
	if not _apply(updates):
		return false
	_say("Config pasted.")
	return true


func has_config_copy() -> bool:
	return not _config_clipboard.is_empty()


# --- Signal links (Config tool) -----------------------------------------------

## Starts linking one of the selected part's inputs: the next click in the
## world picks the part the signal comes from.
func begin_link(input_id: String) -> void:
	if config_record().is_empty():
		return
	link_input = input_id
	link_source_uid = 0
	selection_changed.emit()
	_say("Click the part this signal should come from.")


func cancel_link() -> void:
	link_input = ""
	link_source_uid = 0
	selection_changed.emit()


## The input currently being linked, as a port, or an empty list.
func _linking_port() -> Array:
	var record: Dictionary = config_record()
	if record.is_empty() or link_input == "":
		return []
	return PartPorts.find_port(PartPorts.inputs_of(record["type"]), link_input)


## The outputs of the clicked source part that fit the input being linked.
func link_choices() -> Array:
	var input_port: Array = _linking_port()
	if input_port.is_empty() or link_source_uid == 0 or not grid.has_part(link_source_uid):
		return []
	var source: Dictionary = grid.get_part(link_source_uid)
	return PartPorts.outputs_for(input_port, source["type"])


## A click in the world while an input is waiting for its source.
func _pick_link_source() -> void:
	var input_port: Array = _linking_port()
	if input_port.is_empty() or _hit_uid == 0:
		cancel_link()
		return
	var source: Dictionary = grid.get_part(_hit_uid)
	var source_type: String = source["type"]
	var choices: Array = PartPorts.outputs_for(input_port, source_type)
	if choices.is_empty():
		_say("%s has no output that fits this input." % PartLibrary.part_name(source_type))
		return
	link_source_uid = _hit_uid
	if choices.size() == 1:
		var only_port: Array = choices[0]
		choose_link_output(only_port[0])
	else:
		selection_changed.emit()
		_say("Pick which output to use in the Config panel.")


## Finishes a link: the waiting input now reads the given output of the source part.
func choose_link_output(output_id: String) -> void:
	var record: Dictionary = config_record()
	if record.is_empty() or link_input == "" or link_source_uid == 0:
		cancel_link()
		return
	var links: Dictionary = record.get("links", {})
	links[link_input] = {"uid": link_source_uid, "output": output_id}
	grid.set_links(selection[0], links)
	link_input = ""
	link_source_uid = 0
	selection_changed.emit()
	_refresh_markers()


func clear_link(input_id: String) -> void:
	var record: Dictionary = config_record()
	if record.is_empty():
		return
	var links: Dictionary = record.get("links", {})
	if links.has(input_id):
		links.erase(input_id)
		grid.set_links(selection[0], links)
	_refresh_markers()


## Config tool: changes one of the selected part's settings.
func set_config_setting(setting_id: String, value: Variant) -> bool:
	var record: Dictionary = config_record()
	if record.is_empty():
		return false
	var type: String = record["type"]
	var props: Dictionary = record.get("props", {})
	if props.has(setting_id) and typeof(props[setting_id]) == typeof(value) and props[setting_id] == value:
		return true   # nothing to change, so no Undo step either
	props[setting_id] = value
	record["props"] = PartSettings.sanitize(type, props)
	var updates: Dictionary = {}
	updates[selection[0]] = record
	return _apply(updates)


# --- Spawn -------------------------------------------------------------------

## Switches between building and the spawned world. Spawning welds the build
## into moving bodies and puts the tools away; going back restores the build
## exactly as it was.
func toggle_spawn() -> void:
	if grid == null or spawner == null:
		return
	if not spawned and grid.part_count() == 0:
		_say("There is nothing to spawn. Place some parts first.")
		return
	if seat_uid != 0:
		_leave_seat()
	near_seat_uid = 0
	if spawned:
		spawner.despawn()
		grid.set_active(true)
		spawned = false
		_say("Back to building.")
	else:
		eyedropper = ""
		paste_armed = false
		link_input = ""
		link_source_uid = 0
		selection = []
		_config_clipboard = {}   # a copied config lasts until Spawn
		var report: Dictionary = spawner.spawn(grid)
		grid.set_active(false)
		spawned = true
		var bodies: int = report["bodies"]
		var mass: float = report["mass"]
		var note: String = "Spawned %d part(s) as %d welded %s, %.1f kg in all." % [
			int(report["parts"]), bodies, "body" if bodies == 1 else "bodies", mass,
		]
		var hinges: int = report["hinges"]
		var locked: int = report["locked"]
		if hinges > 0:
			note += "\n%d joint(s) free to turn." % hinges
		if locked > 0:
			note += "\n%d joint(s) locked: both sides are welded to the same body." % locked
		var fighting: int = int(report.get("gear_conflicts", 0))
		if fighting > 0:
			note += "\nWarning: %d gear mesh(es) fight the rest of their train (the tooth ratios round a loop do not agree), so it is jammed." % fighting
		var thrusters: int = report["thrusters"]
		var panels: int = report["panels"]
		if thrusters > 0 or panels > 0:
			note += "\n%d thruster(s), %d aero panel(s)." % [thrusters, panels]
		_say(note)
	_preview.visible = false
	_hover.visible = false
	_hide_axes()
	_update_paste_preview()
	_refresh_markers()
	selection_changed.emit()
	spawn_changed.emit(spawned)


# --- Seats -------------------------------------------------------------------

## How fast the vehicle sat in is turning, in degrees per second (0 on foot).
func seat_spin() -> float:
	if seat_uid == 0 or _seat_owner == null or not is_instance_valid(_seat_owner):
		return 0.0
	return _seat_owner.seat_spin(seat_uid)


## The line the interface shows about sitting, or "" for nothing to say.
func seat_prompt() -> String:
	if seat_uid != 0:
		return "Space (View on a controller) to stand up" if Gamepad.connected() else "Space to stand up"
	if near_seat_uid != 0:
		return "E (Y on a controller) to sit" if Gamepad.connected() else "E to sit"
	return ""


## Sits down and stands up when asked, and keeps track of the seat in reach.
func _update_seat() -> void:
	if grid == null or player == null:
		return
	# Key binds work only in the vehicle sat in.
	if spawner != null:
		spawner.occupied_seat = seat_uid if spawned and _seat_owner == spawner else 0
	if fleet != null:
		for item in fleet.spawners():
			var vehicle: Node = item
			vehicle.occupied_seat = seat_uid if vehicle == _seat_owner else 0
	if seat_uid != 0:
		_seat_request = false   # E does nothing while seated; only Space stands up
		var typing: bool = get_viewport().gui_get_focus_owner() != null
		var stand := _pad_stand
		_pad_stand = false
		if (Input.is_physical_key_pressed(KEY_SPACE) or stand) and not typing:
			_leave_seat()
		elif _seat_owner != null:
			# A spawned seat moves, so the sitter is carried along every tick.
			var frame: Array = _seat_frame(seat_uid)
			if frame.is_empty() or not is_instance_valid(_seat_owner):
				_leave_seat()
			else:
				var riding: Array = _seat_place(frame)
				player.hold_seat(riding[0], riding[1])
				player.ride_velocity = _seat_owner.seat_velocity(seat_uid)
		return
	if _seat_request or _tick % SEAT_EVERY_TICKS == 0:
		near_seat_uid = _nearest_seat()
	if _seat_request:
		_seat_request = false
		_seat_owner = _near_owner
		var frame: Array = _seat_frame(near_seat_uid)
		if frame.is_empty():
			_seat_owner = null
			near_seat_uid = 0
			_say("There is no seat within reach.")
			return
		var place: Array = _seat_place(frame)
		seat_uid = near_seat_uid
		near_seat_uid = 0
		player.sit(place[0], place[1])


## The nearest seat the character can reach: a spawned one while spawned,
## otherwise one on the build grid. Returns its uid, or 0 for none.
func _nearest_seat() -> int:
	var chest: Vector3 = player.global_position + Vector3(0.0, Player.BODY_HEIGHT * 0.5, 0.0)
	# Spawned seats: the build's, then the fleet's, the nearest of them.
	var owners: Array = []
	if spawned:
		owners.append(spawner)
	if fleet != null:
		owners.append_array(fleet.spawners())
	var best := 0
	var best_distance := INF
	_near_owner = null
	for item in owners:
		var owner_spawner: Node = item
		var uid: int = owner_spawner.nearest_seat(chest, SEAT_REACH)
		if uid == 0:
			continue
		var frame: Array = owner_spawner.seat_frame(uid)
		if frame.is_empty():
			continue
		var distance: float = (frame[0] as Transform3D).origin.distance_to(chest)
		if distance < best_distance:
			best_distance = distance
			best = uid
			_near_owner = owner_spawner
	if best != 0 or spawned:
		return best
	var local_chest: Vector3 = grid.global_transform.affine_inverse() * chest
	return grid.nearest_of_type("seat", local_chest, SEAT_REACH)


## A seat's place in the world: [its transform, its size in metres]. Empty if
## the seat does not exist. Works for a seat on the grid and a spawned one.
func _seat_frame(uid: int) -> Array:
	if uid == 0:
		return []
	if _seat_owner != null:
		return _seat_owner.seat_frame(uid) if is_instance_valid(_seat_owner) else []
	if spawned:
		return spawner.seat_frame(uid)
	if not grid.has_part(uid):
		return []
	var record: Dictionary = grid.get_part(uid)
	var rot: Basis = record["rot"]
	var size_units: Vector3i = record["size"]
	var centre: Vector3 = Vector3(record["pos"] as Vector3i) * Units.UNIT
	return [grid.global_transform * Transform3D(rot, centre), Units.to_metres(size_units)]


## Where a seat puts its sitter: [the world point on top of the cushion,
## the heading the seat faces]. A seat faces along its own -Z.
func _seat_place(frame: Array) -> Array:
	var seat: Transform3D = frame[0]
	var size_m: Vector3 = frame[1]
	# These match the seat model: the cushion top is 0.15 of the height below
	# the middle, and the cushion sits a little forward of the backrest.
	var cushion: Vector3 = seat * Vector3(0.0, -0.15 * size_m.y, 0.05 * size_m.z)
	var forward: Vector3 = -seat.basis.z
	var heading: float = player.get_heading()   # kept if the seat faces straight up or down
	if Vector2(forward.x, forward.z).length() > 0.5:
		heading = atan2(-forward.x, -forward.z)
	return [cushion, heading]


## Sits the character in the first seat of a spawned vehicle (a fleet
## vehicle spawned for a race). Returns true if there was a seat.
func sit_in(vehicle: Node) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	if seat_uid != 0:
		_leave_seat()
	for key in vehicle.all_records():
		var uid: int = key
		if str((vehicle.all_records()[uid] as Dictionary)["type"]) != "seat":
			continue
		var frame: Array = vehicle.seat_frame(uid)
		if frame.is_empty():
			continue
		_seat_owner = vehicle
		var place: Array = _seat_place(frame)
		seat_uid = uid
		near_seat_uid = 0
		player.sit(place[0], place[1])
		return true
	return false


func _leave_seat() -> void:
	# If the seat is gone, simply stand where the character was sitting.
	var exit_point: Vector3 = player.global_position + Vector3(0.0, Player.HIP_HEIGHT, 0.0)
	var frame: Array = _seat_frame(seat_uid)
	if not frame.is_empty():
		exit_point = _seat_exit(frame)
	seat_uid = 0
	_seat_owner = null
	player.stand_up(exit_point)


## Sends the character back to `at` (world position), facing `heading`,
## standing up first if it is seated.
func respawn(at: Vector3, heading: float) -> void:
	if seat_uid != 0:
		_leave_seat()
	player.teleport(at, heading)


## Where the character's feet go on standing up: on top of the seat if there
## is head room, otherwise beside it, trying the front first.
func _seat_exit(frame: Array) -> Vector3:
	var seat: Transform3D = frame[0]
	var size_m: Vector3 = frame[1]
	var centre: Vector3 = seat.origin
	# Half the size of the box that encloses the seat, however it is turned.
	var half: Vector3 = (seat.basis.x * size_m.x).abs() + (seat.basis.y * size_m.y).abs() \
			+ (seat.basis.z * size_m.z).abs()
	half *= 0.5
	var forward: Vector3 = -seat.basis.z
	forward.y = 0.0
	if forward.length() < 0.5:
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	var top: Vector3 = centre + Vector3(0.0, half.y, 0.0)
	var spots: Array = [top]
	for direction in [forward, right, -right, -forward]:
		var way: Vector3 = direction
		var clearance: float = absf(way.x) * half.x + absf(way.z) * half.z + Player.BODY_RADIUS + 0.05
		spots.append(centre + way * clearance - Vector3(0.0, half.y, 0.0))
	for spot in spots:
		var feet: Vector3 = spot
		if _has_standing_room(feet):
			return feet
	return top


## True if the character's body fits with its feet at the given world point.
func _has_standing_room(feet: Vector3) -> bool:
	var body := CylinderShape3D.new()
	body.radius = Player.BODY_RADIUS * 0.95
	body.height = Player.BODY_HEIGHT - 0.06
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, Player.BODY_HEIGHT * 0.5 + 0.03, 0.0))
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- Aiming and markers ------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_tick += 1
	_update_seat()
	if spawned:
		return
	if _tick % AIM_EVERY_TICKS != 0:
		return
	_update_target()
	_update_cursor_markers()
	_update_paste_preview()
	_update_handles()


## Casts the aim ray and works out which part and which cell it points at.
func _update_target() -> void:
	_hit_uid = 0
	_has_target = false
	if grid == null or player == null:
		return

	var ray: Array = player.get_pick_ray()
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * REACH)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var collider: Object = hit["collider"]
	if collider is Node and (collider as Node).has_meta("uid"):
		var uid: int = (collider as Node).get_meta("uid")
		if grid.has_part(uid):
			_hit_uid = uid

	var hit_point: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var to_grid: Transform3D = grid.global_transform.affine_inverse()
	var local_point: Vector3 = to_grid * hit_point
	var local_normal: Vector3 = (to_grid.basis * hit_normal).normalized()
	# Step half a cell off the surface to land in the cell in front of it.
	_target_cell = grid.point_to_cell(local_point + local_normal * (Units.CELL * 0.5))
	_target_axis = local_normal.abs().max_axis_index()
	_target_sign = 1 if local_normal[_target_axis] >= 0.0 else -1
	_has_target = true


## The placement preview and the highlight on the part under the cursor.
func _update_cursor_markers() -> void:
	_preview.visible = false
	_hover.visible = false
	_hide_axes()
	if current_tool == Tool.PLACE:
		if _has_target:
			var record: Dictionary = _placement_record()
			var problem: String = grid.check(record)
			var preview_color: Color = PREVIEW_OK if problem == "" else PREVIEW_BLOCKED
			_fit_marker(_preview, record, preview_color, 1.0)
			_fit_axes(record)
		return
	if current_tool == Tool.CONFIG and not selection.is_empty() and grid.has_part(selection[0]):
		# Show the selected part's own X, Y and Z, to match the three size boxes.
		_fit_axes(grid.get_part(selection[0]))
	if _hit_uid != 0 and current_tool != Tool.NONE:
		var hover_color: Color = HOVER_DELETE if current_tool == Tool.DELETE else HOVER_OTHER
		var hovered: Dictionary = grid.get_part(_hit_uid)
		_fit_marker(_hover, hovered, hover_color, 1.03)


func _hide_axes() -> void:
	for bar in _axis_markers:
		(bar as MeshInstance3D).visible = false


## Draws the ghost part's own X, Y and Z axes from its centre, in red, green
## and blue. They turn with the part, so they show which way it is facing.
func _fit_axes(record: Dictionary) -> void:
	var rot: Basis = record["rot"]
	var size_units: Vector3i = record["size"]
	var half: Vector3 = Units.to_metres(size_units) * 0.5
	var centre: Vector3 = Vector3(record["pos"] as Vector3i) * Units.UNIT
	for axis in 3:
		var length: float = half[axis] + AXIS_OVERHANG
		var bar_size := Vector3(AXIS_WIDTH, AXIS_WIDTH, AXIS_WIDTH)
		bar_size[axis] = length
		var along: Vector3 = rot[axis]
		var bar: MeshInstance3D = _axis_markers[axis]
		var bar_basis := Basis(rot.x * bar_size.x, rot.y * bar_size.y, rot.z * bar_size.z)
		bar.global_transform = grid.global_transform * Transform3D(bar_basis, centre + along * (length * 0.5))
		bar.visible = true


## While a paste is armed, shows where the copied parts would land.
func _update_paste_preview() -> void:
	var active: bool = current_tool == Tool.TRANSFORM and paste_armed and _has_target and grid != null and not spawned
	var count: int = mini(_clipboard.size(), PASTE_PREVIEW_LIMIT) if active else 0
	while _paste_markers.size() < count:
		_paste_markers.append(_new_marker("PastePreview"))
	var base := Vector3i.ZERO
	if active:
		base = _paste_base()
	for index in _paste_markers.size():
		var marker: MeshInstance3D = _paste_markers[index]
		if index < count:
			var record: Dictionary = (_clipboard[index] as Dictionary).duplicate(true)
			var offset: Vector3i = record["pos"]
			record["pos"] = base + offset
			_fit_marker(marker, record, PREVIEW_OK, 1.0)
		else:
			marker.visible = false


## In the Config tool, draws a line for every signal link of the selected
## part: green from the parts it listens to, blue to the parts listening to it.
func _draw_link_lines() -> void:
	_link_mesh.clear_surfaces()
	_link_lines.visible = false
	if current_tool != Tool.CONFIG or selection.is_empty() or not grid.has_part(selection[0]):
		return
	var uid: int = selection[0]
	var record: Dictionary = grid.get_part(uid)
	var here: Vector3 = BuildGrid.bounds_of(record).get_center()
	var segments: Array = []   # [from, to, colour]
	var links: Dictionary = record.get("links", {})
	for input_id in links:
		var link: Dictionary = links[input_id]
		var source_uid: int = int(link.get("uid", 0))
		if grid.has_part(source_uid) and source_uid != uid:
			var source: Dictionary = grid.get_part(source_uid)
			segments.append([BuildGrid.bounds_of(source).get_center(), here, LINK_IN])
	for consumer in grid.consumers_of(uid):
		var consumer_uid: int = consumer[0]
		if consumer_uid != uid:
			var listener: Dictionary = grid.get_part(consumer_uid)
			segments.append([here, BuildGrid.bounds_of(listener).get_center(), LINK_OUT])
	if segments.is_empty():
		return
	var to_world: Transform3D = grid.global_transform
	_link_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment in segments:
		var from: Vector3 = segment[0]
		var to: Vector3 = segment[1]
		var color: Color = segment[2]
		_link_mesh.surface_set_color(color)
		_link_mesh.surface_add_vertex(to_world * from)
		_link_mesh.surface_set_color(color)
		_link_mesh.surface_add_vertex(to_world * to)
	_link_mesh.surface_end()
	_link_lines.visible = true


## Lays a see-through copy of a part's shape over where the record puts it.
func _fit_marker(marker: MeshInstance3D, record: Dictionary, color: Color, inflate: float) -> void:
	if record.is_empty():
		marker.visible = false
		return
	var size_units: Vector3i = record["size"]
	var size_m: Vector3 = Units.to_metres(size_units) * inflate
	var rot: Basis = record["rot"]
	var pos: Vector3i = record["pos"]
	var shape_basis := Basis(rot.x * size_m.x, rot.y * size_m.y, rot.z * size_m.z)
	marker.mesh = PartLibrary.mesh_for_record(record)
	marker.material_override = PartLibrary.overlay_material(color)
	marker.global_transform = grid.global_transform * Transform3D(shape_basis, Vector3(pos) * Units.UNIT)
	marker.visible = true


## Redraws the selection highlights and the centre-of-mass marker.
func _refresh_markers() -> void:
	if grid == null:
		return
	while _selection_markers.size() < selection.size():
		_selection_markers.append(_new_marker("Selected"))
	for index in _selection_markers.size():
		var marker: MeshInstance3D = _selection_markers[index]
		if index < selection.size():
			var record: Dictionary = grid.get_part(selection[index])
			_fit_marker(marker, record, SELECTED, 1.05)
		else:
			marker.visible = false

	_draw_link_lines()

	# The balance markers show while configuring or moving parts.
	var balancing: bool = current_tool == Tool.CONFIG or current_tool == Tool.TRANSFORM
	var show_mass: bool = balancing and grid.part_count() > 0 and not spawned
	_mass_marker.visible = show_mass
	_lift_marker.visible = false
	if show_mass:
		var center: Vector3 = grid.center_of_mass()
		_mass_marker.global_position = grid.global_transform * center
		var lift: Array = grid.center_of_lift()
		if lift[0]:
			var lift_point: Vector3 = lift[1]
			_lift_marker.global_position = grid.global_transform * lift_point
			_lift_marker.visible = true
