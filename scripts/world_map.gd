extends Control
## The full map, opened and closed with M. North is up.
##
## Scroll to zoom in and out about the mouse, drag to move the map, click to
## set a waypoint (shown on the mini map, with its distance and bearing on
## screen), right-click to clear it. It shows the whole lake and the land
## round it: towns, islands, airports, wizard towers and where you are.

const Origin = preload("res://scripts/origin.gd")

const BACKGROUND := Color(0.03, 0.04, 0.06, 0.94)
const GRID := Color(1.0, 1.0, 1.0, 0.08)
const PLAYER := Color(1.0, 0.85, 0.2)
const PLACE := Color(1.0, 0.82, 0.30)
const TOWER := Color(0.75, 0.55, 1.0)
const WAYPOINT := Color(1.0, 0.3, 0.35)
const MIN_SCALE := 2.0      # metres per pixel, zoomed right in
const MAX_SCALE := 120.0    # zoomed right out

var minimap: Control = null   # minimap.gd: the picture and the names
var player: Node3D = null     # player.gd

var _centre := Vector2.ZERO   # the map position in the middle of the screen
var _scale := 40.0            # metres per pixel
var _dragging := false
var _dragged := 0.0           # pixels moved since the button went down, to tell a click from a drag


func _ready() -> void:
	visible = false
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Opens the map centred on the player, zoomed to show the whole lake, or closes it.
func toggle() -> void:
	visible = not visible
	if not visible:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var area: Rect2 = minimap.picture_area()
	if area.size.x > 1.0 and size.x > 1.0:
		_scale = clampf(maxf(area.size.x / size.x, area.size.y / size.y) * 0.75, MIN_SCALE, MAX_SCALE)
	if player != null:
		var at := Origin.to_map(player.global_position)
		_centre = Vector2(at.x, at.z)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _to_screen(map_point: Vector2) -> Vector2:
	return size * 0.5 + (map_point - _centre) / _scale


func _to_map(screen_point: Vector2) -> Vector2:
	return _centre + (screen_point - size * 0.5) * _scale


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# Zoom about the point under the mouse.
			var before := _to_map(button.position)
			var factor := 0.8 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25
			_scale = clampf(_scale * factor, MIN_SCALE, MAX_SCALE)
			_centre += before - _to_map(button.position)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_dragged = 0.0
			else:
				_dragging = false
				if _dragged < 6.0:
					minimap.waypoint = _to_map(button.position)
					minimap.has_waypoint = true
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			minimap.has_waypoint = false
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_centre -= motion.relative * _scale
		_dragged += motion.relative.length()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if minimap == null:
		return
	var font := get_theme_default_font()
	var picture: Texture2D = minimap.picture()
	var area: Rect2 = minimap.picture_area()
	if picture != null:
		draw_texture_rect(picture, Rect2(_to_screen(area.position), area.size / _scale), false)

	# A grid every 5 km (every 1 km close in), to judge distances by.
	var step := 5000.0 if _scale > 12.0 else 1000.0
	var top_left := _to_map(Vector2.ZERO)
	var bottom_right := _to_map(size)
	var x := floorf(top_left.x / step) * step
	while x < bottom_right.x:
		var sx := _to_screen(Vector2(x, 0.0)).x
		draw_line(Vector2(sx, 0.0), Vector2(sx, size.y), GRID, 1.0)
		x += step
	var z := floorf(top_left.y / step) * step
	while z < bottom_right.y:
		var sz := _to_screen(Vector2(0.0, z)).y
		draw_line(Vector2(0.0, sz), Vector2(size.x, sz), GRID, 1.0)
		z += step

	for item in minimap.islands():
		var island: Array = item
		draw_string(font, _to_screen(island[0]) + Vector2(-24.0, 4.0), str(island[1]), HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 12, Color(1.0, 1.0, 1.0, 0.75))
	for item in minimap.towns():
		var town: Array = item
		draw_string(font, _to_screen(town[0]) + Vector2(-28.0, 4.0), str(town[1]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, 14, Color(0.85, 0.95, 1.0, 0.95))
	for item in minimap.places():
		var place: Array = item
		var spot := _to_screen(place[0])
		var tower := str(place[1]) == "Wizard tower"
		draw_circle(spot, 5.0 if tower else 3.5, TOWER if tower else PLACE)
		if _scale < 30.0 or tower:
			draw_string(font, spot + Vector2(7.0, 4.0), str(place[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12,
					Color(0.9, 0.8, 1.0, 0.95) if tower else Color(1.0, 0.92, 0.6, 0.95))

	# Fleet vehicles.
	for item in minimap.vehicle_spots():
		var vehicle: Array = item
		var spot := _to_screen(vehicle[0])
		draw_rect(Rect2(spot - Vector2(4, 4), Vector2(8, 8)), Color(0.45, 1.0, 0.55))
		draw_string(font, spot + Vector2(7.0, 4.0), str(vehicle[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12,
				Color(0.7, 1.0, 0.75, 0.95))

	# The waypoint, and a line to it from the player.
	var here := Vector2.ZERO
	if player != null:
		var at := Origin.to_map(player.global_position)
		here = Vector2(at.x, at.z)
	if minimap.has_waypoint:
		var mark := _to_screen(minimap.waypoint)
		draw_line(_to_screen(here), mark, Color(WAYPOINT, 0.6), 2.0)
		draw_circle(mark, 7.0, WAYPOINT)
		draw_circle(mark, 3.0, Color(1, 1, 1))

	# The player.
	if player != null:
		var heading: float = player.get_heading()
		var facing := Vector2(-sin(heading), -cos(heading))
		var sideways := Vector2(-facing.y, facing.x)
		var middle := _to_screen(here)
		draw_colored_polygon(PackedVector2Array([
			middle + facing * 14.0, middle - facing * 7.0 + sideways * 8.0, middle - facing * 7.0 - sideways * 8.0,
		]), PLAYER)
		draw_circle(middle, 3.0, Color(0.1, 0.1, 0.12))

	# Scale bar, help and north.
	var bar_metres := step
	var bar := bar_metres / _scale
	var corner := Vector2(24.0, size.y - 30.0)
	draw_line(corner, corner + Vector2(bar, 0.0), Color(1, 1, 1, 0.9), 3.0)
	draw_string(font, corner + Vector2(0.0, -8.0), "%d km" % int(bar_metres / 1000.0), HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 14, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(24.0, 34.0), "MAP    M to close    scroll to zoom    drag to move    click: set waypoint    right-click: clear it",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(1, 1, 1, 0.85))
	draw_string(font, Vector2(size.x * 0.5 - 5.0, 60.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 1, 0.9))
