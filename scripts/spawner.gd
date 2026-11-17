extends Node3D
## Spawn: turns the build into moving bodies and runs its machines.
##
## Parts that touch face to face, or overlap, are welded into one rigid body
## with their combined mass and centre of mass. Gravity and collisions then
## act on it.
##
## A "machine" part (hinge, motor, piston, wheel and so on) comes apart into
## pieces when spawned. Each piece welds to what touches it, and the pieces
## are held together by a joint, so one side can turn or slide on the other.
## MACHINES below lists them.
##
## Every tick this script then runs the machines: drives, sliders, springs,
## the gear train, thrusters and the air on aero panels. Signals are read
## from input blocks while the character is seated.
##
## Parts have health. combat.gd deals the damage; this script removes a part
## whose health runs out, and if that leaves a body in separate chunks, each
## chunk becomes a body of its own.
##
## Special cases from the design: a dynamic offsetter is invisible and
## untouchable once spawned, but still welds. A body that contains an anchor
## block, or any part made of the frictionless surface material, is fixed.

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Aero = preload("res://scripts/aero.gd")
const MapInfo = preload("res://scripts/map_info.gd")

## Emitted when a part's health runs out and it is removed.
signal part_destroyed(uid: int, type: String, at: Vector3, props: Dictionary)

const TOUCH := 0.0004   # metres; faces this close together count as touching
const BUCKET := 1.0     # metres; size of the sorting boxes used to find neighbours
const PIECES := 8       # a part's pieces are numbered uid * PIECES + 0, 1, 2 ...

const SERVO_GAIN := 0.2      # share of a position error a servo or piston sets out to close each tick
const SOLENOID_SPEED := 5.0  # m/s; a solenoid snaps across as fast as its force allows, up to this
const WATER_DENSITY := 1000.0   # kg/m^3
const WATER_DRAG := 0.5         # drag coefficient of a submerged float
const BODY_DRAG := 1.0          # drag coefficient of a body's outline (a flat face square to the air is 1.2, a rounded one less)
const FLOAT_CELL := 1.0         # metres; floats are merged into cubes this size
const MAX_AIR_CELLS := 1500000  # bigger builds skip the sealed-air search

