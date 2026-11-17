extends CanvasLayer
## The title screen, the pause menu, and the windows they open: Settings and
## the parts guide. Above the rest of the interface, and working while the
## game is paused.
##
## The game opens on the title screen, paused, with the world behind it. Esc
## (with the cursor free) pauses and brings up the pause menu; Esc again
## goes back. F1 opens the parts guide.

const Sound = preload("res://scripts/sound.gd")
const PartsGuide = preload("res://scripts/parts_guide.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")

signal respawn_requested

var player: Node = null       # player.gd
var hud: Node = null          # hud.gd, for the full map
var settings_panel: PanelContainer   # settings_panel.gd
var guide: PanelContainer            # parts_guide.gd
var version := ""

var _dim: ColorRect
var _title: Control
var _pause: Control
var _back_to: Control = null  # the menu to show again when a window closes


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.05, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	_title = _build_title()
	add_child(_title)
	_pause = _build_pause()
	add_child(_pause)

	settings_panel = SettingsPanel.new()
	add_child(_centred(settings_panel))
	settings_panel.closed.connect(_on_window_closed)
	guide = PartsGuide.new()
	add_child(_centred(guide))
	guide.closed.connect(_on_window_closed)


## Holds a window in the middle of the screen without blocking clicks around it.
func _centred(window: Control) -> CenterContainer:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(window)
	return centre


func _menu_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(280, 46)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(func() -> void:
		Sound.play_ui("click")
		action.call())
	parent.add_child(button)
	return button


func _build_title() -> Control:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.09, 0.78)
	shade.anchor_bottom = 1.0
	shade.offset_right = 520.0
	screen.add_child(shade)
	var column := VBoxContainer.new()
	column.position = Vector2(70, 110)
	column.add_theme_constant_override("separation", 14)
	screen.add_child(column)
	var name_label := Label.new()
	name_label.text = "IDEAL WORLD"
	name_label.add_theme_font_size_override("font_size", 62)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	column.add_child(name_label)
	var subtitle := Label.new()
	subtitle.text = "Build it. Spawn it. Fly it over Flathead Lake."
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.modulate = Color(1, 1, 1, 0.85)
	column.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	column.add_child(gap)
	_menu_button(column, "Play", start_game)
	_menu_button(column, "Parts guide", func() -> void: _open(guide, _title))
	_menu_button(column, "Settings", func() -> void: _open(settings_panel, _title))
	_menu_button(column, "Quit", func() -> void: get_tree().quit())
	var footer := Label.new()
	footer.name = "Footer"
	footer.add_theme_font_size_override("font_size", 12)
	footer.modulate = Color(1, 1, 1, 0.6)
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = 70.0
	footer.offset_top = -70.0
	footer.text = "Elevation: AWS Terrain Tiles (Mapzen)    Towns: © OpenStreetMap contributors, ODbL"
	screen.add_child(footer)
	return screen


func _build_pause() -> Control:
	var screen := CenterContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	var panel := PanelContainer.new()
	screen.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "Paused"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	_menu_button(column, "Resume", resume)
	_menu_button(column, "Parts guide", func() -> void: _open(guide, _pause))
	_menu_button(column, "Settings", func() -> void: _open(settings_panel, _pause))
	_menu_button(column, "Back to the build pad", func() -> void:
		resume()
		respawn_requested.emit())
	_menu_button(column, "Title screen", show_title)
	_menu_button(column, "Quit game", func() -> void: get_tree().quit())
	return screen


# --- Showing and hiding ----------------------------------------------------------

func show_title() -> void:
	_pause.visible = false
	_title.visible = true
	(_title.get_node("Footer") as Label).text = "%s    Elevation: AWS Terrain Tiles (Mapzen)    Towns: © OpenStreetMap contributors, ODbL" % version
	_set_paused(true)


func start_game() -> void:
	_title.visible = false
	_set_paused(false)


func pause() -> void:
	_pause.visible = true
	_set_paused(true)


func resume() -> void:
	_pause.visible = false
	_set_paused(false)


func is_open() -> bool:
	return _title.visible or _pause.visible or settings_panel.visible or guide.visible


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_dim.visible = paused
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif player != null and player.has_method("is_first_person") and player.is_first_person():
		player.cursor_free = false   # back into first person: take the mouse again


## Opens a window from a menu, hiding the menu until the window closes.
func _open(window: Control, from: Control) -> void:
	_back_to = from
	from.visible = false
	window.visible = true


func _on_window_closed() -> void:
	if _back_to != null and not settings_panel.visible and not guide.visible:
		_back_to.visible = true
		_back_to = null


func toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible


func toggle_guide() -> void:
	guide.visible = not guide.visible


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F1:
		toggle_guide()
		get_viewport().set_input_as_handled()
		return
	if key.physical_keycode != KEY_ESCAPE:
		return
	# Esc closes whatever is open, the topmost first.
	if guide.visible:
		guide.visible = false
	elif settings_panel.visible:
		settings_panel.visible = false
	elif _pause.visible:
		resume()
	elif _title.visible:
		return
	elif hud != null and hud.has_method("world_map_open") and hud.world_map_open():
		hud.toggle_world_map()
	elif player != null and player.is_first_person() and not bool(player.cursor_free):
		return   # first Esc in first person frees the cursor (player.gd)
	else:
		pause()
	get_viewport().set_input_as_handled()
