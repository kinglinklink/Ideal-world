extends Node
## The game's sound. One of these is made by main.gd; other scripts reach it
## through its static functions (Sound.play_at and so on), which do nothing
## if it is not there.
##
## Four groups, each with its own volume in Settings: Effects (guns, blasts,
## collapses, splashes), Machines (motors, jets, rockets, propellers,
## engines), Ambience (wind, birds, crickets) and Interface (clicks). The
## sounds themselves are made by tools/make_sounds.py.
##
## Machines are heard from where they are: each running motor, thruster,
## jet, rocket, propeller and pump on a spawned build carries its own
## looping sound, louder and higher as it works harder. Wind rises with the
## character's speed. By day there is a breeze and birds; at night, crickets.

const Origin = preload("res://scripts/origin.gd")

const BUSES := ["Effects", "Machines", "Ambience", "Interface"]
const FILES := {
	"motor_loop": "res://sounds/motor_loop.wav", "jet_loop": "res://sounds/jet_loop.wav",
	"rocket_loop": "res://sounds/rocket_loop.wav", "prop_loop": "res://sounds/prop_loop.wav",
	"thruster_loop": "res://sounds/thruster_loop.wav",
	"wind_loop": "res://sounds/wind_loop.wav", "day_loop": "res://sounds/day_loop.wav",
	"night_loop": "res://sounds/night_loop.wav", "gunshot": "res://sounds/gunshot.wav",
	"cannon": "res://sounds/cannon.wav", "explosion": "res://sounds/explosion.wav",
	"collapse": "res://sounds/collapse.wav", "piston_pop": "res://sounds/piston_pop.wav",
	"click": "res://sounds/click.wav", "place": "res://sounds/place.wav",
	"remove": "res://sounds/remove.wav", "spawn": "res://sounds/spawn.wav",
	"splash": "res://sounds/splash.wav",
	"rain_loop": "res://sounds/rain_loop.wav", "tornado_loop": "res://sounds/tornado_loop.wav",
	"car_loop": "res://sounds/car_loop.wav", "plane_loop": "res://sounds/plane_loop.wav",
	"thunder": "res://sounds/thunder.wav", "rumble": "res://sounds/rumble.wav",
	"eruption": "res://sounds/eruption.wav", "wave_crash": "res://sounds/wave_crash.wav",
	"beep": "res://sounds/beep.wav", "go": "res://sounds/go.wav",
	"checkpoint": "res://sounds/checkpoint.wav", "cash": "res://sounds/cash.wav",
	"fire_loop": "res://sounds/fire_loop.wav", "fire_whoosh": "res://sounds/fire_whoosh.wav",
	"sputter": "res://sounds/sputter.wav", "spark": "res://sounds/spark.wav",
	"shutter": "res://sounds/shutter.wav", "boat_loop": "res://sounds/boat_loop.wav",
	"chirp": "res://sounds/chirp.wav",
}
const LOOPS := ["motor_loop", "jet_loop", "rocket_loop", "thruster_loop", "prop_loop", "wind_loop", "day_loop",
		"night_loop", "rain_loop", "tornado_loop", "car_loop", "plane_loop", "fire_loop", "boat_loop"]
const VOICES := 24            # one-shots that can sound at once; the oldest gives way
const MAX_MACHINES := 32      # machine sounds on one build
const GUN_GAP := 0.03         # s: shots from guns closer together than this share one sound

static var instance: Node = null
## How hard it is raining, 0 to 1, and how windy, in m/s: set by weather.gd.
static var rain_amount := 0.0
static var wind_speed := 0.0

var spawner: Node = null      # spawner.gd
var player: Node3D = null     # player.gd
var daylight: Node = null     # daylight.gd
var fleet: Node = null        # fleet.gd: its vehicles' machines are heard too

var _streams: Dictionary = {}
var _voices: Array = []       # AudioStreamPlayer3D, reused in turn
var _next_voice := 0
var _flat: AudioStreamPlayer  # interface sounds, not placed in the world
var _wind: AudioStreamPlayer
var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _generation := -1
var _machines: Array = []     # {"uid", "type", "player", "full"}
var _last_gun := -1.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	make_buses()
	for key in FILES:
		var path: String = FILES[key]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if LOOPS.has(key) and stream is AudioStreamWAV:
				var wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate()
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(wav.get_length() * wav.mix_rate)
				stream = wav
			_streams[key] = stream
	for index in VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "Effects"
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		_voices.append(voice)
	_flat = AudioStreamPlayer.new()
	_flat.bus = "Interface"
	_flat.process_mode = Node.PROCESS_MODE_ALWAYS   # menu clicks while the game is paused
	add_child(_flat)
	_wind = _ambient("wind_loop")
	_day = _ambient("day_loop")
	_night = _ambient("night_loop")
	_rain = _ambient("rain_loop")


func _ambient(key: String) -> AudioStreamPlayer:
	var sound := AudioStreamPlayer.new()
	sound.bus = "Ambience"
	sound.process_mode = Node.PROCESS_MODE_ALWAYS   # heard on the title screen and pause menu too
	sound.stream = _streams.get(key)
	sound.volume_db = -80.0
	add_child(sound)
	if sound.stream != null:
		sound.play()
	return sound


