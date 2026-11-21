extends RefCounted
## Ghost runs: the best run of each race, kept so a race already won can be
## run again against it.
##
## While a race runs, the vehicle is sampled RATE times a second: where each
## of its bodies is (map positions, so the world re-centring does not
## matter). At the start, what each body is made of is noted: every part,
## as written in a save file, and where it sits in its body. When a run is
## the best time on that race, it is written to saves/ghosts/slotN/<race>.json
## with the name of the build it was driven in. Racing the ghost draws that
## same build, see-through and pale blue, flying its recorded run.

const Origin = preload("res://scripts/origin.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const Units = preload("res://scripts/units.gd")
const Profile = preload("res://scripts/profile.gd")

const RATE := 8.0
const GHOST_COLOR := Color(0.55, 0.8, 1.0, 0.38)

var _bodies: Array = []        # RigidBody3D, in the order sampled
var _shapes: Array = []        # per body: [[part entry, 12 floats of its place in the body]]
var _samples: Array = []       # [time, [12 floats per body]]
var _timer := 0.0
var _build := ""


static func _path(race_id: String) -> String:
	return Profile.ghosts_dir(SaveManager.saves_dir()).path_join(race_id + ".json")


static func has_ghost(race_id: String) -> bool:
	return FileAccess.file_exists(_path(race_id))


## {"time", "build"} of a race's ghost, or empty.
static func about(race_id: String) -> Dictionary:
	var data := _read(race_id)
	if data.is_empty():
		return {}
	return {"time": float(data.get("time", 0.0)), "build": str(data.get("build", ""))}


static func _read(race_id: String) -> Dictionary:
	if not has_ghost(race_id):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(race_id)))
	return parsed if parsed is Dictionary else {}


static func _pack(place: Transform3D) -> Array:
	var b := place.basis
	var o := place.origin
	var values := [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]
	for index in values.size():
		values[index] = snappedf(float(values[index]), 0.001)
	return values


static func _unpack(values: Array) -> Transform3D:
	if values.size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]),
			Vector3(values[6], values[7], values[8])), Vector3(values[9], values[10], values[11]))


# --- Recording ---------------------------------------------------------------------

## Starts recording `vehicle` (a spawner), raced in the save `build_name`.
func begin(vehicle: Node, build_name: String) -> void:
	_bodies.clear()
	_shapes.clear()
	_samples.clear()
	_timer = 0.0
	_build = build_name
	for item in vehicle.all_bodies():
		var body := item as RigidBody3D
		if body == null or not is_instance_valid(body):
			continue
		var inverse := body.global_transform.affine_inverse()
		var parts: Array = []
		var seen: Dictionary = {}
		for piece in vehicle.body_pieces(body):
			var uid := int(vehicle._uid_of(int(piece)))
			if seen.has(uid):
				continue
			seen[uid] = true
			var record: Dictionary = vehicle.record_of(uid)
			var frame: Array = vehicle.part_frame(uid)
			if record.is_empty() or frame.is_empty():
				continue
			parts.append([SaveManager._record_to_entry(record), _pack(inverse * (frame[0] as Transform3D))])
		if parts.is_empty():
			continue
		_bodies.append(body)
		_shapes.append(parts)


## Notes where the vehicle is, `clock` seconds into the race.
func sample(clock: float, delta: float) -> void:
	if _bodies.is_empty():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0 / RATE
	var places: Array = []
	var last: Array = _samples[_samples.size() - 1][1] if not _samples.is_empty() else []
	for index in _bodies.size():
		var body := _bodies[index] as RigidBody3D
		if is_instance_valid(body) and body.is_inside_tree():
			var place := body.global_transform
			place.origin += Origin.offset
			places.append(_pack(place))
		elif index < last.size():
			places.append(last[index])   # gone: stays where it was last seen
		else:
			places.append(_pack(Transform3D.IDENTITY))
	_samples.append([snappedf(clock, 0.001), places])


## Writes the run as the race's ghost.
func save(race_id: String, time: float) -> void:
	if _samples.size() < 2:
		return
	DirAccess.make_dir_recursive_absolute(Profile.ghosts_dir(SaveManager.saves_dir()))
	var data := {"race": race_id, "time": time, "build": _build, "bodies": _shapes, "samples": _samples}
	var file := FileAccess.open(_path(race_id), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))


# --- Playing ------------------------------------------------------------------------

## The ghost of a race, drawn under `parent`: {"nodes": [Node3D per body],
## "samples"} or empty if there is none.
static func load_ghost(race_id: String, parent: Node) -> Dictionary:
	var data := _read(race_id)
	if data.is_empty():
		return {}
	var look := StandardMaterial3D.new()
	look.albedo_color = GHOST_COLOR
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	var nodes: Array = []
	for item in data.get("bodies", []):
		var body_node := Node3D.new()
		body_node.name = "GhostBody"
		for part_item in (item as Array):
			var pair: Array = part_item
			var record: Dictionary = SaveManager._entry_to_record(pair[0])
			if record.is_empty():
				continue
			var shown := MeshInstance3D.new()
			shown.mesh = PartLibrary.mesh_for_record(record)
			shown.material_override = look
			shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var place := _unpack(pair[1])
			shown.transform = Transform3D(place.basis * Basis.from_scale(Units.to_metres(record["size"])), place.origin)
			body_node.add_child(shown)
		parent.add_child(body_node)
		nodes.append(body_node)
	var label := Label3D.new()
	label.text = "Your best: %s" % str(data.get("build", ""))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.02
	label.modulate = Color(0.6, 0.85, 1.0)
	label.no_depth_test = true
	if not nodes.is_empty():
		(nodes[0] as Node3D).add_child(label)
		label.position = Vector3(0.0, 4.0, 0.0)
	return {"nodes": nodes, "samples": data.get("samples", []), "time": float(data.get("time", 0.0))}


## Puts a loaded ghost where it was `clock` seconds into its run.
static func show(ghost: Dictionary, clock: float) -> void:
	var samples: Array = ghost.get("samples", [])
	var nodes: Array = ghost.get("nodes", [])
	if samples.size() < 2 or nodes.is_empty():
		return
	var low := 0
	var high := samples.size() - 1
	if clock >= float(samples[high][0]):
		low = high
	else:
		while high - low > 1:
			var middle: int = (low + high) >> 1
			if float(samples[middle][0]) <= clock:
				low = middle
			else:
				high = middle
	var a: Array = samples[low]
	var b: Array = samples[high]
	var span := maxf(float(b[0]) - float(a[0]), 0.0001)
	var blend := clampf((clock - float(a[0])) / span, 0.0, 1.0)
	for index in nodes.size():
		var node := nodes[index] as Node3D
		if not is_instance_valid(node) or index >= (a[1] as Array).size():
			continue
		var from := _unpack(a[1][index])
		var to := _unpack(b[1][index]) if index < (b[1] as Array).size() else from
		var place := Transform3D(from.basis.orthonormalized().slerp(to.basis.orthonormalized(), blend), from.origin.lerp(to.origin, blend))
		place.origin -= Origin.offset
		node.global_transform = place
		node.visible = clock >= 0.0
