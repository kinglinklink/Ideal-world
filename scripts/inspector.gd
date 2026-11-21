extends Node
## The Inspector (key 8, while spawned): a diagnostic probe for wiring and
## drivetrains, drawn over the build as it runs.
##
##   - Every logic link is a line from the part it reads to the part that
##     reads it: green while its signal is on or not zero, grey while off.
##     Each part shows its values.
##   - Turning joints and gears show their speed (rpm) and the torque through
##     them, ringed in a colour from blue (light load) to red (near what the
##     motor can give). Gear trains whose tooth ratios disagree are red and
##     marked jammed.
##   - Fluid networks show their pressure and flow on each tank, pump and
##     cylinder, and the pipes between them coloured by pressure.
##   - The part under the mouse (or the middle of the screen, while the mouse
##     steers) gets a card with all of its inputs and outputs, live.
##
## A drive's torque is not something the physics engine reports. When a
## motor can't hold the speed asked of it, it is at its limit; otherwise the
## torque shown is what its gears carry plus what speeds up what it turns,
## marked ≈.

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const PartPorts = preload("res://scripts/part_ports.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const Spawner = preload("res://scripts/spawner.gd")

const REACH := 90.0                # metres from the camera beyond which nothing is labelled
const MAX_LABELS := 140
const LABEL_EVERY := 0.1           # seconds between label updates
const DRIVES := ["motor", "servo"]
const GEARS := ["gear", "bevel_gear", "pulley", "rack"]
const ON := Color(0.25, 1.0, 0.35)
const OFF := Color(0.55, 0.57, 0.6)
const JAMMED := Color(1.0, 0.15, 0.1)

var spawner: Node = null           # spawner.gd
var engines: Node = null           # engines.gd
var controller: Node = null        # build_controller.gd, to know when the build is spawned
var game_hud: Node = null          # for a word when it switches on and off
var active := false

var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _labels: Array = []            # Label3D pool
var _card_layer: CanvasLayer
var _card: PanelContainer
var _card_text: RichTextLabel
var _label_timer := 0.0
var _spin_before: Dictionary = {}  # turner uid -> its speed last frame, rad/s
var _torque: Dictionary = {}       # turner uid -> [estimated N m, at its limit]


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.no_depth_test = true
	look.render_priority = 10
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lines.material_override = look
	_lines.top_level = true
	_lines.extra_cull_margin = 16384.0
	add_child(_lines)
	_card_layer = CanvasLayer.new()
	_card_layer.layer = 55
	add_child(_card_layer)
	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.88)
	style.border_color = Color(0.3, 0.8, 1.0, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_card.add_theme_stylebox_override("panel", style)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.add_child(_card)
	_card_text = RichTextLabel.new()
	_card_text.bbcode_enabled = true
	_card_text.fit_content = true
	_card_text.scroll_active = false
	_card_text.custom_minimum_size = Vector2(300, 0)
	_card_text.add_theme_font_size_override("normal_font_size", 13)
	_card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_text)
	_set_active(false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_8 \
			and get_viewport().gui_get_focus_owner() == null:
		if not _spawned():
			if game_hud != null:
				game_hud.announce("", "The Inspector works on a spawned build", 2.0)
			return
		_set_active(not active)
		if game_hud != null:
			game_hud.announce("", "Inspector on: links, shafts, gears and fluids" if active else "Inspector off", 2.0)


func _spawned() -> bool:
	return spawner != null and bool(spawner.spawned)


func _set_active(on: bool) -> void:
	active = on
	_lines.visible = on
	_card.visible = false
	for label in _labels:
		(label as Label3D).visible = false
	_mesh.clear_surfaces()
	_spin_before.clear()
	_torque.clear()


func _process(delta: float) -> void:
	if not active:
		return
	if not _spawned():
		_set_active(false)
		return
	_estimate_torques(delta)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var notes: Dictionary = {}     # uid -> [lines of text, colour]
	_draw_links(notes)
	_draw_drivetrain(notes)
	_draw_fluids(notes)
	_mesh.surface_add_vertex(Vector3.ZERO)   # a surface needs at least two vertices
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_end()
	_label_timer -= delta
	if _label_timer <= 0.0:
		_label_timer = LABEL_EVERY
		_place_labels(notes)
		_update_card()


# --- Logic -------------------------------------------------------------------------

## The value on one of a part's outputs, read the way a link would read it.
func output_value(uid: int, output_id: String) -> float:
	return float(spawner.input_value({"x": {"uid": uid, "output": output_id}}, "x", 0.0))


func _draw_links(notes: Dictionary) -> void:
	var records: Dictionary = spawner.all_records()
	for key in records:
		var uid: int = key
		if spawner.is_dead(uid):
			continue
		var record: Dictionary = records[uid]
		var links: Dictionary = record.get("links", {})
		if links.is_empty():
			continue
		var to: Variant = spawner.part_position(uid)
		if to == null:
			continue
		for input_id in links:
			var link: Dictionary = links[input_id]
			var source: int = int(link.get("uid", 0))
			var from: Variant = spawner.part_position(source)
			if from == null:
				continue
			var value: float = spawner.input_value(links, str(input_id), 0.0)
			var colour := ON if value != 0.0 else OFF
			_line(from, to, colour)
			# A small arrowhead two thirds of the way along, pointing to the reader.
			var along: Vector3 = (to as Vector3) - (from as Vector3)
			if along.length() > 0.05:
				var tip: Vector3 = (from as Vector3) + along * 0.66
				var back := along.normalized() * minf(0.12, along.length() * 0.2)
				var side := back.cross(Vector3.UP).normalized() * 0.05
				if side.length() < 0.01:
					side = back.cross(Vector3.RIGHT).normalized() * 0.05
				_line(tip, tip - back + side, colour)
				_line(tip, tip - back - side, colour)
			var port := PartPorts.find_port(PartPorts.inputs_of(str(record["type"])), str(input_id))
			var port_name: String = str(port[1]) if not port.is_empty() else str(input_id)
			_note(notes, uid, "%s ← %s" % [port_name, _number(value)], colour if value != 0.0 else Color.WHITE)
			_note_outputs(notes, source)


func _note_outputs(notes: Dictionary, uid: int) -> void:
	if notes.has(uid) and bool(notes[uid].get("outputs_done", false)):
		return
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return
	for port in PartPorts.outputs_of(str(record["type"])):
		if str(port[2]) == "ammo":
			continue
		var value := output_value(uid, str(port[0]))
		_note(notes, uid, "%s → %s" % [port[1], _number(value)], ON if value != 0.0 else Color.WHITE)
	notes[uid]["outputs_done"] = true


# --- Drivetrain -------------------------------------------------------------------

## Estimates each drive's torque (see the top of this script).
func _estimate_torques(delta: float) -> void:
	for item in spawner.turners():
		var turner: Dictionary = item
		var uid: int = turner["uid"]
		var spin: float = turner["spin"]
		var before: float = _spin_before.get(uid, spin)
		_spin_before[uid] = spin
		if not DRIVES.has(str(turner["role"])):
			continue
		var grip: float = turner["grip"]
		var asked: float = turner.get("rate", 0.0)
		var at_limit := bool(turner["motor_on"]) and absf(asked) > 0.01 \
				and absf(asked - spin) > maxf(0.05 * absf(asked), 0.5)
		var torque := grip
		if not at_limit:
			var turned: RigidBody3D = spawner.piece_body(turner["b"])
			var carried := 0.0
			for gear in spawner.gear_load:
				var gear_body: RigidBody3D = spawner.piece_body(int(gear) * Spawner.PIECES)
				if gear_body == turned:
					carried += float(spawner.gear_load[gear])
			var speeding := 0.0
			if turned != null and not turned.freeze and delta > 0.0:
				var axis: Vector3 = turned.global_transform.basis * (turner["axis"] as Vector3)
				var inverse: float = spawner._inverse_inertia(turned, axis.normalized(), turned.global_position)
				if inverse > 0.0:
					speeding = absf(spin - before) / delta / inverse
			torque = minf(carried + speeding, grip)
		var last: Array = _torque.get(uid, [torque, at_limit])
		_torque[uid] = [lerpf(float(last[0]), torque, 0.15), at_limit]


## Blue (light) through green and yellow to red (at the limit).
static func load_colour(share: float) -> Color:
	var t := clampf(share, 0.0, 1.0)
	if t < 0.5:
		return Color(0.2, 0.5, 1.0).lerp(Color(0.3, 1.0, 0.4), t * 2.0)
	return Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.2, 0.1), (t - 0.5) * 2.0)


