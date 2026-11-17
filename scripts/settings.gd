extends RefCounted
## The player's settings, kept in user://settings.cfg between runs.
##
##   frame_mode     "vsync"     frames wait for the screen (the default)
##                  "cap"       at most `frame_cap` frames a second
##                  "unlimited" as many frames as the computer can draw
##   frame_cap      1 to 240
##   tree_distance  how far away trees are drawn, in metres
##   show_fps       show frames per second beside the speed
##   sky            "cycle" (day and night), "day" or "night"
##
## The physics always runs 240 steps a second, whatever the frame rate.

const PATH := "user://settings.cfg"
const SKIES := ["cycle", "day", "night"]
const SECTION := "settings"
const DEFAULTS := {
	"frame_mode": "vsync",
	"frame_cap": 60,
	"tree_distance": 2600.0,
	"show_fps": true,
	"sky": "cycle",
}


static func load_settings() -> Dictionary:
	var values: Dictionary = DEFAULTS.duplicate()
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		for key in DEFAULTS:
			values[key] = file.get_value(SECTION, key, DEFAULTS[key])
	values["frame_cap"] = clampi(int(values["frame_cap"]), 1, 240)
	values["tree_distance"] = clampf(float(values["tree_distance"]), 500.0, 5000.0)
	if not ["vsync", "cap", "unlimited"].has(str(values["frame_mode"])):
		values["frame_mode"] = "vsync"
	if not SKIES.has(str(values["sky"])):
		values["sky"] = "cycle"
	return values


static func save_settings(values: Dictionary) -> void:
	var file := ConfigFile.new()
	for key in DEFAULTS:
		file.set_value(SECTION, key, values.get(key, DEFAULTS[key]))
	file.save(PATH)


## Puts the settings into effect. `forest` is forest.gd, or null.
static func apply(values: Dictionary, forest: Node) -> void:
	match str(values["frame_mode"]):
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			Engine.max_fps = 0
		"cap":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = int(values["frame_cap"])
		_:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
	if forest != null:
		forest.set_draw_distance(float(values["tree_distance"]))
