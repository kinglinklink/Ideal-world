extends Node
## Grabbing and towing: the electromagnet, the winch and hook, and the
## coupler of a spawned build. One of these runs beside each spawner.
##
## Electromagnet. When on, it grabs the first loose body touching its pole
## face (its own +Y), or with "Grabs the ground" on, the ground and
## buildings too, and holds it rigidly. It lets go when switched off, or
## when holding on would take more than its holding force (worked out from
## how hard the held body is being accelerated, against its weight).
##
## Winch and hook. A rope runs from the winch's bottom face (-Y) to a hook
## that hangs on it. The rope pulls only when taut: a stiff spring with
## damping, tuned to the masses at each end, so it does not bounce. Reel
## (+1 in, -1 out) winds it in or out at the reel speed, between half a
## metre and the longest rope. The hook grabs whatever loose body it
## touches (not the build it hangs from) while Hook grabs is on, and the
## rope snaps past its breaking tension.
##
## Coupler. Two couplers whose cones (their -Z faces) meet, face to face and
## close, lock together while both want to (Couple on, or "Couples with no
## input"), even between two vehicles: a train, a tow bar, a docking port.
## A coupler set to give or take fuel moves fuel at its flow between the two
## builds' fuel tanks while coupled, for refuelling in mid-air.

const Units = preload("res://scripts/units.gd")

const HOOK_MASS := 15.0
const HOOK_SIZE := 0.35
const ROPE_RADIUS := 0.025
const ROPE_HERTZ := 6.0           # how stiff the rope is: the bounce rate of the masses on it
const COUPLE_REACH := 0.35        # metres between coupler faces that still couple
const GRAVITY := Vector3(0.0, -9.81, 0.0)

var spawner: Node3D = null        # spawner.gd

var _generation := -1
var _magnets: Array = []
var _winches: Array = []
var _couplers: Array = []
var _rope_mesh: CylinderMesh = null
var _hook_mesh: Mesh = null


func setup(the_spawner: Node3D) -> void:
	spawner = the_spawner
	add_to_group("rigging")


func _physics_process(delta: float) -> void:
	if spawner == null:
		return
	if not bool(spawner.spawned):
		if _generation != -1:
			_clear()
		return
	if int(spawner.generation) != _generation:
		_clear()
		_start()
	for item in _magnets:
		_run_magnet(item, delta)
	for item in _winches:
		_run_winch(item, delta)
	for item in _couplers:
		_run_coupler(item, delta)


func _process(_delta: float) -> void:
	for item in _winches:
		_draw_rope(item)


func _start() -> void:
	_generation = int(spawner.generation)
	var records: Dictionary = spawner.all_records()
	for key in records:
		var uid: int = key
		var record: Dictionary = records[uid]
		var props: Dictionary = record.get("props", {})
		match str(record["type"]):
			"magnet":
				_magnets.append({"uid": uid, "strength": float(props.get("strength", 50000.0)),
						"unlinked": bool(props.get("on_unlinked", false)),
						"ground": bool(props.get("grabs_ground", false)),
						"joint": null, "target": null, "last": Vector3.ZERO, "over": 0.0})
			"winch":
				var winch := {"uid": uid, "length": float(props.get("start_length", 4.0)),
						"max": float(props.get("max_length", 40.0)), "speed": float(props.get("reel_speed", 2.0)),
						"strength": float(props.get("strength", 100000.0)),
						"unlinked": bool(props.get("grabs_unlinked", true)),
						"hook": null, "rope": null, "joint": null, "target": null, "tension": 0.0, "snapped": false}
				winch["max"] = maxf(float(winch["max"]), 0.5)
				winch["length"] = clampf(float(winch["length"]), 0.5, float(winch["max"]))
				_make_hook(winch)
				_winches.append(winch)
			"coupler":
				_couplers.append({"uid": uid, "unlinked": bool(props.get("couples_unlinked", true)),
						"fuel": str(props.get("fuel", "None")), "rate": float(props.get("fuel_rate", 5.0)),
						"joint": null, "partner": null, "moved": 0.0, "wants": false})


