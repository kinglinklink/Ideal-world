extends Control
## A small top-down map that stays centred on the player, drawn over a
## picture of the lake baked by tools/bake_map.py. North is up.
##
## It zooms out as you go faster: about 600 m across standing still, out to
## 12 km across in a fast plane.

const MapInfo = preload("res://scripts/map_info.gd")
const Origin = preload("res://scripts/origin.gd")

const NEAR_RANGE := 300.0    # metres from the centre to the edge, standing still
const FAR_RANGE := 6000.0
const RANGE_PER_SPEED := 25.0   # extra metres of range per m/s
const BACKGROUND := Color(0.06, 0.08, 0.11, 0.85)
const BORDER := Color(1.0, 1.0, 1.0, 0.5)
const PLAYER := Color(1.0, 0.85, 0.2)
const PLACE := Color(1.0, 0.82, 0.30)

var player: Node3D = null   # player.gd
var features: Array = []    # each is [Rect2 footprint in world X and Z, colour, label]

var _picture: Texture2D = null
var _picture_area := Rect2()   # the world X and Z the picture covers
var _islands: Array = []       # [Vector2, name]
var _places: Array = []        # [Vector2, name]
var _towns: Array = []         # [Vector2, name]
var _range := NEAR_RANGE


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(190, 190)


## The lake picture and the places to label, from world.json and landmarks.gd.
func set_world(world: Dictionary, places: Array) -> void:
	var image := Image.load_from_file(MapInfo.MINIMAP_FILE)
	if image != null and not image.is_empty():
		_picture = ImageTexture.create_from_image(image)
	var area: Dictionary = world.get("minimap", {})
	_picture_area = Rect2(float(area.get("x0", 0.0)), float(area.get("z0", 0.0)),
			float(area.get("width", 1.0)), float(area.get("depth", 1.0)))
	_islands.clear()
	for item in world.get("islands", []):
		var island: Dictionary = item
		var at: Array = island["at"]
		_islands.append([Vector2(float(at[0]), float(at[1])), str(island["name"])])
	_towns.clear()
	for item in world.get("town_names", []):
		var town: Dictionary = item
		var spot: Array = town["at"]
		_towns.append([Vector2(float(spot[0]), float(spot[1])), str(town["name"])])
	_places = places


func _process(delta: float) -> void:
	if player != null:
		var moving: Vector3 = player.ride_velocity if player.seated else player.velocity
		var wanted := clampf(NEAR_RANGE + moving.length() * RANGE_PER_SPEED, NEAR_RANGE, FAR_RANGE)
		_range = lerpf(_range, wanted, clampf(delta * 1.5, 0.0, 1.0))
	queue_redraw()


## Where a world position lands on the map, in pixels: east is right and
## north (-Z) is up.
func _to_map(world_x: float, world_z: float, centre: Vector3, pixels_per_metre: float) -> Vector2:
	var half := size * 0.5
	return Vector2(half.x + (world_x - centre.x) * pixels_per_metre,
			half.y + (world_z - centre.z) * pixels_per_metre)


func _draw() -> void:
	var extent := size
	draw_rect(Rect2(Vector2.ZERO, extent), BACKGROUND)
	if player == null:
		return
	var centre := Origin.to_map(player.global_position)   # everything on the map is in map positions
	var pixels_per_metre := extent.x * 0.5 / _range
	var font := get_theme_default_font()

	# The lake picture under everything.
	if _picture != null:
		var seen := Rect2(centre.x - _range, centre.z - _range, _range * 2.0, _range * 2.0)
		var texels := Vector2(_picture.get_width(), _picture.get_height()) / _picture_area.size
		var source := Rect2((seen.position - _picture_area.position) * texels, seen.size * texels)
		draw_texture_rect_region(_picture, Rect2(Vector2.ZERO, extent), source)

	for feature in features:
		var area: Rect2 = feature[0]
		var tint: Color = feature[1]
		var corner := _to_map(area.position.x, area.position.y, centre, pixels_per_metre)
		var outline := Rect2(corner, area.size * pixels_per_metre)
		if outline.size.x < 2.0:
			outline = Rect2(outline.get_center() - Vector2(1.0, 1.0), Vector2(2.0, 2.0))
		draw_rect(outline, tint)

	# Island names, and the airports and buildings.
	for item in _islands:
		var island: Array = item
		var at: Vector2 = island[0]
		var spot := _to_map(at.x, at.y, centre, pixels_per_metre)
		if Rect2(Vector2.ZERO, extent).grow(40.0).has_point(spot):
			draw_string(font, spot + Vector2(-20.0, 4.0), str(island[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10,
					Color(1.0, 1.0, 1.0, 0.7))
	for item in _towns:
		var town: Array = item
		var at: Vector2 = town[0]
		var spot := _to_map(at.x, at.y, centre, pixels_per_metre)
		if Rect2(Vector2.ZERO, extent).grow(60.0).has_point(spot):
			draw_string(font, spot + Vector2(-24.0, 4.0), str(town[1]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
					Color(0.85, 0.95, 1.0, 0.85))
	for item in _places:
		var place: Array = item
		var at: Vector2 = place[0]
		var spot := _to_map(at.x, at.y, centre, pixels_per_metre)
		if Rect2(Vector2.ZERO, extent).has_point(spot):
			draw_circle(spot, 3.0, PLACE)
			draw_string(font, spot + Vector2(5.0, 4.0), str(place[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10,
					Color(1.0, 0.92, 0.6, 0.9))

	# The player: a pointer showing which way the character faces.
	var heading: float = player.get_heading()
	var facing := Vector2(-sin(heading), -cos(heading))
	var sideways := Vector2(-facing.y, facing.x)
	var middle := extent * 0.5
	draw_colored_polygon(PackedVector2Array([
		middle + facing * 10.0,
		middle - facing * 5.0 + sideways * 5.5,
		middle - facing * 5.0 - sideways * 5.5,
	]), PLAYER)
	draw_circle(middle, 2.5, Color(0.1, 0.1, 0.12))

	var across := _range * 2.0
	var scale_text := "%d m across" % int(across) if across < 2000.0 else "%.1f km across" % (across / 1000.0)
	draw_string(font, Vector2(5.0, extent.y - 6.0), scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11,
			Color(1.0, 1.0, 1.0, 0.7))
	draw_string(font, Vector2(extent.x * 0.5 - 4.0, 13.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12,
			Color(1.0, 1.0, 1.0, 0.8))
	draw_rect(Rect2(Vector2.ZERO, extent), BORDER, false, 2.0)
