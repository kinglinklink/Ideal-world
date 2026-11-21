extends PanelContainer
## The settings window, opened from the Settings button at the top of the
## screen, the pause menu or the title screen. Four tabs: Display, Sound,
## World and Controls. Every change applies at once and is saved for next
## time. It works while the game is paused.

const Settings = preload("res://scripts/settings.gd")
const Sound = preload("res://scripts/sound.gd")

signal changed(values: Dictionary)
signal jump_time(fraction: float)   # 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight
signal closed

const MODES := ["vsync", "cap", "unlimited"]
const VOLUMES := [
	["volume_master", "Master"], ["volume_effects", "Effects"], ["volume_machines", "Machines"],
	["volume_ambience", "Wind and nature"], ["volume_interface", "Clicks"],
]
const CONTROLS := [
	"Walking",
	"  W A S D        walk (or swim)          Shift   run",
	"  Space          jump, swim up, or stand up from a seat",
	"  E              sit in the nearest seat",
	"  Scroll         zoom from first person out to third person",
	"  Right mouse    hold to turn the camera",
	"  Esc            free the cursor (first person); again for the pause menu",
	"  P              back to the hangar         M   full map",
	"  E              also talks to race hosts and cargo agents at airports",
	"",
	"Building",
	"  1 to 6         Place, Delete, Config, Transform, Paint, Scale (again to put away)",
	"  7              sub-assemblies: save a selection, drag one onto your build",
	"  G              grab the selection and carry it onto another part (Esc puts it back)",
	"  Left click     use the tool               R / T / Y   turn 90° about X / Y / Z",
	"  Ctrl+Z / Ctrl+Y   undo / redo",
	"  Transform: Shift+click add, arrows and Page Up/Down move,",
	"             Ctrl+C / X / V copy, cut, paste, Ctrl+Shift+V paste in place,",
	"             Ctrl+A select all, Delete remove",
	"  Config: Shift+C / Shift+V copy and paste a part's size and settings",
	"  Enter          Spawn, or back to Build",
	"",
	"Spawned",
	"  Keys you bind in input blocks work while you sit in a seat.",
	"  0              replay the last 30 seconds (Space or Esc skips)",
	"  9              stress view: parts coloured by load, blue to red",
	"  8              inspector: signals, shaft speeds and torque, fluid flow on the build",
	"  Left click     fires hit-scan guns at the crosshair",
	"",
	"Anywhere",
	"  C              camera (wheel zoom, F filter, click: photo)   B   bird guide",
	"  J              mission board            L   failure log      F3   performance",
	"  F              refuel, at a pump",
	"  Hover the mouse over a bird for a close-up",
	"  F1 or the Guide button: what every part does.",
]

var values: Dictionary = {}
var _forest: Node = null
var _events: OptionButton
var _mode: OptionButton
var _cap: SpinBox
var _scale: HSlider
var _scale_label: Label
var _msaa: OptionButton
var _shadows: CheckBox
var _trees: HSlider
var _trees_label: Label
var _fps: CheckBox
var _sky: OptionButton
var _crash: CheckBox
var _checks: Dictionary = {}   # setting key -> CheckBox, for the simple on/off settings
var _volume_sliders: Dictionary = {}
var _volume_labels: Dictionary = {}


func setup(forest: Node) -> void:
	_forest = forest
	values = Settings.load_settings()
	Settings.apply(values, _forest)
	_build()
	_show_values()