## Makes the four sound groups if they are not there yet.
static func make_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


## Sets the volumes from the settings: volume_master and one per group, 0 to 100.
static func apply_volumes(values: Dictionary) -> void:
	make_buses()
	var pairs := {"Master": "volume_master", "Effects": "volume_effects", "Machines": "volume_machines",
			"Ambience": "volume_ambience", "Interface": "volume_interface"}
	for bus_name in pairs:
		var index := AudioServer.get_bus_index(bus_name)
		if index == -1:
			continue
		var share := clampf(float(values.get(pairs[bus_name], 80.0)) / 100.0, 0.0, 1.0)
		AudioServer.set_bus_mute(index, share <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(share, 0.001)))


## Plays a sound at a place in the world. `loudness` is in decibels and
## `reach` sets how far it carries (metres to where it has fallen to half).
static func play_at(key: String, where: Vector3, loudness: float = 0.0, reach: float = 20.0, pitch: float = 1.0) -> void:
	if instance != null:
		instance._play_at(key, where, loudness, reach, pitch)


## A looping sound to carry on a node of your own (a tornado, a car), not
## yet playing. Null if the sound is missing. `bus` is one of BUSES.
static func make_loop(key: String, bus: String = "Effects") -> AudioStreamPlayer3D:
	if instance == null or not instance._streams.has(key):
		return null
	var sound := AudioStreamPlayer3D.new()
	sound.stream = instance._streams[key]
	sound.bus = bus
	sound.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return sound


## Plays a sound with no place: the interface.
static func play_ui(key: String) -> void:
	if instance != null:
		instance._play_ui(key)


## A gun or cannon firing: guns firing many rounds a second share sounds.
static func gun(key: String, where: Vector3, loudness: float = 0.0, reach: float = 40.0) -> void:
	if instance == null:
		return
	instance._gun(key, where, loudness, reach)


