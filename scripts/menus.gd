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
const Profile = preload("res://scripts/profile.gd")

signal respawn_requested
signal runway_requested   # take the build to a runway
signal slot_chosen(slot: int)   # a save slot was picked to play (main.gd restores its clock)

var player: Node = null       # player.gd
var hud: Node = null          # hud.gd, for the full map
var settings_panel: PanelContainer   # settings_panel.gd
var guide: PanelContainer            # parts_guide.gd
var version := ""

var _dim: ColorRect
var _title: Control
var _pause: Control
var _back_to: Control = null  # the menu to show again when a window closes
var _slots: Control             # the three save slots, after Play
var _slot_cards: VBoxContainer
var _delete_armed := 0
var playing := false            # a slot has been picked this session


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
	_slots = _build_slots()
	add_child(_slots)

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
	button.focus_mode = Control.FOCUS_ALL
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
	_menu_button(column, "Play", show_slots)
	_menu_button(column, "Parts guide", func() -> void: _open(guide, _title))
	_menu_button(column, "Settings", func() -> void: _open(settings_panel, _title))
	_menu_button(column, "Quit", func() -> void:
		get_tree().quit())
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
	_menu_button(column, "Take the build to a runway", func() -> void:
		resume()
		runway_requested.emit())
	_menu_button(column, "Switch save slot", func() -> void:
		Profile.save()
		_pause.visible = false
		show_slots())
	_menu_button(column, "Title screen", show_title)
	_menu_button(column, "Quit game", func() -> void:
		Profile.save()
		get_tree().quit())
	return screen


# --- Save slots -------------------------------------------------------------------

func _build_slots() -> Control:
	var screen := CenterContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.visible = false
	var panel := PanelContainer.new()
	screen.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "Choose a save slot"
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	var about := Label.new()
	about.text = "Each slot keeps its own money, races won, missions, ghosts and bird guide.\nYour builds, sub-assemblies and photos are shared by all three."
	about.add_theme_font_size_override("font_size", 14)
	about.modulate = Color(1, 1, 1, 0.8)
	column.add_child(about)
	_slot_cards = VBoxContainer.new()
	_slot_cards.add_theme_constant_override("separation", 10)
	column.add_child(_slot_cards)
	var back := Button.new()
	back.text = "Back"
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func() -> void:
		_slots.visible = false
		if playing:
			_pause.visible = true
		else:
			_title.visible = true)
	column.add_child(back)
	return screen


func show_slots() -> void:
	_title.visible = false
	_slots.visible = true
	_delete_armed = 0
	_fill_slots()


func _fill_slots() -> void:
	for child in _slot_cards.get_children():
		child.queue_free()
	for which in range(1, Profile.SLOTS + 1):
		var summary := Profile.slot_summary(which)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(560, 0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		var title := Label.new()
		title.text = "Slot %d%s" % [which, "   (playing)" if playing and which == Profile.slot else ""]
		title.add_theme_font_size_override("font_size", 20)
		words.add_child(title)
		var facts := Label.new()
		if bool(summary["exists"]):
			facts.text = "%s   ·   %d races won   ·   %d birds photographed\nLast played %s" % [
				Profile.money(int(summary["cash"])), int(summary["won"]), int(summary["photographed"]),
				str(summary["last_played"]).replace("T", " ").substr(0, 16)]
		else:
			facts.text = "Empty"
		facts.add_theme_font_size_override("font_size", 14)
		facts.modulate = Color(1, 1, 1, 0.8)
		words.add_child(facts)
		if bool(summary["exists"]):
			_slot_button(row, "Continue", func() -> void: _play_slot(which, false))
		_slot_button(row, "Start over?" if _delete_armed == -which else "New game", func() -> void: _play_slot(which, true))
		if bool(summary["exists"]):
			_slot_button(row, "Delete" if _delete_armed != which else "Sure?", func() -> void:
				if _delete_armed == which:
					Profile.delete_slot(which)
					_delete_armed = 0
				else:
					_delete_armed = which
				_fill_slots())
		_slot_cards.add_child(card)


func _slot_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(104, 40)
	button.pressed.connect(func() -> void:
		Sound.play_ui("click")
		action.call())
	parent.add_child(button)


func _play_slot(which: int, fresh: bool) -> void:
	if playing:
		Profile.save()
	if fresh and Profile.slot_exists(which) and _delete_armed != -which:
		# Starting a used slot over asks once more.
		_delete_armed = -which
		_fill_slots()
		return
	if fresh:
		Profile.new_game(which)
	else:
		Profile.use_slot(which)
	_delete_armed = 0
	_slots.visible = false
	playing = true
	slot_chosen.emit(which)
	start_game()


# --- Showing and hiding ----------------------------------------------------------

func show_title() -> void:
	_pause.visible = false
	_title.visible = true
	(_title.get_node("Footer") as Label).text = "%s    Elevation: AWS Terrain Tiles (Mapzen)    Towns: © OpenStreetMap contributors, ODbL" % version
	_set_paused(true)


func start_game() -> void:
	_title.visible = false
	_slots.visible = false
	_set_paused(false)
	get_viewport().gui_release_focus()


func pause() -> void:
	_pause.visible = true
	_set_paused(true)


func resume() -> void:
	_pause.visible = false
	_set_paused(false)
	get_viewport().gui_release_focus()


func is_open() -> bool:
	return _title.visible or _pause.visible or _slots.visible or settings_panel.visible or guide.visible


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


## A controller works the menus: Menu (Options) opens the pause menu or
## takes the first button of an open one, the D-pad moves between buttons,
## A (Cross) presses and B (Circle) goes back, like Esc.
func _on_pad(button: InputEventJoypadButton) -> void:
	if not button.pressed:
		return
	var open_menu: Control = null
	for menu in [_slots, _pause, _title]:
		if (menu as Control).visible:
			open_menu = menu
			break
	if button.button_index == JOY_BUTTON_START:
		if open_menu == _pause:
			resume()
		elif open_menu == null and not settings_panel.visible and not guide.visible:
			pause()
			_focus_first(_pause)
		elif open_menu != null:
			_focus_first(open_menu)
		get_viewport().set_input_as_handled()
	elif button.button_index == JOY_BUTTON_B and (open_menu != null or settings_panel.visible or guide.visible):
		if guide.visible:
			guide.visible = false
		elif settings_panel.visible:
			settings_panel.visible = false
		elif open_menu == _pause:
			resume()
		elif open_menu == _slots:
			_slots.visible = false
			(_pause if playing else _title).visible = true
			_focus_first(_pause if playing else _title)
		get_viewport().set_input_as_handled()
	elif open_menu != null and get_viewport().gui_get_focus_owner() == null:
		_focus_first(open_menu)


## Gives the first button in a menu the controller's focus.
func _focus_first(menu: Control) -> void:
	var buttons := menu.find_children("*", "Button", true, false)
	for item in buttons:
		var found := item as Button
		if found.is_visible_in_tree() and found.focus_mode != Control.FOCUS_NONE:
			found.grab_focus()
			return


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_on_pad(event as InputEventJoypadButton)
		return
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