func _clear() -> void:
	_generation = -1
	for item in _magnets:
		_free_joint(item)
	for item in _winches:
		var winch: Dictionary = item
		_free_joint(winch)
		for key in ["hook", "rope"]:
			var node: Node = winch[key]
			if is_instance_valid(node):
				node.queue_free()
	for item in _couplers:
		_uncouple(item)
	_magnets.clear()
	_winches.clear()
	_couplers.clear()


func _free_joint(entry: Dictionary) -> void:
	var joint: Node = entry.get("joint")
	if is_instance_valid(joint):
		joint.queue_free()
	entry["joint"] = null
	entry["target"] = null


## A joint that holds two bodies rigidly together at `at` (world).
func _lock(a: PhysicsBody3D, b: PhysicsBody3D, at: Vector3) -> Generic6DOFJoint3D:
	var joint := Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_transform = Transform3D(Basis.IDENTITY, at)
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()
	return joint


func _frame(uid: int) -> Array:
	return spawner.part_frame(uid)


func _size(uid: int) -> Vector3:
	var record: Dictionary = spawner.record_of(uid)
	if record.is_empty():
		return Vector3.ONE * Units.CELL
	return Units.to_metres(record["size"] as Vector3i)


func _own_rids() -> Array:
	var rids: Array = []
	for item in spawner.all_bodies():
		var body: RigidBody3D = item
		if is_instance_valid(body):
			rids.append(body.get_rid())
	return rids


# --- Electromagnet -----------------------------------------------------------------

func _run_magnet(magnet: Dictionary, delta: float) -> void:
	var uid: int = magnet["uid"]
	var record: Dictionary = spawner.record_of(uid)
	var frame_and_body: Array = _frame(uid)
	if record.is_empty() or frame_and_body.is_empty():
		_free_joint(magnet)
		return
	var frame: Transform3D = frame_and_body[0]
	var body: RigidBody3D = frame_and_body[1]
	var links: Dictionary = record.get("links", {})
	var on: bool = spawner.input_value(links, "on", 1.0 if bool(magnet["unlinked"]) else 0.0) != 0.0
	var target: Object = magnet["target"]
	if magnet["joint"] != null and (not on or not is_instance_valid(target)):
		_free_joint(magnet)
	elif magnet["joint"] != null:
		# Too much for it to hold? From how hard the held body is being pushed about.
		var held := target as RigidBody3D
		if held != null and not held.freeze:
			var velocity := held.linear_velocity
			var needed := held.mass * ((velocity - (magnet["last"] as Vector3)) / delta - GRAVITY)
			magnet["last"] = velocity
			if needed.length() > float(magnet["strength"]):
				magnet["over"] = float(magnet["over"]) + delta
				if float(magnet["over"]) > 0.15:
					_free_joint(magnet)
			else:
				magnet["over"] = 0.0
	elif on:
		var size := _size(uid)
		var up := frame.basis.y.normalized()
		var face := frame.origin + up * (size.y * 0.5)
		var box := BoxShape3D.new()
		box.size = Vector3(size.x * 0.9, 0.12, size.z * 0.9)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = box
		query.transform = Transform3D(frame.basis.orthonormalized(), face + up * 0.06)
		query.collision_mask = Units.LAYER_BODIES | (Units.LAYER_WORLD if bool(magnet["ground"]) else 0)
		query.exclude = [body.get_rid()]
		for hit in spawner.get_world_3d().direct_space_state.intersect_shape(query, 6):
			var thing := (hit as Dictionary).get("collider") as PhysicsBody3D
			if thing == null:
				continue
			var loose := thing as RigidBody3D
			if loose == null and not bool(magnet["ground"]):
				continue
			magnet["joint"] = _lock(body, thing, face)
			magnet["target"] = thing
			magnet["last"] = loose.linear_velocity if loose != null else Vector3.ZERO
			magnet["over"] = 0.0
			break
	spawner.set_outputs(uid, {"holding": 1.0 if magnet["joint"] != null else 0.0})