## The parts that come apart when spawned. Places and sizes are fractions of
## the part's own size, along the part's own axes.
##   role    what runs it; see _add_turner and _add_slider
##   pieces  one entry each: [model name, middle, size of the box it fills,
##           trim]. Trim scales the piece's collision box, so a square piece
##           has room to turn. A piece welds to whatever touches its box.
##   joints  one entry each: [piece, piece, kind, axis (0 = X, 1 = Y, 2 = Z),
##           a point on the axis]. Kinds: "hinge" turns about the axis,
##           "slide" moves along it, "ball" swivels about the point, and
##           "end" is a linkage bar's end, set by its End joints setting.
const MACHINES := {
	# Two leaves on a pin.
	"hinge": {"role": "hinge",
		"pieces": [["base", Vector3(0, -0.25, 0), Vector3(1, 0.5, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.25, 0), Vector3(1, 0.5, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "hinge", 0, Vector3(0, 0, 0)]]},
	# A housing, with the output on the top face turning about the shaft.
	"motor": {"role": "motor",
		"pieces": [["base", Vector3(0, -0.125, 0), Vector3(1, 0.75, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.375, 0), Vector3(1, 0.25, 1), Vector3(0.7, 1, 0.7)]],
		"joints": [[0, 1, "hinge", 1, Vector3(0, 0, 0)]]},
	"servo": {"role": "servo",
		"pieces": [["base", Vector3(0, -0.125, 0), Vector3(1, 0.75, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.375, 0), Vector3(1, 0.25, 1), Vector3(0.7, 1, 0.7)]],
		"joints": [[0, 1, "hinge", 1, Vector3(0, 0, 0)]]},
	# A plate on the bottom and a leaf standing at the back (-Z), hinged
	# along the edge they share.
	"door_hinge_servo": {"role": "servo",
		"pieces": [["base", Vector3(0, -0.4375, 0), Vector3(1, 0.125, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.0625, -0.4375), Vector3(1, 0.875, 0.125), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "hinge", 0, Vector3(0, -0.3125, -0.3125)]]},
	# Two halves that swivel on a ball.
	"ball_joint": {"role": "ball",
		"pieces": [["base", Vector3(0, -0.25, 0), Vector3(1, 0.5, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.25, 0), Vector3(1, 0.5, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "ball", 1, Vector3(0, 0, 0)]]},
	# A housing that welds by its four sides, and a shaft through it that
	# welds by its two ends and turns freely.
	"bearing": {"role": "bearing",
		"pieces": [["base", Vector3(0, 0, 0), Vector3(1, 0.75, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0, 0), Vector3(0.3, 1, 0.3), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "hinge", 1, Vector3(0, 0, 0)]]},
	# A barrel, and a rod end on top that runs out along the barrel's axis.
	"piston": {"role": "piston",
		"pieces": [["base", Vector3(0, -0.125, 0), Vector3(1, 0.75, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.375, 0), Vector3(1, 0.25, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "slide", 1, Vector3(0, 0, 0)]]},
	# Fluid and combustion cylinders: a barrel and a rod end like a piston's,
	# moved by the pressure inside (engines.gd) instead of a drive.
	"fluid_cylinder": {"role": "cylinder",
		"pieces": [["base", Vector3(0, -0.125, 0), Vector3(1, 0.75, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.375, 0), Vector3(1, 0.25, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "slide", 1, Vector3(0, 0, 0)]]},
	"combustion_cylinder": {"role": "cylinder",
		"pieces": [["base", Vector3(0, -0.125, 0), Vector3(1, 0.75, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.375, 0), Vector3(1, 0.25, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "slide", 1, Vector3(0, 0, 0)]]},
	"solenoid": {"role": "solenoid",
		"pieces": [["base", Vector3(0, -0.125, 0), Vector3(1, 0.75, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.375, 0), Vector3(1, 0.25, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "slide", 1, Vector3(0, 0, 0)]]},
	# Two end plates that move toward and away from each other.
	"spring": {"role": "spring",
		"pieces": [["base", Vector3(0, -0.25, 0), Vector3(1, 0.5, 1), Vector3(1, 1, 1)],
			["top", Vector3(0, 0.25, 0), Vector3(1, 0.5, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "slide", 1, Vector3(0, 0, 0)]]},
	# Journals that weld by the two ends (along X), and the webs and crank
	# pin between them, which turn and weld by the other four faces.
	"crankshaft": {"role": "crank",
		"pieces": [["base", Vector3(0, 0, 0), Vector3(1, 0.3, 0.3), Vector3(1, 1, 1)],
			["top", Vector3(0, 0, 0), Vector3(0.5, 1, 1), Vector3(1, 0.7, 0.7)]],
		"joints": [[0, 1, "hinge", 0, Vector3(0, 0, 0)]]},
	# A hub that welds by the two ends of the axle (along X), and the tyre,
	# which turns on it. Only when the wheel is set to spin freely.
	"wheel": {"role": "wheel",
		"pieces": [["base", Vector3(0, 0, 0), Vector3(1, 0.3, 0.3), Vector3(1, 1, 1)],
			["top", Vector3(0, 0, 0), Vector3(0.8, 1, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "hinge", 0, Vector3(0, 0, 0)]]},
	# A bar with a joint at each end. Each end welds to what touches it.
	"linkage_bar": {"role": "link",
		"pieces": [["bar", Vector3(0, 0, 0), Vector3(0.84, 1, 1), Vector3(1, 1, 1)],
			["end_a", Vector3(-0.46, 0, 0), Vector3(0.08, 1, 1), Vector3(1, 1, 1)],
			["end_b", Vector3(0.46, 0, 0), Vector3(0.08, 1, 1), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "end", 1, Vector3(-0.46, 0, 0)], [0, 2, "end", 1, Vector3(0.46, 0, 0)]]},
	# Two plates that turn against each other, or grip.
	"clutch": {"role": "clutch",
		"pieces": [["base", Vector3(0, -0.25, 0), Vector3(1, 0.5, 1), Vector3(0.7, 1, 0.7)],
			["top", Vector3(0, 0.25, 0), Vector3(1, 0.5, 1), Vector3(0.7, 1, 0.7)]],
		"joints": [[0, 1, "hinge", 1, Vector3(0, 0, 0)]]},
	# A caliper that welds by the +X face, and a disc on a hub that welds by
	# its two ends (along Y) and turns with whatever shaft runs through it.
	"brake": {"role": "brake",
		"pieces": [["base", Vector3(0.3, 0, 0), Vector3(0.4, 1, 0.45), Vector3(1, 1, 1)],
			["top", Vector3(0, 0, 0), Vector3(0.6, 1, 0.6), Vector3(1, 1, 1)]],
		"joints": [[0, 1, "hinge", 1, Vector3(0, 0, 0)]]},
}

var spawned := false
var engines: Node = null       # engines.gd: pressures for cylinders, fuel for thrusters
var generation := 0            # goes up by one at every spawn, so other scripts can tell a new one
var occupied_seat := 0         # uid of the seat the character is sitting in; set by the build controller

var _records: Dictionary = {}      # uid -> part record, as spawned
var _dead: Dictionary = {}         # uid -> true for parts that have been destroyed
var _health: Dictionary = {}       # uid -> health points left
var _boxes: Dictionary = {}        # piece -> its bounding box in the grid's space, for welding
var _pieces: Dictionary = {}       # piece -> {"uid", "body", "mesh", "collider", "extras", "mass", "friction", "centre", "place"}
var _bodies: Array = []            # every RigidBody3D
var terrain: Node3D = null         # terrain.gd, to tell lake from dry land
var _floats: Dictionary = {}       # body -> [PackedVector3Array points in the body, PackedFloat32Array volumes, reach]
var _air: Dictionary = {}          # body -> [PackedVector3Array, PackedFloat32Array]: sealed air, merged into cubes
var _drag: Dictionary = {}         # body -> {"count": pieces it was worked out for, "axes": [[area m², point in the body], x3]}
var _body_pieces: Dictionary = {}  # body -> Array of the pieces in it
var _body_count := 0               # for naming bodies
var _shapes: Dictionary = {}       # collision shapes, shared between identical pieces
var _fixed_buckets: Dictionary = {}   # sorting box -> immovable pieces reaching into it
var _grid_frame := Transform3D.IDENTITY

var _joints: Array = []        # {"node", "uid", "a", "b", "local"}: local is the joint's frame inside a's body
var _seats: Dictionary = {}    # seat uid -> [piece, its transform inside the body, its size in metres]
var _thrusters: Array = []     # [piece, transform inside the body, thrust in newtons, links, flame]
var _panels: Array = []        # aero panels: [piece, centre inside the body, normal inside it, area, dragless]
var _inputs: Dictionary = {}   # input block uid -> its keys and what it is putting out
var _outputs: Dictionary = {}  # part uid -> {output id: number}
var _turners: Array = []       # every joint that turns about an axis; see _add_turner
var _sliders: Array = []       # pistons, solenoids and springs; see _add_slider
var _gears: Dictionary = {}    # gear or pulley uid -> where it is and what it turns against; see _find_gears
var _meshes: Array = []        # pairs of gears or pulleys that turn together; see _find_meshes
var _racks: Array = []         # racks, each with the gears that drive it
var _flame_mesh: Mesh = null

# The physics engine's joint motors may count a positive speed either way
# round. The first time a drive moves, its answer is compared with what was
# asked, and the sign is settled for good: once for turning, once for sliding.
var _turn_sign := -1.0
var _turn_sign_known := false
var _turn_votes := 0
var _slide_sign := 1.0
var _slide_sign_known := false
var _slide_votes := 0


# --- Machines and pieces -----------------------------------------------------

## The MACHINES entry for a part, or {} for a part that stays in one piece.
## The uid of the part a piece belongs to.
static func _uid_of(piece: int) -> int:
	return floori(float(piece) / PIECES)


static func machine_of(record: Dictionary) -> Dictionary:
	var type: String = record["type"]
	if not MACHINES.has(type):
		return {}
	if type == "wheel":
		var props: Dictionary = record.get("props", {})
		if not bool(props.get("free_spinning", true)):
			return {}   # a solid wheel, for bolting to a motor
	return MACHINES[type]


static func piece_count(record: Dictionary) -> int:
	var machine: Dictionary = machine_of(record)
	if machine.is_empty():
		return 1
	var listed: Array = machine["pieces"]
	return listed.size()


## One piece's entry from its machine: [model name, middle, size, trim].
static func _piece_spec(piece: int, record: Dictionary) -> Array:
	var listed: Array = machine_of(record)["pieces"]
	return listed[piece % PIECES]


## The middle of a machine's piece, in the grid's space, in metres.
static func _piece_middle(piece: int, record: Dictionary) -> Vector3:
	var rot: Basis = record["rot"]
	var size_units: Vector3i = record["size"]
	var middle: Vector3 = _piece_spec(piece, record)[1]
	return Vector3(record["pos"] as Vector3i) * Units.UNIT + rot * (middle * Units.to_metres(size_units))


## The size of a machine's piece along the part's own axes, in metres.
static func _piece_size(piece: int, record: Dictionary) -> Vector3:
	var size_units: Vector3i = record["size"]
	var share: Vector3 = _piece_spec(piece, record)[2]
	return share * Units.to_metres(size_units)


## The bounding box of a piece, in the grid's space.
static func _piece_box(piece: int, record: Dictionary) -> AABB:
	if machine_of(record).is_empty():
		return BuildGrid.bounds_of(record)
	var rot: Basis = record["rot"]
	var half: Vector3 = _piece_size(piece, record) * 0.5
	var reach: Vector3 = (rot.x * half.x).abs() + (rot.y * half.y).abs() + (rot.z * half.z).abs()
	var centre: Vector3 = _piece_middle(piece, record)
	return AABB(centre - reach, reach * 2.0)


## The mass of a piece in kilograms. A machine's mass is shared among its
## pieces by the size of the box each fills.
static func _piece_mass(piece: int, record: Dictionary) -> float:
	var machine: Dictionary = machine_of(record)
	if machine.is_empty():
		return BuildGrid.mass_of(record)
	var total := 0.0
	var mine := 0.0
	var listed: Array = machine["pieces"]
	for index in listed.size():
		var spec: Array = listed[index]
		var box: Vector3 = spec[2]
		var volume: float = box.x * box.y * box.z
		total += volume
		if index == piece % PIECES:
			mine = volume
	return BuildGrid.mass_of(record) * mine / total


## A piece's centre of mass, in the grid's space.
static func _piece_centre(piece: int, record: Dictionary) -> Vector3:
	if machine_of(record).is_empty():
		return BuildGrid.centroid_of(record)
	return _piece_middle(piece, record)


# --- Spawning ----------------------------------------------------------------

## Builds the bodies from everything on the grid. Returns a short report:
## {"parts", "bodies", "mass" (kg), "hinges" (joints free to move), "locked"
## (joints whose two sides ended up welded to the same body, so they cannot
## move), "thrusters", "panels"}.
func spawn(grid: Node3D) -> Dictionary:
	despawn()
	_grid_frame = grid.global_transform
	for uid in grid.all_uids():
		_records[uid] = grid.get_part(uid)
	var forced := _apply_offsetters()

	# Every piece and its box.
	var all_pieces: Array = []
	for uid in _records:
		var part_uid: int = uid
		var record: Dictionary = _records[part_uid]
		var material: String = record["material"]
		var immovable: bool = MaterialLibrary.is_immovable(material)
		if immovable:
			_health[part_uid] = INF
		else:
			_health[part_uid] = BuildGrid.mass_of(record) * float(MaterialLibrary.info(material)["strength"])
		for index in piece_count(record):
			var piece: int = part_uid * PIECES + index
			var box: AABB = _piece_box(piece, record)
			_boxes[piece] = box
			all_pieces.append(piece)
			if immovable:
				_file_fixed(piece, box)

	# Weld them into bodies.
	var total_mass := 0.0
	for group in _merge_forced(weld_groups(all_pieces, _boxes), forced):
		var pieces: Array = group
		# The engine gives one friction value to a whole body, so frictionless
		# parts get a body of their own. They and everything welded to them
		# are fixed, so nothing needs to hold the two bodies together.
		var slick: Array = []
		var rough: Array = []
		for piece in pieces:
			var piece_id: int = piece
			var piece_record: Dictionary = _records[_uid_of(piece_id)]
			var piece_material: String = piece_record["material"]
			if MaterialLibrary.is_immovable(piece_material):
				slick.append(piece_id)
			else:
				rough.append(piece_id)
		if not slick.is_empty():
			total_mass += _make_body(slick, true)
		if not rough.is_empty():
			total_mass += _make_body(rough, not slick.is_empty() or _has_anchor(rough))

	for uid in _records:
		var input_uid: int = uid
		var input_record: Dictionary = _records[input_uid]
		if input_record["type"] == "input_block":
			_inputs[input_uid] = _new_input_state(input_record.get("props", {}))

	# Join the pieces of each machine.
	var free_joints := 0
	var locked := 0
	for uid in _records:
		var machine_uid: int = uid
		var machine_record: Dictionary = _records[machine_uid]
		var machine: Dictionary = machine_of(machine_record)
		if machine.is_empty():
			continue
		var listed: Array = machine["joints"]
		for joint_spec in listed:
			var spec: Array = joint_spec
			var a: int = machine_uid * PIECES + int(spec[0])
			var b: int = machine_uid * PIECES + int(spec[1])
			var a_body: RigidBody3D = _piece_body(a)
			var b_body: RigidBody3D = _piece_body(b)
			if a_body == null or b_body == null:
				continue
			if a_body == b_body:
				locked += 1
				continue
			_make_joint(machine_uid, machine_record, str(machine["role"]), spec, a, b)
			free_joints += 1

	_find_gears()
	_find_meshes()
	_find_air()
	generation += 1
	spawned = true
	return {
		"parts": _records.size(), "bodies": _bodies.size(), "mass": total_mass,
		"hinges": free_joints, "locked": locked,
		"thrusters": _thrusters.size(), "panels": _panels.size(),
	}


## Dynamic offsetters: before welding, everything built on an offsetter's
## top face (its own +Y), and everything joined on beyond that, is turned
## about the middle of that face by the offsetter's turn settings and moved
## by its shift, both along the offsetter's own axes. The offsetter then
## holds what it moved welded to itself, however far it moved. If what is on
## top also reaches round to another face of the offsetter, it cannot be told
## apart from the rest, and nothing moves. Returns [offsetter uid, uids it
## holds] pairs for _merge_forced.
func _apply_offsetters() -> Array:
	var forced: Array = []
	for key in _records.keys():
		var uid: int = key
		var record: Dictionary = _records[uid]
		if str(record["type"]) != "dynamic_offsetter":
			continue
		var props: Dictionary = record.get("props", {})
		var shift_local := Vector3(float(props.get("shift_x", 0.0)), float(props.get("shift_y", 0.0)),
				float(props.get("shift_z", 0.0))) * Units.CELL
		var turn_local := Vector3(float(props.get("turn_x", 0.0)), float(props.get("turn_y", 0.0)),
				float(props.get("turn_z", 0.0)))
		if shift_local.length() < 0.0001 and turn_local.length() < 0.01:
			continue
		var rot: Basis = record["rot"]
		var own_box: AABB = BuildGrid.bounds_of(record)
		var up: Vector3 = rot.y.normalized()
		var size_m: Vector3 = Units.to_metres(record["size"] as Vector3i)
		var top_middle: Vector3 = Vector3(record["pos"] as Vector3i) * Units.UNIT + up * size_m.y * 0.5
		# What sits on the top face, then everything joined on beyond it.
		var boxes: Dictionary = {}
		for other_key in _records:
			if other_key != uid:
				boxes[other_key] = BuildGrid.bounds_of(_records[other_key])
		var seeds: Array = []
		for other_key in boxes:
			var box: AABB = boxes[other_key]
			if _touching(box, own_box) and (box.get_center() - top_middle).dot(up) > -0.001:
				seeds.append(other_key)
		if seeds.is_empty():
			continue
		var moving: Dictionary = {}
		var queue: Array = seeds.duplicate()
		for first_part in seeds:
			moving[first_part] = true
		var tangled := false
		while not queue.is_empty() and not tangled:
			var current: int = queue.pop_back()
			var current_box: AABB = boxes[current]
			for other_key in boxes:
				if moving.has(other_key):
					continue
				if not _touching(boxes[other_key], current_box):
					continue
				var other_box: AABB = boxes[other_key]
				if _touching(other_box, own_box) and (other_box.get_center() - top_middle).dot(up) <= -0.001:
					tangled = true   # it wraps round to the offsetter's other side
					break
				moving[other_key] = true
				queue.append(other_key)
		if tangled:
			continue
		var turn := rot * Basis.from_euler(turn_local * PI / 180.0) * rot.inverse()
		var shift: Vector3 = rot * shift_local
		for moved_key in moving:
			var moved: Dictionary = _records[moved_key]
			var at: Vector3 = Vector3(moved["pos"] as Vector3i) * Units.UNIT
			var new_at: Vector3 = top_middle + turn * (at - top_middle) + shift
			moved["pos"] = Vector3i((new_at / Units.UNIT).round())
			moved["rot"] = (turn * (moved["rot"] as Basis)).orthonormalized()
		forced.append([uid, seeds])
	return forced


## Joins the weld groups that an offsetter holds together (see _apply_offsetters).
static func _merge_forced(groups: Array, forced: Array) -> Array:
	if forced.is_empty():
		return groups
	var group_of: Dictionary = {}   # piece -> index into groups
	for index in groups.size():
		for piece in groups[index]:
			group_of[piece] = index
	for item in forced:
		var pair: Array = item
		var holder: int = int(pair[0]) * PIECES
		for held_uid in pair[1]:
			var held: int = int(held_uid) * PIECES
			if not group_of.has(holder) or not group_of.has(held):
				continue
			var keep: int = group_of[holder]
			var gone: int = group_of[held]
			if keep == gone:
				continue
			for piece in groups[gone]:
				(groups[keep] as Array).append(piece)
				group_of[piece] = keep
			groups[gone] = []
	var merged: Array = []
	for group in groups:
		if not (group as Array).is_empty():
			merged.append(group)
	return merged


## Removes every spawned body and joint.
func despawn() -> void:
	for entry in _joints:
		var joint_entry: Dictionary = entry
		var node: Node = joint_entry["node"]
		if is_instance_valid(node):
			node.queue_free()
	for body in _bodies:
		var body_node: Node = body
		if is_instance_valid(body_node):
			body_node.queue_free()
	_records = {}
	_dead.clear()
	_health.clear()
	_boxes.clear()
	_pieces.clear()
	_bodies.clear()
	_body_pieces.clear()
	_shapes.clear()
	_fixed_buckets.clear()
	_joints.clear()
	_seats.clear()
	_thrusters.clear()
	_panels.clear()
	_inputs.clear()
	_outputs.clear()
	_turners.clear()
	_sliders.clear()
	_gears.clear()
	_meshes.clear()
	_racks.clear()
	_floats.clear()
	_air.clear()
	_drag.clear()
	occupied_seat = 0
	spawned = false


## The body a piece is in, or null if the piece is gone.
func _piece_body(piece: int) -> RigidBody3D:
	if not _pieces.has(piece):
		return null
	var entry: Dictionary = _pieces[piece]
	return entry["body"]


func _has_anchor(pieces: Array) -> bool:
	for piece in pieces:
		var piece_id: int = piece
		var record: Dictionary = _records[_uid_of(piece_id)]
		if record["type"] == "anchor_block":
			return true
	return false


## The velocity of a point on a body. `arm` is the point's offset from the
## body's origin, in world directions.
static func velocity_at(body: RigidBody3D, arm: Vector3) -> Vector3:
	var from_mass_centre: Vector3 = arm - body.global_transform.basis * body.center_of_mass
	return body.linear_velocity + body.angular_velocity.cross(from_mass_centre)


# --- Seats -------------------------------------------------------------------

## Where a spawned seat is now: [its transform in the world, its size in
## metres]. Empty if there is no such seat.
func seat_frame(uid: int) -> Array:
	if not _seats.has(uid):
		return []
	var seat: Array = _seats[uid]
	var body: RigidBody3D = _piece_body(seat[0])
	if body == null:
		return []
	var place: Transform3D = seat[1]
	return [body.global_transform * place, seat[2]]


## How fast a spawned seat is moving, in metres per second.
func seat_velocity(uid: int) -> Vector3:
	if not _seats.has(uid):
		return Vector3.ZERO
	var seat: Array = _seats[uid]
	var body: RigidBody3D = _piece_body(seat[0])
	if body == null:
		return Vector3.ZERO
	var place: Transform3D = seat[1]
	return velocity_at(body, body.global_transform.basis * place.origin)


## The spawned seat nearest to a point in the world and within `reach`
## metres of it. Returns its uid, or 0 for none.
## How fast a spawned seat's body is turning, in degrees per second.
func seat_spin(uid: int) -> float:
	if not _seats.has(uid):
		return 0.0
	var body: RigidBody3D = _piece_body(_seats[uid][0])
	return rad_to_deg(body.angular_velocity.length()) if body != null else 0.0


func nearest_seat(world_point: Vector3, reach: float) -> int:
	var best := 0
	var best_distance := reach
	for uid in _seats:
		var seat: Array = _seats[uid]
		var body: RigidBody3D = _piece_body(seat[0])
		if body == null:
			continue
		var place: Transform3D = seat[1]
		var distance: float = (body.global_transform * place.origin).distance_to(world_point)
		if distance < best_distance:
			best = uid
			best_distance = distance
	return best


# --- Welding -----------------------------------------------------------------

## Sorts pieces into weld groups. Two pieces weld when their bounding boxes
## share a face, or part of one, or overlap. Meeting only along an edge or at
## a corner is not a weld. `boxes` must hold the box of every piece that
## still exists, not only the ones being sorted. Returns an array of arrays.
static func weld_groups(pieces: Array, boxes: Dictionary) -> Array:
	var parent: Dictionary = {}    # piece -> another piece in the same group
	var buckets: Dictionary = {}   # sorting box -> the pieces that reach into it
	for piece in pieces:
		var piece_id: int = piece
		_add_piece(piece_id, parent, boxes, buckets)

	var groups: Dictionary = {}
	for piece in parent:
		var member: int = piece
		var root: int = _root(parent, member)
		if not groups.has(root):
			groups[root] = []
		var members: Array = groups[root]
		members.append(member)
	return groups.values()


## Files one piece and welds it to every piece already filed that it touches.
static func _add_piece(piece: int, parent: Dictionary, boxes: Dictionary, buckets: Dictionary) -> void:
	parent[piece] = piece
	var box: AABB = boxes[piece]
	# Only pieces that reach into the same sorting box can be touching.
	var margin := Vector3(TOUCH, TOUCH, TOUCH)
	var low: Vector3 = ((box.position - margin) / BUCKET).floor()
	var high: Vector3 = ((box.end + margin) / BUCKET).floor()
	for x in range(int(low.x), int(high.x) + 1):
		for y in range(int(low.y), int(high.y) + 1):
			for z in range(int(low.z), int(high.z) + 1):
				var key := Vector3i(x, y, z)
				if not buckets.has(key):
					buckets[key] = []
				var neighbours: Array = buckets[key]
				for other in neighbours:
					var other_piece: int = other
					if _welds(piece, other_piece, boxes):
						_join(parent, piece, other_piece)
				neighbours.append(piece)


## True if two pieces weld to each other.
static func _welds(a: int, b: int, boxes: Dictionary) -> bool:
	if _uid_of(a) == _uid_of(b):
		return false   # pieces of one machine: held by its joints, never welded
	var box_a: AABB = boxes[a]
	var box_b: AABB = boxes[b]
	if not _touching(box_a, box_b):
		return false
	return _chooses(a, b, boxes) and _chooses(b, a, boxes)


## Something that touches several pieces of one machine welds to only one of
## them, or it would lock the machine solid. It takes the piece it shares the
## most area with, and the earliest listed if they are even. This answers
## whether `other` welds to `piece` rather than to another piece of the same
## machine.
static func _chooses(other: int, piece: int, boxes: Dictionary) -> bool:
	var first: int = piece - (piece % PIECES)
	if not boxes.has(first + 1):
		return true   # not a machine: it has only the one piece
	var other_box: AABB = boxes[other]
	var best := -1
	var best_contact := -1.0
	for index in PIECES:
		var candidate: int = first + index
		if not boxes.has(candidate):
			break
		var candidate_box: AABB = boxes[candidate]
		if not _touching(other_box, candidate_box):
			continue
		var contact: float = _contact(other_box, candidate_box)
		# A later piece has to share clearly more area to be chosen.
		if best < 0 or contact > best_contact * 1.02 + 0.000001:
			best = candidate
			best_contact = contact
	return best == piece


## How much two touching boxes share: the area of the face they meet over.
static func _contact(a: AABB, b: AABB) -> float:
	var a_high: Vector3 = a.end
	var b_high: Vector3 = b.end
	var spans: Array = []
	for axis in 3:
		spans.append(maxf(minf(a_high[axis], b_high[axis]) - maxf(a.position[axis], b.position[axis]), 0.0))
	spans.sort()
	var middle_span: float = spans[1]
	var widest_span: float = spans[2]
	return middle_span * widest_span


## True if two boxes overlap, or meet over an area rather than a line or point.
static func _touching(a: AABB, b: AABB) -> bool:
	var a_high: Vector3 = a.end
	var b_high: Vector3 = b.end
	var shared_axes := 0
	for axis in 3:
		var overlap: float = minf(a_high[axis], b_high[axis]) - maxf(a.position[axis], b.position[axis])
		if overlap < -TOUCH:
			return false   # a gap between them
		if overlap > TOUCH:
			shared_axes += 1
	return shared_axes >= 2


## The piece that stands for a piece's whole group.
static func _root(parent: Dictionary, piece: int) -> int:
	var root: int = piece
	while parent[root] != root:
		root = parent[root]
	# Point everything on the way straight at the root, to keep later lookups short.
	var current: int = piece
	while current != root:
		var next: int = parent[current]
		parent[current] = root
		current = next
	return root


static func _join(parent: Dictionary, a: int, b: int) -> void:
	var root_a: int = _root(parent, a)
	var root_b: int = _root(parent, b)
	if root_a != root_b:
		parent[root_a] = root_b


## Notes where an immovable piece is, so that later it is quick to tell
## whether a chunk of a damaged body still touches something immovable.
func _file_fixed(piece: int, box: AABB) -> void:
	var margin := Vector3(TOUCH, TOUCH, TOUCH)
	var low: Vector3 = ((box.position - margin) / BUCKET).floor()
	var high: Vector3 = ((box.end + margin) / BUCKET).floor()
	for x in range(int(low.x), int(high.x) + 1):
		for y in range(int(low.y), int(high.y) + 1):
			for z in range(int(low.z), int(high.z) + 1):
				var key := Vector3i(x, y, z)
				if not _fixed_buckets.has(key):
					_fixed_buckets[key] = []
				var filed: Array = _fixed_buckets[key]
				filed.append(piece)


## True if a piece welds to an immovable piece.
func _touches_fixed(piece: int) -> bool:
	var box: AABB = _boxes[piece]
	var margin := Vector3(TOUCH, TOUCH, TOUCH)
	var low: Vector3 = ((box.position - margin) / BUCKET).floor()
	var high: Vector3 = ((box.end + margin) / BUCKET).floor()
	for x in range(int(low.x), int(high.x) + 1):
		for y in range(int(low.y), int(high.y) + 1):
			for z in range(int(low.z), int(high.z) + 1):
				var key := Vector3i(x, y, z)
				if not _fixed_buckets.has(key):
					continue
				var filed: Array = _fixed_buckets[key]
				for other in filed:
					var other_piece: int = other
					if other_piece != piece and _boxes.has(other_piece) and _welds(piece, other_piece, _boxes):
						return true
	return false


# --- Bodies ------------------------------------------------------------------

## A new, empty rigid body, set up the way every spawned body is.
func _new_body(fixed: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.ZERO
	var surface := PhysicsMaterial.new()
	surface.bounce = 0.0
	body.physics_material_override = surface
	# An ideal world: nothing slows a body except contact (and, later, drag).
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	if fixed:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	# Bodies meet the world and each other. They do not look for the
	# character: see the note on layers in units.gd.
	body.collision_layer = Units.LAYER_BODIES
	body.collision_mask = Units.LAYER_WORLD | Units.LAYER_BODIES
	body.name = "Body%d" % _body_count
	_body_count += 1
	return body


## Makes one rigid body from a set of welded pieces. `fixed` makes it
## immovable. Returns its mass in kilograms.
func _make_body(pieces: Array, fixed: bool) -> float:
	var mass := 0.0
	var moment := Vector3.ZERO   # sum of mass x position, for the centre of mass
	for piece in pieces:
		var piece_id: int = piece
		var record: Dictionary = _records[_uid_of(piece_id)]
		var piece_mass: float = _piece_mass(piece_id, record)
		mass += piece_mass
		moment += _piece_centre(piece_id, record) * piece_mass
	if mass <= 0.0:
		return 0.0
	# The body's origin is put at the centre of mass.
	var centre: Vector3 = moment / mass

	var body := _new_body(fixed)
	body.transform = _grid_frame * Transform3D(Basis.IDENTITY, centre)
	var solid := false
	var kept: Array = []
	for piece in pieces:
		var built_piece: int = piece
		if _build_piece(body, built_piece, centre):
			solid = true
		kept.append(built_piece)
	if not solid:
		# Nothing to see or touch, so nothing to simulate.
		for piece in kept:
			_pieces.erase(piece)
		body.free()
		return 0.0
	_body_pieces[body] = kept
	_refresh_body(body)
	add_child(body)
	_bodies.append(body)
	return mass


## Builds one piece into a body: what it looks like, what it collides with,
## and whatever it does. `centre` is the body's origin in the grid's space.
## Returns true if the piece is solid.
func _build_piece(body: RigidBody3D, piece: int, centre: Vector3) -> bool:
	var uid: int = _uid_of(piece)
	var record: Dictionary = _records[uid]
	var type: String = record["type"]
	var rot: Basis = record["rot"]
	var size_units: Vector3i = record["size"]
	var size_m: Vector3 = Units.to_metres(size_units)
	var material: String = record["material"]
	var color: Color = record["color"]
	var props: Dictionary = record.get("props", {})
	var machine: Dictionary = machine_of(record)
	# Where the whole part sits inside the body.
	var place := Transform3D(rot, Vector3(record["pos"] as Vector3i) * Units.UNIT - centre)
	var extras: Array = []
	var entry := {
		"uid": uid, "body": body, "mesh": null, "collider": null, "extras": extras,
		"mass": _piece_mass(piece, record),
		"friction": float(MaterialLibrary.info(material)["friction"]),
		"centre": _piece_centre(piece, record) - centre,   # its centre of mass, inside the body
		"place": place,                                    # the whole part's own axes and middle, inside the body
	}
	_pieces[piece] = entry
	if type == "seat":
		_seats[uid] = [piece, place, size_m]
	if type == "dynamic_offsetter":
		return false   # it only welds; it has no look and no collision once spawned

	var mesh: Mesh
	var shape_key: String
	var shape_place := place
	if machine.is_empty():
		mesh = PartLibrary.mesh_for_record(record)
		shape_key = type + str(size_units)
		if not _shapes.has(shape_key):
			_shapes[shape_key] = PartLibrary.make_shape(type, size_m, true)
	else:
		# Only this piece of the machine: its model, and a shape for it.
		var spec: Array = _piece_spec(piece, record)
		var piece_name: String = spec[0]
		var options := {"half": piece_name}
		var cylinder := type == "fluid_cylinder" or type == "combustion_cylinder"
		if piece_name == "top" and (type == "piston" or type == "solenoid" or cylinder) and size_m.y > 0.0:
			# Enough rod to show when it is run right out.
			var travel: float = float(props.get("max_length", props.get("stroke", 1.0))) * Units.CELL
			options["reach"] = snappedf(clampf(travel / size_m.y, 0.0, 64.0), 0.01)
		mesh = PartLibrary.get_mesh("piston" if cylinder else type, options)
		shape_key = "%s %s %s" % [type, piece_name, size_units]
		if type == "wheel" and piece_name == "top":
			# The tyre is round, so that it rolls.
			if not _shapes.has(shape_key):
				_shapes[shape_key] = PartLibrary.make_shape(type, size_m, true)
		else:
			if not _shapes.has(shape_key):
				var trim: Vector3 = spec[3]
				var piece_box := BoxShape3D.new()
				piece_box.size = _piece_size(piece, record) * trim
				_shapes[shape_key] = piece_box
			shape_place = Transform3D(rot, _piece_middle(piece, record) - centre)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = Transform3D(
			Basis(rot.x * size_m.x, rot.y * size_m.y, rot.z * size_m.z), place.origin)
	mesh_instance.set_surface_override_material(0, MaterialLibrary.surface(material, color))
	body.add_child(mesh_instance)
	entry["mesh"] = mesh_instance

	var collider := CollisionShape3D.new()
	collider.shape = _shapes[shape_key]
	collider.transform = shape_place
	collider.set_meta("uid", uid)   # so a hit on this shape can be traced to its part
	body.add_child(collider)
	entry["collider"] = collider

	if type == "thruster":
		var flame := _new_flame(place, size_m)
		body.add_child(flame)
		extras.append(flame)
		_thrusters.append([piece, place, float(props.get("thrust", 1000.0)), record.get("links", {}), flame])
	elif PartLibrary.is_aero_panel(type):
		var area: float = size_m.x * size_m.z
		if PartLibrary.is_triangle_panel(type):
			area *= 0.5
		# The air acts at the middle of the panel's area. Its flat faces
		# look along its own Y axis.
		_panels.append([piece, BuildGrid.centroid_of(record) - centre, rot.y, area,
				PartLibrary.is_dragless(type)])
	return true


## Brings a body's mass, centre of mass and friction in line with the pieces
## it now holds.
func _refresh_body(body: RigidBody3D) -> void:
	var pieces: Array = _body_pieces.get(body, [])
	var mass := 0.0
	var moment := Vector3.ZERO
	var grip := 0.0
	for piece in pieces:
		var entry: Dictionary = _pieces[piece]
		var piece_mass: float = entry["mass"]
		var piece_centre: Vector3 = entry["centre"]
		mass += piece_mass
		moment += piece_centre * piece_mass
		grip += float(entry["friction"]) * piece_mass
	if mass <= 0.0:
		return
	var centre: Vector3 = moment / mass
	if body.is_inside_tree() and not body.freeze:
		# The body's speed is that of its centre of mass. Moving the centre
		# along a spinning body changes the number, not the motion. The
		# speeds are read straight from the physics engine, so a push given
		# earlier in the same tick is not lost.
		var shift: Vector3 = body.global_transform.basis * (centre - body.center_of_mass)
		if shift.length_squared() > 0.000000000001:
			body.linear_velocity = _fresh_speed(body) + _fresh_spin(body).cross(shift)
	body.mass = maxf(mass, 0.001)
	body.center_of_mass = centre
	body.physics_material_override.friction = grip / mass   # the mass-weighted average of its materials
	body.inertia = _inertia_of(pieces, centre, mass)
	_rebuild_floats(body)
	var drag: Dictionary = _drag.get(body, {})
	if int(drag.get("count", -1)) != pieces.size():
		_drag[body] = {"count": pieces.size(), "axes": _drag_areas(pieces)}


## A body's moments of inertia about its centre of mass, along its own axes,
## from each piece's real mass and box (a solid box, moved out by the
## parallel-axis rule). The cross terms are left out, so the engine treats
## the body's axes as its principal axes.
func _inertia_of(pieces: Array, centre: Vector3, mass: float) -> Vector3:
	var total := Vector3.ZERO
	for piece in pieces:
		var entry: Dictionary = _pieces[piece]
		var piece_mass: float = entry["mass"]
		var size: Vector3 = (_boxes[piece] as AABB).size if _boxes.has(piece) else Vector3.ONE * Units.CELL
		var away: Vector3 = (entry["centre"] as Vector3) - centre
		total += piece_mass / 12.0 * Vector3(size.y * size.y + size.z * size.z,
				size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y)
		total += piece_mass * Vector3(away.y * away.y + away.z * away.z,
				away.x * away.x + away.z * away.z, away.x * away.x + away.y * away.y)
	# Never quite zero, which the solver cannot take.
	var least := maxf(mass, 0.001) * 0.0001
	return Vector3(maxf(total.x, least), maxf(total.y, least), maxf(total.z, least))


## How much a body catches the air from each side: for each of its own three
## axes, the area of its outline seen along that axis (the parts' boxes laid
## on a grid of quarter-block cells, so overlaps count once), and the middle
## of that outline, where the drag acts. Aero panels and propellers are left
## out: they work out their own air forces.
func _drag_areas(pieces: Array) -> Array:
	var axes: Array = []
	var boxes: Array = []
	for piece in pieces:
		var uid: int = _uid_of(piece)
		var record: Dictionary = _records[uid]
		var type: String = record["type"]
		if PartLibrary.is_aero_panel(type) or type == "propeller" or not _boxes.has(piece):
			continue
		var entry: Dictionary = _pieces[piece]
		var place: Transform3D = entry["place"]
		var grid_box: AABB = _boxes[piece]
		# The piece's box in the body: the part's own middle, plus where the
		# piece sits from it.
		var middle: Vector3 = place.origin + (grid_box.get_center() - Vector3(record["pos"] as Vector3i) * Units.UNIT)
		boxes.append(AABB(middle - grid_box.size * 0.5, grid_box.size))
	for axis in 3:
		var u_axis := (axis + 1) % 3
		var v_axis := (axis + 2) % 3
		var cells: Dictionary = {}
		for item in boxes:
			var box: AABB = item
			var u0 := int(ceil(box.position[u_axis] / Units.CELL - 0.5))
			var u1 := int(floor(box.end[u_axis] / Units.CELL - 0.5))
			var v0 := int(ceil(box.position[v_axis] / Units.CELL - 0.5))
			var v1 := int(floor(box.end[v_axis] / Units.CELL - 0.5))
			for u in range(u0, u1 + 1):
				for v in range(v0, v1 + 1):
					cells[Vector2i(u, v)] = true
		var area := cells.size() * Units.CELL * Units.CELL
		var sum := Vector2.ZERO
		for key in cells:
			var cell: Vector2i = key
			sum += (Vector2(cell) + Vector2(0.5, 0.5)) * Units.CELL
		var point := Vector3.ZERO
		if not cells.is_empty():
			sum /= cells.size()
			point[u_axis] = sum.x
			point[v_axis] = sum.y
		axes.append([area, point])
	return axes


## Air drag on every body, from its outline along each of its own axes:
## force = ½ × air density × BODY_DRAG × area × speed² against the motion
## along that axis, acting at the middle of that outline, so a body with more
## outline behind its centre of mass turns its nose into the wind.
func _run_body_drag() -> void:
	for body in _bodies:
		var spawned_body: RigidBody3D = body
		if not is_instance_valid(spawned_body) or spawned_body.freeze or not _drag.has(spawned_body):
			continue
		var axes: Array = _drag[spawned_body]["axes"]
		var frame: Transform3D = spawned_body.global_transform
		var density: float = Aero.air_density(frame.origin.y)
		var pushed := false
		for axis in 3:
			var pair: Array = axes[axis]
			var area: float = pair[0]
			if area <= 0.0:
				continue
			var point: Vector3 = pair[1]
			point[axis] = spawned_body.center_of_mass[axis]
			var arm: Vector3 = frame.basis * point
			var direction: Vector3 = frame.basis[axis].normalized()
			var speed: float = velocity_at(spawned_body, arm).dot(direction)
			if absf(speed) < 0.5:
				continue
			var force: float = 0.5 * density * BODY_DRAG * area * speed * absf(speed)
			# Never more than would stop that motion in one tick.
			force = minf(absf(force), spawned_body.mass * absf(speed) * 240.0 * 0.5) * signf(force)
			spawned_body.apply_force(-direction * force, arm)
			pushed = true
		if pushed:
			spawned_body.sleeping = false


# --- Damage ------------------------------------------------------------------

## The part a collision shape belongs to: its uid, or 0. `collider` is the
## body that was hit and `shape` the index of the shape on it.
func part_of_shape(collider: Object, shape: int) -> int:
	var body := collider as RigidBody3D
	if body == null or not _body_pieces.has(body) or shape < 0:
		return 0
	var owner_node: Object = body.shape_owner_get_owner(body.shape_find_owner(shape))
	if owner_node == null or not owner_node.has_meta("uid"):
		return 0
	return int(owner_node.get_meta("uid"))


## A part's health left, or 0 if it is gone.
func health_of(uid: int) -> float:
	return float(_health.get(uid, 0.0))


## Where a part is now, in the world, and the body it is in: [point, body].
## Empty if the part is gone.
func part_place(uid: int) -> Array:
	var piece: int = uid * PIECES
	if not _pieces.has(piece):
		return []
	var entry: Dictionary = _pieces[piece]
	var body: RigidBody3D = entry["body"]
	var local: Vector3 = entry["centre"]
	return [body.global_transform * local, body]


## A part's own axes and middle as they are now, in the world, and the body
## it is in: [transform, body]. Empty if the part is gone.
func part_frame(uid: int) -> Array:
	var piece: int = uid * PIECES
	if not _pieces.has(piece):
		return []
	var entry: Dictionary = _pieces[piece]
	var body: RigidBody3D = entry["body"]
	var place: Transform3D = entry["place"]
	return [body.global_transform * place, body]


## A part's drawn meshes and collision shapes, for logic.gd to light up or
## hide: [MeshInstance3D or null, CollisionShape3D or null] for each of its
## pieces. Empty if the part is gone.
func part_nodes(uid: int) -> Array:
	var found: Array = []
	for index in PIECES:
		var piece: int = uid * PIECES + index
		if not _pieces.has(piece):
			continue
		var entry: Dictionary = _pieces[piece]
		found.append([entry["mesh"], entry["collider"]])
	return found


## Every part that still exists: its uid.
func live_parts() -> Array:
	return _health.keys()


## Takes health from a part. Returns true if that destroyed it.
func damage_part(uid: int, amount: float) -> bool:
	var destroyed: Array = damage_parts({uid: amount})
	return not destroyed.is_empty()


## Takes health from many parts at once: {uid: amount}. Returns the uids of
## the parts that destroyed. The bodies they were in are checked once, after
## all of them have gone, which is far quicker than one part at a time.
func damage_parts(amounts: Dictionary) -> Array:
	var doomed: Array = []
	for key in amounts:
		var uid: int = key
		var amount: float = amounts[key]
		if not _health.has(uid) or amount <= 0.0:
			continue
		var left: float = float(_health[uid]) - amount
		if left > 0.0:
			_health[uid] = left
		else:
			doomed.append(uid)
	_destroy_parts(doomed)
	return doomed


## Removes a part outright, whatever its health.
func destroy_part(uid: int) -> void:
	_destroy_parts([uid])


## Removes parts. If that leaves a body in separate chunks, each chunk
## becomes a body of its own.
func _destroy_parts(uids: Array) -> void:
	var touched: Array = []   # bodies that lost pieces
	var gone: Array = []      # [uid, type, where it was, props]
	for item in uids:
		var uid: int = item
		_remove_part(uid, touched, gone)
	for touched_body in touched:
		_resplit(touched_body)
	for item in gone:
		var news: Array = item
		part_destroyed.emit(news[0], news[1], news[2], news[3])


## Takes one part out of the world. The bodies it was in are added to
## `touched`, and what to announce about it to `gone`.
func _remove_part(uid: int, touched: Array, gone: Array) -> void:
	if not _records.has(uid) or _dead.has(uid):
		return
	var record: Dictionary = _records[uid]
	var place: Array = part_place(uid)
	var at := Vector3.ZERO
	if not place.is_empty():
		at = place[0]
	_dead[uid] = true
	_health.erase(uid)
	_seats.erase(uid)
	_outputs.erase(uid)
	_gears.erase(uid)

	# Its joints go with it.
	var kept_joints: Array = []
	for item in _joints:
		var joint_entry: Dictionary = item
		if int(joint_entry["uid"]) == uid:
			var joint_node: Node = joint_entry["node"]
			joint_node.queue_free()
		else:
			kept_joints.append(joint_entry)
	_joints = kept_joints

	for index in PIECES:
		var piece: int = uid * PIECES + index
		if not _pieces.has(piece):
			continue
		var entry: Dictionary = _pieces[piece]
		var body: RigidBody3D = entry["body"]
		var collider := entry["collider"] as CollisionShape3D
		if collider != null:
			# Nodes are freed at the end of the frame. Until then nothing more
			# should hit this one.
			collider.disabled = true
		var owned: Array = [entry["mesh"], entry["collider"]]
		owned.append_array(entry["extras"])
		for thing in owned:
			var node := thing as Node
			if node != null:
				node.queue_free()
		var held: Array = _body_pieces.get(body, [])
		held.erase(piece)
		_pieces.erase(piece)
		_boxes.erase(piece)
		if not touched.has(body):
			touched.append(body)
	gone.append([uid, str(record["type"]), at, record.get("props", {})])


## After a body has lost pieces: frees it if nothing solid is left, and
## otherwise checks whether what is left still hangs together. Each separate
## chunk beyond the heaviest becomes a new body.
func _resplit(body: RigidBody3D) -> void:
	# A hull that has lost a part is holed: its sealed air floods.
	if _air.has(body):
		_air.erase(body)
		_rebuild_floats(body)
	var pieces: Array = _body_pieces.get(body, [])
	if not _any_solid(pieces):
		for piece in pieces:
			_pieces.erase(piece)
			_boxes.erase(piece)
		_body_pieces.erase(body)
		_bodies.erase(body)
		_floats.erase(body)
		_air.erase(body)
		_drag.erase(body)
		body.queue_free()
		return

	var groups: Array = weld_groups(pieces, _boxes)
	if groups.size() > 1:
		# The heaviest chunk keeps the body.
		var heaviest := 0
		var heaviest_mass := -1.0
		for index in groups.size():
			var chunk: Array = groups[index]
			var chunk_mass: float = _mass_of_pieces(chunk)
			if chunk_mass > heaviest_mass:
				heaviest = index
				heaviest_mass = chunk_mass
		for index in groups.size():
			if index != heaviest:
				var moved: Array = groups[index]
				_move_to_new_body(body, moved)
	var remaining: Array = _body_pieces[body]
	body.freeze = _chunk_is_fixed(remaining)
	_refresh_body(body)
	body.sleeping = false


func _any_solid(pieces: Array) -> bool:
	for piece in pieces:
		var entry: Dictionary = _pieces[piece]
		if entry["collider"] != null:
			return true
	return false


func _mass_of_pieces(pieces: Array) -> float:
	var mass := 0.0
	for piece in pieces:
		var entry: Dictionary = _pieces[piece]
		mass += float(entry["mass"])
	return mass


## True if a chunk should be fixed in place: it holds an anchor block or
## something immovable, or still welds to something immovable.
func _chunk_is_fixed(pieces: Array) -> bool:
	for piece in pieces:
		var piece_id: int = piece
		var record: Dictionary = _records[_uid_of(piece_id)]
		var material: String = record["material"]
		if record["type"] == "anchor_block" or MaterialLibrary.is_immovable(material):
			return true
		if not _fixed_buckets.is_empty() and _touches_fixed(piece_id):
			return true
	return false


## Moves a chunk of a body's pieces into a new body, at the same place and
## moving the same way.
func _move_to_new_body(old: RigidBody3D, pieces: Array) -> void:
	var old_held: Array = _body_pieces[old]
	if not _any_solid(pieces):
		# Nothing to see or touch in this chunk: it simply goes.
		for piece in pieces:
			old_held.erase(piece)
			_pieces.erase(piece)
			_boxes.erase(piece)
		return
	var fixed: bool = _chunk_is_fixed(pieces)
	var body := _new_body(fixed)
	# The same frame as the old body, so every piece keeps its place in it.
	body.transform = old.global_transform
	for piece in pieces:
		var entry: Dictionary = _pieces[piece]
		var owned: Array = [entry["mesh"], entry["collider"]]
		owned.append_array(entry["extras"])
		for thing in owned:
			var node := thing as Node
			if node != null:
				old.remove_child(node)
				body.add_child(node)
		entry["body"] = body
		old_held.erase(piece)
	_body_pieces[body] = pieces.duplicate()
	_refresh_body(body)
	add_child(body)
	_bodies.append(body)
	if not fixed and not old.freeze:
		var old_centre: Vector3 = old.global_transform * old.center_of_mass
		var new_centre: Vector3 = body.global_transform * body.center_of_mass
		var old_spin: Vector3 = _fresh_spin(old)
		body.linear_velocity = _fresh_speed(old) + old_spin.cross(new_centre - old_centre)
		body.angular_velocity = old_spin

	# Joints that hold one of the moved pieces now hold the new body.
	var kept_joints: Array = []
	for item in _joints:
		var joint_entry: Dictionary = item
		if pieces.has(joint_entry["a"]) or pieces.has(joint_entry["b"]):
			if not _repoint_joint(joint_entry):
				continue
		kept_joints.append(joint_entry)
	_joints = kept_joints


## Fastens a joint to the bodies its two pieces are in now. Returns false,
## and removes the joint, if it no longer joins two different bodies.
func _repoint_joint(joint_entry: Dictionary) -> bool:
	var node: Joint3D = joint_entry["node"]
	var a_body: RigidBody3D = _piece_body(joint_entry["a"])
	var b_body: RigidBody3D = _piece_body(joint_entry["b"])
	if a_body == null or b_body == null or a_body == b_body:
		node.queue_free()
		return false
	var local: Transform3D = joint_entry["local"]
	node.global_transform = a_body.global_transform * local
	node.node_a = NodePath("")
	node.node_b = NodePath("")
	node.node_a = NodePath("../" + str(a_body.name))
	node.node_b = NodePath("../" + str(b_body.name))
	return true


# --- Joints ------------------------------------------------------------------

## Joins two pieces of a machine. The two bodies a joint connects do not
## collide with each other, so that the machine can move without its own
## pieces or its neighbours jamming it.
func _make_joint(uid: int, record: Dictionary, role: String, spec: Array, a: int, b: int) -> void:
	var a_body: RigidBody3D = _piece_body(a)
	var b_body: RigidBody3D = _piece_body(b)
	var rot: Basis = record["rot"]
	var props: Dictionary = record.get("props", {})
	var size_units: Vector3i = record["size"]
	var size_m: Vector3 = Units.to_metres(size_units)
	var kind: String = spec[2]
	var axis_index: int = spec[3]
	var pivot_share: Vector3 = spec[4]
	if kind == "end":
		# A linkage bar's end is a ball joint or a hinge, as its setting says.
		var ends: String = str(props.get("ends", "Ball joints"))
		kind = "ball"
		if ends == "Hinges about Y":
			kind = "hinge"
			axis_index = 1
		elif ends == "Hinges about Z":
			kind = "hinge"
			axis_index = 2
	var pivot: Vector3 = Vector3(record["pos"] as Vector3i) * Units.UNIT + rot * (pivot_share * size_m)
	var axis: Vector3 = rot[axis_index]
	var across: Vector3 = rot[(axis_index + 1) % 3]
	var third: Vector3 = rot[(axis_index + 2) % 3]
	var world_pivot: Vector3 = _grid_frame * pivot

	var joint: Joint3D
	if kind == "hinge":
		var hinge := HingeJoint3D.new()
		# A hinge joint turns about its own Z axis, so its Z is laid along the pin.
		hinge.transform = _grid_frame * Transform3D(Basis(across, third, axis), pivot)
		joint = hinge
	elif kind == "slide":
		var slide := Generic6DOFJoint3D.new()
		# A six-way joint starts out locked every way. Its X is laid along
		# the line the top slides on, and that one way is opened in _add_slider.
		slide.transform = _grid_frame * Transform3D(Basis(axis, across, third), pivot)
		joint = slide
	else:
		var limited: bool = bool(props.get("limited", false))
		var carries: bool = bool(props.get("carries_rotation", false))
		if role == "ball" and (limited or carries):
			# A cone joint swings up to an angle from its own X axis and
			# twists about it. No twist at all carries rotation through.
			var cone := ConeTwistJoint3D.new()
			cone.transform = _grid_frame * Transform3D(Basis(axis, across, third), pivot)
			var swing: float = PI
			if limited:
				swing = deg_to_rad(float(props.get("max_angle", 45.0)))
			var twist: float = PI
			if carries:
				twist = 0.0
			cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, swing)
			cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, twist)
			joint = cone
		else:
			var pin := PinJoint3D.new()
			pin.transform = _grid_frame * Transform3D(Basis.IDENTITY, pivot)
			joint = pin

	# Both bodies start out square to the grid, so directions in the grid's
	# space are also directions inside each body.
	if kind == "hinge":
		_add_turner(uid, role, joint as HingeJoint3D, a, b, axis, across, record)
	elif kind == "slide":
		var anchor_a: Vector3 = a_body.transform.affine_inverse() * world_pivot
		var anchor_b: Vector3 = b_body.transform.affine_inverse() * world_pivot
		_add_slider(uid, role, joint as Generic6DOFJoint3D, a, b, axis, anchor_a, anchor_b, record)

	# The joint and the bodies are all children of this node.
	joint.node_a = NodePath("../" + str(a_body.name))
	joint.node_b = NodePath("../" + str(b_body.name))
	add_child(joint)
	_joints.append({
		"node": joint, "uid": uid, "a": a, "b": b,
		"local": a_body.transform.affine_inverse() * joint.transform,
	})


# --- Turning joints ----------------------------------------------------------

## Notes a joint that turns about an axis, and sets up whatever its role
## needs. Every one is measured each tick: its angle and its turning speed.
##   hinge    limits and friction torque from its settings
##   bearing, wheel   friction torque from its settings
##   crank, link      turns freely
##   clutch, brake    grips with up to its max torque when told to
##   motor, servo     driven; see _run_turners
func _add_turner(uid: int, role: String, joint: HingeJoint3D, a: int, b: int,
		axis: Vector3, across: Vector3, record: Dictionary) -> void:
	var props: Dictionary = record.get("props", {})
	var step: float = 1.0 / float(Engine.physics_ticks_per_second)
	var grip := 0.0   # the most torque the joint's motor may use, in N m
	var motor_on := false
	if role == "hinge" and bool(props.get("limited", false)):
		var lowest: float = deg_to_rad(float(props.get("min_angle", -90.0)))
		var highest: float = deg_to_rad(float(props.get("max_angle", 90.0)))
		if lowest <= highest:
			joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, lowest)
			joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, highest)
	if role == "hinge" or role == "bearing" or role == "wheel":
		# Friction torque: a motor that aims for no turning, with only the
		# friction torque to do it with.
		grip = float(props.get("friction", 0.0))
		motor_on = grip > 0.0
	elif role == "motor" or role == "servo":
		# A drive hands the joint's motor the turning speed it wants each
		# tick, and the engine holds that speed as part of solving the joint,
		# with at most the drive's max torque. Solved that way a drive is as
		# stiff as a real one, however light or heavy the things it turns.
		grip = float(props.get("max_torque", 100.0))
		motor_on = true
	# Torque x time step is the motor's impulse limit.
	joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
	joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, grip * step)
	joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, motor_on)
	_turners.append({
		"uid": uid, "role": role, "joint": joint, "a": a, "b": b,
		"axis": axis,                   # the axis, inside a's body
		"from": across, "to": across,   # one direction square to the axis, inside a's body and inside b's
		"props": props, "links": record.get("links", {}),
		"motor_on": motor_on, "grip": grip, "asked": 0.0,   # the joint motor's state
		"last": 0.0, "angle": 0.0, "spin": 0.0,   # the angle, wrapped and then counted through whole turns, and the speed
		"rate": 0.0,                    # the speed being asked for, in rad/s
		"setpoint": 0.0, "hold": 0.0,   # servo: where it should be now, and where it holds when idle
	})


## Measures a turning joint: the angle of b against a, counted through whole
## turns, and its turning speed in rad/s. Positive is counterclockwise seen
## from b looking back at a. Returns false if either side is gone.
func _measure_turner(turner: Dictionary) -> bool:
	var a_body: RigidBody3D = _piece_body(turner["a"])
	var b_body: RigidBody3D = _piece_body(turner["b"])
	if a_body == null or b_body == null:
		return false
	var a_frame: Basis = a_body.global_transform.basis
	var local_axis: Vector3 = turner["axis"]
	var local_from: Vector3 = turner["from"]
	var local_to: Vector3 = turner["to"]
	var axis: Vector3 = (a_frame * local_axis).normalized()
	var from: Vector3 = a_frame * local_from
	var to: Vector3 = b_body.global_transform.basis * local_to
	var wrapped: float = atan2(axis.dot(from.cross(to)), from.dot(to))
	var last: float = turner["last"]
	turner["angle"] = float(turner["angle"]) + wrapf(wrapped - last, -PI, PI)
	turner["last"] = wrapped
	turner["spin"] = (b_body.angular_velocity - a_body.angular_velocity).dot(axis)
	return true


## Runs every turning joint: measures it, works out what its motor should be
## doing, and reports its outputs.
func _run_turners(delta: float) -> void:
	var alive: Array = []
	for item in _turners:
		var turner: Dictionary = item
		if not _measure_turner(turner):
			continue   # one side has been destroyed
		alive.append(turner)
		var role: String = turner["role"]
		var props: Dictionary = turner["props"]
		var links: Dictionary = turner["links"]
		var angle: float = turner["angle"]
		var spin: float = turner["spin"]
		var uid: int = turner["uid"]
		var rpm: float = spin * 60.0 / TAU

		if role == "motor":
			var top_spin: float = float(props.get("max_speed", 600.0)) * TAU / 60.0
			var ramp: float = float(props.get("acceleration", 600.0)) * TAU / 60.0
			var rate: float = turner["rate"]
			# Speed is a share of max speed, -1 to 1. The two switches add a full turn each way.
			var command: float = clampf(_input_value(links, "speed", 0.0), -1.0, 1.0)
			if _input_value(links, "counterclockwise", 0.0) != 0.0:
				command += 1.0
			if _input_value(links, "clockwise", 0.0) != 0.0:
				command -= 1.0
			command = clampf(command, -1.0, 1.0)
			var max_torque: float = float(props.get("max_torque", 100.0))
			if command == 0.0 and str(props.get("when_idle", "Hold still")) == "Spin freely":
				turner["rate"] = spin   # so it picks up smoothly from whatever speed it has coasted to
				_set_turner_motor(turner, false, 0.0, max_torque)
			else:
				rate = move_toward(rate, command * top_spin, ramp * delta)
				turner["rate"] = rate
				_set_turner_motor(turner, true, rate, max_torque)
			_outputs[uid] = {"shaft_speed": rpm}
		elif role == "servo":
			var go_positive: bool = _input_value(links, "go_positive", 0.0) != 0.0
			var go_negative: bool = _input_value(links, "go_negative", 0.0) != 0.0
			var target: float = deg_to_rad(float(props.get("default_angle", 0.0)))
			var commanded := true
			if go_positive and not go_negative:
				target = deg_to_rad(float(props.get("positive_angle", 90.0)))
			elif go_negative and not go_positive:
				target = deg_to_rad(float(props.get("negative_angle", -90.0)))
			elif links.has("angle"):
				target = deg_to_rad(_input_value(links, "angle", 0.0))
			else:
				commanded = false
				if str(props.get("when_idle", "Return to default angle")) == "Hold position":
					target = turner["hold"]
			var eased: Vector2 = _ease_toward(float(turner["setpoint"]), float(turner["rate"]), target,
					deg_to_rad(float(props.get("speed", 90.0))), deg_to_rad(float(props.get("easing", 360.0))), delta)
			turner["setpoint"] = eased.x
			turner["rate"] = eased.y
			if commanded:
				turner["hold"] = eased.x
			# Follow the moving setpoint, and close a share of any error each tick.
			var wanted: float = eased.y + SERVO_GAIN * (eased.x - angle) / delta
			_set_turner_motor(turner, true, wanted, float(props.get("max_torque", 100.0)))
			_outputs[uid] = {"angle": rad_to_deg(angle)}
		elif role == "clutch":
			# Engaged, the two plates are held at the same speed with up to
			# the clutch's max torque; past that they slip. With nothing
			# linked the clutch follows its own setting.
			var engaged: bool = bool(props.get("engaged", true))
			var share := 1.0
			if links.has("engage"):
				engaged = _input_value(links, "engage", 0.0) != 0.0
			if links.has("amount"):
				share = clampf(_input_value(links, "amount", 0.0), 0.0, 1.0)
				if not links.has("engage"):
					engaged = share > 0.0
			_set_turner_motor(turner, engaged, 0.0, float(props.get("max_torque", 200.0)) * share)
		elif role == "brake":
			# On, the disc is held still against the caliper with up to the
			# brake's max torque. Amount, 0 to 1, squeezes it part way.
			var braking: bool = _input_value(links, "brake", 0.0) != 0.0
			var squeeze := 1.0
			if not braking and links.has("amount"):
				squeeze = clampf(_input_value(links, "amount", 0.0), 0.0, 1.0)
				braking = squeeze > 0.0
			_set_turner_motor(turner, braking, 0.0, float(props.get("max_torque", 200.0)) * squeeze)
			_outputs[uid] = {"speed": rpm}
		elif role == "crank":
			_outputs[uid] = {"angle": rad_to_deg(angle), "speed": rpm}
		elif role == "hinge":
			_outputs[uid] = {"angle": rad_to_deg(angle)}
		else:
			_outputs[uid] = {"speed": rpm}
	_turners = alive


## Moves `setpoint` toward `target`: no faster than `top_speed`, easing away
## from rest and easing in to stop on the target. `rate` is the speed it is
## moving at. Returns the new (setpoint, rate).
static func _ease_toward(setpoint: float, rate: float, target: float, top_speed: float,
		easing: float, delta: float) -> Vector2:
	var error: float = target - setpoint
	var approach: float = top_speed
	if easing > 0.0:
		approach = minf(top_speed, sqrt(2.0 * easing * absf(error)))
		rate = move_toward(rate, signf(error) * approach, easing * delta)
	else:
		rate = signf(error) * approach
	if absf(error) <= absf(rate) * delta:
		return Vector2(target, 0.0)
	return Vector2(setpoint + rate * delta, rate)


## Sets a turning joint's motor: on or off, the turning speed to hold in
## rad/s (positive counterclockwise seen from b), and the most torque to use.
func _set_turner_motor(turner: Dictionary, on: bool, wanted_spin: float, max_torque: float) -> void:
	var joint: HingeJoint3D = turner["joint"]
	var asked: float = turner["asked"]
	var motor_on: bool = turner["motor_on"]
	var spin: float = turner["spin"]

	# Settle which way the engine counts a positive motor speed. A motor
	# follows what it is asked almost exactly, so if the joint is turning at
	# the speed asked the sign is right, and if it is turning at the same
	# speed the other way the sign is backwards. Three clear answers decide.
	if not _turn_sign_known and motor_on and absf(asked) > 0.05:
		if absf(spin - asked) < 0.25 * absf(asked):
			_turn_votes += 1
		elif absf(spin + asked) < 0.25 * absf(asked):
			_turn_votes -= 1
		if _turn_votes >= 3:
			_turn_sign_known = true
		elif _turn_votes <= -3:
			_turn_sign = -_turn_sign
			_turn_sign_known = true
			asked = INF   # force the speed to be sent again with the new sign

	if max_torque != float(turner["grip"]):
		joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,
				max_torque / float(Engine.physics_ticks_per_second))
		turner["grip"] = max_torque
	if on != motor_on:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, on)
		turner["motor_on"] = on
	if not on:
		turner["asked"] = 0.0
		return
	if wanted_spin != asked:
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, _turn_sign * wanted_spin)
	turner["asked"] = wanted_spin
	# A body at rest goes to sleep, and a sleeping body ignores its motor.
	if absf(wanted_spin - spin) > 0.005:
		_wake(_piece_body(turner["a"]))
		_wake(_piece_body(turner["b"]))


