extends PanelContainer
## The bird guide (B, or the Birds button): a field guide with a page for
## every species of bird in the game.
##
## A bird you have not seen is a grey "Not yet seen" line. Hover the mouse
## over a bird in the world to spot it; take a photo with it in the frame
## (C) to photograph it. Each page keeps the game and the real world apart:
## the blue panel says what it does in this game (how rare it is here,
## when and where it turns up, its nest), the green one gives real facts
## about the species, with where they come from.

const BirdData = preload("res://scripts/bird_data.gd")
const Profile = preload("res://scripts/profile.gd")
const SaveManager = preload("res://scripts/save_manager.gd")

const GAME_COLOR := Color(0.12, 0.2, 0.34, 0.95)
const REAL_COLOR := Color(0.1, 0.26, 0.16, 0.95)

var player: Node = null          # player.gd, to free the cursor

var _list: VBoxContainer
var _page: VBoxContainer
var _count: Label
var _sort: OptionButton
var _chosen := ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Bird guide: Flathead Lake"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_sort = OptionButton.new()
	for choice in ["By how common", "By season here now", "Seen first"]:
		_sort.add_item(choice)
	_sort.focus_mode = Control.FOCUS_NONE
	_sort.item_selected.connect(func(_index: int) -> void: refresh())
	head.add_child(_sort)
	var close := Button.new()
	close.text = "Close (B)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 14)
	column.add_child(_count)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(300, 520)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list)
	var page_scroll := ScrollContainer.new()
	page_scroll.custom_minimum_size = Vector2(560, 520)
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(page_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 8)
	page_scroll.add_child(_page)


func toggle() -> void:
	visible = not visible
	if visible:
		if player != null:
			player.cursor_free = true
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_B \
			and get_viewport().gui_get_focus_owner() == null:
		toggle()


static func seen(species: String) -> bool:
	return not Profile.bird(species).is_empty()


static func photographed(species: String) -> bool:
	return str(Profile.bird(species).get("photo", "")) != ""


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var ids: Array = BirdData.ids()
	if _sort.selected == 1:
		var season := _season()
		ids.sort_custom(func(a: String, b: String) -> bool:
			var here_a: bool = (BirdData.SPECIES[a]["seasons"] as Array).has(season)
			var here_b: bool = (BirdData.SPECIES[b]["seasons"] as Array).has(season)
			return here_a and not here_b if here_a != here_b else ids.find(a) < ids.find(b))
	elif _sort.selected == 2:
		ids.sort_custom(func(a: String, b: String) -> bool:
			return seen(a) and not seen(b) if seen(a) != seen(b) else ids.find(a) < ids.find(b))
	var spotted := 0
	var shot := 0
	for species in ids:
		var info: Dictionary = BirdData.SPECIES[species]
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		if seen(species):
			spotted += 1
			if photographed(species):
				shot += 1
			button.text = "%s %s   (%s)" % ["📷" if photographed(species) else "✓", info["name"], str(info["status"]).to_lower()]
		else:
			button.text = "?  Not yet seen   (%s)" % str(info["status"]).to_lower()
			button.modulate = Color(0.65, 0.65, 0.68)
		button.pressed.connect(func() -> void:
			_chosen = species
			_show(species))
		_list.add_child(button)
	_count.text = "Spotted %d of %d   ·   Photographed %d of %d   ·   Hover over a bird to spot it; C takes photos" % [
		spotted, ids.size(), shot, ids.size()]
	_show(_chosen if _chosen != "" else str(ids[0]))


func _season() -> String:
	var weather: Node = get_tree().get_first_node_in_group("weather") if is_inside_tree() else null
	if weather != null and weather.has_method("season_name"):
		return weather.season_name()
	return "summer"


func _show(species: String) -> void:
	for child in _page.get_children():
		child.queue_free()
	var info: Dictionary = BirdData.SPECIES[species]
	var record: Dictionary = Profile.bird(species)
	if record.is_empty():
		_line(_page, "Not yet seen", 24, Color(0.75, 0.75, 0.78))
		_line(_page, "A %s bird. Find one and hover the mouse over it to fill in this page." % str(info["status"]).to_lower(), 15)
		_line(_page, "Hint: %s" % _hint(info), 14, Color(0.8, 0.85, 0.9))
		return
	_line(_page, str(info["name"]), 26, Color(1.0, 0.95, 0.8))
	_line(_page, str(info["latin"]), 16, Color(0.85, 0.85, 0.8))
	var photo := str(record.get("photo", ""))
	if photo != "":
		var image := Image.load_from_file(photo)
		if image != null and not image.is_empty():
			image.resize(520, int(520.0 * image.get_height() / maxf(image.get_width(), 1.0)))
			var picture := TextureRect.new()
			picture.texture = ImageTexture.create_from_image(image)
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_page.add_child(picture)
	var game := _panel(_page, "IN THE GAME", GAME_COLOR)
	var chance := float(BirdData.STATUS_CHANCE[info["status"]]) * 100.0
	_fact(game, "How common", "%s: a %s chance in each place you go, in season (three times that near its nests)" % [
			info["status"], ("%d %%" % int(round(chance))) if chance >= 1.0 else ("%.1f %%" % chance)])
	_fact(game, "Seasons here", ", ".join(info["seasons"] as Array).capitalize())
	_fact(game, "Where and its nest", str(info["game"]))
	_fact(game, "Group size", "%d to %d" % [int(info["flock"][0]), int(info["flock"][1])])
	_fact(game, "Spotted", str(record.get("spotted", "")))
	_fact(game, "Photographed", photo.get_file() if photo != "" else "Not yet: take a photo with it in the frame (C).")
	var real := _panel(_page, "REAL-WORLD FACTS", REAL_COLOR)
	var facts: Dictionary = info["real"]
	_fact(real, "Size", str(facts["size"]))
	_fact(real, "Food", str(facts["food"]))
	_fact(real, "Nest", str(facts["nest"]))
	_fact(real, "Breeding", str(facts["breeding"]))
	_fact(real, "Migration", str(facts["migration"]))
	_fact(real, "In the Flathead", str(facts["local"]))
	_fact(real, "Did you know", str(facts["fact"]))
	_line(real, "Sources: %s" % facts["sources"], 12, Color(0.8, 0.9, 0.8))


func _hint(info: Dictionary) -> String:
	var habitats: Array = info["habitats"]
	return "look in %s, %s." % [" or ".join(habitats).replace("_", " "), "all year" if (info["seasons"] as Array).size() == 4
			else "in " + " and ".join(info["seasons"] as Array)]


func _panel(parent: Control, title: String, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_line(column, title, 15, Color(1, 1, 1, 0.85))
	return column


func _fact(parent: Control, caption: String, text: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(520, 0)
	label.text = "[b]%s:[/b] %s" % [caption, text]
	parent.add_child(label)


func _line(parent: Control, text: String, font_size: int, color: Color = Color(1, 1, 1)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520, 0)
	parent.add_child(label)
