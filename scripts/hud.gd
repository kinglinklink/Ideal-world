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
const Minimap = preload("res://scripts/minimap.gd")
const WorldMap = preload("res://scripts/world_map.gd")
const Sound = preload("res://scripts/sound.gd")
const MapInfo = preload("res://scripts/map_info.gd")

const SNAP_STOPS := [1.0, 0.5, 0.25, 0.1, 0.05, 0.025, 0.01, 0.005]   # in cells
const AXIS_NAMES := ["X", "Y", "Z"]
## Shown in the bottom-right corner, so it is easy to tell which copy of the
## game is running. Raised with every pushed change.
const VERSION := "Build 26"
const MESSAGE_SECONDS := 3.5
const TURN_KEYS := ["R", "T", "Y"]
const AXIS_COLORS := [Color(0.95, 0.25, 0.3), Color(0.3, 0.85, 0.3), Color(0.3, 0.5, 1.0)]   # X, Y, Z
## Short names for the category tabs. A category not listed uses its own name.
const TAB_LABELS := {
	"Structural": "Struct.",
	"Advanced": "Adv.",
	"Mechanical": "Mech",
	"Fluid and Engine": "Fluids",
}

signal garage_button_pressed
signal weather_pressed
signal respawn_pressed

var controller: Node = null          # build_controller.gd
var grid: Node = null                # build_grid.gd
var player: CharacterBody3D = null   # player.gd

var _tool_buttons: Array = []
var _panels: Array = []              # one panel per tool, in Tool order; null for Place, which uses the parts list
var _part_buttons: Dictionary = {}   # part id -> Button
var _category_buttons: Dictionary = {}   # category name -> its tab
var _part_category := ""             # the category whose parts are listed; "" while the list is folded away
var _last_category := "Basic"        # the category that opens when the Place tool is picked up
var _shown_tool: int = BuildController.Tool.NONE   # the tool the interface last showed
var _parts_title: Label
var _part_search: LineEdit
var _material_buttons: Dictionary = {}
var _place_brush_label: Label
var _transform_info: Label
var _snap_option: OptionButton
var _config_title: Label
var _config_spins: Array = []
var _config_captions: Array = []     # the three dimension labels beside the spin boxes
var _config_info: Label
var _build_info: Label
var _color_button: ColorPickerButton
var _pick_material_button: Button
var _pick_color_button: Button
var _paint_brush_label: Label
var _count_label: Label
var _speed_label: Label
var _fps_label: Label
var _settings_panel: PanelContainer   # settings_panel.gd
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
var _minimap: Control
var daylight: Node = null            # daylight.gd, for the clock
var menus: Node = null               # menus.gd: settings, guide, pause
var _clock_label: Label
var _part_total := 0
var fleet: Node = null               # fleet.gd
var _fleet_panel: PanelContainer
var _fleet_saves: ItemList
var _fleet_list: ItemList
var _waypoint_label: Label
var _world_map: Control              # world_map.gd, opened with M
var _garage_button: Button
var _spawn_button: Button
var _tabs: Control                   # the category tabs up the left edge
var _parts_panel: Control            # the parts list that opens beside the tabs
var _tool_panel: Control             # holds the Delete, Config, Transform and Paint panels
var _build_bar: Control              # search and rotation, beside the Spawn button
var _build_only: Array = []          # controls that are hidden while the build is spawned
var _seat_label: Label
var _modules_panel: PanelContainer
var _modules_list: ItemList
var _module_name: LineEdit
var _modules_status: Label


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
	controller.connect("spawn_changed", _on_changed_with_value)
	grid.connect("parts_changed", _on_changed)
	grid.connect("parts_changed", _on_parts_sound)
	controller.connect("spawn_changed", _on_spawn_sound)
	_part_total = grid.part_count()
	_refresh()


## The buildings and areas the mini map should draw.
func set_map_features(features: Array) -> void:
	_minimap.features = features


## Tells the interface whether the garage door is open, so the button at the
## top of the screen offers the opposite.
func set_garage_open(open: bool) -> void:
	_garage_button.text = "Close hangar" if open else "Open hangar"