func _wake(body: RigidBody3D) -> void:
	if body != null and not body.freeze:
		body.sleeping = false


# --- Sliding joints ----------------------------------------------------------

## Notes a joint that slides along an axis: a piston, a solenoid or a spring.
## The joint keeps the two sides in line; what moves them is in _run_sliders.
func _add_slider(uid: int, role: String, joint: Generic6DOFJoint3D, a: int, b: int,
		axis: Vector3, anchor_a: Vector3, anchor_b: Vector3, record: Dictionary) -> void:
	var props: Dictionary = record.get("props", {})
	var size_units: Vector3i = record["size"]
	var size_m: Vector3 = Units.to_metres(size_units)
	var start := 0.0     # how far out it is as built, in metres
	var longest := 0.0   # how far out it can go, in metres
	var force := 0.0
	if role == "piston":
		longest = float(props.get("max_length", 1.0)) * Units.CELL
		start = clampf(float(props.get("current_length", 0.0)) * Units.CELL, 0.0, longest)
		force = float(props.get("max_force", 1000.0))
	elif role == "solenoid":
		longest = float(props.get("stroke", 0.5)) * Units.CELL
		force = float(props.get("force", 500.0))
	var hydraulic := false
	if role == "cylinder":
		longest = float(props.get("stroke", 1.0)) * Units.CELL
		hydraulic = str(record["type"]) == "fluid_cylinder" \
				and str(props.get("fluid", "Hydraulic oil")) == "Hydraulic oil"
		force = 1.0

	if role == "spring" or (role == "cylinder" and not hydraulic):
		# Free along its line: the pressure inside pushes it (engines.gd).
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, role == "cylinder")
		if role == "cylinder":
			joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -longest - 0.01)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, longest + 0.01)
	elif role == "spring":
		# A spring is free to move along its line; the spring force is applied by hand.
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, false)
	else:
		# The engine may count "out" as either direction along the line, so
		# the joint allows the full travel both ways. The drive itself keeps
		# the piston between closed and its longest reach.
		var room: float = maxf(start, longest - start) + 0.01
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -room)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, room)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_TARGET_VELOCITY, 0.0)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_FORCE_LIMIT, force)
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, true)

	var slider := {
		"uid": uid, "role": role, "joint": joint, "a": a, "b": b,
		"axis": axis, "anchor_a": anchor_a, "anchor_b": anchor_b,   # the axis inside a's body; one point, inside each body
		"props": props, "links": record.get("links", {}),
		"start": start, "longest": longest,
		"asked": 0.0, "rate": 0.0,
		"setpoint": 0.0, "hold": 0.0,   # measured from where it was built
		"built": size_m.y,              # spring: its length as built
		"coils": null, "coils_place": Transform3D.IDENTITY, "coils_size": size_m,
		"hydraulic": hydraulic, "limit": force,
	}
	if role == "spring":
		# The coils are drawn on the base and stretched to reach the top.
		var rot: Basis = record["rot"]
		var a_body: RigidBody3D = _piece_body(a)
		var material: String = record["material"]
		var color: Color = record["color"]
		var coils := MeshInstance3D.new()
		coils.mesh = PartLibrary.get_mesh("spring", {"half": "coils"})
		coils.set_surface_override_material(0, MaterialLibrary.surface(material, color))
		var body_origin: Vector3 = _grid_frame.affine_inverse() * a_body.transform.origin
		var origin: Vector3 = Vector3(record["pos"] as Vector3i) * Units.UNIT - body_origin
		coils.transform = Transform3D(Basis(rot.x * size_m.x, rot.y * size_m.y, rot.z * size_m.z), origin)
		a_body.add_child(coils)
		var a_entry: Dictionary = _pieces[a]
		var extras: Array = a_entry["extras"]
		extras.append(coils)
		slider["coils"] = coils
		slider["coils_place"] = Transform3D(rot, origin)
	_sliders.append(slider)


