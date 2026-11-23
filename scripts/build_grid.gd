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
const PartSettings = preload("res://scripts/part_settings.gd")
const Aero = preload("res://scripts/aero.gd")

const SIZE := Vector3i(256, 128, 256)   # cells: X width, Y height, Z length (64 × 32 × 64 m)
const MAX_SIZE_UNITS := 64 * 200        # largest single part: 64 cells per side
const EPSILON := 0.0001                 # metres; keeps touching parts from counting as overlapping
const HISTORY_LIMIT := 100              # how many steps Undo can go back

var _parts: Dictionary = {}   # uid -> record (see make_record)
var _nodes: Dictionary = {}   # uid -> StaticBody3D
var _next_uid := 1
var _batching := false
var _batch_dirty := false
var _batch_before: Dictionary = {}   # the build as it was when the batch began
var _undo_stack: Array = []          # earlier states of the whole build
var _redo_stack: Array = []
var _active := true                  # false while the build is spawned: parts hidden and untouchable


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
		"props": PartSettings.defaults(type),   # the part's settings, by setting id
		"links": {},        # input id -> {"uid": source part, "output": output id}
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
	return (_parts[uid] as Dictionary).duplicate(true)


## Shows or hides every part. While the build is spawned its parts are
## hidden and take no part in collisions; the spawned bodies stand in for them.
func set_active(active: bool) -> void:
	_active = active
	for uid in _nodes:
		var body: StaticBody3D = _nodes[uid]
		body.visible = active
		body.collision_layer = 1 if active else 0


## A part's type, or "" for none. Cheaper than get_part for a quick look.
func type_of(uid: int) -> String:
	if not _parts.has(uid):
		return ""
	return str((_parts[uid] as Dictionary)["type"])


func get_node_for(uid: int) -> Node3D:
	return _nodes.get(uid, null)


## The nearest part of one kind whose centre lies within `reach` metres of a
## point given in this node's local space. Returns its uid, or 0 for none.
func nearest_of_type(type: String, local_point: Vector3, reach: float) -> int:
	var best := 0
	var best_distance := reach
	for uid in _parts:
		var record: Dictionary = _parts[uid]
		if record["type"] != type:
			continue
		var distance := bounds_of(record).get_center().distance_to(local_point)
		if distance < best_distance:
			best = uid
			best_distance = distance
	return best


## Every link that reads from the given part, as [consumer uid, input id, output id].
func consumers_of(uid: int) -> Array:
	var found: Array = []
	for other_uid in _parts:
		var links: Dictionary = (_parts[other_uid] as Dictionary).get("links", {})
		for input_id in links:
			var link: Dictionary = links[input_id]
			if int(link.get("uid", 0)) == uid:
				found.append([other_uid, input_id, str(link.get("output", ""))])
	return found


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


## Control parts (inputs, gates, PIDs, PWM, the mouse click block) only
## think: once spawned they weigh nothing, have no shape and are not drawn,
## so wiring never changes how a build flies. Sensors stay solid, since
## they measure where they are. Their "Visible after spawn" setting keeps
## one as an ordinary part, for checking a build.
const CONTROL_PARTS := ["input_block", "boolean_gate", "number_gate", "pid_controller", "pwm_generator", "mouse_click",
		"gamepad_input"]


static func is_hidden_control(record: Dictionary) -> bool:
	return CONTROL_PARTS.has(str(record.get("type", ""))) \
			and not bool((record.get("props", {}) as Dictionary).get("visible_after_spawn", false))


## Mass of a part in kilograms (none for a control part, which weighs
## nothing once spawned).
static func mass_of(record: Dictionary) -> float:
	if is_hidden_control(record):
		return 0.0
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


## The centre of lift of the build's aero panels, for level flight at a
## 5 degree angle of attack. "Forward" and "up" are those of the first seat
## placed, or the grid's own -Z and +Y if there is no seat. Each panel's lift
## is worked out with the same formula Spawn uses, and the centre of lift is
## where those lifts balance. Returns [true, the point] or [false, zero] if
## nothing makes lift.
func center_of_lift() -> Array:
	var forward := Vector3(0.0, 0.0, -1.0)
	var up := Vector3(0.0, 1.0, 0.0)
	for uid in _parts:
		var seat: Dictionary = _parts[uid]
		if seat["type"] == "seat":
			var seat_rot: Basis = seat["rot"]
			forward = seat_rot * Vector3(0.0, 0.0, -1.0)
			up = seat_rot * Vector3(0.0, 1.0, 0.0)
			break
	# Flying forward and sinking a little: the air meets the underside at 5 degrees.
	var attack: float = deg_to_rad(5.0)
	var moving: Vector3 = (forward * cos(attack) - up * sin(attack)) * 10.0
	var total := 0.0
	var weighted := Vector3.ZERO
	for uid in _parts:
		var record: Dictionary = _parts[uid]
		var type: String = record["type"]
		if not PartLibrary.is_aero_panel(type):
			continue
		var rot: Basis = record["rot"]
		var size_m: Vector3 = Units.to_metres(record["size"])
		var area: float = size_m.x * size_m.z
		if PartLibrary.is_triangle_panel(type):
			area *= 0.5
		var lift: float = Aero.panel_force(moving, rot.y, area, true, Aero.SEA_LEVEL_AIR).dot(up)
		total += lift
		weighted += centroid_of(record) * lift
	if absf(total) < 0.000001:
		return [false, Vector3.ZERO]
	return [true, weighted / total]


