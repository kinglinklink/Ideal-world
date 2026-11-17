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
##   render_scale   the share of full resolution the 3D view is drawn at, 50 to 100 (%)
##   msaa           edge smoothing: "off", "2x" or "4x"
##   shadows        whether the sun casts shadows
##   volume_*       master, effects, machines, ambience and interface volumes, 0 to 100
##   crash_damage   whether hard knocks damage spawned parts
##   structural_failure  whether overloaded parts break (stress.gd)
##   player_damage  whether the character can be hurt
##
## The physics always runs 240 steps a second, whatever the frame rate.

const Sound = preload("res://scripts/sound.gd")
const Spawner = preload("res://scripts/spawner.gd")
const Stress = preload("res://scripts/stress.gd")
const Player = preload("res://scripts/player.gd")
const Disasters = preload("res://scripts/disasters.gd")

const PATH := "user://settings.cfg"
const SKIES := ["cycle", "day", "night"]
const SECTION := "settings"
const DEFAULTS := {
	"frame_mode": "vsync",
	"frame_cap": 60,
	"tree_distance": 2600.0,
	"show_fps": true,
	"sky": "cycle",
	"render_scale": 100,
	"msaa": "2x",
	"shadows": true,
	"volume_master": 80,
	"volume_effects": 80,
	"volume_machines": 80,
	"volume_ambience": 70,
	"volume_interface": 60,
	"crash_damage": true,
	"structural_failure": true,
	"player_damage": true,
	"random_disasters": true,
}
const MSAA := ["off", "2x", "4x"]


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
	if not MSAA.has(str(values["msaa"])):
		values["msaa"] = "2x"
	values["render_scale"] = clampi(int(values["render_scale"]), 50, 100)
	for key in ["volume_master", "volume_effects", "volume_machines", "volume_ambience", "volume_interface"]:
		values[key] = clampi(int(values[key]), 0, 100)
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
	var root := (Engine.get_main_loop() as SceneTree).root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = float(values["render_scale"]) / 100.0
	root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][MSAA.find(str(values["msaa"]))]
	Sound.apply_volumes(values)
	Spawner.crash_damage = bool(values["crash_damage"])
	Stress.failure = bool(values["structural_failure"])
	Player.damage_enabled = bool(values["player_damage"])
	Disasters.random_events = bool(values["random_disasters"])