func _draw_drivetrain(notes: Dictionary) -> void:
	var strongest := 1.0          # the most torque any drive here can give, for colouring gears
	for item in spawner.turners():
		var turner: Dictionary = item
		if DRIVES.has(str(turner["role"])):
			strongest = maxf(strongest, float(turner["grip"]))
	for item in spawner.turners():
		var turner: Dictionary = item
		var uid: int = turner["uid"]
		var at: Variant = spawner.part_position(uid)
		var a_body: RigidBody3D = spawner.piece_body(turner["a"])
		if at == null or a_body == null:
			continue
		var axis: Vector3 = (a_body.global_transform.basis * (turner["axis"] as Vector3)).normalized()
		var rpm: float = float(turner["spin"]) * 60.0 / TAU
		var role: String = turner["role"]
		if DRIVES.has(role):
			var estimate: Array = _torque.get(uid, [0.0, false])
			var grip: float = maxf(float(turner["grip"]), 0.001)
			var colour := load_colour(float(estimate[0]) / grip)
			_ring(at, axis, 0.3, colour)
			if bool(estimate[1]):
				_note(notes, uid, "%s rpm, %s N·m: at its limit" % [_number(rpm), _number(grip)], colour)
			else:
				_note(notes, uid, "%s rpm, ≈%s of %s N·m" % [_number(rpm), _number(float(estimate[0])), _number(grip)], colour)
		elif role in ["bearing", "wheel", "clutch", "brake", "hinge"]:
			if absf(rpm) < 0.5 and role == "hinge":
				continue
			_ring(at, axis, 0.25, Color(0.6, 0.85, 1.0))
			_note(notes, uid, "%s rpm" % _number(rpm), Color(0.75, 0.9, 1.0))
	# Gears: speed, the torque through their teeth, and jams.
	var records: Dictionary = spawner.all_records()
	for key in records:
		var uid: int = key
		if spawner.is_dead(uid) or not GEARS.has(str(records[uid]["type"])):
			continue
		var at: Variant = spawner.part_position(uid)
		if at == null:
			continue
		var frame: Array = spawner.part_frame(uid)
		var axis := Vector3.UP
		if not frame.is_empty():
			axis = (frame[0] as Transform3D).basis.y.normalized()
		var size: Vector3 = Units.to_metres(records[uid]["size"])
		var radius := maxf(size.x, size.z) * 0.55
		if spawner.conflict_gears.has(uid):
			_ring(at, axis, radius, JAMMED)
			_ring(at, axis, radius * 1.08, JAMMED)
			_note(notes, uid, "JAMMED: its tooth ratios fight the rest of the train", JAMMED)
			continue
		var torque: float = spawner.gear_load.get(uid, 0.0)
		var rpm: float = float(spawner.outputs_of(uid).get("speed", 0.0))
		var colour := load_colour(torque / strongest)
		_ring(at, axis, radius, colour)
		_note(notes, uid, "%s rpm, %s N·m" % [_number(rpm), _number(torque)], colour)
	for item in spawner.gear_meshes():
		var mesh: Dictionary = item
		var from: Variant = spawner.part_position(mesh["a"])
		var to: Variant = spawner.part_position(mesh["b"])
		if from != null and to != null:
			var fighting: bool = spawner.conflict_gears.has(mesh["a"]) and spawner.conflict_gears.has(mesh["b"])
			_line(from, to, JAMMED if fighting else Color(0.6, 0.85, 1.0, 0.6))


