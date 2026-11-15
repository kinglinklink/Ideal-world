extends Node3D
## The build pad's contents: every part, with its exact size and position.
##
## The grid's minimum corner sits at this node's origin and Y is up. A part's
## position is the centre of its bounding box. Positions and sizes are whole
## numbers of units (see units.gd), so nothing drifts.

signal parts_changed

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")

const SIZE := Vector3i(128, 128, 256)   # cells: X width, Y height, Z length
const MAX_SIZE_UNITS := 64 * 200        # largest single part: 64 cells per side
const EPSILON := 0.0001                 # metres; keeps touching parts from counting as overlapping

var _parts: Dictionary = {}   # uid -> record (see make_record)
var _nodes: Dictionary = {}   # uid -> StaticBody3D
var _next_uid := 1


# --- Records -----------------------------------------------------------------

## Builds the plain-data description of one part.
static func make_record(type: String, pos: Vector3i, rot: Basis, size: Vector3i,
		material: String, color: Color) -> Dictionary:
	return {
		"type": type,       # part id from part_library.gd
		"pos": pos,         # units, centre of the part, relative to the grid corner
		"rot": rot,         # quarter-turn rotation
		"size": size,       # units, along the part's own axes
		"material": material,
		"color": color,
	}


static func default_size_units(type: String) -> Vector3i:
	var cells := PartLibrary.default_size_cells(type)
	return Vector3i((cells * float(Units.UNITS_PER_CELL)).round())


func cell_center_units(cell: Vector3i) -> Vector3i:
	return cell * Units.UNITS_PER_CELL + Vector3i(Units.HALF_CELL_UNITS, Units.HALF_CELL_UNITS, Units.HALF_CELL_UNITS)


## The cell containing a point given in this node's local space (metres).
func point_to_cell(local_point: Vector3) -> Vector3i:
	return Vector3i((local_point / Units.CELL).floor())


func size_metres() -> Vector3:
	return Vector3(SIZE) * Units.CELL


## Half the size of a part's world-aligned bounding box, in units (may end in .5).
static func half_extent_units(record: Dictionary) -> Vector3:
	var rot: Basis = record["rot"]
	var size := Vector3(record["size"] as Vector3i)
	var along_x := (rot.x * size.x).abs()
	var along_y := (rot.y * size.y).abs()
	var along_z := (rot.z * size.z).abs()
	return (along_x + along_y + along_z) * 0.5


## A part's bounding box in this node's local space, in metres.
static func bounds_of(record: Dictionary) -> AABB:
	var half := half_extent_units(record) * Units.UNIT
	var center := Vector3(record["pos"] as Vector3i) * Units.UNIT
	return AABB(center - half, half * 2.0)


static func _overlaps(a: AABB, b: AABB) -> bool:
	return a.grow(-EPSILON).intersects(b)


# --- Queries -----------------------------------------------------------------

func part_count() -> int:
	return _parts.size()


func has_part(uid: int) -> bool:
	return _parts.has(uid)


func all_uids() -> Array:
	return _parts.keys()


## A copy of a part's record, or an empty dictionary.
func get_part(uid: int) -> Dictionary:
	if not _parts.has(uid):
		return {}
	return (_parts[uid] as Dictionary).duplicate()


func get_node_for(uid: int) -> Node3D:
	return _nodes.get(uid, null)


## Returns "" when a part may sit where the record says, or the reason it may not.
## Parts listed in `ignore` are left out of the overlap test.
func check(record: Dictionary, ignore: Array = []) -> String:
	var bounds := bounds_of(record)
	var pad := size_metres()
	var low := bounds.position
	var high := bounds.end
	if low.x < -EPSILON or low.y < -EPSILON or low.z < -EPSILON \
			or high.x > pad.x + EPSILON or high.y > pad.y + EPSILON or high.z > pad.z + EPSILON:
		return "That is outside the build grid."
	for uid in _parts:
		if ignore.has(uid):
			continue
		var other: Dictionary = _parts[uid]
		if not _overlaps(bounds, bounds_of(other)):
			continue
		if other["material"] != record["material"]:
			return "Materials must be homogeneous to overlap."
		if other["type"] == record["type"] and other["pos"] == record["pos"] \
				and other["size"] == record["size"] and (other["rot"] as Basis).is_equal_approx(record["rot"]):
			return "An identical part is already there."
	return ""


## Every part whose bounding box overlaps the given part, directly or through
## a chain of overlaps. Includes the part itself.
func overlap_group(uid: int) -> Array:
	var group: Array = [uid]
	var queue: Array = [uid]
	while not queue.is_empty():
		var current: int = queue.pop_back()
		var bounds := bounds_of(_parts[current])
		for other_uid in _parts:
			if group.has(other_uid):
				continue
			if _overlaps(bounds, bounds_of(_parts[other_uid])):
				group.append(other_uid)
				queue.append(other_uid)
	return group