func _build() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(560, 470)
	visibility_changed.connect(func() -> void:
		if not visible:
			closed.emit())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	column.add_child(tabs)

	# --- Display ---
	var display := _page(tabs, "Display")
	var frame_row := _row(display, "Frame rate")
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

	var scale_row := _row(display, "Resolution")
	_scale = _slider(50, 100, 5)
	_scale.value_changed.connect(func(value: float) -> void:
		values["render_scale"] = int(value)
		_commit())
	scale_row.add_child(_scale)
	_scale_label = Label.new()
	scale_row.add_child(_scale_label)

	var msaa_row := _row(display, "Edge smoothing")
	_msaa = OptionButton.new()
	_msaa.focus_mode = Control.FOCUS_NONE
	for option in ["Off", "2×", "4×"]:
		_msaa.add_item(option)
	_msaa.item_selected.connect(func(index: int) -> void:
		values["msaa"] = Settings.MSAA[clampi(index, 0, 2)]
		_commit())
	msaa_row.add_child(_msaa)

	var tree_row := _row(display, "Tree distance")
	_trees = _slider(500, 5000, 100)
	_trees.value_changed.connect(_on_trees)
	tree_row.add_child(_trees)
	_trees_label = Label.new()
	tree_row.add_child(_trees_label)

	_shadows = CheckBox.new()
	_shadows.text = "Shadows"
	_shadows.focus_mode = Control.FOCUS_NONE
	_shadows.toggled.connect(func(on: bool) -> void:
		values["shadows"] = on
		_commit())
	display.add_child(_shadows)

	_fps = CheckBox.new()
	_fps.text = "Show frames per second"
	_fps.focus_mode = Control.FOCUS_NONE
	_fps.toggled.connect(_on_fps)
	display.add_child(_fps)

	var presets := HBoxContainer.new()
	display.add_child(presets)
	presets.add_child(_caption("Quick set"))
	var low := _small_button("Laptop (fast)")
	low.pressed.connect(func() -> void: _preset(60, 70, "off", false, 1200.0))
	presets.add_child(low)
	var high := _small_button("Desktop (best)")
	high.pressed.connect(func() -> void: _preset(0, 100, "4x", true, 3600.0))
	presets.add_child(high)

	display.add_child(_note("Lower the resolution, smoothing, shadows or tree distance to speed up a slow\ncomputer or keep a laptop cool. Physics always runs 240 steps a second."))

	# --- Sound ---
	var sound := _page(tabs, "Sound")
	for pair in VOLUMES:
		var key: String = pair[0]
		var row := _row(sound, str(pair[1]))
		var slider := _slider(0, 100, 1)
		slider.value_changed.connect(func(value: float) -> void:
			values[key] = int(value)
			_commit())
		slider.drag_ended.connect(func(_moved: bool) -> void: Sound.play_ui("click"))
		row.add_child(slider)
		var label := Label.new()
		row.add_child(label)
		_volume_sliders[key] = slider
		_volume_labels[key] = label
	sound.add_child(_note("Machines are motors, jets, rockets, propellers and engines.\nEffects are guns, explosions and things falling down."))

	# --- World ---
	var world := _page(tabs, "World")
	var sky_row := _row(world, "Time of day")
	_sky = OptionButton.new()
	_sky.focus_mode = Control.FOCUS_NONE
	_sky.add_item("Day and night (20 min)")
	_sky.add_item("Always day")
	_sky.add_item("Always night")
	_sky.item_selected.connect(_on_sky)
	sky_row.add_child(_sky)
	var jump_row := _row(world, "Jump to")
	for pair in [["Dawn", 0.0], ["Noon", 0.25], ["Dusk", 0.47], ["Night", 0.75]]:
		var jump := _small_button(str(pair[0]))
		var fraction: float = pair[1]
		jump.pressed.connect(func() -> void: jump_time.emit(fraction))
		jump_row.add_child(jump)
	_crash = CheckBox.new()
	_crash.text = "Crash damage (hard knocks break parts)"
	_crash.focus_mode = Control.FOCUS_NONE
	_crash.toggled.connect(func(on: bool) -> void:
		values["crash_damage"] = on
		_commit())
	world.add_child(_crash)
	_check(world, "structural_failure", "Structural failure (overloaded parts break; see the stress view, key 9)")
	_check(world, "player_damage", "You can be hurt (crashes, falls, blasts, too many g)")
	_check(world, "random_disasters", "Random disasters (a tornado, hurricane, tsunami or eruption every 20 to 40 minutes)")
	_check(world, "traffic", "Traffic: cars on the highways and planes between the airports")
	var events_row := _row(world, "Event distance")
	_events = OptionButton.new()
	_events.focus_mode = Control.FOCUS_NONE
	for km in Settings.EVENT_DISTANCES:
		_events.add_item("%d km%s" % [int(km), "  (the whole map)" if int(km) == 50 else ""])
	_events.item_selected.connect(func(index: int) -> void:
		values["event_distance"] = Settings.EVENT_DISTANCES[index]
		_commit())
	events_row.add_child(_events)
	world.add_child(_note("How far from you disasters can start and are fully simulated (lava bombs,\ntornado damage). Further off they are still drawn. Higher costs speed."))
	world.add_child(_note("A day lasts 20 minutes: 10 of daylight, 10 of night.\nRunway lights come on after dusk.\nCrash damage: a body whose speed changes faster than 20 g (over 50 ms) damages\nevery part in it, by its mass: heavy, weak parts break first."))

	# --- Controls ---
	var controls := _page(tabs, "Controls")
	var keys := Label.new()
	keys.text = "\n".join(PackedStringArray(CONTROLS))
	keys.add_theme_font_size_override("font_size", 13)
	controls.add_child(keys)

	var close := _small_button("Close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: visible = false)
	column.add_child(close)


## A check box for an on/off setting.
func _check(parent: Control, key: String, text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(on: bool) -> void:
		values[key] = on
		_commit())
	parent.add_child(box)
	_checks[key] = box
	return box


func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	return page


func _row(parent: Control, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_caption(caption))
	return row


func _slider(low: float, high: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	return slider


func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: Sound.play_ui("click"))
	return button


func _note(text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.7)
	return note


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(130, 0)
	return label


func _preset(cap: int, resolution: int, msaa: String, shadows: bool, trees: float) -> void:
	if cap > 0:
		values["frame_mode"] = "cap"
		values["frame_cap"] = cap
	else:
		values["frame_mode"] = "vsync"
	values["render_scale"] = resolution
	values["msaa"] = msaa
	values["shadows"] = shadows
	values["tree_distance"] = trees
	values["event_distance"] = 5 if resolution < 100 else 30
	_commit()


func _show_values() -> void:
	_mode.select(MODES.find(str(values["frame_mode"])))
	_cap.set_value_no_signal(int(values["frame_cap"]))
	_cap.editable = values["frame_mode"] == "cap"
	_scale.set_value_no_signal(int(values["render_scale"]))
	_scale_label.text = "%d%%" % int(values["render_scale"])
	_msaa.select(Settings.MSAA.find(str(values["msaa"])))
	_shadows.set_pressed_no_signal(bool(values["shadows"]))
	_trees.set_value_no_signal(float(values["tree_distance"]))
	_trees_label.text = "%.1f km" % (float(values["tree_distance"]) / 1000.0)
	_fps.set_pressed_no_signal(bool(values["show_fps"]))
	_sky.select(Settings.SKIES.find(str(values["sky"])))
	_crash.set_pressed_no_signal(bool(values["crash_damage"]))
	_events.select(Settings.EVENT_DISTANCES.find(int(values["event_distance"])))
	for key in _checks:
		(_checks[key] as CheckBox).set_pressed_no_signal(bool(values.get(key, true)))
	for key in _volume_sliders:
		var slider: HSlider = _volume_sliders[key]
		slider.set_value_no_signal(int(values[key]))
		(_volume_labels[key] as Label).text = "%d%%" % int(values[key])


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