## Runs every piston, solenoid and spring.
func _run_sliders(delta: float) -> void:
	var alive: Array = []
	for item in _sliders:
		var slider: Dictionary = item
		var a_body: RigidBody3D = _piece_body(slider["a"])
		var b_body: RigidBody3D = _piece_body(slider["b"])
		if a_body == null or b_body == null:
			continue   # one side has been destroyed
		alive.append(slider)
		var role: String = slider["role"]
		var props: Dictionary = slider["props"]
		var links: Dictionary = slider["links"]
		var uid: int = slider["uid"]
		var local_axis: Vector3 = slider["axis"]
		var local_a: Vector3 = slider["anchor_a"]
		var local_b: Vector3 = slider["anchor_b"]
		var axis: Vector3 = (a_body.global_transform.basis * local_axis).normalized()
		var point_a: Vector3 = a_body.global_transform * local_a
		var point_b: Vector3 = b_body.global_transform * local_b
		# How far the top has moved out from where it was built, and how fast.
		var out: float = (point_b - point_a).dot(axis)
		var speed_b: Vector3 = velocity_at(b_body, point_b - b_body.global_position)
		var speed_a: Vector3 = velocity_at(a_body, point_a - a_body.global_position)
		var moving: float = (speed_b - speed_a).dot(axis)

		if role == "spring":
			_run_spring(slider, a_body, b_body, axis, point_a, point_b, out, moving, delta)
			_outputs[uid] = {"length": (float(slider["built"]) + out) / Units.CELL}
			continue
		if role == "cylinder":
			_run_cylinder(slider, a_body, b_body, axis, point_a, point_b, out, moving, delta)
			continue

		var start: float = slider["start"]
		var longest: float = slider["longest"]
		var target := 0.0   # measured from where it was built
		var top_speed: float = SOLENOID_SPEED
		var easing := 0.0
		if role == "piston":
			top_speed = float(props.get("speed", 0.5))
			easing = float(props.get("easing", 2.0))
			var commanded := true
			if _input_value(links, "extend", 0.0) != 0.0:
				target = float(props.get("target_length", 1.0)) * Units.CELL - start
			elif links.has("length"):
				target = _input_value(links, "length", 0.0) * Units.CELL - start
			else:
				commanded = false
				if str(props.get("when_idle", "Hold position")) == "Hold position":
					target = slider["hold"]
			if commanded:
				slider["hold"] = slider["setpoint"]
		elif _input_value(links, "on", 0.0) != 0.0:
			target = longest
		target = clampf(target, -start, longest - start)
		var eased: Vector2 = _ease_toward(float(slider["setpoint"]), float(slider["rate"]), target,
				top_speed, easing, delta)
		slider["setpoint"] = eased.x
		slider["rate"] = eased.y
		var wanted: float = eased.y + SERVO_GAIN * (eased.x - out) / delta
		_set_slider_motor(slider, wanted, moving)
		if role == "piston":
			_outputs[uid] = {"length": (start + out) / Units.CELL, "pressure": 0.0}
		else:
			_outputs[uid] = {"state": 1.0 if out > longest * 0.5 else 0.0}
	_sliders = alive


