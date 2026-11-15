extends CanvasLayer
## The build-mode interface: tool bar, part menu, readouts and help text.
## Everything is built in code so the layout lives in one readable file.

const PartLibrary = preload("res://scripts/part_library.gd")
const BuildController = preload("res://scripts/build_controller.gd")

var controller: Node = null          # build_controller.gd
var grid: Node = null                # build_grid.gd
var player: CharacterBody3D = null   # player.gd

var _tool_buttons: Array = []
var _part_buttons: Dictionary = {}   # part id -> Button
var _part_panel: PanelContainer
var _count_label: Label
var _fps_label: Label
var _speed_label: Label
var _crosshair: Label


func setup(p_controller: Node, p_grid: Node, p_player: CharacterBody3D) -> void:
	controller = p_controller
	grid = p_grid
	player = p_player
	_build_interface()
	controller.connect("tool_changed", _on_tool_changed)
	controller.connect("part_changed", _on_part_changed)
	grid.connect("block_count_changed", _on_block_count_changed)
	_refresh()


func _build_interface() -> void:
	# One full-screen margin box; each child pins itself to a corner or edge.
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(side, 16)
	add_child(root)

	# Help text, top left.
	var help := Label.new()
	help.text = "WASD walk   Shift run   Space jump\n" \
			+ "Scroll zoom   Hold right mouse to look   Esc free cursor (first person)\n" \
			+ "1 Place   2 Delete   Left click use tool   R / T / Y rotate part"
	help.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	help.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help.add_theme_constant_override("outline_size", 4)
	root.add_child(help)

	# Crosshair, screen centre, shown while the mouse is captured.
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_crosshair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_theme_font_size_override("font_size", 22)
	root.add_child(_crosshair)

	# Tool bar, bottom centre.
	var toolbar := HBoxContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toolbar.size_flags_vertical = Control.SIZE_SHRINK_END
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)

	var tool_names: Array = BuildController.TOOL_NAMES
	var tools_ready: Array = BuildController.TOOLS_READY
	for index in tool_names.size():
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, tool_names[index]]
		button.custom_minimum_size = Vector2(110, 56)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		if tools_ready[index]:
			button.pressed.connect(_on_tool_button.bind(index))
		else:
			button.disabled = true
			button.tooltip_text = "Coming in a later update"
		toolbar.add_child(button)
		_tool_buttons.append(button)

	# Part menu, bottom left.
	_part_panel = PanelContainer.new()
	_part_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_part_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	root.add_child(_part_panel)

	var part_box := VBoxContainer.new()
	part_box.add_theme_constant_override("separation", 6)
	_part_panel.add_child(part_box)

	var part_title := Label.new()
	part_title.text = "Basic parts"
	part_box.add_child(part_title)

	for id in PartLibrary.part_ids():
		var part_button := Button.new()
		part_button.text = PartLibrary.part_name(id)
		part_button.custom_minimum_size = Vector2(150, 40)
		part_button.toggle_mode = true
		part_button.focus_mode = Control.FOCUS_NONE
		part_button.pressed.connect(_on_part_button.bind(id))
		part_box.add_child(part_button)
		_part_buttons[id] = part_button

	var rotate_hint := Label.new()
	rotate_hint.text = "R / T / Y  rotate 90°\nabout X / Y / Z"
	rotate_hint.add_theme_font_size_override("font_size", 13)
	part_box.add_child(rotate_hint)

	# Readouts, bottom right.
	var readouts := VBoxContainer.new()
	readouts.size_flags_horizontal = Control.SIZE_SHRINK_END
	readouts.size_flags_vertical = Control.SIZE_SHRINK_END
	readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(readouts)

	_count_label = _readout_label(readouts)
	_speed_label = _readout_label(readouts)
	_fps_label = _readout_label(readouts)


func _readout_label(parent: Control) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


func _process(_delta: float) -> void:
	if player == null:
		return
	_fps_label.text = "FPS  %d" % int(Engine.get_frames_per_second())
	_speed_label.text = "Speed  %.1f m/s" % player.velocity.length()
	_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _on_tool_button(index: int) -> void:
	controller.set_tool(index)
	_refresh()


func _on_part_button(id: String) -> void:
	controller.set_part(id)
	_refresh()


func _on_tool_changed(_new_tool: int) -> void:
	_refresh()


func _on_part_changed(_part_id: String) -> void:
	_refresh()


func _on_block_count_changed(_count: int) -> void:
	_refresh()


## Brings every button and label in line with the controller's state.
func _refresh() -> void:
	var active_tool: int = controller.current_tool
	for index in _tool_buttons.size():
		var button: Button = _tool_buttons[index]
		button.set_pressed_no_signal(index == active_tool)

	var active_part: String = controller.part_id
	for id in _part_buttons:
		var part_button: Button = _part_buttons[id]
		part_button.set_pressed_no_signal(id == active_part)

	_part_panel.visible = active_tool == BuildController.Tool.PLACE
	var count: int = grid.block_count()
	_count_label.text = "Blocks  %d" % count
