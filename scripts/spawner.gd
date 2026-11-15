extends Node3D
## Spawn: turns the build into moving bodies.
##
## Parts that touch face to face, or overlap, are welded into one rigid body
## with their combined mass and centre of mass. Gravity and collisions then
## act on it. This is the basic version: apart from the hinge, no part does
## anything yet, so every other joint, motor and engine is welded solid.
##
## A hinge is the one working joint. It splits into two halves, base and top,
## at its middle. Each half welds to what touches it, and the two halves are
## joined so that they turn about the hinge's pin.
##
## Two more special cases already follow the design. A dynamic offsetter is
## invisible and untouchable once spawned, but still welds. A body that
## contains an anchor block is fixed to the world.

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")

const TOUCH := 0.0004   # metres; faces this close together count as touching
const BUCKET := 1.0     # metres; size of the sorting boxes used to find neighbours

var spawned := false

var _bodies: Array = []        # every RigidBody3D made by the last spawn
var _joints: Array = []        # every joint made by the last spawn
var _seats: Dictionary = {}    # seat uid -> [its body, its transform inside that body, its size in metres]
var _piece_bodies: Dictionary = {}   # piece -> the body it ended up in


# Welding works on "pieces". Most parts are one piece. A hinge is two: its
# base half and its top half. A piece is numbered from its part's uid:
# uid * 2 for a whole part or a hinge's base, uid * 2 + 1 for a hinge's top.

static func is_hinge(record: Dictionary) -> bool:
	return record["type"] == "hinge"


## Builds the bodies from everything on the grid. Returns a short report:
## {"parts", "bodies", "mass" (kg), "hinges" (working), "locked" (hinges whose
## two sides ended up welded to the same body, so they cannot turn)}.
func spawn(grid: Node3D) -> Dictionary:
	despawn()
	var records: Dictionary = {}
	for uid in grid.all_uids():
		records[uid] = grid.get_part(uid)
	var grid_frame: Transform3D = grid.global_transform
	var shapes: Dictionary = {}   # collision shapes, shared between identical parts
	var total_mass := 0.0
	for group in weld_groups(records):
		var pieces: Array = group
		total_mass += _make_body(grid_frame, pieces, records, shapes)

	var hinges := 0
	var locked := 0
	for uid in records:
		var part_uid: int = uid
		var record: Dictionary = records[part_uid]
		if not is_hinge(record):
			continue
		var base_body: RigidBody3D = _piece_bodies.get(part_uid * 2)
		var top_body: RigidBody3D = _piece_bodies.get(part_uid * 2 + 1)
		if base_body == null or top_body == null:
			continue
		if base_body == top_body:
			locked += 1
			continue
		_make_hinge(grid_frame, record, base_body, top_body)
		hinges += 1

	_piece_bodies.clear()
	spawned = true
	return {
		"parts": records.size(), "bodies": _bodies.size(), "mass": total_mass,
		"hinges": hinges, "locked": locked,
	}


## Removes every spawned body and joint.
func despawn() -> void:
	for joint in _joints:
		(joint as Node).queue_free()
	for body in _bodies:
		(body as Node).queue_free()
	_joints.clear()
	_bodies.clear()
	_seats.clear()
	_piece_bodies.clear()
	spawned = false


## Where a spawned seat is now: [its transform in the world, its size in
## metres]. Empty if there is no such seat.
func seat_frame(uid: int) -> Array:
	if not _seats.has(uid):
		return []
	var seat: Array = _seats[uid]
	var body: RigidBody3D = seat[0]
	var place: Transform3D = seat[1]
	return [body.global_transform * place, seat[2]]


## The spawned seat nearest to a point in the world and within `reach`
## metres of it. Returns its uid, or 0 for none.
func nearest_seat(world_point: Vector3, reach: float) -> int:
	var best := 0
	var best_distance := reach
	for uid in _seats:
		var seat: Array = _seats[uid]
		var body: RigidBody3D = seat[0]
		var place: Transform3D = seat[1]
		var distance: float = (body.global_transform * place.origin).distance_to(world_point)
		if distance < best_distance:
			best = uid
			best_distance = distance
	return best


# --- Pieces ------------------------------------------------------------------