## Hands a piston's or solenoid's wanted speed, in m/s outward, to its joint's motor.
func _set_slider_motor(slider: Dictionary, wanted: float, moving: float) -> void:
	var joint: Generic6DOFJoint3D = slider["joint"]
	var asked: float = slider["asked"]
	# Settle which way the engine counts a positive sliding speed, the same
	# way as for turning: by comparing what happens with what was asked.
	if not _slide_sign_known and absf(asked) > 0.02:
		if absf(moving - asked) < 0.25 * absf(asked):
			_slide_votes += 1
		elif absf(moving + asked) < 0.25 * absf(asked):
			_slide_votes -= 1
		if _slide_votes >= 3:
			_slide_sign_known = true
		elif _slide_votes <= -3:
			_slide_sign = -_slide_sign
			_slide_sign_known = true
			asked = INF
	if wanted != asked:
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_TARGET_VELOCITY, _slide_sign * wanted)
	slider["asked"] = wanted
	if absf(wanted - moving) > 0.001:
		_wake(_piece_body(slider["a"]))
		_wake(_piece_body(slider["b"]))


## A fluid or combustion cylinder. A hydraulic one is driven at the speed
## the pumps feeding it give, with the force their pressure allows, and
## holds still (the oil locked in) when they stop. A gas or combustion one
## is pushed by the pressure inside it less the air outside, both worked
## out by engines.gd; it cannot be pushed in past closed.
func _run_cylinder(slider: Dictionary, a_body: RigidBody3D, b_body: RigidBody3D, axis: Vector3,
		point_a: Vector3, point_b: Vector3, out: float, moving: float, delta: float) -> void:
	var uid: int = slider["uid"]
	var longest: float = slider["longest"]
	if bool(slider["hydraulic"]):
		var drive: Array = [0.0, 20000000.0 * 0.01]
		if engines != null:
			drive = engines.hydraulic_drive(uid, out)
		var speed: float = drive[0]
		var limit: float = maxf(float(drive[1]), 1.0)
		if absf(limit - float(slider["limit"])) > limit * 0.01:
			var joint: Generic6DOFJoint3D = slider["joint"]
			joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_MOTOR_FORCE_LIMIT, limit)
			slider["limit"] = limit
		# Oil in, the rod goes out; none, it stays where it is.
		var setpoint := clampf(float(slider["setpoint"]) + speed * delta, 0.0, longest)
		slider["setpoint"] = setpoint
		_set_slider_motor(slider, speed * (1.0 if setpoint > 0.0 and setpoint < longest else 0.0)
				+ SERVO_GAIN * (setpoint - out) / delta, moving)
		return
	var force := 0.0
	if engines != null:
		force = engines.cylinder_force(uid, out, moving, delta)
	# A hard stop at closed, held by a stiff spring the masses can bear.
	if out < 0.0:
		var looseness := 0.0
		if not a_body.freeze:
			looseness += 1.0 / a_body.mass
		if not b_body.freeze:
			looseness += 1.0 / b_body.mass
		if looseness > 0.0:
			var shared_mass: float = 1.0 / looseness
			force += 0.2 * shared_mass / (delta * delta) * -out - 0.5 * shared_mass / delta * minf(moving, 0.0)
	force = clampf(force, -50000000.0, 50000000.0)
	if absf(force) > 0.0001:
		if not a_body.freeze:
			a_body.sleeping = false
			a_body.apply_force(-axis * force, point_a - a_body.global_position)
		if not b_body.freeze:
			b_body.sleeping = false
			b_body.apply_force(axis * force, point_b - b_body.global_position)