## Loads and applies the saved settings. `forest` is forest.gd,
## `the_daylight` daylight.gd and `panel` the settings window (settings_panel.gd).
func setup_settings(forest: Node, the_daylight: Node, panel: PanelContainer) -> void:
	daylight = the_daylight
	_settings_panel = panel
	_settings_panel.setup(forest)
	_settings_panel.connect("changed", _on_settings_changed)
	_settings_panel.connect("jump_time", _on_jump_time)
	_on_settings_changed(_settings_panel.values)


func _on_settings_changed(values: Dictionary) -> void:
	_fps_label.visible = bool(values.get("show_fps", true))
	if daylight != null and str(values.get("sky", "cycle")) != daylight.mode:
		daylight.set_mode(str(values.get("sky", "cycle")))
	if daylight != null:
		daylight.set_shadows(bool(values.get("shadows", true)))


func _on_jump_time(fraction: float) -> void:
	if daylight == null:
		return
	if daylight.mode != "cycle":
		_settings_panel.values["sky"] = "cycle"   # a jump starts the clock again
		_settings_panel.call("_commit")
	daylight.set_time(fraction)


func set_fleet(the_fleet: Node) -> void:
	fleet = the_fleet
	_minimap.fleet = the_fleet


func _build_fleet_panel() -> PanelContainer:
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
	box.add_child(_label("Fleet", 18))
	var note := _label("Spawn a saved build out into the world as a vehicle of its own, in front of you.\nIt stays, working, until you despawn it. The build on the pad is separate.", 12)
	box.add_child(note)
	box.add_child(_label("Saved builds"))
	_fleet_saves = ItemList.new()
	_fleet_saves.custom_minimum_size = Vector2(440, 170)
	_fleet_saves.focus_mode = Control.FOCUS_NONE
	_fleet_saves.item_activated.connect(func(_index: int) -> void: _spawn_from_fleet())
	box.add_child(_fleet_saves)
	var spawn_row := _row()
	box.add_child(spawn_row)
	var spawn_button := _button("Spawn in front of me", 200.0)
	spawn_button.pressed.connect(_spawn_from_fleet)
	spawn_row.add_child(spawn_button)
	box.add_child(_label("Out in the world"))
	_fleet_list = ItemList.new()
	_fleet_list.custom_minimum_size = Vector2(440, 120)
	_fleet_list.focus_mode = Control.FOCUS_NONE
	box.add_child(_fleet_list)
	var row := _row()
	box.add_child(row)
	var despawn := _button("Despawn", 110.0)
	despawn.pressed.connect(func() -> void:
		var picked := _fleet_list.get_selected_items()
		if fleet != null and not picked.is_empty():
			fleet.despawn(picked[0])
		_refresh_fleet())
	row.add_child(despawn)
	var despawn_all := _button("Despawn all", 120.0)
	despawn_all.pressed.connect(func() -> void:
		if fleet != null:
			fleet.despawn_all()
		_refresh_fleet())
	row.add_child(despawn_all)
	var close := _button("Close", 90.0)
	close.pressed.connect(func() -> void: _fleet_panel.visible = false)
	row.add_child(close)
	return panel


func _refresh_fleet() -> void:
	_fleet_saves.clear()
	for save_name in SaveManager.list_saves():
		_fleet_saves.add_item(str(save_name))
	_fleet_list.clear()
	if fleet == null:
		return
	for item in fleet.vehicles:
		var vehicle: Dictionary = item
		_fleet_list.add_item("%s   (%d parts, %.0f kg)" % [vehicle["name"], int(vehicle["parts"]), float(vehicle["mass"])])


func _spawn_from_fleet() -> void:
	var picked := _fleet_saves.get_selected_items()
	if fleet == null or picked.is_empty():
		_on_message("Pick a saved build first.")
		return
	var message: String = fleet.spawn_save(_fleet_saves.get_item_text(picked[0]), player)
	_on_message(message)
	Sound.play_ui("spawn")
	_refresh_fleet()


## Opens or closes the full map (the M key).
func toggle_world_map() -> void:
	_world_map.toggle()


func world_map_open() -> bool:
	return _world_map.visible


