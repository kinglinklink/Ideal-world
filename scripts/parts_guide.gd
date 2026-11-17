extends PanelContainer
## The parts guide: a page for every part and for each general topic.
## Opened with F1, the Guide button, or from the title screen and pause
## menu. Search filters the list by name and words on the page.
##
## Each part's page says what it does and where its limits are
## (parts_guide_text.gd), then lists its default size, its settings with
## their units, defaults and ranges, and its inputs and outputs, read
## straight from the part tables so they always match the game.

const PartLibrary = preload("res://scripts/part_library.gd")
const PartSettings = preload("res://scripts/part_settings.gd")
const PartPorts = preload("res://scripts/part_ports.gd")
const GuideText = preload("res://scripts/parts_guide_text.gd")
const Sound = preload("res://scripts/sound.gd")

signal closed

const CATEGORY_ORDER := ["Basic", "Structural", "Advanced", "Mechanical", "Logic", "Combat", "Fluid and Engine", "Aero", "Misc"]
const SHAPE_CATEGORIES := ["Basic", "Structural", "Advanced"]

var _search: LineEdit
var _tree: Tree
var _page: RichTextLabel


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(1080, 660)
	visibility_changed.connect(func() -> void:
		if not visible:
			closed.emit())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := Label.new()
	title.text = "Parts guide"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search parts and pages"
	_search.custom_minimum_size = Vector2(260, 0)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _fill_list())
	top.add_child(_search)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void:
		Sound.play_ui("click")
		visible = false)
	top.add_child(close)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	column.add_child(split)
	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(270, 0)
	_tree.hide_root = true
	_tree.item_selected.connect(_on_selected)
	split.add_child(_tree)
	_page = RichTextLabel.new()
	_page.bbcode_enabled = true
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.scroll_active = true
	_page.selection_enabled = true
	_page.add_theme_constant_override("line_separation", 3)
	split.add_child(_page)
	_fill_list()
	_show_topic(0)


func _fill_list() -> void:
	var filter := _search.text.strip_edges().to_lower()
	_tree.clear()
	var root := _tree.create_item()
	var topics := _tree.create_item(root)
	topics.set_text(0, "How things work")
	topics.set_selectable(0, false)
	for index in GuideText.TOPICS.size():
		var topic: Array = GuideText.TOPICS[index]
		if filter != "" and not (str(topic[0]) + " " + str(topic[1])).to_lower().contains(filter):
			continue
		var item := _tree.create_item(topics)
		item.set_text(0, str(topic[0]))
		item.set_metadata(0, "topic:%d" % index)
	for category in CATEGORY_ORDER:
		var branch: TreeItem = null
		for id in PartLibrary.PARTS:
			var entry: Array = PartLibrary.PARTS[id]
			if str(entry[1]) != category:
				continue
			var words := (str(entry[0]) + " " + str(GuideText.PARTS.get(id, ""))).to_lower()
			if filter != "" and not words.contains(filter):
				continue
			if branch == null:
				branch = _tree.create_item(root)
				branch.set_text(0, category)
				branch.set_selectable(0, false)
				branch.collapsed = filter == "" and SHAPE_CATEGORIES.has(category)
			var item := _tree.create_item(branch)
			item.set_text(0, str(entry[0]))
			item.set_metadata(0, "part:" + str(id))


func _on_selected() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	Sound.play_ui("click")
	var tag := str(item.get_metadata(0))
	if tag.begins_with("topic:"):
		_show_topic(int(tag.trim_prefix("topic:")))
	elif tag.begins_with("part:"):
		_show_part(tag.trim_prefix("part:"))


func _show_topic(index: int) -> void:
	var topic: Array = GuideText.TOPICS[index]
	_page.clear()
	_page.append_text("[font_size=26][b]%s[/b][/font_size]\n\n%s" % [topic[0], topic[1]])
	_page.scroll_to_line(0)


func _show_part(id: String) -> void:
	var entry: Array = PartLibrary.PARTS[id]
	var dims: Vector3 = entry[2]
	var text := "[font_size=26][b]%s[/b][/font_size]   [color=#9aa]%s[/color]\n" % [entry[0], entry[1]]
	text += "[color=#9aa]Default size %s × %s × %s blocks (%s × %s × %s m)[/color]\n\n" % [
		_number(dims.x), _number(dims.y), _number(dims.z),
		_number(dims.x * 0.25), _number(dims.y * 0.25), _number(dims.z * 0.25)]
	if SHAPE_CATEGORIES.has(str(entry[1])):
		text += str(GuideText.PARTS.get(id, "")) + "\n\n" + GuideText.SHAPE
	else:
		text += str(GuideText.PARTS.get(id, "No page yet."))

	var settings: Array = PartSettings.for_type(id)
	if not settings.is_empty():
		text += "\n\n[font_size=19][b]Settings[/b][/font_size]  [color=#9aa](Config tool)[/color]\n"
		for item in settings:
			var setting: Dictionary = item
			text += "  •  [b]%s[/b]: %s\n" % [setting["name"], _describe_setting(setting)]

	var ports: Dictionary = PartPorts.PORTS.get(id, {})
	var inputs: Array = ports.get("inputs", [])
	var outputs: Array = ports.get("outputs", [])
	if not inputs.is_empty() or not outputs.is_empty():
		text += "\n[font_size=19][b]Signals[/b][/font_size]  [color=#9aa](Config tool → Link)[/color]\n"
		for port in inputs:
			text += "  ⇢  in:  [b]%s[/b]  [color=#9aa](%s)[/color]\n" % [port[1], _kind(str(port[2]))]
		for port in outputs:
			text += "  ⇠  out: [b]%s[/b]  [color=#9aa](%s)[/color]\n" % [port[1], _kind(str(port[2]))]
	_page.clear()
	_page.append_text(text)
	_page.scroll_to_line(0)


func _describe_setting(setting: Dictionary) -> String:
	match str(setting["kind"]):
		"number":
			var unit := str(setting.get("unit", ""))
			var spaced := (" " + unit) if unit != "" else ""
			return "default %s%s, from %s to %s" % [_number(float(setting["default"])), spaced,
					_number(float(setting["min"])), _number(float(setting["max"]))]
		"choice":
			var options: Array = setting["options"]
			if options.size() > 8:
				return "one of %d choices, default %s" % [options.size(), setting["default"]]
			return " / ".join(PackedStringArray(options)) + "  (default %s)" % setting["default"]
		"flag":
			return "on or off, default %s" % ("on" if bool(setting["default"]) else "off")
		"color":
			return "a color"
		"text":
			return "text, default \"%s\"" % setting["default"]
	return ""


static func _kind(kind: String) -> String:
	match kind:
		"bool":
			return "on/off"
		"number":
			return "number"
		"ammo":
			return "ammo"
	return kind


static func _number(value: float) -> String:
	if absf(value - roundf(value)) < 0.0001:
		var whole := int(roundf(value))
		if absf(value) >= 10000.0:
			return _grouped(whole)
		return str(whole)
	return ("%.3f" % value).rstrip("0").rstrip(".")


static func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