## The middle of one half of a hinge, in the grid's space, in metres.
## The halves are split across the hinge's own Y axis; the top half is at +Y.
static func _half_centre(record: Dictionary, top: bool) -> Vector3:
	var rot: Basis = record["rot"]
	var size_units: Vector3i = record["size"]
	var size_m: Vector3 = Units.to_metres(size_units)
	var lift: float = size_m.y * (0.25 if top else -0.25)
	return Vector3(record["pos"] as Vector3i) * Units.UNIT + rot * Vector3(0.0, lift, 0.0)


## The size of one half of a hinge along the hinge's own axes, in metres.
static func _half_size(record: Dictionary) -> Vector3:
	var size_units: Vector3i = record["size"]
	var size_m: Vector3 = Units.to_metres(size_units)
	return Vector3(size_m.x, size_m.y * 0.5, size_m.z)


## The bounding box of a piece, in the grid's space.
static func _piece_box(piece: int, record: Dictionary) -> AABB:
	if not is_hinge(record):
		return BuildGrid.bounds_of(record)
	var rot: Basis = record["rot"]
	var half: Vector3 = _half_size(record) * 0.5
	var reach: Vector3 = (rot.x * half.x).abs() + (rot.y * half.y).abs() + (rot.z * half.z).abs()
	var centre: Vector3 = _half_centre(record, (piece & 1) == 1)
	return AABB(centre - reach, reach * 2.0)


## The mass of a piece in kilograms. A hinge's mass is shared by its halves.
static func _piece_mass(record: Dictionary) -> float:
	if is_hinge(record):
		return BuildGrid.mass_of(record) * 0.5
	return BuildGrid.mass_of(record)


## A piece's centre of mass, in the grid's space.
static func _piece_centre(piece: int, record: Dictionary) -> Vector3:
	if is_hinge(record):
		return _half_centre(record, (piece & 1) == 1)
	return BuildGrid.centroid_of(record)


# --- Welding -----------------------------------------------------------------

## Sorts pieces into weld groups. Two pieces weld when their bounding boxes
## share a face, or part of one, or overlap. Meeting only along an edge or at
## a corner is not a weld. Returns an array of arrays of piece numbers.
static func weld_groups(records: Dictionary) -> Array:
	var parent: Dictionary = {}    # piece -> another piece in the same group
	var boxes: Dictionary = {}     # piece -> bounding box
	var buckets: Dictionary = {}   # sorting box -> the pieces that reach into it
	for uid in records:
		var part_uid: int = uid
		var record: Dictionary = records[part_uid]
		_add_piece(part_uid * 2, record, parent, boxes, buckets)
		if is_hinge(record):
			_add_piece(part_uid * 2 + 1, record, parent, boxes, buckets)

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
static func _add_piece(piece: int, record: Dictionary, parent: Dictionary,
		boxes: Dictionary, buckets: Dictionary) -> void:
	parent[piece] = piece
	var box: AABB = _piece_box(piece, record)
	boxes[piece] = box
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
	if (a >> 1) == (b >> 1):
		return false   # the two halves of one hinge: joined by its pin, never welded
	var box_a: AABB = boxes[a]
	var box_b: AABB = boxes[b]
	if not _touching(box_a, box_b):
		return false
	# Something that touches both halves of a hinge, such as a block standing
	# beside it, welds to the base half only. Otherwise one neighbour would
	# lock the hinge solid.
	if (a & 1) == 1:
		var base_of_a: AABB = boxes[a - 1]
		if _touching(box_b, base_of_a):
			return false
	if (b & 1) == 1:
		var base_of_b: AABB = boxes[b - 1]
		if _touching(box_a, base_of_b):
			return false
	return true


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


# --- Bodies ------------------------------------------------------------------

