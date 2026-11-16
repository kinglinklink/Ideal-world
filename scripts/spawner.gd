extends Node3D
## Spawn: turns the build into moving bodies.
##
## Parts that touch face to face, or overlap, are welded into one rigid body
## with their combined mass and centre of mass. Gravity and collisions then
## act on it. This is the basic version: apart from the hinge, no part does
## anything yet, so every other joint, motor and engine is welded solid.
##
## Hinges, motors and servos are the working joints. Each splits into a base
## and a top. Each side welds to what touches it, and the two are joined so
## that the top turns on the base: freely for a hinge, driven for the others.
##
## Thrusters push, and aero panels make lift and drag from the air moving
## over them. Input blocks read their keys while the character is seated, and
## a thruster follows whatever is linked to its inputs.
##
## More special cases follow the design. A dynamic offsetter is invisible and
## untouchable once spawned, but still welds. A body that contains an anchor
## block, or any part made of the frictionless surface material, is fixed to
## the world.

const Units = preload("res://scripts/units.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Aero = preload("res://scripts/aero.gd")

const TOUCH := 0.0004   # metres; faces this close together count as touching
const BUCKET := 1.0     # metres; size of the sorting boxes used to find neighbours

var spawned := false
var occupied_seat := 0         # uid of the seat the character is sitting in; set by the build controller

var _bodies: Array = []        # every RigidBody3D made by the last spawn
var _joints: Array = []        # every joint made by the last spawn
var _seats: Dictionary = {}    # seat uid -> [its body, its transform inside that body, its size in metres]
var _piece_bodies: Dictionary = {}   # piece -> the body it ended up in
var _records: Dictionary = {}  # uid -> part record, as spawned; signal links are looked up here
var _thrusters: Array = []     # [body, transform inside it, thrust in newtons, links, flame]
var _panels: Array = []        # aero panels: [body, centre inside it, normal inside it, area in m^2, dragless]
var _inputs: Dictionary = {}   # input block uid -> its keys and what it is putting out
var _drives: Array = []        # motors and servos; see _make_joint for what each holds
var _outputs: Dictionary = {}  # drive uid -> the number on its output: RPM for a motor, degrees for a servo
var _flame_mesh: Mesh = null
# The physics engine's hinge motor may count a positive speed as clockwise or
# as counterclockwise. The first time a drive moves, its answer is compared
# with what was asked, and the sign is settled for good.
var _motor_sign := -1.0
var _motor_sign_known := false
var _motor_sign_votes := 0


# Welding works on "pieces". Most parts are one piece. A jointed part is two:
# a base and a top that turns on it. A piece is numbered from its part's uid:
# uid * 2 for a whole part or a joint's base, uid * 2 + 1 for a joint's top.

## The parts that split in two when spawned. Places and sizes are fractions
## of the part's own size, along the part's own axes.
##   axis   the axis the top turns about: 0 = X, 1 = Y, 2 = Z
##   pivot  a point on that axis
##   base, top   [middle, size] of the box each side fills
##   trim   scales the top's collision box, so a square top has room to turn
const JOINTED := {
	# Two leaves on a pin.
	"hinge": {"axis": 0, "pivot": Vector3(0, 0, 0), "trim": Vector3(1, 1, 1),
		"base": [Vector3(0, -0.25, 0), Vector3(1, 0.5, 1)],
		"top": [Vector3(0, 0.25, 0), Vector3(1, 0.5, 1)]},
	# A housing, with the output on the top face turning about the shaft.
	"motor": {"axis": 1, "pivot": Vector3(0, 0, 0), "trim": Vector3(0.7, 1, 0.7),
		"base": [Vector3(0, -0.125, 0), Vector3(1, 0.75, 1)],
		"top": [Vector3(0, 0.375, 0), Vector3(1, 0.25, 1)]},
	"servo": {"axis": 1, "pivot": Vector3(0, 0, 0), "trim": Vector3(0.7, 1, 0.7),
		"base": [Vector3(0, -0.125, 0), Vector3(1, 0.75, 1)],
		"top": [Vector3(0, 0.375, 0), Vector3(1, 0.25, 1)]},
	# A plate on the bottom and a leaf standing at the back (-Z), hinged
	# along the edge they share.
	"door_hinge_servo": {"axis": 0, "pivot": Vector3(0, -0.3125, -0.3125), "trim": Vector3(1, 1, 1),
		"base": [Vector3(0, -0.4375, 0), Vector3(1, 0.125, 1)],
		"top": [Vector3(0, 0.0625, -0.4375), Vector3(1, 0.875, 0.125)]},
}

## The jointed parts that are driven, and how.
const DRIVES := {"motor": "motor", "servo": "servo", "door_hinge_servo": "servo"}

const SERVO_GAIN := 0.2         # share of a servo's angle error it sets out to close each tick


static func is_jointed(record: Dictionary) -> bool:
	return JOINTED.has(record["type"])


## Builds the bodies from everything on the grid. Returns a short report:
## {"parts", "bodies", "mass" (kg), "hinges" (working), "locked" (hinges whose
## two sides ended up welded to the same body, so they cannot turn)}.
func spawn(grid: Node3D) -> Dictionary:
	despawn()
	var records: Dictionary = {}
	for uid in grid.all_uids():
		records[uid] = grid.get_part(uid)
	_records = records
	var grid_frame: Transform3D = grid.global_transform
	var shapes: Dictionary = {}   # collision shapes, shared between identical parts
	var total_mass := 0.0
	for group in weld_groups(records):
		var pieces: Array = group
		# An anchor block or a frictionless part fixes everything welded to it.
		var fixed := false
		var slick: Array = []   # the frictionless pieces
		var rough: Array = []   # everything else
		for piece in pieces:
			var piece_id: int = piece
			var record: Dictionary = records[piece_id >> 1]
			var material: String = record["material"]
			if MaterialLibrary.is_immovable(material):
				fixed = true
				slick.append(piece_id)
			else:
				rough.append(piece_id)
			if record["type"] == "anchor_block":
				fixed = true
		# The engine gives one friction value to a whole body, so frictionless
		# parts get a body of their own. Both bodies are fixed, so nothing
		# needs to hold them together.
		if not slick.is_empty():
			total_mass += _make_body(grid_frame, slick, records, shapes, true)
		if not rough.is_empty():
			total_mass += _make_body(grid_frame, rough, records, shapes, fixed)

	for uid in records:
		var input_uid: int = uid
		var input_record: Dictionary = records[input_uid]
		if input_record["type"] == "input_block":
			_inputs[input_uid] = _new_input_state(input_record.get("props", {}))

	var hinges := 0   # joints of every kind that are free to turn
	var locked := 0
	for uid in records:
		var part_uid: int = uid
		var record: Dictionary = records[part_uid]
		if not is_jointed(record):
			continue
		var base_body: RigidBody3D = _piece_bodies.get(part_uid * 2)
		var top_body: RigidBody3D = _piece_bodies.get(part_uid * 2 + 1)
		if base_body == null or top_body == null:
			continue
		if base_body == top_body:
			locked += 1
			continue
		_make_joint(grid_frame, part_uid, record, base_body, top_body)
		hinges += 1

	_piece_bodies.clear()
	spawned = true
	return {
		"parts": records.size(), "bodies": _bodies.size(), "mass": total_mass,
		"hinges": hinges, "locked": locked,
		"thrusters": _thrusters.size(), "panels": _panels.size(),
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
	_records = {}
	_thrusters.clear()
	_panels.clear()
	_inputs.clear()
	_drives.clear()
	_outputs.clear()
	occupied_seat = 0
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


## How fast a spawned seat is moving, in metres per second.
func seat_velocity(uid: int) -> Vector3:
	if not _seats.has(uid):
		return Vector3.ZERO
	var seat: Array = _seats[uid]
	var body: RigidBody3D = seat[0]
	var place: Transform3D = seat[1]
	return body.linear_velocity + body.angular_velocity.cross(body.global_transform.basis * place.origin)


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

## The [middle, size] of a jointed part's base or top, as fractions of the part.
static func _piece_fractions(piece: int, record: Dictionary) -> Array:
	var joint: Dictionary = JOINTED[record["type"]]
	return joint["top"] if (piece & 1) == 1 else joint["base"]


## The middle of one side of a jointed part, in the grid's space, in metres.
static func _piece_middle(piece: int, record: Dictionary) -> Vector3:
	var rot: Basis = record["rot"]
	var size_units: Vector3i = record["size"]
	var middle: Vector3 = _piece_fractions(piece, record)[0]
	return Vector3(record["pos"] as Vector3i) * Units.UNIT + rot * (middle * Units.to_metres(size_units))


## The size of one side of a jointed part along the part's own axes, in metres.
static func _piece_size(piece: int, record: Dictionary) -> Vector3:
	var size_units: Vector3i = record["size"]
	var share: Vector3 = _piece_fractions(piece, record)[1]
	return share * Units.to_metres(size_units)


## The bounding box of a piece, in the grid's space.
static func _piece_box(piece: int, record: Dictionary) -> AABB:
	if not is_jointed(record):
		return BuildGrid.bounds_of(record)
	var rot: Basis = record["rot"]
	var half: Vector3 = _piece_size(piece, record) * 0.5
	var reach: Vector3 = (rot.x * half.x).abs() + (rot.y * half.y).abs() + (rot.z * half.z).abs()
	var centre: Vector3 = _piece_middle(piece, record)
	return AABB(centre - reach, reach * 2.0)


## The mass of a piece in kilograms. A jointed part's mass is shared by its two sides.
static func _piece_mass(record: Dictionary) -> float:
	if is_jointed(record):
		return BuildGrid.mass_of(record) * 0.5
	return BuildGrid.mass_of(record)


## A piece's centre of mass, in the grid's space.
static func _piece_centre(piece: int, record: Dictionary) -> Vector3:
	if is_jointed(record):
		return _piece_middle(piece, record)
	return BuildGrid.centroid_of(record)


# --- Welding -----------------------------------------------------------------

## Sorts pieces into weld groups. Two pieces weld when their bounding boxes
## share a face, or part of one, or overlap. Meeting only along an edge or at
## a corner is not a weld. Returns an array of arrays of piece numbers.
static func weld_groups(records: Dictionary) -> Array:
	var parent: Dictionary = {}    # piece -> another piece in the same group
	var boxes: Dictionary = {}     # piece -> bounding box
	var buckets: Dictionary = {}   # sorting box -> the pieces that reach into it
	# Every box first, because welding to one side of a joint has to look at the other side too.
	for uid in records:
		var part_uid: int = uid
		var record: Dictionary = records[part_uid]
		boxes[part_uid * 2] = _piece_box(part_uid * 2, record)
		if is_jointed(record):
			boxes[part_uid * 2 + 1] = _piece_box(part_uid * 2 + 1, record)
	for piece in boxes:
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
	if (a >> 1) == (b >> 1):
		return false   # the two sides of one joint: joined by its pin, never welded
	var box_a: AABB = boxes[a]
	var box_b: AABB = boxes[b]
	if not _touching(box_a, box_b):
		return false
	return _chooses(a, b, boxes) and _chooses(b, a, boxes)


## Something that touches both sides of a joint welds to only one of them,
## or it would lock the joint solid. It takes the side it shares more area
## with, and the base if they are even. This answers whether `other` welds to
## `piece` rather than to the other side of `piece`'s joint.
static func _chooses(other: int, piece: int, boxes: Dictionary) -> bool:
	var sibling: int = piece ^ 1
	if not boxes.has(sibling):
		return true   # not a jointed part
	var other_box: AABB = boxes[other]
	var sibling_box: AABB = boxes[sibling]
	if not _touching(other_box, sibling_box):
		return true
	var piece_box: AABB = boxes[piece]
	var with_piece: float = _contact(other_box, piece_box)
	var with_sibling: float = _contact(other_box, sibling_box)
	var even: bool = absf(with_piece - with_sibling) <= 0.02 * maxf(with_piece, with_sibling)
	if (piece & 1) == 0:
		return even or with_piece > with_sibling   # the base wins a tie
	return not even and with_piece > with_sibling


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


# --- Bodies ------------------------------------------------------------------

## Makes one rigid body from a set of welded pieces. `fixed` makes it
## immovable. Returns its mass in kilograms.
func _make_body(grid_frame: Transform3D, pieces: Array, records: Dictionary, shapes: Dictionary,
		fixed: bool) -> float:
	var mass := 0.0
	var moment := Vector3.ZERO   # sum of mass x position, for the centre of mass
	var grip := 0.0              # sum of mass x friction
	for piece in pieces:
		var piece_id: int = piece
		var record: Dictionary = records[piece_id >> 1]
		var piece_mass: float = _piece_mass(record)
		var material: String = record["material"]
		mass += piece_mass
		moment += _piece_centre(piece_id, record) * piece_mass
		grip += float(MaterialLibrary.info(material)["friction"]) * piece_mass
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
	if fixed:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	# Bodies meet the world and each other. They do not look for the
	# character: see the note on layers in units.gd.
	body.collision_layer = Units.LAYER_BODIES
	body.collision_mask = Units.LAYER_WORLD | Units.LAYER_BODIES
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
		if is_jointed(record):
			# Only this piece's side of the joint: its model, and a box for it.
			var top: bool = (piece_id & 1) == 1
			var side: String = "top" if top else "base"
			mesh = PartLibrary.get_mesh(type, {"half": side})
			shape_key = "%s %s %s" % [type, side, size_units]
			if not shapes.has(shape_key):
				var side_box := BoxShape3D.new()
				side_box.size = _piece_size(piece_id, record)
				if top:
					var trim: Vector3 = JOINTED[type]["trim"]
					side_box.size *= trim
				shapes[shape_key] = side_box
			shape_place = Transform3D(rot, _piece_middle(piece_id, record) - centre)
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

		if type == "thruster":
			var props: Dictionary = record.get("props", {})
			var flame := _new_flame(place, size_m)
			body.add_child(flame)
			_thrusters.append([body, place, float(props.get("thrust", 1000.0)), record.get("links", {}), flame])
		elif PartLibrary.is_aero_panel(type):
			var area: float = size_m.x * size_m.z
			if PartLibrary.is_triangle_panel(type):
				area *= 0.5
			# The air acts at the middle of the panel's area. Its flat faces
			# look along its own Y axis.
			_panels.append([body, BuildGrid.centroid_of(record) - centre, rot.y, area,
					PartLibrary.is_dragless(type)])

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

## Joins the two sides of a jointed part so that the top turns on the base.
##
## The angle is zero as built. A plain hinge takes its limits and friction
## from its settings. A motor or servo is left free here and driven every
## tick by _run_drives. The two bodies a joint connects do not collide with
## each other, so that it can turn without its own halves or its neighbours
## jamming it.
func _make_joint(grid_frame: Transform3D, uid: int, record: Dictionary,
		base_body: RigidBody3D, top_body: RigidBody3D) -> void:
	var type: String = record["type"]
	var rot: Basis = record["rot"]
	var props: Dictionary = record.get("props", {})
	var size_units: Vector3i = record["size"]
	var joint_data: Dictionary = JOINTED[type]
	var axis_index: int = joint_data["axis"]
	var pivot_share: Vector3 = joint_data["pivot"]
	var pivot: Vector3 = Vector3(record["pos"] as Vector3i) * Units.UNIT \
			+ rot * (pivot_share * Units.to_metres(size_units))
	var axis: Vector3 = rot[axis_index]
	var across: Vector3 = rot[(axis_index + 1) % 3]

	var joint := HingeJoint3D.new()
	# A hinge joint turns about its own Z axis, so its Z is laid along the pin.
	var pin_frame := Basis(across, rot[(axis_index + 2) % 3], axis)
	joint.transform = grid_frame * Transform3D(pin_frame, pivot)

	if type == "hinge":
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

	if DRIVES.has(type):
		# A motor or servo uses the joint's own motor: each tick it is told
		# the turning speed wanted, and the engine holds that speed as part of
		# solving the joint, with at most the drive's max torque. Solved that
		# way a drive is as stiff as a real one, however light or heavy the
		# things it turns. Torque x time step is the motor's impulse limit.
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
		joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,
				float(props.get("max_torque", 100.0)) / float(Engine.physics_ticks_per_second))
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)

	# The joint and the bodies are all children of this node.
	joint.node_a = NodePath("../" + str(base_body.name))
	joint.node_b = NodePath("../" + str(top_body.name))
	add_child(joint)
	_joints.append(joint)

	if DRIVES.has(type):
		# Both bodies start out square to the grid, so directions in the
		# grid's space are also directions inside each body.
		_drives.append({
			"uid": uid, "kind": DRIVES[type], "base": base_body, "top": top_body, "joint": joint,
			"axis": axis,                # the axis, inside the base body
			"from": across, "to": across,   # one direction square to the axis, inside the base and inside the top
			"motor_on": true, "asked": 0.0,   # the joint motor's state and the speed last asked of it
			"props": props, "links": record.get("links", {}),
			"last": 0.0, "turned": 0.0,     # the angle now, wrapped and counted through whole turns
			"rate": 0.0,                    # the speed being asked for, in rad/s
			"setpoint": 0.0, "hold": 0.0,   # servo: where it should be now, and where it holds when idle
		})