# --- Winch and hook ------------------------------------------------------------------

func _make_hook(winch: Dictionary) -> void:
	var frame_and_body: Array = _frame(int(winch["uid"]))
	if frame_and_body.is_empty():
		return
	var frame: Transform3D = frame_and_body[0]
	var size := _size(int(winch["uid"]))
	var down := -frame.basis.y.normalized()
	var hook := RigidBody3D.new()
	hook.name = "Hook"
	hook.mass = HOOK_MASS
	hook.collision_layer = Units.LAYER_BODIES
	hook.collision_mask = Units.LAYER_WORLD | Units.LAYER_BODIES
	hook.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	hook.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	hook.angular_damp = 0.5
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * HOOK_SIZE
	var collider := CollisionShape3D.new()
	collider.shape = shape
	hook.add_child(collider)
	var look := MeshInstance3D.new()
	look.mesh = _get_hook_mesh()
	hook.add_child(look)
	add_child(hook)
	hook.global_position = frame.origin + down * (size.y * 0.5 + float(winch["length"]))
	var anchor: Node3D = frame_and_body[1]
	hook.linear_velocity = (anchor as RigidBody3D).linear_velocity
	winch["hook"] = hook
	var rope := MeshInstance3D.new()
	rope.name = "Rope"
	rope.mesh = _get_rope_mesh()
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rope)
	winch["rope"] = rope


func _get_rope_mesh() -> CylinderMesh:
	if _rope_mesh == null:
		_rope_mesh = CylinderMesh.new()
		_rope_mesh.top_radius = ROPE_RADIUS
		_rope_mesh.bottom_radius = ROPE_RADIUS
		_rope_mesh.height = 1.0
		_rope_mesh.radial_segments = 6
		_rope_mesh.rings = 1
		var look := StandardMaterial3D.new()
		look.albedo_color = Color(0.15, 0.14, 0.12)
		look.roughness = 0.9
		_rope_mesh.material = look
	return _rope_mesh


func _get_hook_mesh() -> Mesh:
	if _hook_mesh == null:
		var body := BoxMesh.new()
		body.size = Vector3(HOOK_SIZE, HOOK_SIZE, HOOK_SIZE)
		var look := StandardMaterial3D.new()
		look.albedo_color = Color(0.95, 0.72, 0.1)
		look.metallic = 0.6
		look.roughness = 0.4
		body.material = look
		_hook_mesh = body
	return _hook_mesh


