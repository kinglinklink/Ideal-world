extends RefCounted
## The player's progress, in one of three save slots: cash from races, cargo
## and photos, the races won and best times, cargo runs done, the bird
## guide (which birds were spotted and photographed, and when), and where
## the year and the day had got to. Stored as JSON in the user folder
## (user://profiles/slot1.json to slot3.json). The single profile.json of
## older builds becomes slot 1, so nothing earned is lost.
##
## Builds, sub-assemblies and photos are not in a slot: they are shared by
## all three.

const SLOTS := 3
const DIR := "user://profiles"
const OLD_PATH := "user://profile.json"

static var slot := 1                 # the slot being played
static var _data: Dictionary = {}
static var _loaded := false


static func path_of(which: int) -> String:
	return DIR.path_join("slot%d.json" % which)


static func _migrate() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if FileAccess.file_exists(OLD_PATH) and not FileAccess.file_exists(path_of(1)):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(OLD_PATH), ProjectSettings.globalize_path(path_of(1)))


static func _read(which: int) -> Dictionary:
	_migrate()
	var data: Dictionary = {}
	if FileAccess.file_exists(path_of(which)):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_of(which)))
		if parsed is Dictionary:
			data = parsed
	_fill(data)
	return data


static func _fill(data: Dictionary) -> void:
	if not data.has("cash"):
		data["cash"] = 0
	for key in ["best", "won", "birds", "missions", "ghosts"]:
		if not (data.get(key) is Dictionary):
			data[key] = {}
	if not data.has("cargo_runs"):
		data["cargo_runs"] = 0


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _read(slot)


static func _save() -> void:
	_load()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_data["last_played"] = Time.get_datetime_string_from_system(false, true)
	var file := FileAccess.open(path_of(slot), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_data, "\t"))


## Saves now (the game calls this when quitting and now and then).
static func save() -> void:
	_save()


# --- Slots ------------------------------------------------------------------------

## Plays slot `which` from now on (1 to 3).
static func use_slot(which: int) -> void:
	slot = clampi(which, 1, SLOTS)
	_loaded = false
	_load()


static func slot_exists(which: int) -> bool:
	_migrate()
	return FileAccess.file_exists(path_of(which))


## What a slot's card shows: cash, races won, birds photographed, last played.
static func slot_summary(which: int) -> Dictionary:
	var data := _read(which)
	var photographed := 0
	for key in data["birds"]:
		# "photo" is the photo's file name, empty until there is one.
		if str((data["birds"][key] as Dictionary).get("photo", "")) != "":
			photographed += 1
	return {"exists": slot_exists(which), "cash": int(data["cash"]), "won": (data["won"] as Dictionary).size(),
			"photographed": photographed, "last_played": str(data.get("last_played", ""))}


## Starts a slot over, empty.
static func new_game(which: int) -> void:
	slot = clampi(which, 1, SLOTS)
	_data = {}
	_fill(_data)
	_loaded = true
	_save()


static func delete_slot(which: int) -> void:
	_migrate()
	if FileAccess.file_exists(path_of(which)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_of(which)))
	if which == slot:
		_loaded = false


# --- Cash ---------------------------------------------------------------------------

static func cash() -> int:
	_load()
	return int(_data["cash"])


static func add_cash(amount: int) -> void:
	_load()
	_data["cash"] = maxi(int(_data["cash"]) + amount, 0)
	_save()


## Takes `amount` if there is that much. True if paid.
static func spend(amount: int) -> bool:
	_load()
	if amount <= 0:
		return true
	if int(_data["cash"]) < amount:
		return false
	_data["cash"] = int(_data["cash"]) - amount
	_save()
	return true


# --- Races and cargo -----------------------------------------------------------------

## The best time on a race in seconds, or 0 if it has never been finished.
static func best_time(race_id: String) -> float:
	_load()
	return float((_data["best"] as Dictionary).get(race_id, 0.0))


## Records a finish. Returns true if it is a new best.
static func record_time(race_id: String, seconds: float) -> bool:
	_load()
	var best: Dictionary = _data["best"]
	var old := float(best.get(race_id, 0.0))
	if old <= 0.0 or seconds < old:
		best[race_id] = seconds
		_save()
		return true
	return false


static func mark_won(race_id: String) -> void:
	_load()
	(_data["won"] as Dictionary)[race_id] = true
	_save()


static func has_won(race_id: String) -> bool:
	_load()
	return bool((_data["won"] as Dictionary).get(race_id, false))


static func add_cargo_run() -> void:
	_load()
	_data["cargo_runs"] = int(_data["cargo_runs"]) + 1
	_save()


static func cargo_runs() -> int:
	_load()
	return int(_data["cargo_runs"])


## Missions done (photo jobs and the like): id -> true.
static func mission_done(mission_id: String) -> bool:
	_load()
	return bool((_data["missions"] as Dictionary).get(mission_id, false))


static func mark_mission(mission_id: String) -> void:
	_load()
	(_data["missions"] as Dictionary)[mission_id] = true
	_save()


# --- Ghosts --------------------------------------------------------------------------

## Where this slot keeps its ghost runs: saves/ghosts/slotN.
static func ghosts_dir(saves_dir: String) -> String:
	return saves_dir.path_join("ghosts").path_join("slot%d" % slot)


# --- Birds ----------------------------------------------------------------------------

## The bird guide's record of a species: {"spotted": date, "photo": file name} or empty.
static func bird(species: String) -> Dictionary:
	_load()
	return (_data["birds"] as Dictionary).get(species, {})


## First sighting of a species. True if it is new.
static func spot_bird(species: String) -> bool:
	_load()
	var birds: Dictionary = _data["birds"]
	if birds.has(species):
		return false
	birds[species] = {"spotted": Time.get_date_string_from_system(), "photo": ""}
	_save()
	return true


## A photo with the species in it. True if it is its first.
static func photograph_bird(species: String, photo_file: String) -> bool:
	_load()
	spot_bird(species)
	var entry: Dictionary = (_data["birds"] as Dictionary)[species]
	var first := str(entry.get("photo", "")) == ""
	if first:
		entry["photo"] = photo_file
		_save()
	return first


# --- The clock ---------------------------------------------------------------------------

## Where the year and the day were: {"year": 0..1, "day": count, "time": 0..1}.
static func clock() -> Dictionary:
	_load()
	return _data.get("clock", {})


static func set_clock(year_fraction: float, day: int, time_of_day: float) -> void:
	_load()
	_data["clock"] = {"year": year_fraction, "day": day, "time": time_of_day}


static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if amount < 0 else "") + "$" + digits + grouped
