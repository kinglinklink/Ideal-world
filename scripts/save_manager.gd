extends RefCounted
## Saving and loading builds as plain-text JSON files in the game's "saves"
## folder. The files are meant to be shared, edited by hand, or written by
## other programs. saves/README.txt describes the format.

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const PartSettings = preload("res://scripts/part_settings.gd")
const PartPorts = preload("res://scripts/part_ports.gd")

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
	var uids: Array = grid.all_uids()
	var index_of: Dictionary = {}   # part uid -> its position in the file's parts list
	for index in uids.size():
		index_of[uids[index]] = index
	for uid in uids:
		var record: Dictionary = grid.get_part(uid)
		var entry: Dictionary = _record_to_entry(record)
		# A link names its source part by position in the parts list, from 0.
		var links: Dictionary = record.get("links", {})
		var plain_links: Dictionary = {}
		for input_id in links:
			var link: Dictionary = links[input_id]
			var source: int = int(link.get("uid", 0))
			if index_of.has(source):
				plain_links[input_id] = {"part": index_of[source], "output": str(link.get("output", ""))}
		if not plain_links.is_empty():
			entry["links"] = plain_links
		entries.append(entry)
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


## Turns the links written for one part into real links, dropping any that
## name a missing part, an unknown port, or ports that cannot connect.
static func _read_links(grid: Node, uid: int, written: Dictionary, uid_at: Dictionary) -> Dictionary:
	var links: Dictionary = {}
	var own: Dictionary = grid.get_part(uid)
	var inputs: Array = PartPorts.inputs_of(own["type"])
	for input_id in written:
		var input_port: Array = PartPorts.find_port(inputs, str(input_id))
		var link: Variant = written[input_id]
		if input_port.is_empty() or not (link is Dictionary):
			continue
		var source_position: Variant = (link as Dictionary).get("part")
		if not (source_position is float or source_position is int):
			continue
		var source_key: int = int(source_position)
		if not uid_at.has(source_key):
			continue
		var source_uid: int = uid_at[source_key]
		var source: Dictionary = grid.get_part(source_uid)
		var output_id := str((link as Dictionary).get("output", ""))
		var output_port: Array = PartPorts.find_port(PartPorts.outputs_of(source["type"]), output_id)
		if output_port.is_empty() or not PartPorts.compatible(input_port, output_port):
			continue
		links[str(input_id)] = {"uid": source_uid, "output": output_id}
	return links


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

	var records: Array = []      # [position in the file, record, that part's links as written]
	var skipped := 0
	var position := 0
	for entry in entries:
		var record: Dictionary = {}
		var written_links: Variant = null
		if entry is Dictionary:
			record = _entry_to_record(entry)
			written_links = (entry as Dictionary).get("links")
		if record.is_empty():
			skipped += 1
		else:
			records.append([position, record, written_links])
		position += 1

	grid.begin_batch()
	grid.clear()
	var loaded := 0
	var uid_at: Dictionary = {}   # position in the file -> the uid that part was given
	for item in records:
		var uid: int = grid.add_part(item[1])
		if uid == 0:
			skipped += 1   # outside the grid, or overlapping a different material
		else:
			loaded += 1
			uid_at[item[0]] = uid
	# With every part in place, connect the links the file describes.
	for item in records:
		if not uid_at.has(item[0]) or not (item[2] is Dictionary):
			continue
		var uid: int = uid_at[item[0]]
		var links: Dictionary = _read_links(grid, uid, item[2], uid_at)
		if not links.is_empty():
			grid.set_links(uid, links)
	grid.end_batch()

	result["loaded"] = loaded
	result["skipped"] = skipped
	return result