# --- Drives ------------------------------------------------------------------

## Runs every motor and servo.
##
## Each one measures the angle and the turning speed of its top against its
## base, decides the speed it wants, and hands that to its joint's motor.
## Positive angles and speeds are counterclockwise seen from the top looking
## back at the base: for a motor or servo that is about its own +Y.
func _run_drives(delta: float) -> void:
	for entry in _drives:
		var drive: Dictionary = entry
		var base: RigidBody3D = drive["base"]
		var top: RigidBody3D = drive["top"]
		var props: Dictionary = drive["props"]
		var links: Dictionary = drive["links"]
		var base_frame: Transform3D = base.global_transform
		var local_axis: Vector3 = drive["axis"]
		var axis: Vector3 = (base_frame.basis * local_axis).normalized()
		var local_from: Vector3 = drive["from"]
		var local_to: Vector3 = drive["to"]
		var from: Vector3 = base_frame.basis * local_from
		var to: Vector3 = top.global_transform.basis * local_to
		var wrapped: float = atan2(axis.dot(from.cross(to)), from.dot(to))
		var last: float = drive["last"]
		var angle: float = float(drive["turned"]) + wrapf(wrapped - last, -PI, PI)
		drive["last"] = wrapped
		drive["turned"] = angle
		var spin: float = (top.angular_velocity - base.angular_velocity).dot(axis)

		var wanted_spin := 0.0
		var powered := true
		var rate: float = drive["rate"]
		if drive["kind"] == "motor":
			var top_spin: float = float(props.get("max_speed", 600.0)) * TAU / 60.0
			var ramp: float = float(props.get("acceleration", 600.0)) * TAU / 60.0
			# Speed is a share of max speed, -1 to 1. The two switches add a full turn each way.
			var command: float = clampf(_input_value(links, "speed", 0.0), -1.0, 1.0)
			if _input_value(links, "counterclockwise", 0.0) != 0.0:
				command += 1.0
			if _input_value(links, "clockwise", 0.0) != 0.0:
				command -= 1.0
			command = clampf(command, -1.0, 1.0)
			if command == 0.0 and str(props.get("when_idle", "Hold still")) == "Spin freely":
				powered = false
				rate = spin   # so it picks up smoothly from whatever speed it has coasted to
			else:
				rate = move_toward(rate, command * top_spin, ramp * delta)
				wanted_spin = rate
			_outputs[drive["uid"]] = spin * 60.0 / TAU
		else:
			var top_speed: float = deg_to_rad(float(props.get("speed", 90.0)))
			var easing: float = deg_to_rad(float(props.get("easing", 360.0)))
			var setpoint: float = drive["setpoint"]
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
					target = drive["hold"]
			# Move the setpoint toward the target: no faster than the servo's
			# speed, easing away from rest and easing in to stop on the target.
			var error: float = target - setpoint
			var approach: float = top_speed
			if easing > 0.0:
				approach = minf(top_speed, sqrt(2.0 * easing * absf(error)))
				rate = move_toward(rate, signf(error) * approach, easing * delta)
			else:
				rate = signf(error) * approach
			if absf(error) <= absf(rate) * delta:
				setpoint = target
				rate = 0.0
			else:
				setpoint += rate * delta
			drive["setpoint"] = setpoint
			if commanded:
				drive["hold"] = setpoint
			# Follow the moving setpoint, and close a share of any error each tick.
			wanted_spin = rate + SERVO_GAIN * (setpoint - angle) / delta
			_outputs[drive["uid"]] = rad_to_deg(angle)
		drive["rate"] = rate
		_drive_joint(drive, powered, wanted_spin, spin)