## The map of the lake behind the mini map, and the places to label on it.
func set_world_map(world: Dictionary, places: Array) -> void:
	_minimap.set_world(world, places)


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
	button.pressed.connect(func() -> void: Sound.play_ui("click"))
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
			"WASD walk or swim   Shift run   Space jump (swim up)   E sit, or talk   Scroll zoom\n"
			+ "Hold right mouse to look   Esc free cursor (first person)   P back to the hangar   M map\n"
			+ "Spawned: 0 replay the last 30 s   9 stress view   F2 give up a race or cargo run\n"
			+ "1 Place   2 Delete   3 Config   4 Transform   5 Paint (press again to put away)   Left click use tool\n"
			+ "R / T / Y turn a part   Enter or the Spawn button (bottom left) sets the build loose", 14))
	help.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	help.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(help)

	# Top centre: the garage button, with messages from the tools under it.
	var top := _column()
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var top_buttons := _row()
	top_buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_buttons)
	_garage_button = _button("Open hangar", 150.0)
	_garage_button.pressed.connect(_on_garage_button)
	top_buttons.add_child(_garage_button)
	var respawn := _button("Respawn (P)", 120.0)
	respawn.tooltip_text = "Back to the build pad"
	respawn.pressed.connect(func() -> void: respawn_pressed.emit())
	top_buttons.add_child(respawn)
	var settings := _button("Settings", 100.0)
	settings.pressed.connect(func() -> void:
		if menus != null:
			menus.toggle_settings())
	top_buttons.add_child(settings)
	var fleet_button := _button("Fleet", 80.0)
	fleet_button.tooltip_text = "Spawn saved builds out into the world as vehicles of their own"
	fleet_button.pressed.connect(func() -> void:
		_fleet_panel.visible = not _fleet_panel.visible
		if _fleet_panel.visible:
			_refresh_fleet())
	top_buttons.add_child(fleet_button)
	var weather_button := _button("Weather", 90.0)
	weather_button.tooltip_text = "The weather, the season, the wind, and disasters to set off"
	weather_button.pressed.connect(func() -> void: weather_pressed.emit())
	top_buttons.add_child(weather_button)
	var guide := _button("Guide (F1)", 110.0)
	guide.tooltip_text = "What every part does, its settings, inputs and outputs"
	guide.pressed.connect(func() -> void:
		if menus != null:
			menus.toggle_guide())
	top_buttons.add_child(guide)
	_message_label = _outlined(_label("", 18))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	top.add_child(_message_label)

	# Crosshair, screen centre, shown while the mouse is captured.
	_crosshair = _label("+", 22)
	_crosshair.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_crosshair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(_crosshair)

	# Bottom centre: the tool bar, with a line above it for the seat prompt.
	var bottom := _column()
	bottom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_seat_label = _outlined(_label("", 18))
	_seat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_seat_label)
	var toolbar := _row()
	toolbar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(toolbar)
	_build_only.append(toolbar)
	var tool_names: Array = BuildController.TOOL_NAMES
	for index in tool_names.size():
		var tool_button := _button("%d  %s" % [index + 1, tool_names[index]], 116.0, true)
		tool_button.custom_minimum_size = Vector2(116, 56)
		tool_button.pressed.connect(_on_tool_button.bind(index))
		toolbar.add_child(tool_button)
		_tool_buttons.append(tool_button)

	# Bottom left: category tabs up the edge of the screen, with the parts
	# list or the current tool's panel opening beside them, and under them a
	# bar holding Spawn, the part search and the rotation buttons.
	var left := _column()
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.size_flags_vertical = Control.SIZE_SHRINK_END
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left)

	var menu := _row()
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(menu)
	_tabs = _build_category_tabs()
	_tabs.size_flags_vertical = Control.SIZE_SHRINK_END
	menu.add_child(_tabs)
	_build_only.append(_tabs)
	_parts_panel = _build_parts_panel()
	_parts_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	menu.add_child(_parts_panel)

	# One panel per tool, only the active one shown. Place has none of its own.
	_tool_panel = PanelContainer.new()
	_tool_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	menu.add_child(_tool_panel)
	var side_margin := MarginContainer.new()
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		side_margin.add_theme_constant_override(margin_name, 8)
	_tool_panel.add_child(side_margin)
	var stack := _column()
	side_margin.add_child(stack)
	_panels = [
		null,
		_build_delete_panel(),
		_build_config_panel(),
		_build_transform_panel(),
		_build_paint_panel(),
	]
	for panel in _panels:
		if panel != null:
			stack.add_child(panel)

	# The bar is pinned to the corner on its own, so that nothing in the
	# column above it can move or hide it. A spacer keeps the column clear of it.
	var bar := _build_bottom_bar()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.size_flags_vertical = Control.SIZE_SHRINK_END
	root.add_child(bar)
	_build_only.append(_build_bar)
	var bar_space := Control.new()
	bar_space.custom_minimum_size = Vector2(0, 58)
	bar_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(bar_space)

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
	_build_only.append(history)
	var file_row := _row()
	file_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	file_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readouts.add_child(file_row)
	_build_only.append(file_row)
	var modules_button := _button("Modules", 110.0)
	modules_button.tooltip_text = "Save a selection (a wing, an engine pod) and put it into any build"
	modules_button.pressed.connect(func() -> void:
		_modules_panel.visible = not _modules_panel.visible
		if _modules_panel.visible:
			_refresh_modules("Select parts with the Transform tool, name the module and save it."))
	file_row.add_child(modules_button)
	var saves_button := _button("Saves", 110.0)
	saves_button.pressed.connect(_on_saves_button)
	file_row.add_child(saves_button)
	_speed_label = _readout(readouts)
	_waypoint_label = _readout(readouts)
	_clock_label = _readout(readouts)
	_fps_label = _readout(readouts)
	_readout(readouts).text = "Ideal World  %s" % VERSION

	# Mini map, top right.
	_minimap = Minimap.new()
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	_minimap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_minimap.player = player
	root.add_child(_minimap)

	# The full map, over everything, opened with M.
	_world_map = WorldMap.new()
	_world_map.minimap = _minimap
	_world_map.player = player
	add_child(_world_map)

	# Saves window, screen centre, hidden until the Saves button is pressed.
	_saves_panel = _build_saves_panel()
	root.add_child(_saves_panel)

	# Fleet window, screen centre, from the Fleet button.
	_fleet_panel = _build_fleet_panel()
	root.add_child(_fleet_panel)

	# Modules window, screen centre, from the Modules button.
	_modules_panel = _build_modules_panel()
	root.add_child(_modules_panel)


