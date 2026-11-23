extends Node
## Stress in a spawned build, for the stress view (key 9, or the settings)
## and for parts that break when overloaded.
##
## Each body is a rigid lump of welded parts, so the physics engine knows
## nothing of what goes on inside it. This works it out the way an engineer
## would on paper, with a few simplifications:
##
## - Loads. Every part carries its own weight and its share of the body's
##   acceleration (m × (g − a), with a from the body's linear and angular
##   acceleration at that part), plus the forces put on it directly: thrust,
##   lift, propellers, lift gas. Whatever is left over to balance (the
##   ground, the water, joints) is shared out over the parts by mass, as if
##   the body were supported evenly.
## - Load paths. The parts form a tree, welded face to face, grown outward
##   from the part at the centre of mass, each part joining by the
##   widest weld it has to the tree so far. Each part hands its load, and
##   that of everything beyond it, to the part it hangs from, through the
##   face they share.
## - Stress. At each face: σ = |F| / A + |M| / Z, the direct stress plus the
##   bending stress, with A the face's area and Z = A^1.5 / 6, the section
##   modulus of a square of that area.
##
## The stress view colours each part by σ over the strength of the weaker
## of its material and its neighbour's: blue easy, green, yellow, red at
## the limit. With structural failure on, a part past its limit for two
## checks in a row breaks off, and everything it held goes with it.