## Hangs something drawn (a flame) on a part, so it moves with the part and
## goes when the part is destroyed. `make` gets the part's place inside its
## body and its size, and returns the node.
func attach_extra(uid: int, make: Callable) -> Node3D:
	var piece: int = uid * PIECES
	if not _pieces.has(piece):
		return null
	var entry: Dictionary = _pieces[piece]
	var record: Dictionary = _records[uid]
	var node: Node3D = make.call(entry["place"], Units.to_metres(record["size"] as Vector3i))
	var body: RigidBody3D = entry["body"]
	body.add_child(node)
	var extras: Array = entry["extras"]
	extras.append(node)
	return node


## A spring pushes its two ends apart when shorter than its rest length and
## pulls them together when longer: force = stiffness x (rest - length),
## less damping x the speed the ends are separating at.
func _run_spring(slider: Dictionary, a_body: RigidBody3D, b_body: RigidBody3D, axis: Vector3,
		point_a: Vector3, point_b: Vector3, out: float, moving: float, delta: float) -> void:
	var props: Dictionary = slider["props"]
	var built: float = slider["built"]
	var length: float = built + out
	var stiffness: float = float(props.get("stiffness", 1000.0))
	var damping: float = float(props.get("damping", 10.0))
	# A force worked out once a tick cannot be made arbitrarily stiff: past a
	# point that depends on the masses it would shake itself apart. Hold the
	# stiffness and damping below that point.
	var looseness := 0.0   # 1/mass of each end, added
	if not a_body.freeze:
		looseness += 1.0 / a_body.mass
	if not b_body.freeze:
		looseness += 1.0 / b_body.mass
	if looseness <= 0.0:
		return
	var shared_mass: float = 1.0 / looseness
	stiffness = minf(stiffness, 0.25 * shared_mass / (delta * delta))
	damping = minf(damping, 0.5 * shared_mass / delta)
	var rest: float = float(props.get("rest_length", 1.0)) * Units.CELL
	var force: float = stiffness * (rest - length) - damping * moving
	if absf(force) > 0.0001:
		if not a_body.freeze:
			a_body.sleeping = false
			a_body.apply_force(-axis * force, point_a - a_body.global_position)
		if not b_body.freeze:
			b_body.sleeping = false
			b_body.apply_force(axis * force, point_b - b_body.global_position)
	# Stretch the coils to reach from one plate to the other.
	var coils := slider["coils"] as MeshInstance3D
	if coils != null and built > 0.0:
		var place: Transform3D = slider["coils_place"]
		var size_m: Vector3 = slider["coils_size"]
		var stretch: float = maxf(length / built, 0.05)
		coils.transform = Transform3D(
				Basis(place.basis.x * size_m.x, place.basis.y * (size_m.y * stretch), place.basis.z * size_m.z),
				place.origin + place.basis.y * (out * 0.5))


# --- Gears, belts and racks --------------------------------------------------
# Gears that mesh, and pulleys on one belt, are held at the right speeds by
# correcting them a little every tick. Each pair is treated exactly: the
# correction is the one push on the two that makes their speeds agree, shared
# between them by how easy each is to turn. Ratios come from tooth counts for
# gears and from sizes for pulleys.