# --- Mass --------------------------------------------------------------------

## Volume of a part in cubic metres.
static func volume_of(record: Dictionary) -> float:
	var size_m := Units.to_metres(record["size"])
	return size_m.x * size_m.y * size_m.z * PartLibrary.volume_fraction(record["type"])


## Mass of a part in kilograms.
static func mass_of(record: Dictionary) -> float:
	return volume_of(record) * MaterialLibrary.density(record["material"])


## A part's centre of mass in this node's local space, in metres.
static func centroid_of(record: Dictionary) -> Vector3:
	var size_m := Units.to_metres(record["size"])
	var offset := PartLibrary.unit_centroid(record["type"]) * size_m
	var rot: Basis = record["rot"]
	return Vector3(record["pos"] as Vector3i) * Units.UNIT + rot * offset


## Total mass of the build in kilograms. Overlapping volume is counted twice
## for now; counting it once comes with the Spawn milestone.
func total_mass() -> float:
	var total := 0.0
	for uid in _parts:
		total += mass_of(_parts[uid])
	return total


## The build's centre of mass in this node's local space, in metres.
func center_of_mass() -> Vector3:
	var total := 0.0
	var weighted := Vector3.ZERO
	for uid in _parts:
		var record: Dictionary = _parts[uid]
		var mass := mass_of(record)
		total += mass
		weighted += centroid_of(record) * mass
	if total <= 0.0:
		return Vector3.ZERO
	return weighted / total


# --- Changes -----------------------------------------------------------------

## Adds a part. Returns its uid, or 0 with nothing changed if it does not fit.
func add_part(record: Dictionary) -> int:
	if check(record) != "":
		return 0
	var uid := _next_uid
	_next_uid += 1
	_parts[uid] = record.duplicate()
	_rebuild_node(uid)
	parts_changed.emit()
	return uid


func remove_part(uid: int) -> bool:
	if not _parts.has(uid):
		return false
	_parts.erase(uid)
	_free_node(uid)
	parts_changed.emit()
	return true


func remove_parts(uids: Array) -> void:
	for uid in uids:
		if _parts.has(uid):
			_parts.erase(uid)
			_free_node(uid)
	parts_changed.emit()


## Replaces several parts' records at once. `updates` maps uid -> new record.
## The parts being updated are not tested against each other, so a group that
## moves together stays valid. Returns "" on success, or the reason for
## refusing, in which case nothing changes.
func update_parts(updates: Dictionary) -> String:
	var ignore: Array = updates.keys()
	for uid in updates:
		if not _parts.has(uid):
			return "That part no longer exists."
		var problem := check(updates[uid], ignore)
		if problem != "":
			return problem
	for uid in updates:
		_parts[uid] = (updates[uid] as Dictionary).duplicate()
		_rebuild_node(uid)
	parts_changed.emit()
	return ""


## Sets the material and colour of a part and of everything overlapping it,
## so that overlapping volume always stays one material.
func paint(uid: int, material: String, color: Color) -> void:
	if not _parts.has(uid):
		return
	for member in overlap_group(uid):
		var record: Dictionary = _parts[member]
		record["material"] = material
		record["color"] = color
		_rebuild_node(member)
	parts_changed.emit()


# --- Nodes -------------------------------------------------------------------

func _free_node(uid: int) -> void:
	if _nodes.has(uid):
		var node: Node = _nodes[uid]
		_nodes.erase(uid)
		node.queue_free()


## Builds the visible, clickable node for a part from its record.
func _rebuild_node(uid: int) -> void:
	_free_node(uid)
	var record: Dictionary = _parts[uid]
	var type: String = record["type"]
	var size_m := Units.to_metres(record["size"])

	var body := StaticBody3D.new()
	body.name = "Part%d" % uid
	body.set_meta("uid", uid)
	body.transform = Transform3D(record["rot"] as Basis, Vector3(record["pos"] as Vector3i) * Units.UNIT)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = PartLibrary.get_mesh(type)
	mesh_instance.scale = size_m
	# Surface 0 is the paintable body. A mechanical part's dark-metal detail
	# is surface 1 and keeps its own look.
	mesh_instance.set_surface_override_material(0, MaterialLibrary.surface(record["material"], record["color"]))
	body.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	collider.shape = PartLibrary.make_shape(type, size_m)
	body.add_child(collider)

	add_child(body)
	_nodes[uid] = body