## Makes one rigid body from a weld group. Returns its mass in kilograms.
func _make_body(grid_frame: Transform3D, pieces: Array, records: Dictionary, shapes: Dictionary) -> float:
	var mass := 0.0
	var moment := Vector3.ZERO   # sum of mass x position, for the centre of mass
	var grip := 0.0              # sum of mass x friction
	var anchored := false
	for piece in pieces:
		var piece_id: int = piece
		var record: Dictionary = records[piece_id >> 1]
		var piece_mass: float = _piece_mass(record)
		var material: String = record["material"]
		mass += piece_mass
		moment += _piece_centre(piece_id, record) * piece_mass
		grip += float(MaterialLibrary.info(material)["friction"]) * piece_mass
		if record["type"] == "anchor_block":
			anchored = true
	if mass <= 0.0:
		return 0.0
	var centre: Vector3 = moment / mass

	var body := RigidBody3D.new()
	body.mass = maxf(mass, 0.001)
	# The body's origin is put at the centre of mass.
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.ZERO
	var surface := PhysicsMaterial.new()
	surface.friction = grip / mass   # the mass-weighted average of its materials
	surface.bounce = 0.0
	body.physics_material_override = surface
	# An ideal world: nothing slows a body except contact (and, later, drag).
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	if anchored:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	body.transform = grid_frame * Transform3D(Basis.IDENTITY, centre)

	var solid := false
	for piece in pieces:
		var piece_id: int = piece
		var part_uid: int = piece_id >> 1
		var record: Dictionary = records[part_uid]
		var type: String = record["type"]
		var rot: Basis = record["rot"]
		var size_units: Vector3i = record["size"]
		var size_m: Vector3 = Units.to_metres(size_units)
		var material: String = record["material"]
		var color: Color = record["color"]
		# Where the whole part sits inside the body.
		var place := Transform3D(rot, Vector3(record["pos"] as Vector3i) * Units.UNIT - centre)
		if type == "seat":
			_seats[part_uid] = [body, place, size_m]
		if type == "dynamic_offsetter":
			continue   # it only welds; it has no look and no collision once spawned

		var mesh: Mesh
		var shape_key: String
		var shape_place := place
		if is_hinge(record):
			# Only this piece's half of the hinge: its leaf, and a box for it.
			var top: bool = (piece_id & 1) == 1
			mesh = PartLibrary.get_mesh(type, {"half": "top" if top else "base"})
			shape_key = "hinge half" + str(size_units)
			if not shapes.has(shape_key):
				var half_box := BoxShape3D.new()
				half_box.size = _half_size(record)
				shapes[shape_key] = half_box
			shape_place = Transform3D(rot, _half_centre(record, top) - centre)
		else:
			mesh = PartLibrary.mesh_for_record(record)
			shape_key = type + str(size_units)
			if not shapes.has(shape_key):
				shapes[shape_key] = PartLibrary.make_shape(type, size_m, true)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.transform = Transform3D(
				Basis(rot.x * size_m.x, rot.y * size_m.y, rot.z * size_m.z), place.origin)
		mesh_instance.set_surface_override_material(0, MaterialLibrary.surface(material, color))
		body.add_child(mesh_instance)

		var collider := CollisionShape3D.new()
		collider.shape = shapes[shape_key]
		collider.transform = shape_place
		body.add_child(collider)
		solid = true

	if not solid:
		body.free()   # nothing to see or touch, so nothing to simulate
		return 0.0
	body.name = "Body%d" % _bodies.size()
	add_child(body)
	_bodies.append(body)
	for piece in pieces:
		_piece_bodies[piece] = body
	return mass


# --- Joints ------------------------------------------------------------------

## Joins the two sides of a hinge so that they turn about its pin.
##
## The pin runs along the hinge's own X axis through its middle. The angle is
## zero as built, and the hinge's settings give its limits and its friction.
## The two bodies a hinge joins do not collide with each other, so that a
## hinge can swing without its own leaves or its neighbours jamming it; use
## the angle limits to stop it where it should stop.
func _make_hinge(grid_frame: Transform3D, record: Dictionary,
		base_body: RigidBody3D, top_body: RigidBody3D) -> void:
	var rot: Basis = record["rot"]
	var props: Dictionary = record.get("props", {})
	var joint := HingeJoint3D.new()
	# A hinge joint turns about its own Z axis, so its Z is laid along the pin.
	var pin_frame := Basis(rot.y, rot.z, rot.x)
	joint.transform = grid_frame * Transform3D(pin_frame, Vector3(record["pos"] as Vector3i) * Units.UNIT)

	if bool(props.get("limited", false)):
		var lowest: float = deg_to_rad(float(props.get("min_angle", -90.0)))
		var highest: float = deg_to_rad(float(props.get("max_angle", 90.0)))
		if lowest <= highest:
			joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, lowest)
			joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, highest)

	# Friction torque: a motor that aims for no turning, with only the
	# friction torque to do it with. Torque x time step is its impulse limit.
	var friction: float = float(props.get("friction", 0.0))
	if friction > 0.0:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,
				friction / float(Engine.physics_ticks_per_second))

	# The joint and the bodies are all children of this node.
	joint.node_a = NodePath("../" + str(base_body.name))
	joint.node_b = NodePath("../" + str(top_body.name))
	add_child(joint)
	_joints.append(joint)