## Notes every gear, pulley and rack: where it is, which way its axis
## points, and what it turns against.
func _find_gears() -> void:
	for uid in _records:
		var part_uid: int = uid
		var record: Dictionary = _records[part_uid]
		var type: String = record["type"]
		if type != "gear" and type != "bevel_gear" and type != "pulley" and type != "rack":
			continue
		var piece: int = part_uid * PIECES
		var body: RigidBody3D = _piece_body(piece)
		if body == null:
			continue
		var rot: Basis = record["rot"]
		var size_units: Vector3i = record["size"]
		var size_m: Vector3 = Units.to_metres(size_units)
		var props: Dictionary = record.get("props", {})
		var centre: Vector3 = Vector3(record["pos"] as Vector3i) * Units.UNIT
		var body_origin: Vector3 = _grid_frame.affine_inverse() * body.transform.origin
		if type == "rack":
			# A rack runs along its own X with its teeth on its +Y face.
			var driven_by: Array = []
			_racks.append({
				"uid": part_uid, "piece": piece, "along": rot.x, "up": rot.y, "side": rot.z,
				"centre": centre, "size": size_m,
				"teeth_per_metre": float(props.get("teeth_per_block", 5.0)) / Units.CELL,
				"gears": driven_by,
			})
			continue
		# What a gear turns against: the other side of a joint that turns
		# its body about the gear's own axis. With no such joint it is
		# measured against the world.
		var axis: Vector3 = rot.y
		var carrier := -1
		for item in _turners:
			var turner: Dictionary = item
			var turner_axis: Vector3 = turner["axis"]
			if absf(turner_axis.dot(axis)) < 0.99:
				continue
			if _piece_body(turner["b"]) == body:
				carrier = turner["a"]
				break
			if _piece_body(turner["a"]) == body:
				carrier = turner["b"]
				break
		_gears[part_uid] = {
			"uid": part_uid, "type": type, "piece": piece, "carrier": carrier,
			"axis": axis, "centre": centre, "local_centre": centre - body_origin,
			"radius": 0.5 * maxf(size_m.x, size_m.z), "thickness": size_m.y,
			"teeth": clampf(float(props.get("teeth", 12.0)), 4.0, 400.0),
			"belt": int(props.get("belt", 1)),
		}


## Finds the gears that mesh, the pulleys that share a belt and the gears
## that drive racks.
func _find_meshes() -> void:
	var uids: Array = _gears.keys()
	for first in uids.size():
		for second in range(first + 1, uids.size()):
			var a: Dictionary = _gears[uids[first]]
			var b: Dictionary = _gears[uids[second]]
			if _piece_body(a["piece"]) == _piece_body(b["piece"]):
				continue   # on the same body: they cannot turn against each other
			var type_a: String = a["type"]
			var type_b: String = b["type"]
			var axis_a: Vector3 = a["axis"]
			var axis_b: Vector3 = b["axis"]
			var centre_a: Vector3 = a["centre"]
			var centre_b: Vector3 = b["centre"]
			var radius_a: float = a["radius"]
			var radius_b: float = b["radius"]
			var between: Vector3 = centre_b - centre_a
			var lined_up: float = axis_a.dot(axis_b)
			var level: bool = absf(between.dot(axis_a)) <= 0.5 * (float(a["thickness"]) + float(b["thickness"]))
			if type_a == "pulley" and type_b == "pulley":
				# One belt: same number, parallel shafts, in line with each
				# other. The rims move at one speed, so they turn the same way.
				if int(a["belt"]) > 0 and int(a["belt"]) == int(b["belt"]) and absf(lined_up) > 0.99 and level:
					_meshes.append({"a": a["uid"], "b": b["uid"], "weight_a": radius_a, "weight_b": radius_b,
							"sense": signf(lined_up)})
			elif type_a == "gear" and type_b == "gear":
				# Spur gears: parallel shafts, level with each other, rims touching.
				var gap: float = between.length() - (radius_a + radius_b)
				if absf(lined_up) > 0.99 and level and absf(gap) <= 0.12 * (radius_a + radius_b) + 0.01:
					var mesh_point: Vector3 = centre_a + between * (radius_a / (radius_a + radius_b))
					_add_gear_mesh(a, b, mesh_point)
			elif type_a == "bevel_gear" and type_b == "bevel_gear":
				# Bevel gears: shafts at right angles, close enough to touch.
				if absf(lined_up) < 0.01 and between.length() <= (radius_a + radius_b) * 1.05 + 0.01:
					_add_gear_mesh(a, b, (centre_a + centre_b) * 0.5)

	# A gear drives a rack when it sits on the rack's teeth with its shaft across the rack.
	for item in _racks:
		var rack: Dictionary = item
		var along: Vector3 = rack["along"]
		var up: Vector3 = rack["up"]
		var side: Vector3 = rack["side"]
		var rack_centre: Vector3 = rack["centre"]
		var rack_size: Vector3 = rack["size"]
		var driven: Array = rack["gears"]
		for uid in _gears:
			var gear: Dictionary = _gears[uid]
			if gear["type"] != "gear" or _piece_body(gear["piece"]) == _piece_body(rack["piece"]):
				continue
			var gear_axis: Vector3 = gear["axis"]
			var gear_centre: Vector3 = gear["centre"]
			var radius: float = gear["radius"]
			var offset: Vector3 = gear_centre - rack_centre
			var height: float = offset.dot(up) - (rack_size.y * 0.5 + radius)
			var across_rack: bool = absf(gear_axis.dot(side)) > 0.99
			var on_teeth: bool = absf(height) <= 0.12 * radius + 0.01
			var over_rack: bool = absf(offset.dot(along)) <= rack_size.x * 0.5 + 0.01
			var in_line: bool = absf(offset.dot(side)) <= 0.5 * (rack_size.z + float(gear["thickness"]))
			if across_rack and on_teeth and over_rack and in_line:
				# Which way the gear's teeth move along the rack, at the rack.
				var sense: float = signf(gear_axis.cross(-up).dot(along))
				driven.append([uid, sense])


## Notes two gears that mesh at a point. Their speeds are in the ratio of
## their tooth counts, and which way round comes from where they touch.
func _add_gear_mesh(a: Dictionary, b: Dictionary, mesh_point: Vector3) -> void:
	var axis_a: Vector3 = a["axis"]
	var axis_b: Vector3 = b["axis"]
	var centre_a: Vector3 = a["centre"]
	var centre_b: Vector3 = b["centre"]
	# The direction a's teeth move at the meshing point when a turns forward,
	# and how b's teeth move there when b turns forward.
	var sweep_a: Vector3 = axis_a.cross(mesh_point - centre_a)
	if sweep_a.length() < 0.0001:
		return
	var sweep_b: float = axis_b.cross(mesh_point - centre_b).dot(sweep_a.normalized())
	if absf(sweep_b) < 0.0001:
		return
	_meshes.append({"a": a["uid"], "b": b["uid"], "weight_a": float(a["teeth"]), "weight_b": float(b["teeth"]),
			"sense": signf(sweep_b)})


## A body's turning speed straight from the physics engine, which is up to
## date even after a push earlier in the same tick.
static func _fresh_spin(body: RigidBody3D) -> Vector3:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)


## The speed of a body's centre of mass, likewise straight from the engine.
static func _fresh_speed(body: RigidBody3D) -> Vector3:
	return PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)


## One over a body's moment of inertia about an axis through `pivot`, both in
## the world. Zero for a body that is fixed in place.
func _inverse_inertia(body: RigidBody3D, axis: Vector3, pivot: Vector3) -> float:
	if body == null or body.freeze:
		return 0.0
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null:
		return 0.0
	var about_centre: float = axis.dot(state.inverse_inertia_tensor * axis)
	if about_centre <= 0.0:
		return 0.0
	# The body turns about the pivot, not about its own centre of mass, so
	# add mass x distance^2 (the parallel axis rule).
	var arm: Vector3 = pivot - body.global_transform * body.center_of_mass
	var distance_squared: float = maxf(arm.length_squared() - pow(arm.dot(axis), 2.0), 0.0)
	return 1.0 / (1.0 / about_centre + body.mass * distance_squared)


## What the gear train needs to know about one gear right now:
## [its body, what it turns against (or null), its axis in the world,
## its turning speed against that, one over its inertia]. Empty if it is gone.
func _gear_state(uid: int) -> Array:
	if not _gears.has(uid):
		return []
	var gear: Dictionary = _gears[uid]
	var body: RigidBody3D = _piece_body(gear["piece"])
	if body == null:
		return []
	var carrier: RigidBody3D = _piece_body(gear["carrier"])
	var local_axis: Vector3 = gear["axis"]
	var local_centre: Vector3 = gear["local_centre"]
	var axis: Vector3 = (body.global_transform.basis * local_axis).normalized()
	var spin: Vector3 = _fresh_spin(body)
	if carrier != null:
		spin -= _fresh_spin(carrier)
	return [body, carrier, axis, spin.dot(axis), _inverse_inertia(body, axis, body.global_transform * local_centre)]


## Gives a gear a twist about its axis, in N m s, and the thing it turns
## against the opposite twist.
func _twist_gear(state: Array, twist: float) -> void:
	var body: RigidBody3D = state[0]
	var carrier: RigidBody3D = state[1]
	var axis: Vector3 = state[2]
	if not body.freeze:
		body.sleeping = false
		body.apply_torque_impulse(axis * twist)
	if carrier != null and not carrier.freeze:
		carrier.apply_torque_impulse(-axis * twist)