# --- Fluids -----------------------------------------------------------------------

func _draw_fluids(notes: Dictionary) -> void:
	if engines == null:
		return
	var neighbours: Dictionary = engines.fluid_neighbours()
	var labelled: Dictionary = {}   # network index -> true once one of its pipes has a label
	for key in neighbours:
		var uid: int = key
		var record: Dictionary = spawner.record_of(uid)
		if record.is_empty():
			continue
		var info: Dictionary = engines.network_info(uid)
		var at: Variant = spawner.part_position(uid)
		if at == null:
			continue
		var share := 0.0
		if not info.is_empty():
			share = float(info["pressure"]) / maxf(float(info.get("max_pressure", 0.0)), 1000000.0)
		var colour := load_colour(share)
		for item in neighbours[uid]:
			var other: int = item
			if other > uid:
				var there: Variant = spawner.part_position(other)
				if there != null:
					_line(at, there, colour)
		var type: String = record["type"]
		if info.is_empty():
			if type == "valve":
				_note(notes, uid, "closed", OFF)
			continue
		if type == "fluid_pipe":
			var network: int = engines.network_index(uid)
			if labelled.has(network):
				continue
			labelled[network] = true
		var text := "%s %s, flow %s L/s" % [str(info["kind"]), _pressure(float(info["pressure"])), _number(float(info["flow"]))]
		if type == "fuel_tank":
			text += ", %s%% full" % _number(float(spawner.outputs_of(uid).get("level", 0.0)))
		_note(notes, uid, text, colour)


