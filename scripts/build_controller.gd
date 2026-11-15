extends Node3D
## The five build-mode tools: Place, Delete, Transform, Config and Paint.

signal tool_changed(new_tool: int)
signal part_type_changed(type: String)
signal brush_changed
signal selection_changed
signal snap_changed(units: int)
signal message(text: String)

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const PartSettings = preload("res://scripts/part_settings.gd")
const PartPorts = preload("res://scripts/part_ports.gd")

enum Tool { PLACE, DELETE, TRANSFORM, CONFIG, PAINT }

const TOOL_NAMES := ["Place", "Delete", "Transform", "Config", "Paint"]
const REACH := 400.0         # metres the tools can reach from the camera
const AIM_EVERY_TICKS := 4   # the aim ray runs at 60 Hz, a quarter of the physics rate
const PASTE_PREVIEW_LIMIT := 200   # most parts drawn in the paste preview

const PREVIEW_OK := Color(0.35, 0.75, 1.0, 0.45)
const PREVIEW_BLOCKED := Color(1.0, 0.25, 0.2, 0.45)
const HOVER_DELETE := Color(1.0, 0.25, 0.2, 0.5)
const HOVER_OTHER := Color(1.0, 0.95, 0.5, 0.3)
const SELECTED := Color(0.3, 1.0, 0.55, 0.4)
const MASS_MARKER := Color(1.0, 0.85, 0.1, 0.95)
const LINK_IN := Color(0.3, 1.0, 0.4)     # lines from the parts this one listens to
const LINK_OUT := Color(0.35, 0.65, 1.0)  # lines to the parts that listen to this one

var grid: Node3D = null              # build_grid.gd
var player: CharacterBody3D = null   # player.gd

var current_tool: int = Tool.PLACE
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

var _clipboard: Array = []     # records whose "pos" is relative to an anchor cell centre
var _tick := 0
var _hit_uid := 0              # part under the cursor, 0 for none
var _has_target := false       # the cursor is on some surface
var _target_cell := Vector3i.ZERO
var _target_axis := 1          # axis the clicked surface faces along
var _target_sign := 1

var _preview: MeshInstance3D
var _hover: MeshInstance3D
var _mass_marker: MeshInstance3D
var _selection_markers: Array = []
var _paste_markers: Array = []
var _link_lines: MeshInstance3D
var _link_mesh: ImmediateMesh


func setup(p_grid: Node3D, p_player: CharacterBody3D) -> void:
	grid = p_grid
	player = p_player
	grid.connect("parts_changed", _on_parts_changed)


func _ready() -> void:
	_preview = _new_marker("Preview")
	_hover = _new_marker("Hover")

	_mass_marker = _new_marker("CentreOfMass")
	var ball := SphereMesh.new()
	ball.radius = 0.4 * Units.CELL
	ball.height = 0.8 * Units.CELL
	_mass_marker.mesh = ball
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = MASS_MARKER
	ball_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball_material.no_depth_test = true   # visible through the build
	_mass_marker.material_override = ball_material

	# Thin lines that show the selected part's signal links.
	_link_lines = _new_marker("SignalLinks")
	_link_mesh = ImmediateMesh.new()
	_link_lines.mesh = _link_mesh
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	_link_lines.material_override = line_material


func _new_marker(marker_name: String) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	add_child(marker)
	return marker


# --- State changes -----------------------------------------------------------

func set_tool(new_tool: int) -> void:
	if new_tool < 0 or new_tool >= TOOL_NAMES.size() or new_tool == current_tool:
		return
	current_tool = new_tool
	eyedropper = ""
	paste_armed = false
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
	_refresh_markers()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_on_key(key)
		elif key.pressed and current_tool == Tool.TRANSFORM:
			_on_move_key(key.physical_keycode)   # held arrows keep nudging
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			get_viewport().gui_release_focus()
			_use_tool()


func _on_key(key: InputEventKey) -> void:
	var code: int = key.physical_keycode
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
				paste()
			elif code == KEY_A:
				select_all()
		return
	if code == KEY_1:
		set_tool(Tool.PLACE)
	elif code == KEY_2:
		set_tool(Tool.DELETE)
	elif code == KEY_3:
		set_tool(Tool.TRANSFORM)
	elif code == KEY_4:
		set_tool(Tool.CONFIG)
	elif code == KEY_5:
		set_tool(Tool.PAINT)
	elif code == KEY_R:
		_on_rotate_key(Vector3(1.0, 0.0, 0.0))
	elif code == KEY_T:
		_on_rotate_key(Vector3(0.0, 1.0, 0.0))
	elif code == KEY_Y:
		_on_rotate_key(Vector3(0.0, 0.0, 1.0))
	elif current_tool == Tool.TRANSFORM:
		if code == KEY_DELETE or code == KEY_BACKSPACE:
			delete_selection()
		else:
			_on_move_key(code)