## Holds meshed gears and belted pulleys at the right speeds, and racks at
## the speed of the gears on them.
func _run_gears() -> void:
	var alive: Array = []
	for item in _meshes:
		var mesh: Dictionary = item
		var a: Array = _gear_state(mesh["a"])
		var b: Array = _gear_state(mesh["b"])
		if a.is_empty() or b.is_empty():
			continue   # one of them has been destroyed
		alive.append(mesh)
		var weight_a: float = mesh["weight_a"]
		var weight_b: float = mesh["weight_b"]
		var sense: float = mesh["sense"]
		# Meshed right, weight_a x speed_a = sense x weight_b x speed_b.
		var slip: float = weight_a * float(a[3]) - sense * weight_b * float(b[3])
		var give: float = weight_a * weight_a * float(a[4]) + weight_b * weight_b * float(b[4])
		if give <= 0.0 or absf(slip) < 0.0001:
			continue
		var push: float = slip / give
		_twist_gear(a, -push * weight_a)
		_twist_gear(b, sense * push * weight_b)
	_meshes = alive

	for item in _racks:
		var rack: Dictionary = item
		var rack_body: RigidBody3D = _piece_body(rack["piece"])
		if rack_body == null or rack_body.freeze:
			continue
		var local_along: Vector3 = rack["along"]
		var along: Vector3 = (rack_body.global_transform.basis * local_along).normalized()
		var teeth_per_metre: float = rack["teeth_per_metre"]
		var driven: Array = rack["gears"]
		for driver in driven:
			var pair: Array = driver
			var gear: Array = _gear_state(pair[0])
			if gear.is_empty():
				continue
			var gear_entry: Dictionary = _gears[pair[0]]
			var sense: float = pair[1]
			# Metres of rack per radian of gear: its teeth, over the rack's teeth per metre.
			var reach: float = float(gear_entry["teeth"]) / (teeth_per_metre * TAU)
			var carrier: RigidBody3D = gear[1]
			var rack_speed: Vector3 = PhysicsServer3D.body_get_state(rack_body.get_rid(),
					PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if carrier != null:
				rack_speed -= carrier.linear_velocity
			var slip: float = sense * reach * float(gear[3]) - rack_speed.dot(along)
			var give: float = reach * reach * float(gear[4]) + 1.0 / rack_body.mass
			if give <= 0.0 or absf(slip) < 0.0001:
				continue
			var push: float = slip / give
			rack_body.sleeping = false
			rack_body.apply_central_impulse(along * push)
			if carrier != null and not carrier.freeze:
				carrier.apply_central_impulse(-along * push)
			_twist_gear(gear, -sense * reach * push)

	for uid in _gears:
		var state: Array = _gear_state(uid)
		if not state.is_empty():
			_outputs[uid] = {"speed": float(state[3]) * 60.0 / TAU}


# --- Signals -----------------------------------------------------------------
# The first small piece of the logic system: enough to drive machines from
# keys. An input block reads its key, a seat reports whether it is occupied,
# a number gate set to Constant gives its number, and a machine reports its
# outputs. Every other source reads as zero for now.

func _new_input_state(props: Dictionary) -> Dictionary:
	return {
		"key": _keycode(str(props.get("key", "W"))),
		"second_key": _keycode(str(props.get("second_key", "S"))),
		"toggle": str(props.get("mode", "Hold")) == "Toggle",
		"two_keys": str(props.get("output", "Boolean")) != "Boolean",
		"was_down": false, "latched": false,
		"pressed": 0.0, "value": 0.0,
	}


## Turns a key's name, such as "W", "Shift" or "Up", into its key code.
static func _keycode(key_name: String) -> int:
	var cleaned := key_name.strip_edges()
	if cleaned.length() == 1:
		cleaned = cleaned.to_upper()
	return OS.find_keycode_from_string(cleaned)


## Reads every input block's keys. Key binds only work while the character is
## seated; on foot the same keys walk.
func _update_inputs() -> void:
	var seated: bool = occupied_seat != 0
	for uid in _inputs:
		var state: Dictionary = _inputs[uid]
		var key: int = state["key"]
		var second_key: int = state["second_key"]
		var down: bool = seated and key != KEY_NONE and Input.is_key_pressed(key as Key)
		var second_down: bool = seated and second_key != KEY_NONE and Input.is_key_pressed(second_key as Key)
		var pressed: bool = down
		if state["toggle"]:
			if down and not state["was_down"]:
				state["latched"] = not state["latched"]
			pressed = state["latched"]
		state["was_down"] = down
		state["pressed"] = 1.0 if pressed else 0.0
		if state["two_keys"]:
			state["value"] = (1.0 if down else 0.0) - (1.0 if second_down else 0.0)
		else:
			state["value"] = state["pressed"]


## The value arriving at one of a part's inputs, or `unlinked` if nothing is
## linked to it. On/off signals are 1 and 0. A destroyed source reads zero.
func input_value(links: Dictionary, input_id: String, unlinked: float) -> float:
	return _input_value(links, input_id, unlinked)


func _input_value(links: Dictionary, input_id: String, unlinked: float) -> float:
	if not links.has(input_id):
		return unlinked
	var link: Dictionary = links[input_id]
	var source_uid: int = int(link.get("uid", 0))
	var output_id: String = str(link.get("output", ""))
	if not _records.has(source_uid):
		return unlinked
	if _dead.has(source_uid):
		return 0.0
	var source: Dictionary = _records[source_uid]
	var type: String = source["type"]
	if type == "input_block":
		var state: Dictionary = _inputs.get(source_uid, {})
		return float(state.get(output_id, 0.0))
	if type == "seat":
		return 1.0 if occupied_seat == source_uid else 0.0
	if _outputs.has(source_uid):
		var reported: Dictionary = _outputs[source_uid]
		return float(reported.get(output_id, 0.0))
	if type == "number_gate":
		var props: Dictionary = source.get("props", {})
		if str(props.get("operation", "")) == "Constant":
			return float(props.get("value", 0.0))
	return 0.0


## The part a link reads from: its uid, or 0 if the input is not linked.
func link_source(links: Dictionary, input_id: String) -> int:
	if not links.has(input_id):
		return 0
	var link: Dictionary = links[input_id]
	return int(link.get("uid", 0))


## Lets another script publish a part's outputs, for links to read.
## What a part is putting out now: output id -> value. Empty if nothing.
func outputs_of(uid: int) -> Dictionary:
	return _outputs.get(uid, {})


func set_outputs(uid: int, values: Dictionary) -> void:
	_outputs[uid] = values


## Where each moving body is and how fast it is going: [position, velocity]
## pairs, for the map to keep the ground solid round them.
func body_motions() -> Array:
	var motions: Array = []
	for item in _bodies:
		var body: RigidBody3D = item
		if is_instance_valid(body) and not body.freeze:
			motions.append([body.global_position, body.linear_velocity])
	return motions


## Every spawned part's record, by uid, as it was spawned. Destroyed parts
## are still listed; ask record_of to leave those out.
func all_records() -> Dictionary:
	return _records


## A part's record as it was spawned, or {} if there is no such part or it
## has been destroyed.
func record_of(uid: int) -> Dictionary:
	if not _records.has(uid) or _dead.has(uid):
		return {}
	return _records[uid]


## Changes the mass of a part that is in one piece, such as an ammo
## generator as it fills. Its body is brought up to date.
func set_part_mass(uid: int, mass: float) -> void:
	var piece: int = uid * PIECES
	if not _pieces.has(piece):
		return
	var entry: Dictionary = _pieces[piece]
	entry["mass"] = maxf(mass, 0.001)
	_refresh_body(entry["body"])


# --- Forces ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not spawned:
		return
	_update_inputs()
	_run_turners(delta)
	_run_sliders(delta)
	_run_gears()
	_run_thrusters()
	_run_aero(delta)
	_run_body_drag()
	_run_buoyancy(delta)


# --- Re-centring ---------------------------------------------------------------

## Moves every body and joint by -`shift` when main.gd re-centres the world.
func shift_origin(shift: Vector3) -> void:
	_grid_frame.origin -= shift
	for item in _bodies:
		var body: RigidBody3D = item
		if is_instance_valid(body):
			body.global_position -= shift
	for entry in _joints:
		var joint_entry: Dictionary = entry
		var node: Node3D = joint_entry["node"]
		if is_instance_valid(node):
			node.global_position -= shift


# --- Floating ------------------------------------------------------------------

## Works out the floats of a body: every part's own solid volume (its mass
## over its material's density), plus any air sealed inside it, merged into
## 1 m cubes. Points are inside the body, measured from its origin.
func _rebuild_floats(body: RigidBody3D) -> void:
	var cubes: Dictionary = {}   # Vector3i -> [volume, volume x position]
	for piece in _body_pieces.get(body, []):
		var entry: Dictionary = _pieces[piece]
		var record: Dictionary = _records[_uid_of(piece)]
		var density: float = MaterialLibrary.density(str(record["material"]))
		if density <= 0.0:
			continue
		var volume: float = float(entry["mass"]) / density
		var point: Vector3 = entry["centre"]
		_add_to_cube(cubes, point, volume)
	if _air.has(body):
		var air: Array = _air[body]
		var points: PackedVector3Array = air[0]
		var volumes: PackedFloat32Array = air[1]
		for index in points.size():
			_add_to_cube(cubes, points[index], volumes[index])
	var out_points := PackedVector3Array()
	var out_volumes := PackedFloat32Array()
	var reach := 0.0
	for key in cubes:
		var cube: Array = cubes[key]
		var volume: float = cube[0]
		if volume <= 0.0:
			continue
		var point: Vector3 = cube[1] / volume
		out_points.append(point)
		out_volumes.append(volume)
		reach = maxf(reach, point.length())
	_floats[body] = [out_points, out_volumes, reach + FLOAT_CELL]


static func _add_to_cube(cubes: Dictionary, point: Vector3, volume: float) -> void:
	var key := Vector3i((point / FLOAT_CELL).floor())
	if not cubes.has(key):
		cubes[key] = [0.0, Vector3.ZERO]
	var cube: Array = cubes[key]
	cube[0] = float(cube[0]) + volume
	cube[1] = (cube[1] as Vector3) + point * volume


## Finds the air sealed inside each body: the empty grid cells inside it that
## cannot be reached from outside without passing through a part. A boat
## with a closed hull floats on that air, as a real one does.
@warning_ignore("integer_division")
func _find_air() -> void:
	var cell := Units.CELL
	var to_grid := _grid_frame.affine_inverse()
	for item in _bodies:
		var body: RigidBody3D = item
		if body.freeze:
			continue
		var pieces: Array = _body_pieces.get(body, [])
		if pieces.is_empty():
			continue
		var bounds := AABB()
		var first := true
		for piece in pieces:
			var box: AABB = _boxes[piece]
			bounds = box if first else bounds.merge(box)
			first = false
		# One empty cell of margin all round, where the flood starts.
		var low := Vector3i((bounds.position / cell).floor()) - Vector3i.ONE
		var high := Vector3i((bounds.end / cell).ceil()) + Vector3i.ONE
		var span := high - low
		var total := span.x * span.y * span.z
		if total <= 0 or total > MAX_AIR_CELLS:
			continue
		var solid := PackedByteArray()
		solid.resize(total)
		for piece in pieces:
			var box: AABB = _boxes[piece]
			var from := Vector3i((box.position / cell + Vector3(0.001, 0.001, 0.001)).floor()) - low
			var to := Vector3i((box.end / cell - Vector3(0.001, 0.001, 0.001)).ceil()) - low
			for x in range(maxi(from.x, 0), mini(to.x, span.x)):
				for y in range(maxi(from.y, 0), mini(to.y, span.y)):
					var row := (x * span.y + y) * span.z
					for z in range(maxi(from.z, 0), mini(to.z, span.z)):
						solid[row + z] = 1
		# Flood the outside: 2 marks a cell the outside water could reach.
		var stack := PackedInt32Array([0])
		solid[0] = 2
		var step_x := span.y * span.z
		var step_y := span.z
		while not stack.is_empty():
			var at: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			@warning_ignore("integer_division")
			var x := at / step_x
			@warning_ignore("integer_division")
			var y := (at % step_x) / step_y
			var z := at % step_y
			if x > 0 and solid[at - step_x] == 0:
				solid[at - step_x] = 2
				stack.append(at - step_x)
			if x < span.x - 1 and solid[at + step_x] == 0:
				solid[at + step_x] = 2
				stack.append(at + step_x)
			if y > 0 and solid[at - step_y] == 0:
				solid[at - step_y] = 2
				stack.append(at - step_y)
			if y < span.y - 1 and solid[at + step_y] == 0:
				solid[at + step_y] = 2
				stack.append(at + step_y)
			if z > 0 and solid[at - 1] == 0:
				solid[at - 1] = 2
				stack.append(at - 1)
			if z < span.z - 1 and solid[at + 1] == 0:
				solid[at + 1] = 2
				stack.append(at + 1)
		# What is left at 0 is sealed air. Gather it into cubes inside the body.
		var origin_in_grid: Vector3 = to_grid * body.global_position
		var cubes: Dictionary = {}
		var cell_volume := cell * cell * cell
		for index in total:
			if solid[index] != 0:
				continue
			@warning_ignore("integer_division")
			var x := index / step_x
			@warning_ignore("integer_division")
			var y := (index % step_x) / step_y
			var z := index % step_y
			var middle := (Vector3(low + Vector3i(x, y, z)) + Vector3(0.5, 0.5, 0.5)) * cell
			_add_to_cube(cubes, middle - origin_in_grid, cell_volume)
		if cubes.is_empty():
			continue
		var points := PackedVector3Array()
		var volumes := PackedFloat32Array()
		for key in cubes:
			var cube: Array = cubes[key]
			points.append((cube[1] as Vector3) / float(cube[0]))
			volumes.append(float(cube[0]))
		_air[body] = [points, volumes]
		_rebuild_floats(body)


## Water holds up whatever is in it with the weight of the water it pushes
## aside (Archimedes), and drags on whatever moves through it. Each float is
## treated as a cube; the share of it below the surface is what counts.
func _run_buoyancy(delta: float) -> void:
	if terrain == null:
		return
	var surface := MapInfo.LAKE_Y
	var gone: Array = []
	for key in _floats:
		# A body freed by a blast is still a key here until it is dropped.
		if not is_instance_valid(key):
			gone.append(key)
			continue
		var body: RigidBody3D = key
		if body.freeze:
			continue
		var data: Array = _floats[body]
		var reach: float = data[2]
		var place := body.global_transform
		if place.origin.y - reach > surface:
			continue   # well clear of the water
		if not terrain.lake_at(place.origin):
			continue
		var points: PackedVector3Array = data[0]
		var volumes: PackedFloat32Array = data[1]
		var centre := place * body.center_of_mass
		var count := points.size()
		var drag_cap := body.mass / maxf(float(count), 1.0) / delta * 0.5
		for index in count:
			var at: Vector3 = place * points[index]
			var depth := surface - at.y
			var volume: float = volumes[index]
			var height := clampf(pow(volume, 1.0 / 3.0), 0.1, FLOAT_CELL)
			var under := clampf(depth / height + 0.5, 0.0, 1.0)
			if under <= 0.0:
				continue
			var force := Vector3(0.0, WATER_DENSITY * 9.81 * volume * under, 0.0)
			var moving: Vector3 = body.linear_velocity + body.angular_velocity.cross(at - centre)
			var speed := moving.length()
			if speed > 0.0001:
				var area := pow(volume, 2.0 / 3.0)
				var drag := 0.5 * WATER_DENSITY * WATER_DRAG * area * speed * under
				drag = minf(drag, drag_cap)   # never more than stops it in one step
				force -= moving * drag
			body.apply_force(force, at - place.origin)
	for key in gone:
		_floats.erase(key)
		_air.erase(key)


## A thruster pushes its body along the thruster's own -Z, at the thruster.
## With nothing linked it runs flat out. A link to "On" switches it, and a
## link to "Throttle" scales it from -1 to 1.
func _run_thrusters() -> void:
	var alive: Array = []
	for thruster in _thrusters:
		var body: RigidBody3D = _piece_body(thruster[0])
		if body == null:
			continue   # destroyed
		alive.append(thruster)
		var place: Transform3D = thruster[1]
		var thrust: float = thruster[2]
		var links: Dictionary = thruster[3]
		var flame: MeshInstance3D = thruster[4]
		var on: bool = _input_value(links, "on", 1.0) != 0.0
		var throttle: float = clampf(_input_value(links, "throttle", 1.0), -1.0, 1.0)
		var push: float = thrust * throttle if on else 0.0
		if push != 0.0 and engines != null:
			# One that does not run without fuel takes it from its tanks.
			push *= engines.thruster_fuel(_uid_of(thruster[0]), absf(push), get_physics_process_delta_time())
		_outputs[_uid_of(thruster[0])] = {"thrust": push}
		flame.visible = push != 0.0
		if push == 0.0 or body.freeze:
			continue
		var frame: Basis = body.global_transform.basis
		body.sleeping = false
		body.apply_force(frame * (place.basis * Vector3(0.0, 0.0, -push)), frame * place.origin)
	_thrusters = alive


## The glow behind a running thruster: a see-through cone trailing along +Z.
func _new_flame(place: Transform3D, size_m: Vector3) -> MeshInstance3D:
	if _flame_mesh == null:
		var cone := CylinderMesh.new()
		cone.height = 1.0
		cone.bottom_radius = 0.5
		cone.top_radius = 0.04
		cone.radial_segments = 16
		cone.rings = 1
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(1.0, 0.62, 0.15, 0.7)
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cone.material = glow
		_flame_mesh = cone
	var flame := MeshInstance3D.new()
	flame.mesh = _flame_mesh
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var width: float = 0.6 * minf(size_m.x, size_m.y)
	var length: float = 1.5 * size_m.z
	# The cone is built along Y with its wide end down. Stretch it, then lay
	# it along +Z with the wide end at the nozzle.
	var lay_back := Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(width, length, width))
	flame.transform = place * Transform3D(lay_back, Vector3(0.0, 0.0, size_m.z * 0.5 + length * 0.5))
	flame.visible = false
	return flame


## Lift and drag on every aero panel. Each panel takes the air's speed at its
## own centre, including the spin of the body it is on. See aero.gd.
func _run_aero(delta: float) -> void:
	var alive: Array = []
	for panel in _panels:
		var body: RigidBody3D = _piece_body(panel[0])
		if body == null:
			continue   # destroyed
		alive.append(panel)
		if body.freeze or body.sleeping:
			continue
		var frame: Transform3D = body.global_transform
		var centre: Vector3 = panel[1]
		var flat: Vector3 = panel[2]
		var area: float = panel[3]
		var dragless: bool = panel[4]
		var arm: Vector3 = frame.basis * centre
		var moving: Vector3 = velocity_at(body, arm)
		var density: float = Aero.air_density(frame.origin.y + arm.y)
		var force: Vector3 = Aero.panel_force(moving, frame.basis * flat, area, dragless, density)
		# A tiny, light body in a fast airflow could be thrown about by one
		# tick's force. Never push harder than would stop it dead in two ticks.
		force = force.limit_length(0.5 * body.mass * moving.length() / delta)
		body.apply_force(force, arm)
	_panels = alive