# --- Changes -----------------------------------------------------------------

## Announces a change, unless a batch of changes is still in progress.
func _changed() -> void:
	if _batching:
		_batch_dirty = true
	else:
		parts_changed.emit()


## Between begin_batch() and end_batch(), any number of changes are announced
## once at the end instead of one by one, and count as one step for Undo.
## Used when loading a build and when pasting a group.
func begin_batch() -> void:
	_batch_before = _snapshot()
	_batching = true
	_batch_dirty = false


func end_batch() -> void:
	_batching = false
	if _batch_dirty:
		_batch_dirty = false
		_push_undo(_batch_before)
		parts_changed.emit()
	_batch_before = {}


# --- Undo and redo -----------------------------------------------------------

## A full copy of every part's record.
func _snapshot() -> Dictionary:
	var copy: Dictionary = {}
	for uid in _parts:
		copy[uid] = (_parts[uid] as Dictionary).duplicate(true)
	return copy


func _push_undo(state: Dictionary) -> void:
	_undo_stack.append(state)
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()


## Called just before any change, so Undo can come back to this state.
func _remember() -> void:
	if not _batching:
		_push_undo(_snapshot())


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_redo_stack.append(_snapshot())
	_restore(_undo_stack.pop_back())
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_undo_stack.append(_snapshot())
	_restore(_redo_stack.pop_back())
	return true


## Makes the build match a saved state, rebuilding only the parts that differ.
func _restore(state: Dictionary) -> void:
	for uid in _parts.keys():
		if not state.has(uid):
			_parts.erase(uid)
			_free_node(uid)
	for uid in state:
		var record: Dictionary = state[uid]
		if not _parts.has(uid) or _parts[uid] != record:
			_parts[uid] = record.duplicate(true)
			_rebuild_node(uid)
	parts_changed.emit()


## Replaces a part's signal links. Links never change a part's shape, so
## nothing needs rebuilding.
func set_links(uid: int, links: Dictionary) -> void:
	if not _parts.has(uid):
		return
	_remember()
	(_parts[uid] as Dictionary)["links"] = links.duplicate(true)
	_changed()


## Drops every link whose source part no longer exists.
func _prune_links() -> void:
	for uid in _parts:
		var record: Dictionary = _parts[uid]
		var links: Dictionary = record.get("links", {})
		for input_id in links.keys():
			var link: Dictionary = links[input_id]
			if not _parts.has(int(link.get("uid", 0))):
				links.erase(input_id)


## Removes every part.
func clear() -> void:
	_remember()
	for uid in _nodes.keys():
		_free_node(uid)
	_parts.clear()
	_nodes.clear()
	_changed()


## Adds a part. Returns its uid, or 0 with nothing changed if it does not fit.
func add_part(record: Dictionary) -> int:
	if check(record) != "":
		return 0
	_remember()
	var uid := _next_uid
	_next_uid += 1
	_parts[uid] = record.duplicate(true)
	_rebuild_node(uid)
	_changed()
	return uid


func remove_part(uid: int) -> bool:
	if not _parts.has(uid):
		return false
	_remember()
	_parts.erase(uid)
	_free_node(uid)
	_prune_links()
	_changed()
	return true


func remove_parts(uids: Array) -> void:
	_remember()
	for uid in uids:
		if _parts.has(uid):
			_parts.erase(uid)
			_free_node(uid)
	_prune_links()
	_changed()


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
	_remember()
	for uid in updates:
		_parts[uid] = (updates[uid] as Dictionary).duplicate(true)
		_rebuild_node(uid)
	_changed()
	return ""


## Sets the material and colour of a part and of everything overlapping it,
## so that overlapping volume always stays one material.
func paint(uid: int, material: String, color: Color) -> void:
	if not _parts.has(uid):
		return
	_remember()
	for member in overlap_group(uid):
		var record: Dictionary = _parts[member]
		record["material"] = material
		record["color"] = color
		_rebuild_node(member)
	_changed()


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
	mesh_instance.mesh = PartLibrary.mesh_for_record(record)
	mesh_instance.scale = size_m
	# Surface 0 is the paintable body. A mechanical part's dark-metal detail
	# is surface 1 and keeps its own look.
	mesh_instance.set_surface_override_material(0, MaterialLibrary.surface(record["material"], record["color"]))
	body.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	collider.shape = PartLibrary.make_shape(type, size_m)
	body.add_child(collider)

	if not _active:
		body.visible = false
		body.collision_layer = 0
	add_child(body)
	_nodes[uid] = body