## Hands a drive's wanted turning speed to its joint's motor.
func _drive_joint(drive: Dictionary, powered: bool, wanted_spin: float, spin: float) -> void:
	var joint: HingeJoint3D = drive["joint"]
	var asked: float = drive["asked"]
	var motor_on: bool = drive["motor_on"]

	# Settle which way the engine counts a positive motor speed. A motor
	# follows what it is asked almost exactly, so if the top is turning at
	# the speed asked the sign is right, and if it is turning at the same
	# speed the other way the sign is backwards. Three clear answers decide.
	if not _motor_sign_known and motor_on and absf(asked) > 0.05:
		if absf(spin - asked) < 0.25 * absf(asked):
			_motor_sign_votes += 1
		elif absf(spin + asked) < 0.25 * absf(asked):
			_motor_sign_votes -= 1
		if _motor_sign_votes >= 3:
			_motor_sign_known = true
		elif _motor_sign_votes <= -3:
			_motor_sign = -_motor_sign
			_motor_sign_known = true
			asked = INF   # force the speed to be sent again with the new sign

	if powered != motor_on:
		joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, powered)
		drive["motor_on"] = powered
	if not powered:
		drive["asked"] = 0.0
		return
	if wanted_spin != asked:
		joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, _motor_sign * wanted_spin)
	drive["asked"] = wanted_spin
	# A body at rest goes to sleep, and a sleeping body ignores its motor.
	if absf(wanted_spin - spin) > 0.005:
		var base: RigidBody3D = drive["base"]
		var top: RigidBody3D = drive["top"]
		if not base.freeze:
			base.sleeping = false
		if not top.freeze:
			top.sleeping = false