# --- Drawing ----------------------------------------------------------------------

func _line(from: Vector3, to: Vector3, colour: Color) -> void:
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(to)


func _ring(centre: Vector3, axis: Vector3, radius: float, colour: Color) -> void:
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.1:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized() * radius
	var other := axis.cross(side)
	var steps := 20
	for index in steps:
		var a := TAU * index / steps
		var b := TAU * (index + 1) / steps
		_line(centre + side * cos(a) + other * sin(a), centre + side * cos(b) + other * sin(b), colour)


func _note(notes: Dictionary, uid: int, text: String, colour: Color) -> void:
	if not notes.has(uid):
		notes[uid] = {"lines": [], "colour": colour}
	(notes[uid]["lines"] as Array).append(text)
	if colour != Color.WHITE:
		notes[uid]["colour"] = colour


func _place_labels(notes: Dictionary) -> void:
	var camera := get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	var shown := 0
	var order: Array = notes.keys()
	order.sort_custom(func(a, b): return _distance_to(a, eye) < _distance_to(b, eye))
	for key in order:
		var uid: int = key
		var at: Variant = spawner.part_position(uid)
		if at == null or (at as Vector3).distance_to(eye) > REACH or shown >= MAX_LABELS:
			continue
		var label := _label(shown)
		var record: Dictionary = spawner.record_of(uid)
		var title := PartLibrary.part_name(str(record.get("type", ""))) if not record.is_empty() else "Part"
		label.text = "%s %d\n%s" % [title, uid, "\n".join(notes[uid]["lines"])]
		label.modulate = notes[uid]["colour"]
		label.global_position = (at as Vector3) + Vector3(0.0, 0.25, 0.0)
		label.visible = true
		shown += 1
	for index in range(shown, _labels.size()):
		(_labels[index] as Label3D).visible = false


