extends CanvasLayer
## The failure log: why things broke. When the stress view breaks a part,
## a crash smashes parts, a gear train locks, a fuel tank blows or the
## volcano melts something, a short note says what and why, for example
## "Steel shaft broke: 412 MPa against steel's 400 MPa limit, at 84 m/s".
## Notes show for a few seconds on the right; L opens the whole log.

const MAX_KEPT := 200
const SHOWN := 4                 # notes on screen at once
const SHOW_TIME := 7.0

static var instance: Node = null

var _entries: Array = []         # {"time", "text", "count"}
var _toasts: VBoxContainer
var _window: PanelContainer
var _list: RichTextLabel
var _clock := 0.0


static func note(text: String) -> void:
	if instance != null:
		instance._add(text)


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	layer = 4
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_toasts.position = Vector2(-520, 230)
	_toasts.custom_minimum_size = Vector2(500, 0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 4)
	add_child(_toasts)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_window = PanelContainer.new()
	_window.visible = false
	centre.add_child(_window)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	_window.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Failure log (L)"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func() -> void:
		_entries.clear()
		_refresh())
	head.add_child(clear)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _window.visible = false)
	head.add_child(close)
	_list = RichTextLabel.new()
	_list.custom_minimum_size = Vector2(760, 460)
	_list.bbcode_enabled = true
	_list.scroll_following = true
	column.add_child(_list)


func _add(text: String) -> void:
	if not _entries.is_empty():
		var last: Dictionary = _entries[_entries.size() - 1]
		if str(last["text"]) == text and _clock - float(last["time"]) < 3.0:
			last["count"] = int(last["count"]) + 1
			last["time"] = _clock
			_toast(text + "  ×%d" % int(last["count"]))
			if _window.visible:
				_refresh()
			return
	_entries.append({"time": _clock, "text": text, "count": 1})
	while _entries.size() > MAX_KEPT:
		_entries.pop_front()
	_toast(text)
	if _window.visible:
		_refresh()


func _toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(500, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.6))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("until", _clock + SHOW_TIME)
	_toasts.add_child(label)
	while _toasts.get_child_count() > SHOWN:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()


func _process(delta: float) -> void:
	_clock += delta
	for child in _toasts.get_children():
		var until := float(child.get_meta("until", 0.0))
		(child as Control).modulate.a = clampf(until - _clock, 0.0, 1.0)
		if _clock > until:
			child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_L \
			and get_viewport().gui_get_focus_owner() == null:
		_window.visible = not _window.visible
		if _window.visible:
			_refresh()
			var player := get_tree().get_first_node_in_group("player")
			if player != null:
				player.cursor_free = true


func _refresh() -> void:
	var lines: Array = []
	for entry in _entries:
		var seconds := int(float(entry["time"]))
		lines.append("[color=#aaaaaa]%d:%02d[/color]  %s%s" % [floori(seconds / 60.0), seconds % 60, entry["text"],
				("  ×%d" % int(entry["count"])) if int(entry["count"]) > 1 else ""])
	_list.text = "\n".join(lines) if not lines.is_empty() else "Nothing has broken yet."


func entry_count() -> int:
	return _entries.size()