func _readout(parent: Control) -> Label:
	var label := _outlined(_label(""))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(label)
	return label


## The category tabs that run up the left edge of the screen.
func _build_category_tabs() -> Control:
	var tabs := _column()
	tabs.add_theme_constant_override("separation", 4)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var categories: Array = PartLibrary.CATEGORIES.duplicate()
	categories.reverse()   # Basic sits at the bottom, nearest the tool bar
	for category in categories:
		var category_name: String = category
		var tab := _button(str(TAB_LABELS.get(category_name, category_name)), 92.0, true)
		tab.custom_minimum_size = Vector2(92, 42)
		tab.tooltip_text = "%s parts" % category_name
		tab.pressed.connect(_on_category_tab.bind(category_name))
		tabs.add_child(tab)
		_category_buttons[category_name] = tab
	return tabs


## The list of parts that opens beside the tabs. It is hidden until a tab is
## opened or something is typed in the search box.
func _build_parts_panel() -> Control:
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(margin_name, 8)
	panel.add_child(margin)
	var listing := _column()
	margin.add_child(listing)
	_parts_title = _label("", 18)
	listing.add_child(_parts_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(210, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	listing.add_child(scroll)
	var buttons := _column()
	buttons.add_theme_constant_override("separation", 4)
	scroll.add_child(buttons)
	# Every part's button lives in the one list; the filter shows the right ones.
	for id in PartLibrary.part_ids():
		var part_button := _button(PartLibrary.part_name(id), 194.0, true)
		part_button.pressed.connect(_on_part_button.bind(id))
		buttons.add_child(part_button)
		_part_buttons[id] = part_button
	_place_brush_label = _label("", 13)
	listing.add_child(_place_brush_label)
	return panel


## The bar along the bottom left: Spawn, the part search and the rotation buttons.
func _build_bottom_bar() -> Control:
	var bar := _row()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_spawn_button = _button("Spawn", 110.0)
	_spawn_button.custom_minimum_size = Vector2(110, 56)
	_tint_button(_spawn_button, Color(0.35, 0.85, 0.4))   # bright green, hard to miss
	_spawn_button.pressed.connect(_on_spawn_button)
	bar.add_child(_spawn_button)

	# Everything else in the bar belongs to building and hides while spawned.
	_build_bar = _row()
	_build_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_build_bar)

	var search_box := _column()
	search_box.add_theme_constant_override("separation", 2)
	search_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar.add_child(search_box)
	_part_search = LineEdit.new()
	_part_search.custom_minimum_size = Vector2(190, 30)
	_part_search.placeholder_text = "Search parts"
	_part_search.clear_button_enabled = true
	_part_search.text_changed.connect(_on_part_search_changed)
	_part_search.text_submitted.connect(_on_part_search_submitted)
	search_box.add_child(_part_search)
	_count_label = _outlined(_label(""))
	search_box.add_child(_count_label)

	var turn_box := _column()
	turn_box.add_theme_constant_override("separation", 2)
	turn_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_bar.add_child(turn_box)
	var turn_row := _row()
	turn_row.add_theme_constant_override("separation", 0)
	turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_box.add_child(turn_row)
	for axis in 3:
		var turn_button := _button(AXIS_NAMES[axis], 40.0)
		turn_button.tooltip_text = "Turn 90° about %s (key %s)" % [AXIS_NAMES[axis], TURN_KEYS[axis]]
		_tint_button(turn_button, AXIS_COLORS[axis])
		turn_button.pressed.connect(_on_rotation_button.bind(axis))
		turn_row.add_child(turn_button)
	var turn_caption := _outlined(_label("Rotation", 13))
	turn_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_box.add_child(turn_caption)
	return bar


## Gives a button a flat background in one colour, with black lettering.
func _tint_button(button: Button, color: Color) -> void:
	var looks := {"normal": color, "hover": color.lightened(0.25), "pressed": color.darkened(0.25)}
	for state in looks:
		var state_name: String = state
		var shade: Color = looks[state_name]
		var box := StyleBoxFlat.new()
		box.bg_color = shade
		box.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state_name, box)
	for font_state in ["font_color", "font_hover_color", "font_pressed_color"]:
		var font_name: String = font_state
		button.add_theme_color_override(font_name, Color.BLACK)
	button.add_theme_font_size_override("font_size", 18)