func _distance_to(uid: int, eye: Vector3) -> float:
	var at: Variant = spawner.part_position(uid)
	return INF if at == null else (at as Vector3).distance_to(eye)


func _label(index: int) -> Label3D:
	while _labels.size() <= index:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0007
		label.font_size = 26
		label.outline_size = 8
		label.render_priority = 11
		label.outline_render_priority = 10
		label.top_level = true
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		add_child(label)
		_labels.append(label)
	return _labels[index]


# --- The card ---------------------------------------------------------------------

## The part under the mouse, or the middle of the screen while the mouse
## steers: its uid, or 0.
func part_under_pointer() -> int:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0
	var point := get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		point = get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(point) * 400.0, Units.LAYER_BODIES)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 0
	return spawner.part_of_shape(hit["collider"], int(hit["shape"]))


func _update_card() -> void:
	var uid := part_under_pointer()
	if uid == 0:
		_card.visible = false
		return
	_card_text.text = card_text(uid)
	_card.visible = true
	var point := get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		point = get_viewport().get_visible_rect().size * 0.5
	_card.position = point + Vector2(24.0, 24.0)


## Everything about one part, live.
func card_text(uid: int) -> String:
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return ""
	var type: String = record["type"]
	var lines: Array = ["[b]%s[/b]  (part %d)" % [PartLibrary.part_name(type), uid]]
	lines.append("%s, health %s of %s" % [MaterialLibrary.display_name(str(record["material"])),
			_number(spawner.health_of(uid)), _number(spawner.full_health_of(uid))])
	var inputs: Array = PartPorts.inputs_of(type)
	var links: Dictionary = record.get("links", {})
	if not inputs.is_empty():
		lines.append("[color=#88ccff]Inputs[/color]")
		for port in inputs:
			var port_id := str(port[0])
			if links.has(port_id):
				var source: int = int(links[port_id].get("uid", 0))
				var source_record: Dictionary = spawner.record_of(source)
				var from_name := PartLibrary.part_name(str(source_record.get("type", ""))) if not source_record.is_empty() else "a destroyed part"
				lines.append("  %s = %s  [color=#aaaaaa](from %s %d: %s)[/color]" % [port[1],
						_number(spawner.input_value(links, port_id, 0.0)), from_name, source, str(links[port_id].get("output", ""))])
			else:
				lines.append("  %s  [color=#888888]not linked[/color]" % port[1])
	var outputs: Array = PartPorts.outputs_of(type)
	if not outputs.is_empty():
		lines.append("[color=#88ffaa]Outputs[/color]")
		for port in outputs:
			if str(port[2]) == "ammo":
				lines.append("  %s" % port[1])
				continue
			lines.append("  %s = %s" % [port[1], _number(output_value(uid, str(port[0])))])
	if _torque.has(uid):
		var estimate: Array = _torque[uid]
		lines.append("Torque %s N·m%s" % [_number(float(estimate[0])), " (at its limit)" if bool(estimate[1]) else " (estimated)"])
	if spawner.conflict_gears.has(uid):
		lines.append("[color=#ff4433]Jammed: the tooth ratios round its train don't agree.[/color]")
	if engines != null:
		var info: Dictionary = engines.network_info(uid)
		if not info.is_empty():
			lines.append("Network: %s at %s, pumps %s L/s" % [info["kind"], _pressure(float(info["pressure"])), _number(float(info["flow"]))])
	return "\n".join(lines)


static func _number(value: float) -> String:
	if absf(value) >= 1000.0:
		return "%.0f" % value
	if absf(value) >= 10.0 or value == roundf(value):
		return "%.0f" % value if value == roundf(value) else "%.1f" % value
	return "%.2f" % value


static func _pressure(pascals: float) -> String:
	if absf(pascals) >= 1000000.0:
		return "%.2f MPa" % (pascals / 1000000.0)
	return "%.0f kPa" % (pascals / 1000.0)
