extends RefCounted
## Saving and loading builds as plain-text JSON files in the game's "saves"
## folder. The files are meant to be shared, edited by hand, or written by
## other programs. saves/README.txt describes the format.

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const PartSettings = preload("res://scripts/part_settings.gd")

const FORMAT := "ideal-world-build"
const VERSION := 1
const EXTENSION := ".json"
const FORBIDDEN := "\\/:*?\"<>|"   # characters a file name may not contain


## The saves folder: inside the project when run from Godot, beside the
## program when run as an exported game.
static func saves_dir() -> String:
	var base := ""
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	else:
		base = OS.get_executable_path().get_base_dir()
	return base.path_join("saves")


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(saves_dir())


## Turns whatever was typed into a safe file name, without the extension.
static func clean_name(typed: String) -> String:
	var cleaned := typed.strip_edges()
	for index in FORBIDDEN.length():
		cleaned = cleaned.replace(FORBIDDEN[index], "_")
	if cleaned.to_lower().ends_with(EXTENSION):
		cleaned = cleaned.substr(0, cleaned.length() - EXTENSION.length())
	return cleaned.strip_edges()


static func path_for(save_name: String) -> String:
	return saves_dir().path_join(save_name + EXTENSION)


static func exists(save_name: String) -> bool:
	return FileAccess.file_exists(path_for(save_name))


## The names of every save in the folder, in alphabetical order.
static func list_saves() -> Array:
	ensure_dir()
	var names: Array = []
	var dir := DirAccess.open(saves_dir())
	if dir == null:
		return names
	for file_name in dir.get_files():
		if file_name.to_lower().ends_with(EXTENSION):
			names.append(file_name.substr(0, file_name.length() - EXTENSION.length()))
	names.sort()
	return names


static func delete_save(save_name: String) -> bool:
	return DirAccess.remove_absolute(path_for(save_name)) == OK


# --- Saving ------------------------------------------------------------------

static func _in_blocks(units: Vector3i) -> Array:
	var per_block := float(Units.UNITS_PER_CELL)
	return [units.x / per_block, units.y / per_block, units.z / per_block]


static func _whole(axis: Vector3) -> Array:
	return [int(round(axis.x)), int(round(axis.y)), int(round(axis.z))]


static func _record_to_entry(record: Dictionary) -> Dictionary:
	var pos: Vector3i = record["pos"]
	var size: Vector3i = record["size"]
	var rot: Basis = record["rot"]
	var color: Color = record["color"]
	var entry := {
		"type": record["type"],
		"pos": _in_blocks(pos),
		"size": _in_blocks(size),
		"x_axis": _whole(rot.x),
		"y_axis": _whole(rot.y),
		"z_axis": _whole(rot.z),
		"material": record["material"],
		"color": "#" + color.to_html(false),
	}
	var props: Dictionary = record.get("props", {})
	if not props.is_empty():
		entry["settings"] = PartSettings.to_plain(props)
	return entry


## Writes the whole build to a file. Returns "" on success or the reason it failed.
static func save_build(grid: Node, save_name: String) -> String:
	ensure_dir()
	var entries: Array = []
	for uid in grid.all_uids():
		var record: Dictionary = grid.get_part(uid)
		entries.append(_record_to_entry(record))
	var data := {
		"format": FORMAT,
		"version": VERSION,
		"name": save_name,
		"block_size_m": Units.CELL,
		"parts": entries,
	}
	var file := FileAccess.open(path_for(save_name), FileAccess.WRITE)
	if file == null:
		return "Could not write to %s" % path_for(save_name)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return ""


# --- Loading -----------------------------------------------------------------

## Reads a list of three numbers. Returns a Vector3, or null if it is not one.
static func _three_numbers(value: Variant) -> Variant:
	if not (value is Array):
		return null
	var list: Array = value
	if list.size() != 3:
		return null
	for item in list:
		if not (item is float or item is int):
			return null
	return Vector3(float(list[0]), float(list[1]), float(list[2]))


## A whole number of quarter turns about one world axis, with exact entries.
static func _quarter_turns(axis: Vector3, degrees: float) -> Basis:
	var quarters := int(round(degrees / 90.0))
	var turn := Basis(axis, float(quarters) * PI * 0.5)
	return Basis(turn.x.round(), turn.y.round(), turn.z.round())