## Shows the parts of the open category, or every part matching the search,
## and opens or folds away the list to suit.
func _apply_part_filter() -> void:
	var query := _part_search.text.strip_edges().to_lower()
	var placing: bool = controller.current_tool == BuildController.Tool.PLACE
	for id in _part_buttons:
		var part_id: String = id
		var part_button: Button = _part_buttons[id]
		if query != "":
			part_button.visible = PartLibrary.part_name(part_id).to_lower().contains(query)
		else:
			part_button.visible = PartLibrary.category(part_id) == _part_category
	if query != "":
		_parts_title.text = "Search results"
	else:
		_parts_title.text = "%s parts" % _part_category
	for category_name in _category_buttons:
		var tab: Button = _category_buttons[category_name]
		tab.set_pressed_no_signal(placing and query == "" and category_name == _part_category)

	# The list is out of the way unless a tab is open or a search is typed.
	# The other tools show their own panel in the same spot.
	var is_spawned: bool = controller.spawned
	_parts_panel.visible = placing and not is_spawned and (query != "" or _part_category != "")
	var active_tool: int = controller.current_tool
	var has_panel: bool = active_tool >= 0 and active_tool < _panels.size() and _panels[active_tool] != null
	_tool_panel.visible = has_panel and not is_spawned


## Opens a category. Clicking the open category's tab folds the list away.
func _on_category_tab(category_name: String) -> void:
	_part_search.text = ""
	_part_search.release_focus()
	var placing: bool = controller.current_tool == BuildController.Tool.PLACE
	if placing and _part_category == category_name:
		_part_category = ""
	else:
		_part_category = category_name
		_last_category = category_name
		if not placing:
			controller.set_tool(BuildController.Tool.PLACE)
	_apply_part_filter()


