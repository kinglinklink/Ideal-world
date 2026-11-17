extends RefCounted
## The Weather window (the Weather button at the top): what the weather is
## doing, and controls to set it, pick the season, set the wind, and start
## any of the disasters.

const Weather = preload("res://scripts/weather.gd")

var panel: PanelContainer
var _status: Label
var _weather: Node
var _disasters: Node
var _wind_check: CheckBox
var _wind_speed: HSlider
var _wind_label: Label
var _wind_turn: HSlider


func build(game_hud: Node, weather: Node, disasters: Node) -> void:
	_weather = weather
	_disasters = disasters
	var made: Array = game_hud.make_window("Weather and events", 560.0)
	panel = made[0]
	var column: VBoxContainer = made[1]
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var kind_row := _row(column, "Weather")
	var kinds := OptionButton.new()
	kinds.focus_mode = Control.FOCUS_NONE
	var kind_ids := ["auto", "clear", "cloudy", "rain", "storm", "snow", "fog"]
	for id in kind_ids:
		kinds.add_item("Auto (changes by itself)" if id == "auto" else str(Weather.NAMES[id]))
	kinds.item_selected.connect(func(index: int) -> void: _weather.set_mode(kind_ids[index]))
	kind_row.add_child(kinds)

	var season_row := _row(column, "Season")
	var seasons := OptionButton.new()
	seasons.focus_mode = Control.FOCUS_NONE
	var season_ids := ["auto", "spring", "summer", "autumn", "winter"]
	for id in season_ids:
		seasons.add_item("Auto (a year lasts 10 days)" if id == "auto" else str(id).capitalize())
	seasons.item_selected.connect(func(index: int) -> void: _weather.set_season(season_ids[index]))
	season_row.add_child(seasons)

	_wind_check = CheckBox.new()
	_wind_check.text = "Set the wind myself"
	_wind_check.focus_mode = Control.FOCUS_NONE
	_wind_check.toggled.connect(func(_on: bool) -> void: _apply_wind())
	column.add_child(_wind_check)
	var speed_row := _row(column, "Wind speed")
	_wind_speed = HSlider.new()
	_wind_speed.min_value = 0.0
	_wind_speed.max_value = 60.0
	_wind_speed.step = 1.0
	_wind_speed.value = 10.0
	_wind_speed.custom_minimum_size = Vector2(260, 0)
	_wind_speed.focus_mode = Control.FOCUS_NONE
	_wind_speed.value_changed.connect(func(_value: float) -> void: _apply_wind())
	speed_row.add_child(_wind_speed)
	_wind_label = Label.new()
	speed_row.add_child(_wind_label)
	var turn_row := _row(column, "Blowing from")
	_wind_turn = HSlider.new()
	_wind_turn.min_value = 0.0
	_wind_turn.max_value = 359.0
	_wind_turn.step = 1.0
	_wind_turn.custom_minimum_size = Vector2(260, 0)
	_wind_turn.focus_mode = Control.FOCUS_NONE
	_wind_turn.value_changed.connect(func(_value: float) -> void: _apply_wind())
	turn_row.add_child(_wind_turn)

	var heading := Label.new()
	heading.text = "Disasters"
	heading.add_theme_font_size_override("font_size", 17)
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 3
	column.add_child(grid)
	for pair in [["Tornado", "start_tornado"], ["Hurricane", "start_hurricane"], ["Tsunami", "start_tsunami"],
			["Earthquake", "start_earthquake"], ["Volcano eruption", "start_eruption"], ["Calm everything", "calm_everything"]]:
		var button := Button.new()
		button.text = str(pair[0])
		button.custom_minimum_size = Vector2(170, 36)
		button.focus_mode = Control.FOCUS_NONE
		var method: String = pair[1]
		button.pressed.connect(func() -> void: _disasters.call(method))
		grid.add_child(button)
	var note := Label.new()
	note.text = "Random disasters can be switched off in Settings, World. The volcano is the tallest\nmountain, west of Lakeside; look for its dark slopes and glowing crater."
	note.add_theme_font_size_override("font_size", 12)
	column.add_child(note)


func _row(parent: Control, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	return row


func _apply_wind() -> void:
	_wind_label.text = "%d m/s" % int(_wind_speed.value)
	if _wind_check.button_pressed:
		_weather.wind_override = _wind_speed.value
		# "From" a compass bearing: the wind blows toward the opposite way.
		var toward := deg_to_rad(_wind_turn.value + 180.0)
		_weather.wind_angle = atan2(-cos(toward), sin(toward))
	else:
		_weather.wind_override = -1.0


func toggle() -> void:
	panel.visible = not panel.visible
	refresh()


func refresh() -> void:
	if panel.visible:
		_status.text = _weather.describe()