## R, T and Y turn things 90 degrees about the world X, Y and Z axes:
## the armed part in the Place tool, the selection in the Transform tool.
func _on_rotate_key(axis: Vector3) -> void:
	if current_tool == Tool.PLACE:
		place_rotation = _quarter_turn(axis) * place_rotation
	elif current_tool == Tool.TRANSFORM:
		rotate_selection(axis)


## A rotation matrix with exact 0 / +1 / -1 entries, so quarter turns never drift.
static func _quarter_turn(axis: Vector3) -> Basis:
	var turn := Basis(axis, PI * 0.5)
	return Basis(turn.x.round(), turn.y.round(), turn.z.round())


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
	if grid == null:
		return
	if current_tool == Tool.PLACE:
		_use_place()
	elif current_tool == Tool.DELETE:
		if _hit_uid != 0:
			grid.remove_part(_hit_uid)
			_hit_uid = 0
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
	var turn: Basis = _quarter_turn(axis)
	var pivot: Vector3i = _selection_pivot()
	var updates: Dictionary = {}
	for uid in selection:
		var record: Dictionary = grid.get_part(uid)
		var pos: Vector3i = record["pos"]
		var rot: Basis = record["rot"]
		var arm: Vector3 = turn * Vector3(pos - pivot)
		record["pos"] = pivot + Vector3i(arm.round())
		var turned: Basis = turn * rot
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
	var anchor: Vector3i = grid.cell_center_units(first_pos / Units.UNITS_PER_CELL)
	for uid in selection:
		var record: Dictionary = grid.get_part(uid)
		var pos: Vector3i = record["pos"]
		record["pos"] = pos - anchor
		record["copied_from"] = uid   # lets a paste re-point links between the copies
		_clipboard.append(record)
	_say("Copied %d part(s). Press Paste or Ctrl+V, pointing where it should go." % _clipboard.size())


func cut_selection() -> void:
	if selection.is_empty():
		return
	copy_selection()
	delete_selection()


## Pastes the clipboard so its first part lands in the cell under the cursor.
func paste() -> void:
	if _clipboard.is_empty():
		_say("Nothing copied yet.")
		return
	if not _has_target:
		_say("Point at a surface to paste onto.")
		return
	var base: Vector3i = grid.cell_center_units(_target_cell)
	var records: Array = []
	for stored in _clipboard:
		var record: Dictionary = (stored as Dictionary).duplicate(true)
		var offset: Vector3i = record["pos"]
		record["pos"] = base + offset
		var problem: String = grid.check(record)
		if problem != "":
			_say("Cannot paste here. " + problem)
			return
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
	grid.end_batch()
	paste_armed = false
	selection = pasted
	selection_changed.emit()
	_refresh_markers()


## Used by the Paste button: the next click in the world pastes there.
func arm_paste() -> void:
	if _clipboard.is_empty():
		_say("Nothing copied yet.")
		return
	paste_armed = true
	selection_changed.emit()
	_say("Click where the copy should go.")


func undo() -> void:
	if grid != null and not grid.undo():
		_say("Nothing to undo.")


func redo() -> void:
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


# --- Aiming and markers ------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_tick += 1
	if _tick % AIM_EVERY_TICKS != 0:
		return
	_update_target()
	_update_cursor_markers()
	_update_paste_preview()


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
	if current_tool == Tool.PLACE:
		if _has_target:
			var record: Dictionary = _placement_record()
			var problem: String = grid.check(record)
			var preview_color: Color = PREVIEW_OK if problem == "" else PREVIEW_BLOCKED
			_fit_marker(_preview, record, preview_color, 1.0)
	elif _hit_uid != 0:
		var hover_color: Color = HOVER_DELETE if current_tool == Tool.DELETE else HOVER_OTHER
		var hovered: Dictionary = grid.get_part(_hit_uid)
		_fit_marker(_hover, hovered, hover_color, 1.03)


## While a paste is armed, shows where the copied parts would land.
func _update_paste_preview() -> void:
	var active: bool = current_tool == Tool.TRANSFORM and paste_armed and _has_target and grid != null
	var count: int = mini(_clipboard.size(), PASTE_PREVIEW_LIMIT) if active else 0
	while _paste_markers.size() < count:
		_paste_markers.append(_new_marker("PastePreview"))
	var base := Vector3i.ZERO
	if active:
		base = grid.cell_center_units(_target_cell)
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
	var type: String = record["type"]
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

	var show_mass: bool = current_tool == Tool.CONFIG and grid.part_count() > 0
	_mass_marker.visible = show_mass
	if show_mass:
		var center: Vector3 = grid.center_of_mass()
		_mass_marker.global_position = grid.global_transform * center
