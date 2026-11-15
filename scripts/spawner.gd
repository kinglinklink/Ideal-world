extends Node3D
## Spawn: turns the build into moving bodies.
##
## Parts that touch face to face, or overlap, are welded into one rigid body
## with their combined mass and centre of mass. Gravity and collisions then
## act on it. This is the basic version: no part does anything yet, so every
## joint, motor and engine is simply welded solid.
##
## Two special cases already follow the design. A dynamic offsetter is
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
var _seats: Dictionary = {}    # seat uid -> [its body, its transform inside that body, its size in metres]


## Builds the bodies from everything on the grid. Returns a short report:
## {"parts": how many parts, "bodies": how many bodies, "mass": kilograms}.
func spawn(grid: Node3D) -> Dictionary:
	despawn()
	var records: Dictionary = {}
	for uid in grid.all_uids():
		records[uid] = grid.get_part(uid)
	var shapes: Dictionary = {}   # collision shapes, shared between identical parts
	var total_mass := 0.0
	for group in weld_groups(records):
		var members: Array = group
		total_mass += _make_body(grid.global_transform, members, records, shapes)
	spawned = true
	return {"parts": records.size(), "bodies": _bodies.size(), "mass": total_mass}


## Removes every spawned body.
func despawn() -> void:
	for body in _bodies:
		(body as Node).queue_free()
	_bodies.clear()
	_seats.clear()
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


# --- Welding -----------------------------------------------------------------

## Sorts parts into weld groups. Two parts weld when their bounding boxes
## share a face, or part of one, or overlap. Meeting only along an edge or at
## a corner is not a weld. Returns an array of arrays of uids.
static func weld_groups(records: Dictionary) -> Array:
	var parent: Dictionary = {}    # uid -> another uid in the same group
	var boxes: Dictionary = {}     # uid -> bounding box
	var buckets: Dictionary = {}   # sorting box -> the uids that reach into it
	var margin := Vector3(TOUCH, TOUCH, TOUCH)
	for uid in records:
		var part_uid: int = uid
		parent[part_uid] = part_uid
		var box: AABB = BuildGrid.bounds_of(records[part_uid])
		boxes[part_uid] = box
		# Only parts that reach into the same sorting box can be touching.
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
						var other_uid: int = other
						var other_box: AABB = boxes[other_uid]
						if _touching(box, other_box):
							_join(parent, part_uid, other_uid)
					neighbours.append(part_uid)

	var groups: Dictionary = {}
	for uid in records:
		var member: int = uid
		var root: int = _root(parent, member)
		if not groups.has(root):
			groups[root] = []
		var members: Array = groups[root]
		members.append(member)
	return groups.values()


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


## The uid that stands for a part's whole group.
static func _root(parent: Dictionary, uid: int) -> int:
	var root: int = uid
	while parent[root] != root:
		root = parent[root]
	# Point everything on the way straight at the root, to keep later lookups short.
	var current: int = uid
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
func _make_body(grid_frame: Transform3D, group: Array, records: Dictionary, shapes: Dictionary) -> float:
	var mass := 0.0
	var moment := Vector3.ZERO   # sum of mass x position, for the centre of mass
	var grip := 0.0              # sum of mass x friction
	var anchored := false
	for uid in group:
		var record: Dictionary = records[uid]
		var part_mass: float = BuildGrid.mass_of(record)
		var material: String = record["material"]
		mass += part_mass
		moment += BuildGrid.centroid_of(record) * part_mass
		grip += float(MaterialLibrary.info(material)["friction"]) * part_mass
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
	for uid in group:
		var part_uid: int = uid
		var record: Dictionary = records[part_uid]
		var type: String = record["type"]
		var rot: Basis = record["rot"]
		var size_units: Vector3i = record["size"]
		var size_m: Vector3 = Units.to_metres(size_units)
		var material: String = record["material"]
		var color: Color = record["color"]
		var place := Transform3D(rot, Vector3(record["pos"] as Vector3i) * Units.UNIT - centre)
		if type == "seat":
			_seats[part_uid] = [body, place, size_m]
		if type == "dynamic_offsetter":
			continue   # it only welds; it has no look and no collision once spawned

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = PartLibrary.mesh_for_record(record)
		mesh_instance.transform = Transform3D(
				Basis(rot.x * size_m.x, rot.y * size_m.y, rot.z * size_m.z), place.origin)
		mesh_instance.set_surface_override_material(0, MaterialLibrary.surface(material, color))
		body.add_child(mesh_instance)

		var shape_key: String = type + str(size_units)
		if not shapes.has(shape_key):
			shapes[shape_key] = PartLibrary.make_shape(type, size_m, true)
		var collider := CollisionShape3D.new()
		collider.shape = shapes[shape_key]
		collider.transform = place
		body.add_child(collider)
		solid = true

	if not solid:
		body.free()   # nothing to see or touch, so nothing to simulate
		return 0.0
	add_child(body)
	_bodies.append(body)
	return mass