func _run_winch(winch: Dictionary, delta: float) -> void:
	var uid: int = winch["uid"]
	var record: Dictionary = spawner.record_of(uid)
	var frame_and_body: Array = _frame(uid)
	var hook := winch["hook"] as RigidBody3D
	if record.is_empty() or frame_and_body.is_empty() or not is_instance_valid(hook):
		if is_instance_valid(hook):
			_snap(winch)
		return
	var frame: Transform3D = frame_and_body[0]
	var body: RigidBody3D = frame_and_body[1]
	var links: Dictionary = record.get("links", {})
	# Reeling.
	var reel := clampf(spawner.input_value(links, "reel", 0.0), -1.0, 1.0)
	winch["length"] = clampf(float(winch["length"]) - reel * float(winch["speed"]) * delta, 0.5, float(winch["max"]))
	# The rope.
	var size := _size(uid)
	var anchor := frame.origin - frame.basis.y.normalized() * (size.y * 0.5)
	var along := hook.global_position - anchor
	var reach := along.length()
	var tension := 0.0
	if reach > float(winch["length"]) and reach > 0.001:
		var direction := along / reach
		var load_mass := hook.mass
		var held := winch["target"] as RigidBody3D
		if held != null and is_instance_valid(held) and not held.freeze:
			load_mass += held.mass
		var anchor_mass: float = body.mass if not body.freeze else 1000000000.0
		var shared := 1.0 / (1.0 / load_mass + 1.0 / anchor_mass)
		var omega := TAU * ROPE_HERTZ
		var stiffness := shared * omega * omega
		var damping := 2.0 * 0.8 * shared * omega
		var arm := anchor - body.global_position
		var anchor_speed: Vector3 = body.linear_velocity + body.angular_velocity.cross(arm)
		var opening := (hook.linear_velocity - anchor_speed).dot(direction)
		tension = maxf(stiffness * (reach - float(winch["length"])) + damping * opening, 0.0)
		if tension > float(winch["strength"]):
			_snap(winch)
			return
		hook.apply_central_force(-direction * tension)
		if not body.freeze:
			body.apply_force(direction * tension, anchor - body.global_position)
		hook.sleeping = false
		body.sleeping = false
	winch["tension"] = tension
	# Grabbing.
	var wants: bool = spawner.input_value(links, "grab", 1.0 if bool(winch["unlinked"]) else 0.0) != 0.0
	var target: Object = winch["target"]
	if winch["joint"] != null and (not wants or not is_instance_valid(target)):
		_free_joint(winch)
	elif winch["joint"] == null and wants:
		var ball := SphereShape3D.new()
		ball.radius = HOOK_SIZE * 0.9
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = ball
		query.transform = Transform3D(Basis.IDENTITY, hook.global_position)
		query.collision_mask = Units.LAYER_BODIES
		var skip: Array = _own_rids()
		skip.append(hook.get_rid())
		query.exclude = skip
		for hit in spawner.get_world_3d().direct_space_state.intersect_shape(query, 4):
			var thing := (hit as Dictionary).get("collider") as RigidBody3D
			if thing == null or thing.freeze:
				continue
			winch["joint"] = _lock(hook, thing, hook.global_position)
			winch["target"] = thing
			break
	spawner.set_outputs(uid, {"length": float(winch["length"]), "tension": tension,
			"holding": 1.0 if winch["joint"] != null else 0.0})


## The rope breaks: the hook drops with whatever it held.
func _snap(winch: Dictionary) -> void:
	_free_joint(winch)
	var rope: Node = winch["rope"]
	if is_instance_valid(rope):
		rope.queue_free()
	winch["rope"] = null
	winch["snapped"] = true
	var hook: Node = winch["hook"]
	if is_instance_valid(hook):
		# The hook lies where it fell for a while, then goes.
		get_tree().create_timer(20.0).timeout.connect(func() -> void:
			if is_instance_valid(hook):
				hook.queue_free())
	winch["hook"] = null


func _draw_rope(winch: Dictionary) -> void:
	var rope := winch["rope"] as MeshInstance3D
	var hook := winch["hook"] as Node3D
	if rope == null or not is_instance_valid(rope) or not is_instance_valid(hook):
		return
	var frame_and_body: Array = _frame(int(winch["uid"]))
	if frame_and_body.is_empty():
		rope.visible = false
		return
	var frame: Transform3D = frame_and_body[0]
	var anchor := frame.origin - frame.basis.y.normalized() * (_size(int(winch["uid"])).y * 0.5)
	var end := hook.global_position
	var along := end - anchor
	var length := along.length()
	if length < 0.01:
		rope.visible = false
		return
	rope.visible = true
	var y := along / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	rope.global_transform = Transform3D(Basis(x, y * length, z), (anchor + end) * 0.5)


# --- Coupler -------------------------------------------------------------------------

func _coupler_face(uid: int) -> Array:
	var frame_and_body: Array = _frame(uid)
	if frame_and_body.is_empty():
		return []
	var frame: Transform3D = frame_and_body[0]
	var out := -frame.basis.z.normalized()
	return [frame.origin + out * (_size(uid).z * 0.5), out, frame_and_body[1]]


