extends Control
## One graph screen drawn in the interface: the lines of a graph block on the
## vehicle the character sits in, with each line's name and latest value.
## The data is the dictionary logic.gd keeps for the block.

const Logic = preload("res://scripts/logic.gd")

var graph: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(360, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, Color(0.02, 0.05, 0.04, 0.82))
	draw_rect(area, Color(0.3, 0.6, 0.4, 0.9), false, 1.0)
	if graph.is_empty():
		return
	var plot := Rect2(Vector2(6, 22), size - Vector2(12, 28))
	var span: Vector2 = Logic.graph_range(graph)
	var font := get_theme_default_font()
	draw_string(font, Vector2(6, 15), "%.3g" % span.y, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 0.65))
	draw_string(font, Vector2(6, size.y - 3), "%.3g" % span.x, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 0.65))
	if span.x < 0.0 and span.y > 0.0:
		var zero_y := plot.position.y + (1.0 - (0.0 - span.x) / (span.y - span.x)) * plot.size.y
		draw_line(Vector2(plot.position.x, zero_y), Vector2(plot.end.x, zero_y), Color(0.25, 0.45, 0.3), 1.0)
	var times: PackedFloat32Array = graph["times"]
	var values: Array = graph["values"]
	var linked: Array = graph["linked"]
	var labels: Array = graph["labels"]
	var window: float = graph["window"]
	var legend_x := 70.0
	for index in 4:
		if not linked[index]:
			continue
		var color: Color = Logic.GRAPH_COLORS[index]
		var line: PackedFloat32Array = values[index]
		if times.size() >= 2 and line.size() == times.size():
			var newest: float = times[times.size() - 1]
			var points := PackedVector2Array()
			for sample in times.size():
				var fraction := clampf((line[sample] - span.x) / (span.y - span.x), 0.0, 1.0)
				points.append(Vector2(plot.position.x + (1.0 - (newest - times[sample]) / window) * plot.size.x,
						plot.position.y + (1.0 - fraction) * plot.size.y))
			draw_polyline(points, color, 1.5, true)
		var latest := line[line.size() - 1] if line.size() > 0 else 0.0
		var text := "%s %.3g" % [str(labels[index]), latest]
		draw_string(font, Vector2(legend_x, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		legend_x += 72.0
