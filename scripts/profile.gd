extends RefCounted
## The player's progress, kept between games: cash earned from races and
## cargo runs, and the best time on each race. Stored as JSON in the user
## folder (user://profile.json).

const PATH := "user://profile.json"

static var _data: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
	if not _data.has("cash"):
		_data["cash"] = 0
	if not (_data.get("best") is Dictionary):
		_data["best"] = {}


static func _save() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_data, "\t"))


static func cash() -> int:
	_load()
	return int(_data["cash"])


static func add_cash(amount: int) -> void:
	_load()
	_data["cash"] = maxi(int(_data["cash"]) + amount, 0)
	_save()


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


static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if amount < 0 else "") + "$" + digits + grouped
