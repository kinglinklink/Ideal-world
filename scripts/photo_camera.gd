extends CanvasLayer
## The camera tool (C) and the Photos window.
##
## C hides the interface behind a viewfinder. The wheel zooms, F cycles the
## filters, a click takes a photo: a PNG of the screen (filter and all, the
## viewfinder left out), saved in the "photos" folder beside "saves". C or
## Esc puts the camera away. It works during a replay too, and on a bird
## close-up.
##
## Each photo is checked for birds (the bird guide marks them photographed,
## and a whole set of one rarity pays a bonus) and for photo jobs on the
## mission board.

const SaveManager = preload("res://scripts/save_manager.gd")
const Profile = preload("res://scripts/profile.gd")
const BirdData = preload("res://scripts/bird_data.gd")
const Sound = preload("res://scripts/sound.gd")

const FILTERS := ["No filter", "Warm", "Cool", "Black and white", "Sepia", "Vivid"]
const FILTER_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform int kind = 0;
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	if (kind == 1) { c = c * vec3(1.08, 1.0, 0.86) + vec3(0.02, 0.01, 0.0); }
	else if (kind == 2) { c = c * vec3(0.88, 1.0, 1.1); }
	else if (kind == 3) { c = vec3(grey); c = (c - 0.5) * 1.15 + 0.5; }
	else if (kind == 4) { c = vec3(grey) * vec3(1.07, 0.95, 0.75) + vec3(0.05, 0.02, 0.0); }
	else if (kind == 5) { c = mix(vec3(grey), c, 1.45); c = (c - 0.5) * 1.08 + 0.5; }
	float vignette = smoothstep(0.85, 0.35, distance(SCREEN_UV, vec2(0.5)));
	COLOR = vec4(c * mix(0.82, 1.0, vignette), 1.0);
}
"""

var screens: Array = []         # CanvasLayers hidden while the camera is up
var birds: Node = null          # birds.gd
var missions: Node = null       # missions.gd
var game_hud: Node = null       # game_hud.gd, for announcements (shown after a photo)
var player: Node = null         # player.gd

var active := false
var _filter := 0
var _filter_rect: ColorRect
var _finder: Control
var _readout: Label
var _flash: ColorRect
var _flash_left := 0.0
var _old_fov := 70.0
var _camera: Camera3D = null
var _hidden: Array = []
var _busy := false
var _photos_window: PanelContainer
var _photos_grid: GridContainer
var _photos_status: Label


static func photos_dir() -> String:
	return SaveManager.saves_dir().get_base_dir().path_join("photos")


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_filter_rect = ColorRect.new()
	_filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FILTER_SHADER
	material.shader = shader
	_filter_rect.material = material
	_filter_rect.visible = false
	add_child(_filter_rect)
	_finder = Control.new()
	_finder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finder.draw.connect(_draw_finder)
	_finder.visible = false
	add_child(_finder)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 16)
	_readout.add_theme_constant_override("outline_size", 6)
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_readout.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_readout.position.y -= 70.0
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finder.add_child(_readout)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	_build_photos_window()


func _draw_finder() -> void:
	var size := _finder.size
	var edge := Vector2(size.x * 0.08, size.y * 0.1)
	var arm := 60.0
	var white := Color(1, 1, 1, 0.9)
	for corner in [Vector2(edge.x, edge.y), Vector2(size.x - edge.x, edge.y), Vector2(edge.x, size.y - edge.y),
			Vector2(size.x - edge.x, size.y - edge.y)]:
		var along_x := arm if corner.x < size.x * 0.5 else -arm
		var along_y := arm if corner.y < size.y * 0.5 else -arm
		_finder.draw_line(corner, corner + Vector2(along_x, 0.0), white, 3.0)
		_finder.draw_line(corner, corner + Vector2(0.0, along_y), white, 3.0)
	var middle := size * 0.5
	_finder.draw_line(middle - Vector2(12, 0), middle + Vector2(12, 0), Color(1, 1, 1, 0.7), 1.5)
	_finder.draw_line(middle - Vector2(0, 12), middle + Vector2(0, 12), Color(1, 1, 1, 0.7), 1.5)
	_finder.draw_circle(Vector2(edge.x + 24.0, edge.y + 24.0), 8.0, Color(1.0, 0.2, 0.2, 0.9))


func toggle() -> void:
	if active:
		close()
	else:
		open()


func open() -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	active = true
	_old_fov = _camera.fov
	_hidden.clear()
	for item in screens:
		var screen := item as CanvasLayer
		if screen != null and screen.visible:
			_hidden.append(screen)
			screen.visible = false
	_finder.visible = true
	_filter_rect.visible = _filter != 0
	_update_readout()


func close() -> void:
	if not active:
		return
	active = false
	if is_instance_valid(_camera):
		_camera.fov = _old_fov
	for screen in _hidden:
		if is_instance_valid(screen):
			(screen as CanvasLayer).visible = true
	_hidden.clear()
	_finder.visible = false
	_filter_rect.visible = false


func _update_readout() -> void:
	var zoom := _old_fov / maxf(_camera.fov, 0.1) if is_instance_valid(_camera) else 1.0
	_readout.text = "Zoom %.1fx   ·   %s   ·   Click: take a photo   ·   Wheel: zoom   ·   F: filter   ·   C or Esc: put the camera away" % [
		zoom, FILTERS[_filter]]


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		_flash.color.a = _flash_left / 0.25 * 0.8
	if active:
		# The camera may have changed under us (a replay starting, a close-up).
		var current := get_viewport().get_camera_3d()
		if current != _camera and current != null:
			if is_instance_valid(_camera):
				_camera.fov = _old_fov
			_camera = current
			_old_fov = current.fov
			_update_readout()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == KEY_C and not key.ctrl_pressed and not key.shift_pressed and get_viewport().gui_get_focus_owner() == null:
			toggle()
			get_viewport().set_input_as_handled()
			return
		if active and key.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
			return
		if active and key.physical_keycode == KEY_F:
			_filter = (_filter + 1) % FILTERS.size()
			_filter_rect.visible = _filter != 0
			(_filter_rect.material as ShaderMaterial).set_shader_parameter("kind", _filter)
			_update_readout()
			get_viewport().set_input_as_handled()
			return
	if not active:
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if is_instance_valid(_camera):
				var factor := 0.88 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88
				_camera.fov = clampf(_camera.fov * factor, 3.0, _old_fov)
				_update_readout()
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			take_photo()
			get_viewport().set_input_as_handled()


## Saves the screen as a PNG in the photos folder, without the viewfinder.
func take_photo() -> String:
	if _busy:
		return ""
	_busy = true
	_finder.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_finder.visible = active
	_busy = false
	if image == null or image.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(photos_dir())
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var path := photos_dir().path_join("photo_%s.png" % stamp)
	var number := 2
	while FileAccess.file_exists(path):
		path = photos_dir().path_join("photo_%s_%d.png" % [stamp, number])
		number += 1
	image.save_png(path)
	_flash_left = 0.25
	Sound.play_ui("shutter")
	_after_photo(path)
	return path


func _after_photo(path: String) -> void:
	var lines: Array = ["Saved %s" % path.get_file()]
	if birds != null and is_instance_valid(_camera):
		for species in birds.birds_in_frame(_camera):
			var info: Dictionary = BirdData.SPECIES[species]
			if Profile.photograph_bird(str(species), path):
				lines.append("New photo for the bird guide: %s" % info["name"])
				lines.append_array(_status_bonus(str(info["status"])))
	if missions != null and is_instance_valid(_camera):
		lines.append_array(missions.photo_taken(_camera))
	if game_hud != null:
		game_hud.announce("", "\n".join(lines), 4.0)
		# Announcements show once the camera is put away; say it in the viewfinder now.
	_readout.text = lines[lines.size() - 1] if lines.size() > 1 else lines[0]
	get_tree().create_timer(2.5, true).timeout.connect(func() -> void:
		if active:
			_update_readout())


## A bonus for a photo of every bird of one rarity.
func _status_bonus(status: String) -> Array:
	var bonus_id := "birds_" + status.to_lower()
	if Profile.mission_done(bonus_id):
		return []
	for species in BirdData.SPECIES:
		if str(BirdData.SPECIES[species]["status"]) == status and str(Profile.bird(species).get("photo", "")) == "":
			return []
	var pay: int = BirdData.STATUS_BONUS[status]
	Profile.mark_mission(bonus_id)
	Profile.add_cash(pay)
	Sound.play_ui("cash")
	return ["Every %s bird photographed! Bonus %s" % [status.to_lower(), Profile.money(pay)]]


# --- The Photos window ---------------------------------------------------------------

func _build_photos_window() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_photos_window = PanelContainer.new()
	_photos_window.visible = false
	centre.add_child(_photos_window)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_photos_window.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Photos"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var open_folder := Button.new()
	open_folder.text = "Open the folder"
	open_folder.focus_mode = Control.FOCUS_NONE
	open_folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(photos_dir())
		OS.shell_open(photos_dir()))
	head.add_child(open_folder)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: _photos_window.visible = false)
	head.add_child(close_button)
	_photos_status = Label.new()
	_photos_status.add_theme_font_size_override("font_size", 13)
	column.add_child(_photos_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(4 * 212 + 20, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_photos_grid = GridContainer.new()
	_photos_grid.columns = 4
	scroll.add_child(_photos_grid)


func toggle_photos() -> void:
	_photos_window.visible = not _photos_window.visible
	if not _photos_window.visible:
		return
	if player != null:
		player.cursor_free = true
	for child in _photos_grid.get_children():
		child.queue_free()
	var files: Array = []
	var dir := DirAccess.open(photos_dir())
	if dir != null:
		for file in dir.get_files():
			if file.to_lower().ends_with(".png"):
				files.append(file)
	files.sort()
	files.reverse()
	_photos_status.text = "%d photos in %s   (C takes one)" % [files.size(), photos_dir()]
	for index in mini(files.size(), 40):
		var image := Image.load_from_file(photos_dir().path_join(files[index]))
		if image == null or image.is_empty():
			continue
		image.resize(200, int(200.0 * image.get_height() / maxf(image.get_width(), 1.0)))
		var cell := VBoxContainer.new()
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(image)
		cell.add_child(picture)
		var caption := Label.new()
		caption.text = str(files[index]).trim_prefix("photo_").trim_suffix(".png")
		caption.add_theme_font_size_override("font_size", 11)
		cell.add_child(caption)
		_photos_grid.add_child(cell)