# --- Signals -----------------------------------------------------------------
# The first small piece of the logic system: enough to drive a thruster from
# a key. An input block reads its key, a seat reports whether it is occupied,
# and a number gate set to Constant gives its number. Every other source
# reads as zero for now.

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
## linked to it. On/off signals are 1 and 0.
func _input_value(links: Dictionary, input_id: String, unlinked: float) -> float:
	if not links.has(input_id):
		return unlinked
	var link: Dictionary = links[input_id]
	var source_uid: int = int(link.get("uid", 0))
	var output_id: String = str(link.get("output", ""))
	if not _records.has(source_uid):
		return unlinked
	var source: Dictionary = _records[source_uid]
	var type: String = source["type"]
	if type == "input_block":
		var state: Dictionary = _inputs.get(source_uid, {})
		return float(state.get(output_id, 0.0))
	if type == "seat":
		return 1.0 if occupied_seat == source_uid else 0.0
	if _outputs.has(source_uid):
		return float(_outputs[source_uid])   # a motor's speed in RPM, a servo's angle in degrees
	if type == "number_gate":
		var props: Dictionary = source.get("props", {})
		if str(props.get("operation", "")) == "Constant":
			return float(props.get("value", 0.0))
	return 0.0


# --- Forces ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not spawned:
		return
	_update_inputs()
	_run_drives(delta)
	_run_thrusters()
	_run_aero(delta)


