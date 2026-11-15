extends CanvasLayer
## The build-mode interface: tool bar, one side panel per tool, readouts and
## help text. Everything is built in code so the layout lives in one file.

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const BuildController = preload("res://scripts/build_controller.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const PartSettings = preload("res://scripts/part_settings.gd")
const PartPorts = preload("res://scripts/part_ports.gd")

const SNAP_STOPS := [1.0, 0.5, 0.25, 0.1, 0.05, 0.025, 0.01, 0.005]   # in cells
const AXIS_NAMES := ["X", "Y", "Z"]
const MESSAGE_SECONDS := 3.5

var controller: Node = null          # build_controller.gd
var grid: Node = null                # build_grid.gd
var player: CharacterBody3D = null   # player.gd

var _tool_buttons: Array = []
var _panels: Array = []              # one panel per tool, in Tool order
var _part_buttons: Dictionary = {}   # part id -> Button
var _material_buttons: Dictionary = {}
var _place_brush_label: Label
var _transform_info: Label
var _snap_option: OptionButton
var _config_title: Label
var _config_spins: Array = []
var _config_info: Label
var _build_info: Label
var _color_button: ColorPickerButton
var _pick_material_button: Button
var _pick_color_button: Button
var _paint_brush_label: Label
var _count_label: Label
var _speed_label: Label
var _fps_label: Label
var _crosshair: Label
var _message_label: Label
var _message_time := 0.0
var _saves_panel: PanelContainer
var _saves_list: ItemList
var _saves_folder_label: Label
var _save_name_edit: LineEdit
var _saves_status: Label
var _pending_action := ""            # a load or delete waiting for its second click
var _paste_button: Button
var _settings_title: Label
var _settings_scroll: ScrollContainer
var _settings_box: VBoxContainer
var _setting_controls: Dictionary = {}   # setting id -> the control that edits it
var _settings_key := ""                  # which part the settings rows were built for
var _signals_title: Label
var _signals_scroll: ScrollContainer
var _signals_box: VBoxContainer


func setup(p_controller: Node, p_grid: Node, p_player: CharacterBody3D) -> void:
	controller = p_controller
	grid = p_grid
	player = p_player
	_build_interface()
	controller.connect("tool_changed", _on_changed_with_value)
	controller.connect("part_type_changed", _on_changed_with_value)
	controller.connect("snap_changed", _on_changed_with_value)
	controller.connect("brush_changed", _on_changed)
	controller.connect("selection_changed", _on_changed)
	controller.connect("message", _on_message)
	grid.connect("parts_changed", _on_changed)
	_refresh()


# --- Small builders ----------------------------------------------------------

func _label(text: String, font_size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	return label


func _outlined(label: Label) -> Label:
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label


func _button(text: String, min_width: float = 0.0, toggle: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = toggle
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(min_width, 34)
	return button


func _column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	return box


func _row() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	return box


func _grid_of(columns: int) -> GridContainer:
	var grid_box := GridContainer.new()
	grid_box.columns = columns
	grid_box.add_theme_constant_override("h_separation", 6)
	grid_box.add_theme_constant_override("v_separation", 6)
	return grid_box


# --- Layout ------------------------------------------------------------------

func _build_interface() -> void:
	# One full-screen margin box; each child pins itself to a corner or edge.
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(margin_name, 16)
	add_child(root)

	# Help text, top left.
	var help := _outlined(_label(
			"WASD walk   Shift run   Space jump   Scroll zoom\n"
			+ "Hold right mouse to look   Esc free cursor (first person)\n"
			+ "1 Place   2 Delete   3 Transform   4 Config   5 Paint   Left click use tool\n"
			+ "Saves button, bottom right, saves and loads builds", 14))
	help.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	help.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(help)

	# Messages from the tools, top centre.
	_message_label = _outlined(_label("", 18))
	_message_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_message_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	root.add_child(_message_label)

	# Crosshair, screen centre, shown while the mouse is captured.
	_crosshair = _label("+", 22)
	_crosshair.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_crosshair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(_crosshair)

	# Tool bar, bottom centre.
	var toolbar := _row()
	toolbar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toolbar.size_flags_vertical = Control.SIZE_SHRINK_END
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toolbar)
	var tool_names: Array = BuildController.TOOL_NAMES
	for index in tool_names.size():
		var tool_button := _button("%d  %s" % [index + 1, tool_names[index]], 116.0, true)
		tool_button.custom_minimum_size = Vector2(116, 56)
		tool_button.pressed.connect(_on_tool_button.bind(index))
		toolbar.add_child(tool_button)
		_tool_buttons.append(tool_button)

	# Side panel, bottom left: one panel per tool, only the active one shown.
	var side := PanelContainer.new()
	side.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	side.size_flags_vertical = Control.SIZE_SHRINK_END
	root.add_child(side)
	var side_margin := MarginContainer.new()
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		side_margin.add_theme_constant_override(margin_name, 8)
	side.add_child(side_margin)
	var stack := _column()
	side_margin.add_child(stack)

	_panels = [
		_build_place_panel(),
		_build_delete_panel(),
		_build_transform_panel(),
		_build_config_panel(),
		_build_paint_panel(),
	]
	for panel in _panels:
		stack.add_child(panel)

	# Readouts, bottom right.
	var readouts := VBoxContainer.new()
	readouts.size_flags_horizontal = Control.SIZE_SHRINK_END
	readouts.size_flags_vertical = Control.SIZE_SHRINK_END
	readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(readouts)
	var history := _row()
	history.size_flags_horizontal = Control.SIZE_SHRINK_END
	history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readouts.add_child(history)
	var undo_button := _button("Undo", 80.0)
	undo_button.tooltip_text = "Ctrl+Z"
	undo_button.pressed.connect(_on_undo_button)
	history.add_child(undo_button)
	var redo_button := _button("Redo", 80.0)
	redo_button.tooltip_text = "Ctrl+Y"
	redo_button.pressed.connect(_on_redo_button)
	history.add_child(redo_button)
	var saves_button := _button("Saves", 110.0)
	saves_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	saves_button.pressed.connect(_on_saves_button)
	readouts.add_child(saves_button)
	_count_label = _readout(readouts)
	_speed_label = _readout(readouts)
	_fps_label = _readout(readouts)

	# Saves window, screen centre, hidden until the Saves button is pressed.
	_saves_panel = _build_saves_panel()
	root.add_child(_saves_panel)


func _readout(parent: Control) -> Label:
	var label := _outlined(_label(""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(label)
	return label


func _build_place_panel() -> Control:
	var panel := _column()
	for category in PartLibrary.CATEGORIES:
		# Each category is a header that folds its buttons away when clicked.
		var category_name: String = category
		var expanded: bool = category_name == "Basic"
		var header := _button(_category_title(category_name, expanded), 0.0, true)
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.set_pressed_no_signal(expanded)
		panel.add_child(header)
		var buttons := _grid_of(3)
		buttons.visible = expanded
		panel.add_child(buttons)
		header.toggled.connect(_on_category_toggled.bind(category_name, header, buttons))
		for id in PartLibrary.part_ids():
			if PartLibrary.category(id) != category:
				continue
			var part_button := _button(PartLibrary.part_name(id), 124.0, true)
			part_button.pressed.connect(_on_part_button.bind(id))
			buttons.add_child(part_button)
			_part_buttons[id] = part_button
	_place_brush_label = _label("", 13)
	panel.add_child(_place_brush_label)
	panel.add_child(_label("R / T / Y  turn 90° about X / Y / Z", 13))
	return panel


static func _category_title(category_name: String, expanded: bool) -> String:
	return "%s  %s parts" % ["-" if expanded else "+", category_name]


func _on_category_toggled(expanded: bool, category_name: String, header: Button, buttons: Control) -> void:
	buttons.visible = expanded
	header.text = _category_title(category_name, expanded)


func _build_delete_panel() -> Control:
	var panel := _column()
	panel.add_child(_label("Delete"))
	panel.add_child(_label("Click a part to remove it.", 13))
	return panel


func _build_transform_panel() -> Control:
	var panel := _column()
	panel.add_child(_label("Transform"))
	_transform_info = _label("", 13)
	panel.add_child(_transform_info)

	var snap_row := _row()
	snap_row.add_child(_label("Step"))
	_snap_option = OptionButton.new()
	_snap_option.focus_mode = Control.FOCUS_NONE
	for stop in SNAP_STOPS:
		var stop_cells: float = stop
		_snap_option.add_item("%s block" % str(stop_cells))
	_snap_option.item_selected.connect(_on_snap_selected)
	snap_row.add_child(_snap_option)
	panel.add_child(snap_row)

	var moves := _grid_of(2)
	panel.add_child(moves)
	for axis in 3:
		for direction in [-1, 1]:
			var sign_text := "-" if direction < 0 else "+"
			var move_button := _button("Move %s %s" % [AXIS_NAMES[axis], sign_text], 132.0)
			move_button.pressed.connect(_on_move_button.bind(axis, direction))
			moves.add_child(move_button)

	var turns := _row()
	panel.add_child(turns)
	for axis in 3:
		var turn_button := _button("Turn %s" % AXIS_NAMES[axis], 86.0)
		turn_button.pressed.connect(_on_turn_button.bind(axis))
		turns.add_child(turn_button)

	var edits := _row()
	panel.add_child(edits)
	var copy_button := _button("Copy", 63.0)
	copy_button.pressed.connect(_on_copy_button)
	edits.add_child(copy_button)
	var cut_button := _button("Cut", 63.0)
	cut_button.pressed.connect(_on_cut_button)
	edits.add_child(cut_button)
	_paste_button = _button("Paste", 63.0, true)
	_paste_button.pressed.connect(_on_paste_button)
	edits.add_child(_paste_button)
	var delete_button := _button("Delete", 63.0)
	delete_button.pressed.connect(_on_delete_button)
	edits.add_child(delete_button)

	var all_button := _button("Select all")
	all_button.pressed.connect(_on_select_all_button)
	panel.add_child(all_button)

	panel.add_child(_label(
			"Click selects, Shift+click adds\n"
			+ "Arrows and PgUp / PgDn move\n"
			+ "R / T / Y turn 90°\n"
			+ "Ctrl+C copy, Ctrl+X cut\n"
			+ "Paste, then click where it goes\n"
			+ "(or point and press Ctrl+V)\n"
			+ "Ctrl+Z undo, Ctrl+Y redo", 13))
	return panel


func _build_config_panel() -> Control:
	var panel := _column()
	_config_title = _label("")
	panel.add_child(_config_title)

	for axis in 3:
		var size_row := _row()
		var caption := _label("Size %s (blocks)" % AXIS_NAMES[axis])
		caption.custom_minimum_size = Vector2(120, 0)
		size_row.add_child(caption)
		var spin := SpinBox.new()
		spin.min_value = 1.0 / Units.UNITS_PER_CELL
		spin.max_value = 64.0
		spin.step = 1.0 / Units.UNITS_PER_CELL
		spin.custom_minimum_size = Vector2(130, 0)
		spin.select_all_on_focus = true
		spin.value_changed.connect(_on_config_size.bind(axis))
		size_row.add_child(spin)
		panel.add_child(size_row)
		_config_spins.append(spin)

	_config_info = _label("", 13)
	panel.add_child(_config_info)

	# The part's own settings. The rows are rebuilt for each kind of part.
	_settings_title = _label("Settings (take effect after Spawn)", 13)
	_settings_title.visible = false
	panel.add_child(_settings_title)
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.visible = false
	panel.add_child(_settings_scroll)
	_settings_box = _column()
	_settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.add_child(_settings_box)

	# The part's signal inputs and outputs, and what they are linked to.
	_signals_title = _label("Signals (green lines in, blue lines out)", 13)
	_signals_title.visible = false
	panel.add_child(_signals_title)
	_signals_scroll = ScrollContainer.new()
	_signals_scroll.visible = false
	panel.add_child(_signals_scroll)
	_signals_box = _column()
	_signals_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_signals_scroll.add_child(_signals_box)

	panel.add_child(HSeparator.new())
	_build_info = _label("", 13)
	panel.add_child(_build_info)
	panel.add_child(_label("The yellow ball marks the centre of mass.", 13))
	return panel


## Builds one row per setting for the given kind of part.
func _rebuild_settings(type: String) -> void:
	for child in _settings_box.get_children():
		_settings_box.remove_child(child)
		child.queue_free()
	_setting_controls.clear()

	var settings: Array = []
	if type != "":
		settings = PartSettings.for_type(type)
	_settings_title.visible = not settings.is_empty()
	_settings_scroll.visible = not settings.is_empty()
	_settings_scroll.custom_minimum_size = Vector2(330, minf(settings.size() * 40.0, 220.0))

	for setting in settings:
		var id: String = setting["id"]
		var kind: String = setting["kind"]
		var title: String = setting["name"]
		if kind == "flag":
			var check := CheckBox.new()
			check.text = title
			check.focus_mode = Control.FOCUS_NONE
			check.toggled.connect(_on_setting_changed.bind(id))
			_settings_box.add_child(check)
			_setting_controls[id] = check
			continue

		var setting_row := _row()
		var caption := _label(title, 13)
		caption.custom_minimum_size = Vector2(140, 0)
		setting_row.add_child(caption)
		if kind == "number":
			var spin := SpinBox.new()
			spin.min_value = setting["min"]
			spin.max_value = setting["max"]
			spin.step = setting["step"]
			var unit: String = setting["unit"]
			if unit != "":
				spin.suffix = unit
			spin.custom_minimum_size = Vector2(170, 0)
			spin.select_all_on_focus = true
			spin.value_changed.connect(_on_setting_changed.bind(id))
			setting_row.add_child(spin)
			_setting_controls[id] = spin
		elif kind == "choice":
			var option := OptionButton.new()
			option.focus_mode = Control.FOCUS_NONE
			var options: Array = setting["options"]
			for item in options:
				option.add_item(str(item))
			option.set_meta("options", options)
			option.item_selected.connect(_on_setting_choice.bind(id))
			setting_row.add_child(option)
			_setting_controls[id] = option
		elif kind == "color":
			var picker := ColorPickerButton.new()
			picker.custom_minimum_size = Vector2(120, 30)
			picker.focus_mode = Control.FOCUS_NONE
			picker.edit_alpha = false
			picker.color_changed.connect(_on_setting_changed.bind(id))
			setting_row.add_child(picker)
			_setting_controls[id] = picker
		else:
			var edit := LineEdit.new()
			edit.max_length = 24
			edit.custom_minimum_size = Vector2(170, 0)
			edit.text_submitted.connect(_on_setting_text.bind(id, edit))
			edit.focus_exited.connect(_on_setting_text_done.bind(id, edit))
			setting_row.add_child(edit)
			_setting_controls[id] = edit
		_settings_box.add_child(setting_row)


## Shows the selected part's settings, rebuilding the rows only when a
## different part is selected so that typing is never interrupted.
func _sync_settings(record: Dictionary) -> void:
	var key := ""
	var type := ""
	if not record.is_empty():
		var chosen: Array = controller.selection
		type = record["type"]
		key = "%s:%s" % [str(chosen[0]), type]
	if key != _settings_key:
		_settings_key = key
		_rebuild_settings(type)
	if record.is_empty():
		return

	var props: Dictionary = record.get("props", {})
	for id in _setting_controls:
		if not props.has(id):
			continue
		var value: Variant = props[id]
		var control: Control = _setting_controls[id]
		if control is SpinBox:
			(control as SpinBox).set_value_no_signal(float(value))
		elif control is CheckBox:
			(control as CheckBox).set_pressed_no_signal(bool(value))
		elif control is OptionButton:
			var options: Array = control.get_meta("options")
			var chosen_index: int = options.find(value)
			if chosen_index >= 0:
				(control as OptionButton).select(chosen_index)
		elif control is ColorPickerButton:
			(control as ColorPickerButton).color = value
		elif control is LineEdit:
			var edit := control as LineEdit
			if not edit.has_focus():
				edit.text = str(value)


## "Motor #12": a part's name with its number, to tell like parts apart.
func _part_label(uid: int) -> String:
	var record: Dictionary = grid.get_part(uid)
	if record.is_empty():
		return "a missing part"
	return "%s #%d" % [PartLibrary.part_name(record["type"]), uid]


## Lists the selected part's inputs and outputs with their links. Rebuilt on
## every refresh, since it is only a handful of rows.
func _sync_signals(record: Dictionary) -> void:
	for child in _signals_box.get_children():
		(child as Control).visible = false
		child.queue_free()

	var inputs: Array = []
	var outputs: Array = []
	if not record.is_empty():
		inputs = PartPorts.inputs_of(record["type"])
		outputs = PartPorts.outputs_of(record["type"])
	var has_ports: bool = not inputs.is_empty() or not outputs.is_empty()
	_signals_title.visible = has_ports
	_signals_scroll.visible = has_ports
	if not has_ports:
		return

	var chosen: Array = controller.selection
	var uid: int = chosen[0]
	var links: Dictionary = record.get("links", {})
	var waiting: String = controller.link_input
	var rows := 0

	# After clicking a source part with several outputs: pick one.
	var choices: Array = controller.link_choices()
	if not choices.is_empty():
		var source_uid: int = controller.link_source_uid
		_signals_box.add_child(_label("Pick an output of %s:" % _part_label(source_uid), 13))
		rows += 1
		for port in choices:
			var choice_button := _button(PartPorts.label(port))
			choice_button.pressed.connect(_on_link_output_chosen.bind(str(port[0])))
			_signals_box.add_child(choice_button)
			rows += 1

	if not inputs.is_empty():
		_signals_box.add_child(_label("Inputs", 13))
		rows += 1
	for port in inputs:
		var input_id: String = port[0]
		var line := _row()
		var link_button := _button("Cancel" if waiting == input_id else "Link", 60.0)
		link_button.pressed.connect(_on_link_button.bind(input_id))
		line.add_child(link_button)
		var text := PartPorts.label(port)
		if waiting == input_id:
			text += "  <- click the source part"
		elif links.has(input_id):
			var link: Dictionary = links[input_id]
			var source: int = int(link.get("uid", 0))
			var source_record: Dictionary = grid.get_part(source)
			var output_name := str(link.get("output", ""))
			if not source_record.is_empty():
				var output_port: Array = PartPorts.find_port(PartPorts.outputs_of(source_record["type"]), output_name)
				if not output_port.is_empty():
					output_name = str(output_port[1])
			text += "  <- %s: %s" % [_part_label(source), output_name]
			var clear_button := _button("Clear", 56.0)
			clear_button.pressed.connect(_on_clear_link_button.bind(input_id))
			line.add_child(clear_button)
		else:
			text += "  (not linked)"
		line.add_child(_label(text, 13))
		_signals_box.add_child(line)
		rows += 1

	if not outputs.is_empty():
		_signals_box.add_child(_label("Outputs", 13))
		rows += 1
	var consumers: Array = grid.consumers_of(uid)
	for port in outputs:
		var listeners := 0
		for consumer in consumers:
			if consumer[2] == port[0]:
				listeners += 1
		var out_text := PartPorts.label(port)
		if listeners > 0:
			out_text += "  -> %d input(s)" % listeners
		_signals_box.add_child(_label(out_text, 13))
		rows += 1

	_signals_scroll.custom_minimum_size = Vector2(330, minf(rows * 34.0, 230.0))


func _on_link_button(input_id: String) -> void:
	var waiting: String = controller.link_input
	if waiting == input_id:
		controller.cancel_link()
	else:
		controller.begin_link(input_id)


func _on_clear_link_button(input_id: String) -> void:
	controller.clear_link(input_id)


func _on_link_output_chosen(output_id: String) -> void:
	controller.choose_link_output(output_id)


func _on_setting_changed(value: Variant, id: String) -> void:
	controller.set_config_setting(id, value)


func _on_setting_choice(index: int, id: String) -> void:
	var option: OptionButton = _setting_controls[id]
	var options: Array = option.get_meta("options")
	controller.set_config_setting(id, options[index])


func _on_setting_text(text: String, id: String, edit: LineEdit) -> void:
	controller.set_config_setting(id, text.strip_edges())
	edit.release_focus()


## A text box that loses the keyboard keeps what was typed, unless the box
## belongs to a part that is no longer the one being configured.
func _on_setting_text_done(id: String, edit: LineEdit) -> void:
	if edit.is_queued_for_deletion() or _setting_controls.get(id) != edit:
		return
	controller.set_config_setting(id, edit.text.strip_edges())


func _build_paint_panel() -> Control:
	var panel := _column()
	panel.add_child(_label("Materials"))
	var materials := _grid_of(3)
	panel.add_child(materials)
	for id in MaterialLibrary.ids():
		var material_button := _button(MaterialLibrary.display_name(id), 104.0, true)
		material_button.tooltip_text = MaterialLibrary.tooltip(id)
		material_button.pressed.connect(_on_material_button.bind(id))
		materials.add_child(material_button)
		_material_buttons[id] = material_button

	var color_row := _row()
	color_row.add_child(_label("Color"))
	_color_button = ColorPickerButton.new()
	_color_button.custom_minimum_size = Vector2(120, 34)
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.edit_alpha = false
	_color_button.color_changed.connect(_on_color_changed)
	color_row.add_child(_color_button)
	panel.add_child(color_row)

	var pick_row := _row()
	_pick_material_button = _button("Pick material", 132.0, true)
	_pick_material_button.pressed.connect(_on_pick_button.bind("material"))
	pick_row.add_child(_pick_material_button)
	_pick_color_button = _button("Pick color", 132.0, true)
	_pick_color_button.pressed.connect(_on_pick_button.bind("color"))
	pick_row.add_child(_pick_color_button)
	panel.add_child(pick_row)

	_paint_brush_label = _label("", 13)
	panel.add_child(_paint_brush_label)
	panel.add_child(_label("Click a part to paint it.\nParts that overlap are painted together.", 13))
	return panel


# --- Saves window ------------------------------------------------------------

func _build_saves_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.visible = false
	var margin := MarginContainer.new()
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(margin_name, 12)
	panel.add_child(margin)
	var box := _column()
	margin.add_child(box)

	box.add_child(_label("Saves", 18))
	_saves_folder_label = _label("", 12)
	_saves_folder_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	box.add_child(_saves_folder_label)

	_saves_list = ItemList.new()
	_saves_list.custom_minimum_size = Vector2(440, 240)
	_saves_list.focus_mode = Control.FOCUS_NONE
	_saves_list.item_selected.connect(_on_save_selected)
	_saves_list.item_activated.connect(_on_save_activated)
	box.add_child(_saves_list)

	var name_row := _row()
	name_row.add_child(_label("Name"))
	_save_name_edit = LineEdit.new()
	_save_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_name_edit.placeholder_text = "Type a name for this build"
	_save_name_edit.text_submitted.connect(_on_save_name_submitted)
	name_row.add_child(_save_name_edit)
	box.add_child(name_row)

	var actions := _row()
	box.add_child(actions)
	var save_button := _button("Save", 104.0)
	save_button.pressed.connect(_on_save_pressed)
	actions.add_child(save_button)
	var load_button := _button("Load", 104.0)
	load_button.pressed.connect(_on_load_pressed)
	actions.add_child(load_button)
	var delete_button := _button("Delete", 104.0)
	delete_button.pressed.connect(_on_delete_save_pressed)
	actions.add_child(delete_button)

	var extras := _row()
	box.add_child(extras)
	var refresh_button := _button("Refresh", 104.0)
	refresh_button.pressed.connect(_on_refresh_saves_pressed)
	extras.add_child(refresh_button)
	var folder_button := _button("Open folder", 104.0)
	folder_button.pressed.connect(_on_open_folder_pressed)
	extras.add_child(folder_button)
	var close_button := _button("Close", 104.0)
	close_button.pressed.connect(_on_close_saves_pressed)
	extras.add_child(close_button)

	_saves_status = _label("", 13)
	_saves_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_saves_status)
	return panel


## Re-reads the saves folder and shows a status line under the list.
func _refresh_saves(status: String) -> void:
	_pending_action = ""
	_saves_list.clear()
	for save_name in SaveManager.list_saves():
		_saves_list.add_item(str(save_name))
	_saves_folder_label.text = "Folder: %s" % SaveManager.saves_dir()
	_saves_status.text = status


func _typed_name() -> String:
	return SaveManager.clean_name(_save_name_edit.text)


## Loading over a build and deleting a save both need a second click.
func _confirmed(action: String) -> bool:
	if _pending_action == action:
		_pending_action = ""
		return true
	_pending_action = action
	return false


func _on_saves_button() -> void:
	_saves_panel.visible = not _saves_panel.visible
	if _saves_panel.visible:
		_refresh_saves("Files in this folder can be copied, shared and edited.")
	else:
		_save_name_edit.release_focus()


func _on_save_selected(index: int) -> void:
	_save_name_edit.text = _saves_list.get_item_text(index)
	_pending_action = ""


func _on_save_activated(index: int) -> void:
	_save_name_edit.text = _saves_list.get_item_text(index)
	_on_load_pressed()


func _on_save_name_submitted(_text: String) -> void:
	_on_save_pressed()
	_save_name_edit.release_focus()


func _on_save_pressed() -> void:
	var save_name := _typed_name()
	if save_name == "":
		_saves_status.text = "Type a name first."
		return
	var replaced: bool = SaveManager.exists(save_name)
	var problem: String = SaveManager.save_build(grid, save_name)
	if problem != "":
		_saves_status.text = problem
		return
	var count: int = grid.part_count()
	var verb := "Replaced" if replaced else "Saved"
	_refresh_saves("%s \"%s\" with %d part(s)." % [verb, save_name, count])


func _on_load_pressed() -> void:
	var save_name := _typed_name()
	if save_name == "" or not SaveManager.exists(save_name):
		_saves_status.text = "Pick a save from the list first."
		return
	var count: int = grid.part_count()
	if count > 0 and not _confirmed("load:" + save_name):
		_saves_status.text = "Loading replaces the current build. Click Load again to confirm."
		return
	var result: Dictionary = SaveManager.load_build(grid, save_name)
	var error: String = result["error"]
	if error != "":
		_saves_status.text = error
		return
	var loaded: int = result["loaded"]
	var skipped: int = result["skipped"]
	var status := "Loaded \"%s\": %d part(s)." % [save_name, loaded]
	if skipped > 0:
		status += " Skipped %d that did not fit or were not recognised." % skipped
	_refresh_saves(status)


func _on_delete_save_pressed() -> void:
	var save_name := _typed_name()
	if save_name == "" or not SaveManager.exists(save_name):
		_saves_status.text = "Pick a save from the list first."
		return
	if not _confirmed("delete:" + save_name):
		_saves_status.text = "Click Delete again to remove \"%s\" for good." % save_name
		return
	if SaveManager.delete_save(save_name):
		_save_name_edit.text = ""
		_refresh_saves("Deleted \"%s\"." % save_name)
	else:
		_saves_status.text = "Could not delete \"%s\"." % save_name


func _on_refresh_saves_pressed() -> void:
	_refresh_saves("List refreshed.")


func _on_open_folder_pressed() -> void:
	SaveManager.ensure_dir()
	OS.shell_open(SaveManager.saves_dir())


func _on_close_saves_pressed() -> void:
	_saves_panel.visible = false
	_save_name_edit.release_focus()


# --- Every frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	_fps_label.text = "FPS  %d" % int(Engine.get_frames_per_second())
	_speed_label.text = "Speed  %.1f m/s" % player.velocity.length()
	_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message_label.text = ""


# --- Button handlers ---------------------------------------------------------

func _on_tool_button(index: int) -> void:
	controller.set_tool(index)
	_refresh()


func _on_part_button(id: String) -> void:
	controller.set_part_type(id)
	_refresh()


func _on_material_button(id: String) -> void:
	controller.set_brush_material(id)
	_refresh()


func _on_color_changed(color: Color) -> void:
	controller.set_brush_color(color)


func _on_pick_button(mode: String) -> void:
	var current: String = controller.eyedropper
	controller.set_eyedropper("" if current == mode else mode)
	_refresh()


func _on_snap_selected(index: int) -> void:
	var stop_cells: float = SNAP_STOPS[index]
	controller.set_snap(int(round(stop_cells * Units.UNITS_PER_CELL)))


func _on_move_button(axis: int, direction: int) -> void:
	var step := Vector3i.ZERO
	var snap: int = controller.snap_units
	step[axis] = direction * snap
	controller.move_selection(step)


func _on_turn_button(axis: int) -> void:
	var turn_axis := Vector3.ZERO
	turn_axis[axis] = 1.0
	controller.rotate_selection(turn_axis)


func _on_copy_button() -> void:
	controller.copy_selection()


func _on_cut_button() -> void:
	controller.cut_selection()


func _on_delete_button() -> void:
	controller.delete_selection()


func _on_select_all_button() -> void:
	controller.select_all()


func _on_paste_button() -> void:
	var armed: bool = controller.paste_armed
	if armed:
		controller.paste_armed = false
	else:
		controller.arm_paste()
	_refresh()


func _on_undo_button() -> void:
	controller.undo()


func _on_redo_button() -> void:
	controller.redo()


func _on_config_size(value: float, axis: int) -> void:
	var accepted: bool = controller.set_config_size(axis, value)
	if not accepted:
		_refresh()   # put the old number back


func _on_message(text: String) -> void:
	_message_label.text = text
	_message_time = MESSAGE_SECONDS


func _on_changed() -> void:
	_refresh()


func _on_changed_with_value(_value: Variant) -> void:
	_refresh()


# --- Refresh -----------------------------------------------------------------

static func _mass_text(kilograms: float) -> String:
	if kilograms >= 1000.0:
		return "%.2f t" % (kilograms / 1000.0)
	return "%.2f kg" % kilograms


## Brings every button and label in line with the controller's state.
func _refresh() -> void:
	var active_tool: int = controller.current_tool
	for index in _tool_buttons.size():
		var tool_button: Button = _tool_buttons[index]
		tool_button.set_pressed_no_signal(index == active_tool)
	for index in _panels.size():
		var panel: Control = _panels[index]
		panel.visible = index == active_tool

	# Place.
	var active_part: String = controller.part_type
	for id in _part_buttons:
		var part_button: Button = _part_buttons[id]
		part_button.set_pressed_no_signal(id == active_part)

	# Brush, shared by Place and Paint.
	var brush_material: String = controller.brush_material
	var brush_color: Color = controller.brush_color
	var brush_text := "Brush: %s" % MaterialLibrary.display_name(brush_material)
	_place_brush_label.text = brush_text + "  (change it with Paint)"
	_paint_brush_label.text = brush_text
	for id in _material_buttons:
		var material_button: Button = _material_buttons[id]
		material_button.set_pressed_no_signal(id == brush_material)
	_color_button.color = brush_color
	var eyedropper: String = controller.eyedropper
	_pick_material_button.set_pressed_no_signal(eyedropper == "material")
	_pick_color_button.set_pressed_no_signal(eyedropper == "color")

	# Transform.
	var selection: Array = controller.selection
	if selection.is_empty():
		_transform_info.text = "Nothing selected"
	else:
		_transform_info.text = "%d part(s) selected" % selection.size()
	var paste_armed: bool = controller.paste_armed
	_paste_button.set_pressed_no_signal(paste_armed)
	var snap: int = controller.snap_units
	for index in SNAP_STOPS.size():
		var stop_cells: float = SNAP_STOPS[index]
		if int(round(stop_cells * Units.UNITS_PER_CELL)) == snap:
			_snap_option.select(index)

	# Config.
	var record: Dictionary = controller.config_record()
	if record.is_empty():
		_config_title.text = "Config: click a part"
		_config_info.text = ""
		for spin_index in _config_spins.size():
			var idle_spin: SpinBox = _config_spins[spin_index]
			idle_spin.editable = false
	else:
		var type: String = record["type"]
		var size: Vector3i = record["size"]
		var material: String = record["material"]
		_config_title.text = "Config: %s" % PartLibrary.part_name(type)
		for spin_index in _config_spins.size():
			var spin: SpinBox = _config_spins[spin_index]
			spin.editable = true
			spin.set_value_no_signal(float(size[spin_index]) / Units.UNITS_PER_CELL)
		var mass: float = BuildGrid.mass_of(record)
		var strength: float = MaterialLibrary.info(material)["strength"]
		var size_m: Vector3 = Units.to_metres(size)
		_config_info.text = "Size: %.3f x %.3f x %.3f m\nMaterial: %s\nVolume: %.5f m³\nMass: %s\nHealth: %d HP" % [
			size_m.x, size_m.y, size_m.z,
			MaterialLibrary.display_name(material),
			BuildGrid.volume_of(record),
			_mass_text(mass),
			int(round(mass * strength)),
		]

	_sync_settings(record)
	_sync_signals(record)

	# Whole build.
	var count: int = grid.part_count()
	if count == 0:
		_build_info.text = "Build: empty"
	else:
		var total: float = grid.total_mass()
		var center: Vector3 = grid.center_of_mass()
		_build_info.text = "Build: %d part(s), %s\nCentre of mass: %.2f, %.2f, %.2f m" % [
			count, _mass_text(total), center.x, center.y, center.z,
		]
	_count_label.text = "Parts  %d" % count