func _on_part_search_changed(text: String) -> void:
	# Searching is part of placing, so it brings the Place tool out.
	if text.strip_edges() != "" and controller.current_tool != BuildController.Tool.PLACE:
		controller.set_tool(BuildController.Tool.PLACE)
	_apply_part_filter()


func _on_part_search_submitted(_text: String) -> void:
	_part_search.release_focus()


func _on_rotation_button(axis: int) -> void:
	controller.turn(axis)


func _on_spawn_button() -> void:
	_part_search.release_focus()
	controller.toggle_spawn()


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

	var place_button := _button("Paste in place")
	place_button.tooltip_text = "Paste the copy exactly where it came from, selected,\nthen step it with the arrows or the Move buttons (Ctrl+Shift+V)"
	place_button.pressed.connect(_on_paste_in_place_button)
	panel.add_child(place_button)

	var all_button := _button("Select all")
	all_button.pressed.connect(_on_select_all_button)
	panel.add_child(all_button)

	panel.add_child(_label(
			"Click selects, Shift+click adds\n"
			+ "Arrows and PgUp / PgDn move\n"
			+ "R / T / Y turn 90°\n"
			+ "Ctrl+C copy, Ctrl+X cut\n"
			+ "Paste, then click where it goes\n"
			+ "(or point and press Ctrl+V);\n"
			+ "the copy rests on the surface\n"
			+ "Ctrl+Shift+V pastes in place\n"
			+ "Ctrl+Z undo, Ctrl+Y redo", 13))
	return panel


func _build_config_panel() -> Control:
	var panel := _column()
	_config_title = _label("")
	panel.add_child(_config_title)

	for axis in 3:
		var size_row := _row()
		var caption := _outlined(_label("Size %s (blocks)" % AXIS_NAMES[axis]))
		caption.custom_minimum_size = Vector2(170, 0)
		# Colored like the axis lines drawn on the selected part.
		caption.add_theme_color_override("font_color", (AXIS_COLORS[axis] as Color).lightened(0.25))
		size_row.add_child(caption)
		_config_captions.append(caption)
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

	# Copy this part's size and settings, and paste them onto other parts.
	var config_copy_row := _row()
	panel.add_child(config_copy_row)
	var copy_config_button := _button("Copy config", 150.0)
	copy_config_button.tooltip_text = "Remember this part's size and settings (Shift+C).\nKept until you copy another or press Spawn."
	copy_config_button.pressed.connect(_on_copy_config_button)
	config_copy_row.add_child(copy_config_button)
	var paste_config_button := _button("Paste config", 150.0)
	paste_config_button.tooltip_text = "Give the selected part the copied size and settings (Shift+V)"
	paste_config_button.pressed.connect(_on_paste_config_button)
	config_copy_row.add_child(paste_config_button)

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


func _build_modules_panel() -> PanelContainer:
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
	box.add_child(_label("Modules", 18))
	var about := _label("A module is part of a build saved on its own: a wing, an engine pod, a landing gear.\n"
			+ "Place one and it is put in like a paste: click where it goes with the Transform tool.", 13)
	box.add_child(about)
	_modules_list = ItemList.new()
	_modules_list.custom_minimum_size = Vector2(440, 220)
	_modules_list.focus_mode = Control.FOCUS_NONE
	_modules_list.item_selected.connect(func(index: int) -> void: _module_name.text = _modules_list.get_item_text(index))
	_modules_list.item_activated.connect(func(_index: int) -> void: _place_module())
	box.add_child(_modules_list)
	var name_row := _row()
	name_row.add_child(_label("Name"))
	_module_name = LineEdit.new()
	_module_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_name.placeholder_text = "Type a name for the module"
	name_row.add_child(_module_name)
	box.add_child(name_row)
	var actions := _row()
	box.add_child(actions)
	var save_button := _button("Save selection", 140.0)
	save_button.pressed.connect(func() -> void:
		var module_name := SaveManager.clean_name(_module_name.text)
		if module_name == "":
			_refresh_modules("Type a name first.")
			return
		var problem: String = controller.save_selection_as_module(module_name)
		_refresh_modules(problem if problem != "" else "Saved \"%s\"." % module_name))
	actions.add_child(save_button)
	var place_button := _button("Place", 104.0)
	place_button.pressed.connect(_place_module)
	actions.add_child(place_button)
	var delete_button := _button("Delete", 104.0)
	delete_button.pressed.connect(func() -> void:
		var module_name := SaveManager.clean_name(_module_name.text)
		if module_name != "" and _confirmed("delete module " + module_name):
			SaveManager.delete_module(module_name)
			_refresh_modules("Deleted \"%s\"." % module_name)
		elif module_name != "":
			_modules_status.text = "Click Delete again to delete \"%s\"." % module_name)
	actions.add_child(delete_button)
	var close_button := _button("Close", 104.0)
	close_button.pressed.connect(func() -> void: panel.visible = false)
	actions.add_child(close_button)
	_modules_status = _label("", 13)
	_modules_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_modules_status)
	return panel