## Reads a part's rotation. Two spellings are accepted:
##   "rotation": [x, y, z]   degrees in steps of 90, applied about the world
##                           X axis, then Y, then Z, like pressing R, T, Y
##   "x_axis", "y_axis", "z_axis"   where the part's own axes end up pointing
## Anything missing or not a clean quarter-turn rotation means "not rotated".
static func _read_rotation(entry: Dictionary) -> Basis:
	var turns: Variant = _three_numbers(entry.get("rotation"))
	if turns != null:
		var degrees: Vector3 = turns
		var about_x := _quarter_turns(Vector3(1.0, 0.0, 0.0), degrees.x)
		var about_y := _quarter_turns(Vector3(0.0, 1.0, 0.0), degrees.y)
		var about_z := _quarter_turns(Vector3(0.0, 0.0, 1.0), degrees.z)
		var combined := about_z * about_y * about_x
		return Basis(combined.x.round(), combined.y.round(), combined.z.round())
	var x_axis: Variant = _three_numbers(entry.get("x_axis"))
	var y_axis: Variant = _three_numbers(entry.get("y_axis"))
	var z_axis: Variant = _three_numbers(entry.get("z_axis"))
	if x_axis == null or y_axis == null or z_axis == null:
		return Basis.IDENTITY
	var x: Vector3 = x_axis
	var y: Vector3 = y_axis
	var z: Vector3 = z_axis
	var rot := Basis(x.round(), y.round(), z.round())
	if absf(rot.determinant() - 1.0) > 0.01 or not rot.is_equal_approx(rot.orthonormalized()):
		return Basis.IDENTITY
	return rot


## Turns one entry from a save file into a part record, or {} if it is unusable.
static func _entry_to_record(entry: Dictionary) -> Dictionary:
	var type := str(entry.get("type", ""))
	if not PartLibrary.PARTS.has(type):
		return {}
	var pos_value: Variant = _three_numbers(entry.get("pos"))
	if pos_value == null:
		return {}
	var per_block := float(Units.UNITS_PER_CELL)
	var pos_blocks: Vector3 = pos_value
	var pos := Vector3i((pos_blocks * per_block).round())

	var size: Vector3i = BuildGrid.default_size_units(type)
	var size_value: Variant = _three_numbers(entry.get("size"))
	if size_value != null:
		var size_blocks: Vector3 = size_value
		size = Vector3i((size_blocks * per_block).round())
		size = size.clamp(Vector3i.ONE, Vector3i.ONE * BuildGrid.MAX_SIZE_UNITS)

	var material := str(entry.get("material", MaterialLibrary.DEFAULT_ID))
	if not MaterialLibrary.MATERIALS.has(material):
		material = MaterialLibrary.DEFAULT_ID

	var color: Color = PartLibrary.placement_color(type, MaterialLibrary.default_color(material))
	var color_text := str(entry.get("color", ""))
	if color_text != "" and Color.html_is_valid(color_text):
		color = Color.html(color_text)

	var record: Dictionary = BuildGrid.make_record(type, pos, _read_rotation(entry), size, material, color)
	record["props"] = PartSettings.sanitize(type, entry.get("settings"))
	return record


## Replaces the current build with a saved one.
## Returns {"error": String, "loaded": int, "skipped": int}. On an error the
## current build is left untouched.
static func load_build(grid: Node, save_name: String) -> Dictionary:
	var result := {"error": "", "loaded": 0, "skipped": 0}
	var path := path_for(save_name)
	if not FileAccess.file_exists(path):
		result["error"] = "There is no save called \"%s\"." % save_name
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		result["error"] = "\"%s\" is not a readable build file." % save_name
		return result
	var data: Dictionary = parsed
	var entries: Variant = data.get("parts")
	if str(data.get("format", "")) != FORMAT or not (entries is Array):
		result["error"] = "\"%s\" is not an Ideal World build file." % save_name
		return result

	var records: Array = []
	var skipped := 0
	for entry in entries:
		var record: Dictionary = {}
		if entry is Dictionary:
			record = _entry_to_record(entry)
		if record.is_empty():
			skipped += 1
		else:
			records.append(record)

	grid.begin_batch()
	grid.clear()
	var loaded := 0
	for record in records:
		var uid: int = grid.add_part(record)
		if uid == 0:
			skipped += 1   # outside the grid, or overlapping a different material
		else:
			loaded += 1
	grid.end_batch()

	result["loaded"] = loaded
	result["skipped"] = skipped
	return result