func _gun(key: String, where: Vector3, loudness: float, reach: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if key == "gunshot" and now - _last_gun < GUN_GAP:
		return
	_last_gun = now
	_play_at(key, where, loudness, reach, randf_range(0.94, 1.06))


func _play_at(key: String, where: Vector3, loudness: float, reach: float, pitch: float) -> void:
	if not _streams.has(key):
		return
	var voice: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _streams[key]
	voice.volume_db = loudness
	voice.unit_size = reach
	voice.max_distance = reach * 60.0
	voice.pitch_scale = pitch
	voice.global_position = where
	voice.play()


func _play_ui(key: String) -> void:
	if not _streams.has(key):
		return
	_flat.stream = _streams[key]
	_flat.play()


# --- Every frame ---------------------------------------------------------------

func _process(_delta: float) -> void:
	_run_ambience()
	if fleet != null:
		for item in fleet.vehicles:
			var vehicle: Dictionary = item
			if not is_instance_valid(vehicle["spawner"]):
				continue
			var vehicle_spawner: Node = vehicle["spawner"]
			if not bool(vehicle_spawner.spawned):
				continue
			if not vehicle.has("sounds"):
				vehicle["sounds"] = _find_machines(vehicle_spawner)
			_run_machines(vehicle_spawner, vehicle["sounds"])
	if spawner == null:
		return
	if not bool(spawner.spawned):
		if _generation != -1:
			_generation = -1
			_machines.clear()   # their players went with the bodies
		return
	if int(spawner.generation) != _generation:
		_generation = int(spawner.generation)
		_machines = _find_machines(spawner)
		if not spawner.parts_added.is_connected(_on_parts_added):
			spawner.parts_added.connect(_on_parts_added)
	_run_machines(spawner, _machines)


func _run_ambience() -> void:
	var speed := 0.0
	if player != null:
		var moving: Vector3 = player.ride_velocity if bool(player.seated) else player.velocity
		speed = moving.length()
	# Wind: nothing standing still, loud past 80 m/s, higher as it gets faster.
	var gust := clampf((speed - 3.0) / 80.0, 0.0, 1.0)
	_wind.volume_db = linear_to_db(maxf(gust, 0.0001)) + 2.0
	_wind.pitch_scale = 0.75 + gust * 0.6
	# Birds by day and crickets by night, faded under the wind.
	var night := 0.0
	if daylight != null:
		night = float(daylight.night_amount())
	var quiet := 1.0 - clampf(speed / 30.0, 0.0, 0.9)
	# Birds and crickets hush in the rain; the rain itself, and the wind on a
	# stormy day even standing still.
	var dry := 1.0 - clampf(rain_amount * 1.5, 0.0, 0.95)
	_day.volume_db = linear_to_db(maxf((1.0 - night) * quiet * 0.6 * dry, 0.0001))
	_night.volume_db = linear_to_db(maxf(night * quiet * 0.6 * dry, 0.0001))
	_rain.volume_db = linear_to_db(maxf(rain_amount * 0.8, 0.0001))
	var weather_gust := clampf((wind_speed - 6.0) / 30.0, 0.0, 1.0)
	if weather_gust > gust:
		_wind.volume_db = linear_to_db(maxf(weather_gust * 0.8, 0.0001)) + 2.0
		_wind.pitch_scale = 0.7 + weather_gust * 0.4


## Gives every machine on a newly spawned build a looping sound, carried on
## its part. Returns the list for _run_machines.
## Parts made while the build is out (a reload gate's payload) get their
## sounds too.
func _on_parts_added(uids: Array) -> void:
	if _generation == int(spawner.generation):
		_find_machines(spawner, uids, _machines)


func _find_machines(source: Node, only: Array = [], found: Array = []) -> Array:
	var records: Dictionary = source.all_records()
	var uids: Array = only if not only.is_empty() else records.keys()
	for key in uids:
		if found.size() >= MAX_MACHINES:
			break
		var uid: int = key
		var record: Dictionary = records.get(uid, {})
		if record.is_empty():
			continue
		var type: String = record["type"]
		var props: Dictionary = record.get("props", {})
		var loop := ""
		var full := 1.0   # the output that counts as working flat out
		match type:
			"motor":
				loop = "motor_loop"
				full = maxf(float(props.get("max_speed", 600.0)), 1.0)
			"pump":
				loop = "motor_loop"
				full = maxf(absf(float(props.get("max_flow", 1.0))), 0.001)
			"thruster":
				loop = "thruster_loop"
				full = maxf(float(props.get("thrust", 1000.0)), 1.0)
			"solid_rocket":
				loop = "rocket_loop"
				full = maxf(float(props.get("thrust", 5000.0)), 1.0)
			"nozzle":
				loop = "jet_loop"
				full = 12000.0
			"propeller":
				loop = "prop_loop"
				full = 2400.0
		if loop == "" or not _streams.has(loop):
			continue
		var stream: AudioStream = _streams[loop]
		var made: Node3D = source.attach_extra(uid, func(place: Transform3D, _size: Vector3) -> Node3D:
			var sound := AudioStreamPlayer3D.new()
			sound.stream = stream
			sound.bus = "Machines"
			sound.transform = place
			sound.volume_db = -80.0
			sound.autoplay = false
			return sound)
		if made == null:
			continue
		found.append({"uid": uid, "type": type, "player": made, "full": full, "props": props})
	return found


func _run_machines(source: Node, machines: Array) -> void:
	for item in machines:
		var machine: Dictionary = item
		# The part (and its sound with it) may have been shot off.
		if not is_instance_valid(machine["player"]):
			continue
		var sound: AudioStreamPlayer3D = machine["player"]
		var uid: int = machine["uid"]
		var type: String = machine["type"]
		var outputs: Dictionary = source.outputs_of(uid)
		var level := 0.0   # 0 idle to 1 flat out
		var size := 1.0    # how big it is, for how far it carries
		match type:
			"motor":
				level = absf(float(outputs.get("shaft_speed", 0.0))) / float(machine["full"])
				size = sqrt(maxf(float((machine["props"] as Dictionary).get("max_torque", 100.0)), 1.0)) * 0.3
			"pump":
				level = absf(float(outputs.get("flow", 0.0))) / float(machine["full"]) * 0.6
			"thruster":
				level = absf(float(outputs.get("thrust", 0.0))) / float(machine["full"])
				size = sqrt(float(machine["full"])) * 0.06
			"solid_rocket":
				level = absf(float(outputs.get("thrust", 0.0))) / float(machine["full"])
				size = sqrt(float(machine["full"])) * 0.15
			"nozzle":
				# A jet sounds by its thrust; the spool shows in the pitch.
				level = clampf(float(outputs.get("thrust", 0.0)) / 20000.0, 0.0, 1.5)
				size = 25.0
			"propeller":
				level = absf(float(outputs.get("speed", 0.0))) / float(machine["full"])
				size = 12.0
		level = clampf(level, 0.0, 1.5)
		if level < 0.02:
			if sound.playing:
				sound.stop()
			continue
		if not sound.playing:
			sound.play()
		sound.unit_size = clampf(size, 2.0, 80.0)
		sound.max_distance = sound.unit_size * 150.0
		# Fade in from silence over the first tenth of the range, so a shaft or
		# propeller turning over slowly (say, settling after a spawn) is not a
		# loud low drone.
		var fade := clampf((level - 0.02) / 0.1, 0.0, 1.0)
		sound.volume_db = linear_to_db(maxf(fade * (0.25 + 0.75 * minf(level, 1.0)), 0.0001))
		if type == "thruster":
			sound.volume_db -= 10.0   # a steady push should not drown everything else
		match type:
			"motor", "pump":
				sound.pitch_scale = clampf(0.35 + level * 1.3, 0.2, 3.0)
			"propeller":
				sound.pitch_scale = clampf(0.4 + level * 1.4, 0.2, 3.0)
			"nozzle":
				sound.pitch_scale = clampf(0.7 + level * 0.4, 0.5, 1.6)
			_:
				sound.pitch_scale = clampf(0.85 + level * 0.25, 0.5, 1.5)