func _run_coupler(coupler: Dictionary, delta: float) -> void:
	var uid: int = coupler["uid"]
	var record: Dictionary = spawner.record_of(uid)
	var face: Array = _coupler_face(uid)
	if record.is_empty() or face.is_empty():
		_uncouple(coupler)
		coupler["wants"] = false
		return
	var links: Dictionary = record.get("links", {})
	coupler["wants"] = spawner.input_value(links, "couple", 1.0 if bool(coupler["unlinked"]) else 0.0) != 0.0
	var partner: Variant = coupler["partner"]
	if partner != null:
		var other: Dictionary = partner
		if not bool(coupler["wants"]) or not bool(other.get("wants", false)) or not is_instance_valid(coupler["joint"]):
			_uncouple(coupler)
		else:
			_move_fuel(coupler, other, delta)
	elif bool(coupler["wants"]):
		_look_for_partner(coupler, face)
	spawner.set_outputs(uid, {"coupled": 1.0 if coupler["partner"] != null else 0.0,
			"fuel_moved": float(coupler["moved"])})


func _look_for_partner(coupler: Dictionary, face: Array) -> void:
	var here: Vector3 = face[0]
	var out: Vector3 = face[1]
	var body: RigidBody3D = face[2]
	for node in get_tree().get_nodes_in_group("rigging"):
		if node == self:
			continue   # a build does not couple to itself
		for item in node.couplers():
			var other: Dictionary = item
			if other["partner"] != null or not bool(other.get("wants", false)):
				continue
			var other_face: Array = node.coupler_face(int(other["uid"]))
			if other_face.is_empty():
				continue
			if (other_face[0] as Vector3).distance_to(here) > COUPLE_REACH:
				continue
			if (other_face[1] as Vector3).dot(out) > -0.7:
				continue   # not face to face
			var other_body: RigidBody3D = other_face[2]
			var joint := _lock(body, other_body, (here + (other_face[0] as Vector3)) * 0.5)
			coupler["joint"] = joint
			other["joint"] = joint
			coupler["partner"] = other
			other["partner"] = coupler
			coupler["rigging"] = node
			other["rigging"] = self
			return


func _uncouple(coupler: Dictionary) -> void:
	var joint: Node = coupler.get("joint")
	if is_instance_valid(joint):
		joint.queue_free()
	var partner: Variant = coupler.get("partner")
	if partner != null:
		var other: Dictionary = partner
		other["partner"] = null
		other["joint"] = null
	coupler["partner"] = null
	coupler["joint"] = null


## Fuel through a coupling: the side set to give pours into the other's
## tanks, or the side set to take draws from them, at its flow.
func _move_fuel(coupler: Dictionary, other: Dictionary, delta: float) -> void:
	var mode: String = coupler["fuel"]
	if mode == "None":
		return
	var other_rigging: Node = coupler.get("rigging")
	if other_rigging == null or not is_instance_valid(other_rigging):
		return
	var mine: Node = spawner.engines
	var theirs: Node = other_rigging.spawner.engines
	if mine == null or theirs == null:
		return
	var litres := float(coupler["rate"]) * delta
	var giver: Node = mine if mode == "Give fuel" else theirs
	var taker: Node = theirs if mode == "Give fuel" else mine
	var taken: float = giver.take_fuel(litres)
	var poured: float = taker.add_fuel(taken)
	if poured < taken:
		giver.add_fuel(taken - poured)   # what did not fit goes back
	coupler["moved"] = float(coupler["moved"]) + poured
	other["moved"] = float(other.get("moved", 0.0)) + poured


## For other riggings: this build's couplers and where their faces are.
func couplers() -> Array:
	return _couplers


func coupler_face(uid: int) -> Array:
	return _coupler_face(uid)


## Moves the hooks with the world when main.gd re-centres it.
func shift_origin(shift: Vector3) -> void:
	for item in _winches:
		var hook := (item as Dictionary).get("hook") as Node3D
		if is_instance_valid(hook):
			hook.global_position -= shift
	for child in get_children():
		var joint := child as Joint3D
		if joint != null:
			joint.global_position -= shift
