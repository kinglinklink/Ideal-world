extends Control
## A small top-down map that stays centred on the player.
##
## The map does not turn. Up on the map is the world's +Z direction, the way
## the character faces at the start: from the garage out across the build pad.

const RANGE := 70.0   # metres from the centre of the map to its edge
const BACKGROUND := Color(0.06, 0.08, 0.11, 0.8)
const BORDER := Color(1.0, 1.0, 1.0, 0.5)
const PLAYER := Color(1.0, 0.85, 0.2)

var player: Node3D = null   # player.gd
var features: Array = []    # each is [Rect2 footprint in world X and Z, colour, label]


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(190, 190)


func _process(_delta: float) -> void:
	queue_redraw()


## Where a world position lands on the map, in pixels. Both axes are flipped,
## which is what a top-down view with +Z upward looks like.
func _to_map(world_x: float, world_z: float, centre: Vector3, pixels_per_metre: float) -> Vector2:
	var half := size * 0.5
	return Vector2(
		half.x - (world_x - centre.x) * pixels_per_metre,
		half.y - (world_z - centre.z) * pixels_per_metre)


func _draw() -> void:
	var extent := size
	draw_rect(Rect2(Vector2.ZERO, extent), BACKGROUND)
	if player == null:
		return
	var centre := player.global_position
	var pixels_per_metre := extent.x * 0.5 / RANGE
	var font := get_theme_default_font()

	for feature in features:
		var area: Rect2 = feature[0]
		var tint: Color = feature[1]
		var caption: String = feature[2]
		var far_corner := _to_map(area.end.x, area.end.y, centre, pixels_per_metre)
		var near_corner := _to_map(area.position.x, area.position.y, centre, pixels_per_metre)
		var outline := Rect2(far_corner, near_corner - far_corner)
		draw_rect(outline, tint)
		draw_rect(outline, tint.lightened(0.4), false, 1.0)
		if caption != "":
			draw_string(font, outline.position + Vector2(3.0, 13.0), caption,
					HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 1.0, 1.0, 0.85))

	# The player: a dot with a pointer showing which way the character faces.
	var heading: float = player.get_heading()
	var facing := Vector2(sin(heading), cos(heading))
	var sideways := Vector2(-facing.y, facing.x)
	var middle := extent * 0.5
	draw_colored_polygon(PackedVector2Array([
		middle + facing * 10.0,
		middle - facing * 5.0 + sideways * 5.5,
		middle - facing * 5.0 - sideways * 5.5,
	]), PLAYER)
	draw_circle(middle, 2.5, Color(0.1, 0.1, 0.12))

	draw_string(font, Vector2(5.0, extent.y - 6.0), "%d m across" % int(RANGE * 2.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 1.0, 1.0, 0.6))
	draw_rect(Rect2(Vector2.ZERO, extent), BORDER, false, 2.0)