func _refresh_modules(status: String) -> void:
	_modules_list.clear()
	for module_name in SaveManager.list_modules():
		_modules_list.add_item(str(module_name))
	_modules_status.text = status


func _place_module() -> void:
	var module_name := SaveManager.clean_name(_module_name.text)
	if module_name == "":
		_refresh_modules("Pick a module first.")
		return
	var problem: String = controller.place_module(module_name)
	if problem != "":
		_modules_status.text = problem
	else:
		_modules_panel.visible = false


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
	if daylight != null:
		_clock_label.text = "Time  %s" % daylight.clock_text()
	var reading: Array = _minimap.waypoint_reading()
	_waypoint_label.visible = not reading.is_empty()
	if not reading.is_empty():
		var metres: float = reading[0]
		var distance := "%d m" % int(metres) if metres < 2000.0 else "%.1f km" % (metres / 1000.0)
		_waypoint_label.text = "Waypoint  %s  bearing %03d°" % [distance, int(round(float(reading[1]))) % 360]
	var moving: Vector3 = player.ride_velocity if player.seated else player.velocity
	# Altitude is real: metres above sea level. The lake is at 881 m.
	_speed_label.text = "Speed  %.1f m/s    %.1f g    Altitude  %.0f m" % [
		moving.length(), float(player.g_force), player.global_position.y + MapInfo.BASE_ELEVATION,
	]
	var spin: float = controller.seat_spin()
	if spin > 0.5:
		_speed_label.text += "    Turning  %.0f°/s" % spin
	if not bool(controller.spawned):
		_speed_label.text = "Parts  %d    " % _part_total + _speed_label.text
	_crosshair.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_seat_label.text = controller.seat_prompt()
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message_label.text = ""


# --- Button handlers ---------------------------------------------------------

func _on_tool_button(index: int) -> void:
	controller.toggle_tool(index)   # pressing the tool in hand puts it away
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


func _on_paste_in_place_button() -> void:
	controller.paste_in_place()


func _on_copy_config_button() -> void:
	controller.copy_config()


func _on_paste_config_button() -> void:
	controller.paste_config()


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


func _on_garage_button() -> void:
	garage_button_pressed.emit()


func _on_message(text: String) -> void:
	_message_label.text = text
	# A longer message stays up longer.
	_message_time = MESSAGE_SECONDS + 2.0 * text.count("\n")


func _on_changed() -> void:
	_refresh()


## A knock when a part goes on or comes off the build.
func _on_parts_sound() -> void:
	var total: int = grid.part_count()
	if total > _part_total:
		Sound.play_ui("place")
	elif total < _part_total:
		Sound.play_ui("remove")
	_part_total = total


func _on_spawn_sound(spawned: Variant) -> void:
	if bool(spawned):
		Sound.play_ui("spawn")


func _on_changed_with_value(_value: Variant) -> void:
	_refresh()


# --- Refresh -----------------------------------------------------------------

static func _mass_text(kilograms: float) -> String:
	if kilograms >= 1000.0:
		return "%.2f t" % (kilograms / 1000.0)
	return "%.2f kg" % kilograms