const MaterialLibrary = preload("res://scripts/material_library.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const FailureLog = preload("res://scripts/failure_log.gd")

const EVERY := 4                 # physics ticks between checks (60 per second)
const BREAK_CHECKS := 2          # checks in a row past the limit before a part breaks
const MAX_BREAKS := 3            # parts broken per check at most
const GRACE := 2.0               # seconds after spawning before anything breaks
const ROOT_REACH := 1.0          # metres from the centre of mass the load tree's root may be
const GRAVITY := Vector3(0.0, -9.81, 0.0)
const BANDS := 10                # colours in the stress view

## Yield (or breaking) strength of each material, in MPa.
const STRENGTH_MPA := {
	"foam": 0.5, "balsa": 10.0, "cork": 1.5, "wood": 40.0, "oak": 55.0, "ice": 1.0,
	"plastic": 40.0, "rubber": 15.0, "nylon": 75.0, "acrylic": 65.0, "kevlar": 1500.0,
	"carbon_fiber": 600.0, "magnesium": 200.0, "fiberglass": 300.0, "brick": 3.0, "concrete": 4.0,
	"glass": 40.0, "aluminum": 270.0, "granite": 15.0, "diamond": 1500.0, "titanium": 880.0,
	"cast_iron": 150.0, "steel": 400.0, "brass": 200.0, "copper": 70.0, "silver": 50.0,
	"lead": 12.0, "depleted_uranium": 850.0, "tungsten": 750.0, "gold": 120.0,
}

## Colour the parts by stress. Key 9 or the settings switch it.
static var view := false
## Overloaded parts break. The settings switch it.
static var failure := true

var spawner: Node3D = null       # spawner.gd: the build this works on
var _tick := 0
var _trees: Dictionary = {}      # body -> its load tree, see _tree_for
var _motion: Dictionary = {}     # body -> [linear velocity, angular velocity] at the last check
var _ratio: Dictionary = {}      # piece -> stress over strength at its face
var _over: Dictionary = {}       # piece -> checks in a row past the limit
var _coloured: Dictionary = {}   # MeshInstance3D -> true while it shows a stress colour
var _bands: Array = []           # a glowing material per colour band
var _why: Dictionary = {}        # piece -> [stress Pa, limit Pa] when it was found overloaded


static func strength_of(material: String) -> float:
	if MaterialLibrary.is_immovable(material):
		return INF
	return float(STRENGTH_MPA.get(material, 40.0)) * 1000000.0


## The colour for stress over strength: blue at nothing, through green and
## yellow, to red at the limit and beyond.
static func ratio_color(ratio: float) -> Color:
	var t := clampf(ratio, 0.0, 1.0)
	if t < 0.33:
		return Color(0.15, 0.35, 1.0).lerp(Color(0.2, 0.9, 0.35), t / 0.33)
	if t < 0.66:
		return Color(0.2, 0.9, 0.35).lerp(Color(1.0, 0.9, 0.15), (t - 0.33) / 0.33)
	return Color(1.0, 0.9, 0.15).lerp(Color(1.0, 0.1, 0.05), (t - 0.66) / 0.34)


func clear() -> void:
	_uncolour()
	_trees.clear()
	_motion.clear()
	_ratio.clear()
	_over.clear()


## Called by the spawner once a tick, after every force has been put on.
func run(alive_time: float) -> void:
	_tick += 1
	if _tick % EVERY != 0:
		return
	var applied: Dictionary = spawner.applied
	if not view and not failure:
		applied.clear()
		_motion.clear()
		if not _coloured.is_empty():
			_uncolour()
		return
	var interval: float = EVERY / float(Engine.physics_ticks_per_second)
	var doomed: Array = []
	for item in spawner.all_bodies():
		var body: RigidBody3D = item
		if not is_instance_valid(body) or body.freeze:
			continue
		var pieces: Array = spawner.body_pieces(body)
		if body.sleeping:
			continue   # nothing has changed, and its contacts are old news
		var previous: Array = _motion.get(body, [])
		var velocity := body.linear_velocity
		var spin := body.angular_velocity
		_motion[body] = [velocity, spin]
		if pieces.size() < 2 or previous.is_empty():
			continue
		var tree: Dictionary = _tree_for(body, pieces)
		_check_body(body, tree, (velocity - (previous[0] as Vector3)) / interval,
				(spin - (previous[1] as Vector3)) / interval, applied, doomed)
	applied.clear()
	if view:
		_colour()
	elif not _coloured.is_empty():
		_uncolour()
	if failure and alive_time > GRACE and not doomed.is_empty():
		var uids: Dictionary = {}
		for piece in doomed:
			uids[int(piece) >> 3] = piece   # a part's pieces are numbered uid x 8 + 0, 1, 2 ...
			if uids.size() >= MAX_BREAKS:
				break
		for uid in uids:
			_note_break(int(uid), int(uids[uid]))
			spawner.destroy_part(int(uid))
	_why.clear()


## A line for the failure log: which part broke, the stress at its joint,
## its material's limit, and how fast it was going.
func _note_break(uid: int, piece: int) -> void:
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return
	var why: Array = _why.get(piece, [])
	var material := str(record.get("material", ""))
	var body: RigidBody3D = spawner.piece_body(piece)
	var speed := body.linear_velocity.length() if body != null and is_instance_valid(body) else 0.0
	var text := "%s %s (part %d) broke" % [MaterialLibrary.display_name(material), PartLibrary.part_name(str(record["type"])).to_lower(), uid]
	if why.size() == 2:
		text += ": %.0f MPa at its joint, past %s's %.0f MPa limit" % [float(why[0]) / 1.0e6,
				MaterialLibrary.display_name(material).to_lower(), float(why[1]) / 1.0e6]
	text += ", at %.0f m/s" % speed
	# A part that was spinning: how fast, as a shaft's rpm.
	var spin := body.angular_velocity.length() if body != null and is_instance_valid(body) else 0.0
	if spin * 60.0 / TAU >= 30.0:
		text += ", turning at %s rpm" % _thousands(spin * 60.0 / TAU)
	FailureLog.note(text)


static func _thousands(value: float) -> String:
	var whole := str(int(roundf(value)))
	var grouped := ""
	while whole.length() > 3:
		grouped = "," + whole.substr(whole.length() - 3) + grouped
		whole = whole.substr(0, whole.length() - 3)
	return whole + grouped


## The load tree of a body: the order to add up loads in (outermost first)
## and, for each part, the part it hangs from, the middle of the face they
## share (in the body's own space) and that face's area. Worked out again
## whenever the body's set of parts changes.
func _tree_for(body: RigidBody3D, pieces: Array) -> Dictionary:
	var known: Dictionary = _trees.get(body, {})
	if not known.is_empty() and int(known["count"]) == pieces.size():
		return known
	var boxes: Dictionary = spawner.piece_boxes()
	var origin: Vector3 = spawner.body_origin_in_grid(body)
	var centre: Vector3 = body.center_of_mass
	# Neighbours, found through sorting boxes as in welding.
	var buckets: Dictionary = {}
	var near: Dictionary = {}
	for item in pieces:
		var piece: int = item
		near[piece] = []
		if not boxes.has(piece):
			continue
		var box: AABB = boxes[piece]
		var low: Vector3 = (box.position / 1.0).floor()
		var high: Vector3 = (box.end / 1.0).floor()
		for x in range(int(low.x), int(high.x) + 1):
			for y in range(int(low.y), int(high.y) + 1):
				for z in range(int(low.z), int(high.z) + 1):
					var key := Vector3i(x, y, z)
					if not buckets.has(key):
						buckets[key] = []
					for other in buckets[key]:
						var other_piece: int = other
						if (near[other_piece] as Array).has(piece):
							continue
						if spawner.welds(piece, other_piece):
							(near[piece] as Array).append(other_piece)
							(near[other_piece] as Array).append(piece)
					(buckets[key] as Array).append(piece)
	# The root: the heaviest part within a metre of the centre of mass (a
	# little sensor sitting right on it makes a poor hub), or if there is
	# none, the nearest. Parts with no weight (logic) can't be it while there
	# is anything else.
	var root: int = pieces[0]
	var best_key := INF
	var at: Vector3 = centre + origin
	for item in pieces:
		var piece: int = item
		if not boxes.has(piece):
			continue
		var box: AABB = boxes[piece]
		var inside := Vector3(clampf(at.x, box.position.x, box.end.x), clampf(at.y, box.position.y, box.end.y),
				clampf(at.z, box.position.z, box.end.z))
		var distance: float = (inside - at).length()
		var mass: float = spawner.mass_of_piece(piece)
		var key: float = distance if distance > ROOT_REACH else -1.0e6 - mass
		if mass <= 0.0:
			key += 1.0e9
		if key < best_key:
			best_key = key
			root = piece
	# Grown from the root by always taking next the part with the widest
	# joint to what is already in the tree (a maximum spanning tree), so each
	# part's load goes in by the path whose narrowest joint is the widest:
	# a wall welded along its whole edge hangs from that edge, not from a
	# corner it happens to touch nearer the root.
	var order: Array = [root]
	var parent: Dictionary = {root: -1}
	var point: Dictionary = {}
	var area: Dictionary = {}
	var heap: Array = []    # [joint area, part, the tree part it would hang from]
	for other in near[root]:
		_heap_push(heap, [spawner.contact_area(root, other), other, root])
	while not heap.is_empty():
		var best_joint: Array = _heap_pop(heap)
		var child: int = best_joint[1]
		if parent.has(child):
			continue
		var piece: int = best_joint[2]
		parent[child] = piece
		order.append(child)
		var a: AABB = boxes[piece]
		var b: AABB = boxes[child]
		var shared := a.intersection(b)
		if shared.size == Vector3.ZERO:
			# Touching faces have no volume in common; take the box between their middles.
			shared = AABB((a.get_center() + b.get_center()) * 0.5, Vector3.ZERO)
		point[child] = shared.get_center() - origin
		area[child] = maxf(float(best_joint[0]), 0.0001)
		for other in near[child]:
			if not parent.has(other):
				_heap_push(heap, [spawner.contact_area(child, other), other, child])
	# Parts the tree could not reach (welded only through a machine) count alone.
	var tree := {"count": pieces.size(), "order": order, "parent": parent, "point": point, "area": area}
	_trees[body] = tree
	return tree


## A binary heap of [key, ...] arrays with the largest key on top.
static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var up := (i - 1) >> 1
		if float(heap[up][0]) >= float(item[0]):
			break
		heap[i] = heap[up]
		i = up
	heap[i] = item


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var count := heap.size()
	while true:
		var child := i * 2 + 1
		if child >= count:
			break
		if child + 1 < count and float(heap[child + 1][0]) > float(heap[child][0]):
			child += 1
		if float(heap[child][0]) <= float(last[0]):
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return top


func _check_body(body: RigidBody3D, tree: Dictionary, acceleration: Vector3, spin_rate: Vector3,
		applied: Dictionary, doomed: Array) -> void:
	var to_local: Basis = body.global_transform.basis.orthonormalized().inverse()
	var spin: Vector3 = to_local * body.angular_velocity
	var accel: Vector3 = to_local * acceleration
	var turn_rate: Vector3 = to_local * spin_rate
	var gravity: Vector3 = to_local * GRAVITY
	var centre: Vector3 = body.center_of_mass
	var order: Array = tree["order"]
	var parent: Dictionary = tree["parent"]
	var point: Dictionary = tree["point"]
	var area: Dictionary = tree["area"]
	# Each part's own load, in the body's space.
	var own: Dictionary = {}
	var total := Vector3.ZERO
	var mass := 0.0
	for item in order:
		var piece: int = item
		var m: float = spawner.mass_of_piece(piece)
		var r: Vector3 = spawner.centre_of_piece(piece) - centre
		var at_part: Vector3 = accel + turn_rate.cross(r) + spin.cross(spin.cross(r))
		var part_load: Vector3 = (gravity - at_part) * m
		if applied.has(piece):
			part_load += to_local * (applied[piece] as Vector3)
		own[piece] = part_load
		total += part_load
		mass += m
	if mass <= 0.0:
		return
	# Where it rests on or hits something: the contact forces, on the part
	# nearest each contact.
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state != null and state.get_contact_count() > 0:
		var from_world := body.global_transform.affine_inverse()
		var per_second := float(Engine.physics_ticks_per_second)
		for contact in state.get_contact_count():
			var push: Vector3 = to_local * (state.get_contact_impulse(contact) * per_second)
			if push.length_squared() < 0.000001:
				continue
			var at: Vector3 = from_world * state.get_contact_local_position(contact)
			var nearest: int = order[0]
			var best := INF
			for item in order:
				var piece: int = item
				var distance: float = (spawner.centre_of_piece(piece) - at).length_squared()
				if distance < best:
					best = distance
					nearest = piece
			own[nearest] = (own[nearest] as Vector3) + push
			total += push
	# What holds it all up, shared out by mass.
	for item in order:
		var piece: int = item
		own[piece] = (own[piece] as Vector3) - total * (spawner.mass_of_piece(piece) / mass)
	# Outermost first: each part passes its load and everything beyond it inward.
	# Only the worst overloaded face in a body breaks per check; the loads are
	# worked out again with it gone.
	var worst := -1
	var worst_ratio := 1.0
	var worst_why: Array = []
	var force: Dictionary = {}
	var moment: Dictionary = {}
	for index in range(order.size() - 1, -1, -1):
		var piece: int = order[index]
		var f: Vector3 = (own[piece] as Vector3) + (force.get(piece, Vector3.ZERO) as Vector3)
		force[piece] = f
		var up: int = parent[piece]
		if up < 0:
			continue
		var face: Vector3 = point[piece]
		var m: Vector3 = (moment.get(piece, Vector3.ZERO) as Vector3) \
				+ (spawner.centre_of_piece(piece) - face).cross(own[piece] as Vector3)
		var a: float = area[piece]
		var z: float = pow(a, 1.5) / 6.0
		var stress: float = f.length() / a + m.length() / z
		var limit: float = minf(strength_of(spawner.material_of_piece(piece)), strength_of(spawner.material_of_piece(up)))
		var ratio: float = stress / limit if limit < INF else 0.0
		_ratio[piece] = ratio
		if ratio > 1.0:
			_over[piece] = int(_over.get(piece, 0)) + 1
			if int(_over[piece]) >= BREAK_CHECKS and ratio > worst_ratio:
				worst = piece
				worst_ratio = ratio
				worst_why = [stress, limit]
		else:
			_over.erase(piece)
		# Hand the load on to the parent, with its moment about the parent's face.
		force[up] = (force.get(up, Vector3.ZERO) as Vector3) + f
		var up_face: Vector3 = point.get(up, spawner.centre_of_piece(up))
		moment[up] = (moment.get(up, Vector3.ZERO) as Vector3) + m + (face - up_face).cross(f)
	if not parent.is_empty():
		var root: int = order[0]
		_ratio[root] = 0.0
	if worst >= 0:
		doomed.append(worst)
		_why[worst] = worst_why


func _band_material(band: int) -> StandardMaterial3D:
	if _bands.is_empty():
		for index in BANDS + 1:
			var look := StandardMaterial3D.new()
			var color := ratio_color(float(index) / BANDS)
			look.albedo_color = color
			look.emission_enabled = true
			look.emission = color
			look.emission_energy_multiplier = 0.35
			look.roughness = 0.6
			_bands.append(look)
	return _bands[clampi(band, 0, BANDS)]


func _colour() -> void:
	for item in spawner.all_bodies():
		var body: RigidBody3D = item
		if not is_instance_valid(body):
			continue
		for piece in spawner.body_pieces(body):
			var shown: MeshInstance3D = spawner.piece_mesh(piece)
			if shown == null:
				continue
			var band := int(round(clampf(float(_ratio.get(piece, 0.0)), 0.0, 1.0) * BANDS))
			shown.material_override = _band_material(band)
			_coloured[shown] = true


func _uncolour() -> void:
	for key in _coloured:
		var shown := key as MeshInstance3D
		if is_instance_valid(shown):
			shown.material_override = null
	_coloured.clear()


## The stress over strength of a part, for the readout: the highest of its pieces.
func ratio_of(uid: int) -> float:
	var highest := 0.0
	for index in 8:
		highest = maxf(highest, float(_ratio.get(uid * 8 + index, 0.0)))
	return highest


## The highest stress over strength anywhere in the build.
func peak_ratio() -> float:
	var highest := 0.0
	for key in _ratio:
		highest = maxf(highest, float(_ratio[key]))
	return highest
