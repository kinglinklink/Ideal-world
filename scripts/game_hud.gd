extends CanvasLayer
## The interface for playing rather than building: health and cash, big
## announcements across the middle of the screen, the prompt for talking to
## people, a red flash when hurt, and a place for the windows of races,
## cargo runs and the weather to open in. hud.gd keeps the build tools.

const Profile = preload("res://scripts/profile.gd")
const GraphView = preload("res://scripts/graph_view.gd")
const Stress = preload("res://scripts/stress.gd")

var player: Node = null          # player.gd

var root: MarginContainer        # windows open in here, centred
var prompt: Label                # "E  Talk to ..." near the bottom
var _health_bar: ProgressBar
var _health_label: Label
var _cash_label: Label
var _announce: Label
var _announce_time := 0.0
var _sub: Label
var _flash: ColorRect
var _flash_amount := 0.0
var _shown_cash := -1
var side: VBoxContainer          # top-left column for race and graph readouts
var _graph_views: Array = []     # graph_view.gd, one per graph screen shown
var _stress_label: Label
var _graph_check := 0.0


func _ready() -> void:
	layer = 2
	root = MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(margin_name, 16)
	add_child(root)

	_flash = ColorRect.new()
	_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	move_child(_flash, 0)

	# Health and cash, low in the middle, above the tool bar.
	var bottom := VBoxContainer.new()
	bottom.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 4)
	root.add_child(bottom)
	prompt = _label("", 20, Color(1.0, 0.95, 0.55))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(prompt)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	bottom.add_child(row)
	_health_label = _label("Health", 15, Color(1, 1, 1))
	row.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(220, 16)
	_health_bar.show_percentage = false
	_health_bar.max_value = 100.0
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.15, 0.15)
	_health_bar.add_theme_stylebox_override("fill", fill)
	row.add_child(_health_bar)
	_cash_label = _label("", 18, Color(0.55, 1.0, 0.55))
	row.add_child(_cash_label)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 96)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)

	# Announcements, big, a little above the middle.
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	middle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(middle)
	_announce = _label("", 56, Color(1.0, 0.9, 0.3))
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_announce)
	_sub = _label("", 22, Color(1, 1, 1))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_sub)
	var lift := Control.new()
	lift.custom_minimum_size = Vector2(0, 160)
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(lift)

	# A column on the left, under the help text, for race and graph readouts.
	side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_theme_constant_override("separation", 6)
	root.add_child(side)
	var under_help := Control.new()
	under_help.custom_minimum_size = Vector2(0, 118)
	under_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(under_help)
	_stress_label = _label("", 17, Color(1, 1, 1))
	side.add_child(_stress_label)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Big words across the middle of the screen for `seconds`, with a smaller
## line under them.
func announce(text: String, subtitle: String = "", seconds: float = 3.0, color: Color = Color(1.0, 0.9, 0.3)) -> void:
	_announce.text = text
	_announce.add_theme_color_override("font_color", color)
	_sub.text = subtitle
	_announce_time = seconds


## A red flash over the screen, stronger for a bigger hurt.
func flash_hurt(amount: float) -> void:
	_flash_amount = clampf(_flash_amount + amount / 40.0, 0.0, 0.6)


func _process(delta: float) -> void:
	if player != null:
		var hp: float = player.hp
		_health_bar.value = hp
		_health_label.text = "Health %d" % int(ceil(hp))
		_health_label.add_theme_color_override("font_color",
				Color(1, 1, 1) if hp > 35.0 else Color(1.0, 0.4, 0.35))
	var money := Profile.cash()
	if money != _shown_cash:
		_shown_cash = money
		_cash_label.text = Profile.money(money)
	if _announce_time > 0.0:
		_announce_time -= delta
		if _announce_time <= 0.0:
			_announce.text = ""
			_sub.text = ""
	_flash_amount = maxf(_flash_amount - delta * 0.8, 0.0)
	_flash.color = Color(0.8, 0.0, 0.0, _flash_amount)
	_graph_check -= delta
	if _graph_check <= 0.0:
		_graph_check = 0.25
		_update_graphs()
		_update_stress()


## While the stress view is on: the most loaded part of each spawned build.
func _update_stress() -> void:
	if not Stress.view:
		_stress_label.text = ""
		return
	var peak := 0.0
	for node in get_tree().get_nodes_in_group("logic"):
		var spawner: Node = node.spawner
		if spawner != null and bool(spawner.spawned) and spawner.stress != null:
			peak = maxf(peak, spawner.stress.peak_ratio())
	_stress_label.text = "Stress view (9)   most loaded part: %d %% of its strength" % int(round(peak * 100.0))
	_stress_label.add_theme_color_override("font_color", Stress.ratio_color(peak))


## Shows the graph screens of the vehicle the character sits in.
func _update_graphs() -> void:
	var wanted: Array = []
	for node in get_tree().get_nodes_in_group("logic"):
		wanted.append_array(node.graphs_for_screen())
	wanted = wanted.slice(0, 3)
	while _graph_views.size() > wanted.size():
		var view: Control = _graph_views.pop_back()
		view.queue_free()
	while _graph_views.size() < wanted.size():
		var view: Control = GraphView.new()
		side.add_child(view)
		_graph_views.append(view)
	for index in wanted.size():
		_graph_views[index].graph = wanted[index]


## A label in the left-hand column for readouts (a race's position and time).
func make_side_label() -> Label:
	var label := _label("", 20, Color(1.0, 1.0, 0.9))
	side.add_child(label)
	side.move_child(label, 1)
	return label


## A window in the middle of the screen with a title and a close button.
## Returns [the panel, the column to fill].
func make_window(title: String, width: float = 520.0) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(width, 0)
	panel.visible = false
	var margin := MarginContainer.new()
	for margin_name in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(margin_name, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: panel.visible = false)
	head.add_child(close)
	root.add_child(panel)
	return [panel, column]