## What a cannon of this size would do, by the design's ballistics: the bore
## is a fifth of the cannon's smaller cross dimension, the projectile is three
## bores long, and propellant pushes it down the barrel at an average 100 MPa.
static func _cannon_text(record: Dictionary) -> String:
	var size_m: Vector3 = Units.to_metres(record["size"])
	var bore: float = 0.2 * minf(size_m.x, size_m.y)
	var barrel: float = size_m.z
	var props: Dictionary = record.get("props", {})
	var projectile_name := str(props.get("projectile_material", "Steel"))
	var density: float = MaterialLibrary.density(MaterialLibrary.id_for_name(projectile_name))
	var bore_area := PI * bore * bore * 0.25
	var projectile_mass := density * bore_area * bore * 3.0
	var energy := 100000000.0 * bore_area * barrel   # joules
	var velocity := 0.0
	if projectile_mass > 0.0:
		velocity = sqrt(2.0 * energy / projectile_mass)
	return "\nBore: %.0f mm\nBarrel: %.2f m\nProjectile: %s of %s\nMuzzle velocity: %.0f m/s\nMuzzle energy: %.0f kJ (%.0f HP per hit)\nFastest fire: one shot per %.2f s" % [
		bore * 1000.0, barrel, _mass_text(projectile_mass), projectile_name,
		velocity, energy / 1000.0, energy / 1000.0, barrel * 0.5,
	]


## Brings every button and label in line with the controller's state.
func _refresh() -> void:
	var active_tool: int = controller.current_tool
	for index in _tool_buttons.size():
		var tool_button: Button = _tool_buttons[index]
		tool_button.set_pressed_no_signal(index == active_tool)
	for index in _panels.size():
		var panel: Control = _panels[index]
		if panel != null:
			panel.visible = index == active_tool
	# Picking up the Place tool brings its menu out, on the category last used.
	if active_tool != _shown_tool:
		if active_tool == BuildController.Tool.PLACE and _part_category == "":
			_part_category = _last_category
		_shown_tool = active_tool

	# Spawned or building: the build controls are put away while spawned.
	var is_spawned: bool = controller.spawned
	_spawn_button.text = "Build" if is_spawned else "Spawn"
	_spawn_button.tooltip_text = "Put the build back on the pad as it was" if is_spawned \
			else "Weld the build into moving bodies and let physics take over"
	for item in _build_only:
		var build_control: Control = item
		build_control.visible = not is_spawned
	if is_spawned:
		_saves_panel.visible = false
		_modules_panel.visible = false
	_apply_part_filter()

	# Place.
	var active_part: String = controller.part_type
	for id in _part_buttons:
		var part_button: Button = _part_buttons[id]
		part_button.set_pressed_no_signal(id == active_part)

	# Brush, shared by Place and Paint.
	var brush_material: String = controller.brush_material
	var brush_color: Color = controller.brush_color
	var brush_text := "Brush: %s" % MaterialLibrary.display_name(brush_material)
	_place_brush_label.text = brush_text
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
		var plain_captions: Array = PartLibrary.size_captions("")
		for spin_index in _config_spins.size():
			var idle_spin: SpinBox = _config_spins[spin_index]
			idle_spin.editable = false
			var idle_caption: Label = _config_captions[spin_index]
			idle_caption.text = plain_captions[spin_index]
	else:
		var type: String = record["type"]
		var size: Vector3i = record["size"]
		var material: String = record["material"]
		_config_title.text = "Config: %s" % PartLibrary.part_name(type)
		var captions: Array = PartLibrary.size_captions(type)
		for spin_index in _config_spins.size():
			var spin: SpinBox = _config_spins[spin_index]
			spin.editable = true
			spin.set_value_no_signal(float(size[spin_index]) / Units.UNITS_PER_CELL)
			var caption: Label = _config_captions[spin_index]
			caption.text = captions[spin_index]
		var mass: float = BuildGrid.mass_of(record)
		var size_m: Vector3 = Units.to_metres(size)
		_config_info.text = "Size: %.3f x %.3f x %.3f m\nMaterial: %s\nVolume: %.5f m³\nMass: %s\nHealth: %s" % [
			size_m.x, size_m.y, size_m.z,
			MaterialLibrary.display_name(material),
			BuildGrid.volume_of(record),
			_mass_text(mass),
			MaterialLibrary.health_text(material, mass),
		]
		if type == "large_cannon":
			_config_info.text += _cannon_text(record)

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
