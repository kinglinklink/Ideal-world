extends PanelContainer
## The sub-assembly menu (key 7, or the Sub-assemblies button): a window in
## the middle of the screen with a card for every saved sub-assembly, each
## with its name, a slowly turning model, its part count and its mass.
##
## Build a piece off to the side (a wing, an engine, a landing-gear leg),
## select it with the Transform tool, type a name here and save it. To use
## one, drag its card out onto your build (or click it): a see-through copy
## follows the cursor and rests on whatever it touches; R / T / Y turn it;
## click to put it down. The Transform tool then holds the whole thing,
## selected, to nudge into exactly the right place. Sub-assemblies are kept
## in saves/modules, for every build and every save slot.

const SaveManager = preload("res://scripts/save_manager.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Units = preload("res://scripts/units.gd")

const CARD_SIZE := Vector2i(170, 120)
const MAX_MODELS := 24          # cards past this many show no turning model
const DRAG_START := 10.0        # pixels the mouse moves on a card before it counts as a drag

var controller: Node = null     # build_controller.gd
var player: Node = null         # player.gd, to free the cursor

var _search: LineEdit
var _cards: GridContainer
var _name_edit: LineEdit
var _status: Label
var _models: Array = []         # Node3D, turned a little each frame
var _press: Dictionary = {}     # {"name", "at"} while the mouse is down on a card
var _carrying := false          # a card was dragged out: the next release puts it down
var _delete_armed := ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	var title := Label.new()
	title.text = "Sub-assemblies"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.custom_minimum_size = Vector2(200, 0)
	_search.text_changed.connect(func(_text: String) -> void: refresh(""))
	title_row.add_child(_search)
	var close := Button.new()
	close.text = "Close (7)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	title_row.add_child(close)
	var about := Label.new()
	about.text = "Drag a card onto your build (or click it), then click to put it down; R / T / Y turn it first.\nThe Transform tool then holds it, selected, to nudge into place."
	about.add_theme_font_size_override("font_size", 13)
	box.add_child(about)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(4 * (CARD_SIZE.x + 12) + 20, 2 * (CARD_SIZE.y + 64) + 10)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_cards = GridContainer.new()
	_cards.columns = 4
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_cards)
	var save_row := HBoxContainer.new()
	box.add_child(save_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name for the selected parts"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_edit)
	var save := Button.new()
	save.text = "Save selection as sub-assembly"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_selection)
	save_row.add_child(save)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func toggle() -> void:
	visible = not visible
	if visible:
		if player != null:
			player.cursor_free = true
		refresh("Select parts with the Transform tool (4) to save them as a sub-assembly.")


func refresh(status: String) -> void:
	for child in _cards.get_children():
		child.queue_free()
	_models.clear()
	var filter := _search.text.strip_edges().to_lower()
	var shown := 0
	for item in SaveManager.list_modules():
		var module_name := str(item)
		if filter != "" and not module_name.to_lower().contains(filter):
			continue
		_cards.add_child(_card(module_name, shown < MAX_MODELS))
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "No sub-assemblies yet." if filter == "" else "None match."
		_cards.add_child(empty)
	if status != "":
		_status.text = status


func _card(module_name: String, with_model: bool) -> Control:
	var records: Array = SaveManager.load_module(module_name)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "Drag onto your build, or click"
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	if with_model:
		column.add_child(_model_view(records))
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(CARD_SIZE)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(spacer)
	var title := Label.new()
	title.text = module_name
	title.clip_text = true
	title.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var mass := 0.0
	for record in records:
		mass += BuildGrid.mass_of(record)
	var row := HBoxContainer.new()
	column.add_child(row)
	var facts := Label.new()
	facts.text = "%d parts · %s" % [records.size(), "%.2f t" % (mass / 1000.0) if mass >= 1000.0 else "%.1f kg" % mass]
	facts.add_theme_font_size_override("font_size", 12)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(facts)
	var delete := Button.new()
	delete.text = "✕"
	delete.tooltip_text = "Delete this sub-assembly"
	delete.focus_mode = Control.FOCUS_NONE
	delete.pressed.connect(func() -> void:
		if _delete_armed == module_name:
			SaveManager.delete_module(module_name)
			_delete_armed = ""
			refresh("Deleted \"%s\"." % module_name)
		else:
			_delete_armed = module_name
			_status.text = "Press ✕ again to delete \"%s\"." % module_name)
	row.add_child(delete)
	card.gui_input.connect(_on_card_input.bind(module_name))
	return card


## A small window onto the sub-assembly, turning slowly.
func _model_view(records: Array) -> Control:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(CARD_SIZE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.size = CARD_SIZE
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	holder.add_child(view)
	var model := Node3D.new()
	view.add_child(model)
	var bounds := AABB()
	var first := true
	for item in records:
		var record: Dictionary = item
		var piece := MeshInstance3D.new()
		piece.mesh = PartLibrary.mesh_for_record(record)
		var size_m := Units.to_metres(record["size"])
		piece.transform = Transform3D((record["rot"] as Basis) * Basis.from_scale(size_m),
				Vector3(record["pos"] as Vector3i) * Units.UNIT)
		piece.set_surface_override_material(0, MaterialLibrary.surface(record["material"], record["color"]))
		model.add_child(piece)
		var box: AABB = BuildGrid.bounds_of(record)
		bounds = box if first else bounds.merge(box)
		first = false
	for child in model.get_children():
		(child as Node3D).position -= bounds.get_center()
	var reach := maxf(bounds.get_longest_axis_size(), 0.25)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, reach * 0.55, reach * 1.45)
	camera.fov = 45.0
	view.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	view.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.6, 0.0)
	fill.light_energy = 0.4
	view.add_child(fill)
	_models.append(model)
	return holder


func _process(delta: float) -> void:
	if not visible:
		return
	for model in _models:
		if is_instance_valid(model):
			(model as Node3D).rotate_y(delta * 0.6)


func _on_card_input(event: InputEvent, module_name: String) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press = {"name": module_name, "at": button.global_position}
		elif not _press.is_empty():
			_press = {}
			_pick_up(module_name, false)   # a click: carried until the next click in the world
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and not _press.is_empty() and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if motion.global_position.distance_to(_press["at"]) > DRAG_START:
			var dragged: String = _press["name"]
			_press = {}
			_pick_up(dragged, true)


func _pick_up(module_name: String, dragged: bool) -> void:
	var problem: String = controller.place_module(module_name)
	if problem != "":
		_status.text = problem
		return
	visible = false
	_carrying = dragged


## A card dragged out of the window is put down where the mouse is let go.
func _input(event: InputEvent) -> void:
	if not _carrying:
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_carrying = false
		if bool(controller.paste_armed):
			controller.paste()
		get_viewport().set_input_as_handled()


func _save_selection() -> void:
	var module_name := SaveManager.clean_name(_name_edit.text)
	if module_name == "":
		_status.text = "Type a name first."
		return
	var problem: String = controller.save_selection_as_module(module_name)
	refresh(problem if problem != "" else "Saved \"%s\"." % module_name)
