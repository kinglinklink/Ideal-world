extends PanelContainer
## The settings window, opened from the Settings button at the top of the
## screen. Every change applies at once and is saved for next time.

const Settings = preload("res://scripts/settings.gd")

signal changed(values: Dictionary)
signal jump_time(fraction: float)   # 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight

var values: Dictionary = {}
var _forest: Node = null
var _mode: OptionButton
var _cap: SpinBox
var _trees: HSlider
var _trees_label: Label
var _fps: CheckBox
var _sky: OptionButton
const MODES := ["vsync", "cap", "unlimited"]


func setup(forest: Node) -> void:
	_forest = forest
	values = Settings.load_settings()
	Settings.apply(values, _forest)
	_build()
	_show_values()


func _build() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	var frame_row := HBoxContainer.new()
	column.add_child(frame_row)
	frame_row.add_child(_caption("Frame rate"))
	_mode = OptionButton.new()
	_mode.focus_mode = Control.FOCUS_NONE
	_mode.add_item("VSync")
	_mode.add_item("Limit to")
	_mode.add_item("Unlimited")
	_mode.item_selected.connect(_on_mode)
	frame_row.add_child(_mode)
	_cap = SpinBox.new()
	_cap.min_value = 1
	_cap.max_value = 240
	_cap.step = 1
	_cap.suffix = "fps"
	_cap.value_changed.connect(_on_cap)
	frame_row.add_child(_cap)

	var tree_row := HBoxContainer.new()
	column.add_child(tree_row)
	tree_row.add_child(_caption("Tree distance"))
	_trees = HSlider.new()
	_trees.min_value = 500
	_trees.max_value = 5000
	_trees.step = 100
	_trees.custom_minimum_size = Vector2(150, 0)
	_trees.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_trees.focus_mode = Control.FOCUS_NONE
	_trees.value_changed.connect(_on_trees)
	tree_row.add_child(_trees)
	_trees_label = Label.new()
	tree_row.add_child(_trees_label)

	var sky_row := HBoxContainer.new()
	column.add_child(sky_row)
	sky_row.add_child(_caption("Time of day"))
	_sky = OptionButton.new()
	_sky.focus_mode = Control.FOCUS_NONE
	_sky.add_item("Day and night (20 min)")
	_sky.add_item("Always day")
	_sky.add_item("Always night")
	_sky.item_selected.connect(_on_sky)
	sky_row.add_child(_sky)

	var jump_row := HBoxContainer.new()
	column.add_child(jump_row)
	jump_row.add_child(_caption("Jump to"))
	for pair in [["Dawn", 0.0], ["Noon", 0.25], ["Dusk", 0.47], ["Night", 0.75]]:
		var jump := Button.new()
		jump.text = str(pair[0])
		jump.focus_mode = Control.FOCUS_NONE
		var fraction: float = pair[1]
		jump.pressed.connect(func() -> void: jump_time.emit(fraction))
		jump_row.add_child(jump)

	_fps = CheckBox.new()
	_fps.text = "Show frames per second"
	_fps.focus_mode = Control.FOCUS_NONE
	_fps.toggled.connect(_on_fps)
	column.add_child(_fps)

	var note := Label.new()
	note.text = "Lower the frame limit or tree distance to keep a laptop cool.\nPhysics always runs 240 steps a second."
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.7)
	column.add_child(note)

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: visible = false)
	column.add_child(close)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(110, 0)
	return label


func _show_values() -> void:
	_mode.select(MODES.find(str(values["frame_mode"])))
	_cap.set_value_no_signal(int(values["frame_cap"]))
	_cap.editable = values["frame_mode"] == "cap"
	_trees.set_value_no_signal(float(values["tree_distance"]))
	_trees_label.text = "%.1f km" % (float(values["tree_distance"]) / 1000.0)
	_fps.set_pressed_no_signal(bool(values["show_fps"]))
	_sky.select(Settings.SKIES.find(str(values["sky"])))


func _commit() -> void:
	Settings.apply(values, _forest)
	Settings.save_settings(values)
	_show_values()
	changed.emit(values)


func _on_mode(index: int) -> void:
	values["frame_mode"] = MODES[clampi(index, 0, MODES.size() - 1)]
	_commit()


func _on_cap(value: float) -> void:
	values["frame_cap"] = clampi(int(value), 1, 240)
	_commit()


func _on_trees(value: float) -> void:
	values["tree_distance"] = value
	_commit()


func _on_sky(index: int) -> void:
	values["sky"] = Settings.SKIES[clampi(index, 0, Settings.SKIES.size() - 1)]
	_commit()


func _on_fps(on: bool) -> void:
	values["show_fps"] = on
	_commit()