## A thruster pushes its body along the thruster's own -Z, at the thruster.
## With nothing linked it runs flat out. A link to "On" switches it, and a
## link to "Throttle" scales it from -1 to 1.
func _run_thrusters() -> void:
	for thruster in _thrusters:
		var body: RigidBody3D = thruster[0]
		var place: Transform3D = thruster[1]
		var thrust: float = thruster[2]
		var links: Dictionary = thruster[3]
		var flame: MeshInstance3D = thruster[4]
		var on: bool = _input_value(links, "on", 1.0) != 0.0
		var throttle: float = clampf(_input_value(links, "throttle", 1.0), -1.0, 1.0)
		var push: float = thrust * throttle if on else 0.0
		flame.visible = push != 0.0
		if push == 0.0 or body.freeze:
			continue
		var frame: Basis = body.global_transform.basis
		body.sleeping = false
		body.apply_force(frame * (place.basis * Vector3(0.0, 0.0, -push)), frame * place.origin)


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
	for panel in _panels:
		var body: RigidBody3D = panel[0]
		if body.freeze or body.sleeping:
			continue
		var frame: Transform3D = body.global_transform
		var centre: Vector3 = panel[1]
		var flat: Vector3 = panel[2]
		var area: float = panel[3]
		var dragless: bool = panel[4]
		var arm: Vector3 = frame.basis * centre
		var moving: Vector3 = body.linear_velocity + body.angular_velocity.cross(arm)
		var density: float = Aero.air_density(frame.origin.y + arm.y)
		var force: Vector3 = Aero.panel_force(moving, frame.basis * flat, area, dragless, density)
		# A tiny, light body in a fast airflow could be thrown about by one
		# tick's force. Never push harder than would stop it dead in two ticks.
		force = force.limit_length(0.5 * body.mass * moving.length() / delta)
		body.apply_force(force, arm)
