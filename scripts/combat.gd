extends Node3D
## Combat: guns, cannon shells, ammo generators and explosives.
##
## The spawner holds the parts and their health; this script fires, flies
## and explodes things, and tells the spawner how much damage each part takes.
## Every number follows the design document:
##   machine gun     4 HP per bullet, fired straight along the gun's -Z
##   large cannon    propellant pushes the shell down the barrel at 100 MPa,
##                   so muzzle energy = 100 MPa x bore area x barrel length.
##                   The shell is steel (or whatever is set), three bores long.
##                   A hit does 1 HP per kJ the shell still carries, and the
##                   shell goes through any part it destroys, slowed by the
##                   energy that took. One shot per 0.5 s per metre of barrel.
##   ammo generator  makes its rate per second, up to its storage, and weighs
##                   more as it fills. A gun linked to one spends from it.
##   hit-scan gun    the machine gun aimed by the mouse: where the cursor
##                   (a crosshair) points, each gun in reach and within its
##                   aiming cone fires at its rate, 4 HP a round, straight to
##                   that point (a part, a building, a crate, a car).
##   explosive       damage = D0 x (1 - distance / radius), D0 = 1000 HP per
##                   metre of blast radius, and a push of 1 N s per HP dealt.
##                   An explosive destroyed by anything goes off one tick later,
##                   so chains of them ripple outward.

const Units = preload("res://scripts/units.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const Sound = preload("res://scripts/sound.gd")
const Birds = preload("res://scripts/birds.gd")

const BULLET_DAMAGE := 4.0          # HP per machine gun round
const BULLET_MASS := 0.01           # kg, the bullet itself
const BULLET_SPEED := 850.0         # m/s, for the push a hit gives and the gun's recoil
const ROUND_MASS := 0.025           # kg, a whole stored cartridge
const MAX_SHOTS_PER_TICK := 20
const CANNON_PRESSURE := 100000000.0   # Pa, the average push of the propellant
const HP_PER_JOULE := 0.001         # 1 HP per kJ
const BLAST_HP_PER_METRE := 1000.0  # D0 = this x blast radius
const BLAST_PUSH := 1.0             # N s of push per HP of blast damage
const SHELL_LIFE := 30.0            # s before a shell that hit nothing is dropped
const TRACER_LIFE := 0.05           # s
const FLASH_LIFE := 0.35            # s
const MAX_TRACERS := 96
const RAY_MASK := Units.LAYER_WORLD | Units.LAYER_BODIES
const AIM_REACH := 10000.0          # m the aiming ray from the camera looks

## The mouse cursor becomes a crosshair while any hit-scan gun can be aimed.
static var _crosshair_frame := -100
static var _crosshair_on := false
static var _crosshair_texture: ImageTexture = null

var spawner: Node3D = null   # spawner.gd
var structures: Array = []   # towns.gd, towers.gd: things in the world that can be destroyed
var resets_world := true     # false for a fleet vehicle's guns: only the pad's Build puts the world back
var terrain: Node3D = null   # terrain.gd: shots also stop at the ground, near or far

var _generation := -1
var _guns: Dictionary = {}         # gun uid -> {"cooldown": s}
var _generators: Dictionary = {}   # generator uid -> {"stored", "rate", "storage", "kind", "base_mass", "unit_mass", "shown_mass", "refresh"}
var _explosives: Array = []        # uids of explosive blocks
var _detonate_source: Dictionary = {}   # explosive uid -> [source uid, output] its Detonate reads
var _shells: Array = []            # {"node", "at", "speed", "mass", "life", "skip"}
var _pending_blasts: Array = []    # [where, radius] to set off next tick
var _tracers: Array = []           # [node, time left]
var _flashes: Array = []           # [node, time left, full size]

var _tracer_mesh: Mesh = null
var _shell_mesh: Mesh = null
var _flash_mesh: Mesh = null
var _dust_mesh: Mesh = null


## Called by main.gd when the world re-centres: this node has already moved
## with everything else, so only the remembered shell positions need moving.
func shift_origin(shift: Vector3) -> void:
	for item in _shells:
		var shell: Dictionary = item
		shell["at"] = (shell["at"] as Vector3) - shift


func setup(the_spawner: Node3D) -> void:
	add_to_group("combat")
	spawner = the_spawner
	spawner.connect("part_destroyed", _on_part_destroyed)


# --- Ballistics --------------------------------------------------------------

## What a cannon of this size fires: {"bore" m, "barrel" m, "mass" kg,
## "energy" J, "speed" m/s, "interval" s}.
static func cannon_ballistics(record: Dictionary) -> Dictionary:
	var size_units: Vector3i = record["size"]
	var size_m: Vector3 = Units.to_metres(size_units)
	var bore: float = 0.2 * minf(size_m.x, size_m.y)
	var barrel: float = size_m.z
	var props: Dictionary = record.get("props", {})
	var projectile_name := str(props.get("projectile_material", "Steel"))
	var density: float = MaterialLibrary.density(MaterialLibrary.id_for_name(projectile_name))
	var bore_area: float = PI * bore * bore * 0.25
	var mass: float = density * bore_area * bore * 3.0
	var energy: float = CANNON_PRESSURE * bore_area * barrel
	var speed := 0.0
	if mass > 0.0:
		speed = sqrt(2.0 * energy / mass)
	return {"bore": bore, "barrel": barrel, "mass": mass, "energy": energy, "speed": speed,
			"interval": maxf(0.5 * barrel, 0.05)}


# --- Every tick --------------------------------------------------------------

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
	_set_off_blasts()
	_run_generators(delta)
	_run_explosives()
	_run_guns(delta)
	_run_shells(delta)
	_fade_effects(delta)


## Parts made while spawned (a reload gate's payload): guns and
## explosives join in.
func _on_parts_added(uids: Array) -> void:
	if _generation != int(spawner.generation):
		return   # not started on this spawn yet; _start will find them
	for item in uids:
		var uid: int = item
		var type := str(spawner.record_of(uid).get("type", ""))
		if type == "machine_gun" or type == "large_cannon" or type == "hitscan_gun":
			_guns[uid] = {"cooldown": 0.0}
		elif type == "explosive_block":
			_explosives.append(uid)


## Notes the combat parts of a new spawn.
func _start() -> void:
	_generation = int(spawner.generation)
	if not spawner.parts_added.is_connected(_on_parts_added):
		spawner.parts_added.connect(_on_parts_added)
	var records: Dictionary = spawner.all_records()
	var cannon_shell_mass: Dictionary = {}   # generator uid -> heaviest shell a linked cannon fires
	for key in records:
		var uid: int = key
		var record: Dictionary = records[uid]
		var type: String = record["type"]
		if type == "machine_gun" or type == "large_cannon" or type == "hitscan_gun":
			_guns[uid] = {"cooldown": 0.0}
			if type == "large_cannon":
				var source: int = spawner.link_source(record.get("links", {}), "ammo")
				if source != 0:
					var shell: float = float(cannon_ballistics(record)["mass"])
					cannon_shell_mass[source] = maxf(float(cannon_shell_mass.get(source, 0.0)), shell)
		elif type == "explosive_block":
			_explosives.append(uid)
	for key in records:
		var uid: int = key
		var record: Dictionary = records[uid]
		if record["type"] != "ammo_generator":
			continue
		var props: Dictionary = record.get("props", {})
		var kind := str(props.get("ammo_type", "Machine gun rounds"))
		var unit_mass: float = ROUND_MASS
		if kind == "Cannon shells":
			unit_mass = float(cannon_shell_mass.get(uid, 10.0))
		var base_mass: float = BuildGrid.mass_of(record)
		_generators[uid] = {
			"stored": 0.0, "kind": kind,
			"rate": maxf(float(props.get("rate", 5.0)), 0.0),
			"storage": maxf(float(props.get("storage", 200.0)), 0.0),
			"base_mass": base_mass, "unit_mass": unit_mass,
			"shown_mass": base_mass, "refresh": 0.0,
		}


## Forgets everything from the last spawn and removes what is still flying.
func _clear() -> void:
	_generation = -1
	if resets_world:
		for item in structures:
			var structure: Node = item
			structure.reset_damage()
	_guns.clear()
	_generators.clear()
	_explosives.clear()
	_detonate_source.clear()
	_pending_blasts.clear()
	for shell in _shells:
		var node: Node = shell["node"]
		if is_instance_valid(node):
			node.queue_free()
	_shells.clear()
	for item in _tracers:
		var node: Node = item[0]
		if is_instance_valid(node):
			node.queue_free()
	_tracers.clear()
	for item in _flashes:
		var node: Node = item[0]
		if is_instance_valid(node):
			node.queue_free()
	_flashes.clear()


# --- Ammo --------------------------------------------------------------------

func _run_generators(delta: float) -> void:
	for key in _generators:
		var uid: int = key
		var generator: Dictionary = _generators[uid]
		if spawner.record_of(uid).is_empty():
			continue   # destroyed
		var stored: float = generator["stored"]
		stored = minf(stored + float(generator["rate"]) * delta, float(generator["storage"]))
		generator["stored"] = stored
		spawner.set_outputs(uid, {"ammo": floorf(stored), "stored": floorf(stored)})
		# Its weight follows what it holds, brought up to date a few times a second.
		generator["refresh"] = float(generator["refresh"]) - delta
		if float(generator["refresh"]) <= 0.0:
			generator["refresh"] = 0.25
			var mass: float = float(generator["base_mass"]) + floorf(stored) * float(generator["unit_mass"])
			if absf(mass - float(generator["shown_mass"])) > 0.0001:
				generator["shown_mass"] = mass
				spawner.set_part_mass(uid, mass)


## Takes one round for a gun. True if it may fire.
func _take_round(record: Dictionary) -> bool:
	var props: Dictionary = record.get("props", {})
	if bool(props.get("unlimited_ammo", true)):
		return true
	var source: int = spawner.link_source(record.get("links", {}), "ammo")
	if not _generators.has(source) or spawner.record_of(source).is_empty():
		return false
	var generator: Dictionary = _generators[source]
	var wanted := "Cannon shells" if record["type"] == "large_cannon" else "Machine gun rounds"
	if generator["kind"] != wanted or float(generator["stored"]) < 1.0:
		return false
	generator["stored"] = float(generator["stored"]) - 1.0
	generator["refresh"] = 0.0   # weigh it again now
	return true


# --- Guns --------------------------------------------------------------------

func _run_guns(delta: float) -> void:
	var aim: Dictionary = {}
	var aimed := false
	for key in _guns:
		var uid: int = key
		var gun: Dictionary = _guns[uid]
		var record: Dictionary = spawner.record_of(uid)
		if record.is_empty():
			continue   # destroyed
		var cooldown: float = maxf(float(gun["cooldown"]) - delta, -delta)
		var links: Dictionary = record.get("links", {})
		var firing: bool = spawner.input_value(links, "fire", 0.0) != 0.0
		var props: Dictionary = record.get("props", {})
		if record["type"] == "hitscan_gun":
			if not aimed:
				aimed = true
				aim = _aim_point()
			firing = _hitscan_wants(uid, record, aim, firing)
			gun["aim"] = aim.get("point", Vector3.ZERO)
		if not firing:
			gun["cooldown"] = maxf(cooldown, 0.0)
			continue
		var interval: float
		if record["type"] == "machine_gun" or record["type"] == "hitscan_gun":
			var rate: float = float(props.get("fire_rate", 10.0))
			if rate <= 0.0:
				gun["cooldown"] = 0.0
				continue
			interval = 1.0 / rate
		else:
			interval = float(cannon_ballistics(record)["interval"])
		var shots := 0
		while cooldown <= 0.0 and shots < MAX_SHOTS_PER_TICK:
			if not _take_round(record):
				cooldown = 0.0
				break
			if record["type"] == "machine_gun":
				_fire_bullet(uid, record)
			elif record["type"] == "hitscan_gun":
				_fire_at(uid, record, gun["aim"])
			else:
				_fire_shell(uid, record)
			cooldown += interval
			shots += 1
		gun["cooldown"] = cooldown


## Where the mouse points: the camera's ray through the cursor (the middle
## of the screen in first person), past this build's own parts and the
## character. {"point", "hit"} or empty when there is no mouse to aim with.
func _aim_point() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var screen := get_viewport().get_visible_rect().size
	var cursor := get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cursor = screen * 0.5
	var from := camera.project_ray_origin(cursor)
	var direction := camera.project_ray_normal(cursor)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * AIM_REACH, RAY_MASK)
	var skip: Array[RID] = []
	for body in spawner.all_bodies():
		if is_instance_valid(body):
			skip.append((body as RigidBody3D).get_rid())
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player != null:
		skip.append(player.get_rid())
	query.exclude = skip
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var end: Vector3 = from + direction * AIM_REACH if hit.is_empty() else hit["position"]
	if terrain != null:
		var ground := _ground_hit(from, end)
		if not ground.is_empty():
			return {"point": ground[0], "hit": true}
	return {"point": end, "hit": not hit.is_empty()}


## Whether a hit-scan gun fires this tick: on its Fire input if linked (or
## set to), else while the mouse button is held, and only if the aim point
## is in its range and inside its aiming cone. The mouse only works for the
## build you sit in, or the one on the pad if it has no seat.
func _hitscan_wants(uid: int, record: Dictionary, aim: Dictionary, signal_on: bool) -> bool:
	var props: Dictionary = record.get("props", {})
	var trigger := str(props.get("trigger", "Left mouse button"))
	var linked: bool = spawner.link_source(record.get("links", {}), "fire") != 0
	var firing := signal_on
	if not linked and trigger != "Fire input only":
		var mine: bool = int(spawner.occupied_seat) != 0 or (resets_world and not _has_seat())
		var button := MOUSE_BUTTON_RIGHT if trigger == "Right mouse button" else MOUSE_BUTTON_LEFT
		firing = mine and Input.is_mouse_button_pressed(button) and get_viewport().gui_get_hovered_control() == null
		if mine:
			_crosshair_frame = Engine.get_physics_frames()
	var out := {"firing": 0.0, "hit_distance": 0.0}
	var muzzle: Array = _muzzle(uid, record)
	if aim.is_empty() or muzzle.is_empty() or not bool(aim.get("hit", false)):
		spawner.set_outputs(uid, out)
		return false
	var to_aim: Vector3 = (aim["point"] as Vector3) - (muzzle[0] as Vector3)
	out["hit_distance"] = to_aim.length()
	var reach: float = maxf(float(props.get("range", 500.0)), 1.0)
	var cone := deg_to_rad(clampf(float(props.get("cone", 60.0)), 1.0, 360.0)) * 0.5
	var can_hit := to_aim.length() <= reach and (muzzle[1] as Vector3).angle_to(to_aim) <= cone
	out["firing"] = 1.0 if firing and can_hit else 0.0
	spawner.set_outputs(uid, out)
	return firing and can_hit


func _has_seat() -> bool:
	for key in spawner.all_records():
		if str((spawner.all_records()[key] as Dictionary)["type"]) == "seat":
			return true
	return false


## A hit-scan round: straight from the muzzle to the aim point (the first
## thing in the way takes it), 4 HP and a small push.
func _fire_at(uid: int, record: Dictionary, aim: Vector3) -> void:
	var muzzle: Array = _muzzle(uid, record)
	if muzzle.is_empty():
		return
	var from: Vector3 = muzzle[0]
	var direction: Vector3 = (aim - from).normalized()
	var body: RigidBody3D = muzzle[2]
	var to: Vector3 = aim + direction * 0.5
	var hit: Dictionary = _cast(from, to)
	if not hit.is_empty():
		to = hit["position"]
		var target := hit["collider"] as RigidBody3D
		if target != null and not target.freeze:
			target.sleeping = false
			target.apply_impulse(direction * BULLET_MASS * BULLET_SPEED, to - target.global_position)
		var part: int = spawner.part_of_shape(hit["collider"], int(hit["shape"]))
		if part != 0:
			_spark(to, spawner.record_of(part))
			spawner.damage_part(part, BULLET_DAMAGE)
		elif hit["collider"] != null:
			_hit_other(hit["collider"], int(hit["shape"]), BULLET_DAMAGE)
	if body != null and not body.freeze:
		body.apply_impulse(-direction * BULLET_MASS * BULLET_SPEED, from - body.global_position)
	_add_tracer(from, to)
	Sound.gun("gunshot", from, -2.0, 30.0)


const METALS := ["steel", "aluminum", "titanium", "cast_iron", "brass", "copper", "tungsten", "magnesium",
		"lead", "silver", "gold", "depleted_uranium"]


## Sparks and a ping where a round hits metal.
func _spark(at: Vector3, record: Dictionary) -> void:
	if not METALS.has(str(record.get("material", ""))):
		return
	_add_flash(at, 0.25)
	Sound.play_at("spark", at, -6.0, 40.0, randf_range(0.9, 1.2))


## Sets off a blast at a world point next tick (a fuel tank going up).
func add_blast(world: Vector3, radius: float) -> void:
	_pending_blasts.append([world, radius])


## Damage to something that is not a part of this build: another build's
## part (a fleet vehicle), or a building or tower block.
func _hit_other(collider: Object, shape: int, amount: float) -> void:
	for node in get_tree().get_nodes_in_group("combat"):
		if node == self:
			continue
		var other: Node = node.spawner
		if other == null or not bool(other.spawned):
			continue
		var part: int = other.part_of_shape(collider, shape)
		if part != 0:
			other.damage_part(part, amount)
			return
	_damage_structure(collider, shape, amount)


func _process(_delta: float) -> void:
	# One crosshair for every build: on while any hit-scan gun can be aimed.
	var wanted := Engine.get_physics_frames() - _crosshair_frame < 8
	if wanted != _crosshair_on:
		_crosshair_on = wanted
		if wanted:
			Input.set_custom_mouse_cursor(_crosshair(), Input.CURSOR_ARROW, Vector2(16, 16))
		else:
			Input.set_custom_mouse_cursor(null)


static func _crosshair() -> ImageTexture:
	if _crosshair_texture == null:
		var image := Image.create(33, 33, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		for i in 33:
			for along in [i]:
				var gap := absi(along - 16) < 4
				if gap:
					continue
				for width in [-1, 0, 1]:
					var shade := Color(0, 0, 0, 0.8) if width != 0 else Color(1.0, 1.0, 1.0, 1.0)
					image.set_pixel(along, 16 + width, shade)
					image.set_pixel(16 + width, along, shade)
		for x in range(15, 18):
			for y in range(15, 18):
				image.set_pixel(x, y, Color(1.0, 0.25, 0.2))
		_crosshair_texture = ImageTexture.create_from_image(image)
	return _crosshair_texture


## The gun's muzzle and the way it points, and its body: [muzzle, direction,
## body]. Empty if the gun is gone.
func _muzzle(uid: int, record: Dictionary) -> Array:
	var frame: Array = spawner.part_frame(uid)
	if frame.is_empty():
		return []
	var place: Transform3D = frame[0]
	var size_units: Vector3i = record["size"]
	var length: float = Units.to_metres(size_units).z
	var direction: Vector3 = -place.basis.z.normalized()
	# Just clear of the gun's own front face.
	return [place.origin + direction * (length * 0.5 + 0.01), direction, frame[1]]


## A machine gun round: an instant line out to the gun's range. The first
## part on the line takes the damage and the bullet's push.
func _fire_bullet(uid: int, record: Dictionary) -> void:
	var muzzle: Array = _muzzle(uid, record)
	if muzzle.is_empty():
		return
	var from: Vector3 = muzzle[0]
	var direction: Vector3 = muzzle[1]
	var body: RigidBody3D = muzzle[2]
	var props: Dictionary = record.get("props", {})
	var reach: float = maxf(float(props.get("range", 500.0)), 1.0)
	var to: Vector3 = from + direction * reach
	var hit: Dictionary = _cast(from, to)
	if not hit.is_empty():
		to = hit["position"]
		var target := hit["collider"] as RigidBody3D
		if target != null and not target.freeze:
			target.sleeping = false
			target.apply_impulse(direction * BULLET_MASS * BULLET_SPEED, to - target.global_position)
		var part: int = spawner.part_of_shape(hit["collider"], int(hit["shape"]))
		if part != 0:
			_spark(to, spawner.record_of(part))
			spawner.damage_part(part, BULLET_DAMAGE)
		else:
			_damage_structure(hit["collider"], int(hit["shape"]), BULLET_DAMAGE)
	if body != null and not body.freeze:
		body.apply_impulse(-direction * BULLET_MASS * BULLET_SPEED, from - body.global_position)
	_add_tracer(from, to)
	Sound.gun("gunshot", from, -2.0, 30.0)


## A cannon shell: it leaves the muzzle at the speed its energy gives, plus
## the speed of the gun, and flies under gravity until it hits something.
func _fire_shell(uid: int, record: Dictionary) -> void:
	var muzzle: Array = _muzzle(uid, record)
	if muzzle.is_empty():
		return
	var from: Vector3 = muzzle[0]
	var direction: Vector3 = muzzle[1]
	var body: RigidBody3D = muzzle[2]
	var shot: Dictionary = cannon_ballistics(record)
	var mass: float = shot["mass"]
	var speed: float = shot["speed"]
	if mass <= 0.0 or speed <= 0.0:
		return
	var carried := Vector3.ZERO
	if body != null:
		carried = body.linear_velocity + body.angular_velocity.cross(
				from - body.global_transform * body.center_of_mass)
		if not body.freeze:
			body.apply_impulse(-direction * mass * speed, from - body.global_position)
	var node := MeshInstance3D.new()
	node.mesh = _get_shell_mesh()
	var bore: float = shot["bore"]
	node.scale = Vector3.ONE * maxf(bore, 0.02)
	add_child(node)
	node.global_position = from
	_shells.append({"node": node, "at": from, "speed": carried + direction * speed,
			"mass": mass, "life": SHELL_LIFE, "skip": []})
	_add_flash(from, maxf(bore * 6.0, 0.3))
	# Bigger guns are louder and carry further.
	Sound.gun("cannon", from, clampf(linear_to_db(maxf(bore / 0.05, 0.2)), -12.0, 8.0), clampf(bore * 800.0, 30.0, 250.0))


func _run_shells(delta: float) -> void:
	var gravity: Vector3 = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var alive: Array = []
	for item in _shells:
		var shell: Dictionary = item
		var node: Node3D = shell["node"]
		shell["life"] = float(shell["life"]) - delta
		var at: Vector3 = shell["at"]
		if float(shell["life"]) <= 0.0 or at.y < -500.0:
			node.queue_free()
			continue
		var speed: Vector3 = shell["speed"]
		speed += gravity * delta
		var next: Vector3 = at + speed * delta
		shell["speed"] = speed
		if _shell_travels(shell, at, next):
			shell["at"] = next
			node.global_position = next
			alive.append(shell)
		else:
			node.queue_free()
	_shells = alive


## Moves a shell along one tick's path. Every part it hits takes 1 HP per kJ
## the shell carries; a part that cannot stand that is destroyed, the energy
## it took is spent, and the shell goes on. Returns false once it stops.
func _shell_travels(shell: Dictionary, from: Vector3, to: Vector3) -> bool:
	var mass: float = shell["mass"]
	var skip: Array = shell["skip"]   # parts it has already gone through
	var start := from
	for _attempt in 8:
		var hit: Dictionary = _cast(start, to)
		if hit.is_empty():
			return true
		var at: Vector3 = hit["position"]
		var speed: Vector3 = shell["speed"]
		var direction: Vector3 = speed.normalized()
		var part: int = spawner.part_of_shape(hit["collider"], int(hit["shape"]))
		var structure: Node = _structure_of(hit["collider"])
		var piece: Variant = part
		if part == 0 and structure != null:
			piece = structure.piece_id(hit["collider"], int(hit["shape"]))
		if (part != 0 or structure != null) and skip.has(piece):
			# Its collision has not been taken out of the world yet; look past it.
			start = at + direction * 0.002
			continue
		var energy: float = 0.5 * mass * speed.length_squared()
		var target := hit["collider"] as RigidBody3D
		var health: float = 0.0
		var breakable := part != 0
		if part != 0:
			health = spawner.health_of(part)
		elif structure != null:
			health = structure.piece_health(hit["collider"], int(hit["shape"]))
			breakable = health >= 0.0
		var spent: float = energy   # joules taken out of the shell here
		var goes_on := false
		if breakable and health < INF and health * 1000.0 < energy:
			spent = health * 1000.0
			goes_on = true
		var left: float = energy - spent
		var new_speed: Vector3 = Vector3.ZERO
		if goes_on and left > 0.0:
			new_speed = direction * sqrt(2.0 * left / mass)
		# The part gets the momentum the shell lost.
		if target != null and not target.freeze:
			target.sleeping = false
			target.apply_impulse((speed - new_speed) * mass, at - target.global_position)
		if part != 0:
			spawner.damage_part(part, spent * HP_PER_JOULE)
		elif breakable:
			_damage_structure(hit["collider"], int(hit["shape"]), spent * HP_PER_JOULE)
		if not goes_on or new_speed == Vector3.ZERO:
			return false
		skip.append(piece)
		shell["speed"] = new_speed
		start = at + direction * 0.002
	return true


## The first thing on the line from `from` to `to`: a body, a building, a
## tree, or the ground itself. The ground is solid for physics only near the
## character and spawned bodies, so a long shot also checks the map's heights
## directly; a ground hit has no collider.
func _cast(from: Vector3, to: Vector3) -> Dictionary:
	if from.is_equal_approx(to):
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if terrain == null:
		return hit
	var end: Vector3 = to if hit.is_empty() else hit["position"]
	var ground := _ground_hit(from, end)
	if ground.is_empty():
		return hit
	return {"position": ground[0], "collider": null, "shape": -1}


## Where a straight line first goes under the ground, or empty. Steps along
## it every few metres, then narrows the crossing down.
func _ground_hit(from: Vector3, to: Vector3) -> Array:
	var length := from.distance_to(to)
	if length < 0.001:
		return []
	var steps := maxi(1, int(ceil(length / 4.0)))
	var previous := from
	if previous.y < terrain.ground_at(previous):
		return []   # starting underground: leave it to the physics
	for step in range(1, steps + 1):
		var point := from.lerp(to, float(step) / steps)
		if point.y < terrain.ground_at(point):
			var above := previous
			var below := point
			for _narrow in 8:
				var middle := (above + below) * 0.5
				if middle.y < terrain.ground_at(middle):
					below = middle
				else:
					above = middle
			return [above]
		previous = point
	return []


# --- Explosives --------------------------------------------------------------

## An explosive block goes off when its Detonate input is on.
func _run_explosives() -> void:
	var detonate: Array = []
	var gone := false
	for item in _explosives:
		var uid: int = item
		var source: Array = _detonate_source.get(uid, [])
		if source.is_empty():
			var record: Dictionary = spawner.record_of(uid)
			if record.is_empty():
				gone = true
				continue
			var links: Dictionary = record.get("links", {})
			if not links.has("detonate"):
				continue   # goes off only when destroyed
			var link: Dictionary = links["detonate"]
			source = [int(link.get("uid", 0)), str(link.get("output", ""))]
			_detonate_source[uid] = source
		if spawner.is_dead(uid):
			gone = true
			continue
		if spawner.read_output(source[0], source[1], 0.0) != 0.0 and not spawner.is_payload_safe(uid):
			detonate.append(uid)
	for item in detonate:
		var uid: int = item
		spawner.destroy_part(uid)   # its blast follows from _on_part_destroyed
	# Destroyed ones are dropped from the list now and then.
	if gone and Engine.get_physics_frames() % 60 == 0:
		_explosives = _explosives.filter(func(uid: int) -> bool: return not spawner.is_dead(uid))


func _on_part_destroyed(uid: int, type: String, at: Vector3, props: Dictionary) -> void:
	if type != "explosive_block":
		return
	if spawner != null and spawner.is_dropped_payload(uid) and spawner.is_payload_safe(uid):
		# A missile or bomb let go less than its gate's safe time ago is not
		# armed yet: smashed into something close by, it is a dud.
		_add_flash(at, 0.3)
		return
	var radius: float = float(props.get("blast_radius", 2.0))
	if radius > 0.0:
		_pending_blasts.append([at, radius])
	else:
		_add_flash(at, 0.3)


## Sets off the blasts waiting from last tick. Explosives these blasts
## destroy queue up for the tick after.
func _set_off_blasts() -> void:
	if _pending_blasts.is_empty():
		return
	var blasts: Array = _pending_blasts
	_pending_blasts = []
	var damage: Dictionary = {}   # uid -> HP, all blasts this tick together
	# Where every part is, found once for all of this tick's blasts. Bombs
	# and missiles this build has let go are left out: a stream of bombs
	# would otherwise go off one after another up through the stream, back
	# to the bomber that dropped them.
	var places: Array = []   # [uid, world point, body]
	for key in spawner.live_parts():
		var uid: int = key
		if spawner.is_dropped_payload(uid):
			continue
		var place: Array = spawner.part_place(uid)
		if not place.is_empty():
			places.append([uid, place[0], place[1]])
	for item in blasts:
		var blast: Array = item
		var centre: Vector3 = blast[0]
		var radius: float = blast[1]
		var peak: float = BLAST_HP_PER_METRE * radius
		_add_flash(centre, radius * 2.0)
		Birds.startle_all(get_tree(), centre, maxf(radius * 30.0, 60.0))
		Sound.play_at("explosion", centre, clampf(linear_to_db(maxf(radius / 2.0, 0.2)), -8.0, 10.0),
				clampf(radius * 25.0, 40.0, 1500.0), clampf(1.15 - radius * 0.02, 0.6, 1.2))
		for entry in places:
			var uid: int = entry[0]
			var point: Vector3 = entry[1]
			var distance: float = point.distance_to(centre)
			if distance >= radius:
				continue
			var dealt: float = peak * (1.0 - distance / radius)
			damage[uid] = float(damage.get(uid, 0.0)) + dealt
			# The push goes on before the damage, so chunks that break off
			# fly off with it.
			var body: RigidBody3D = entry[2]
			if body != null and not body.freeze:
				var away: Vector3 = point - centre
				if away.length_squared() < 0.000001:
					away = Vector3.UP
				body.sleeping = false
				body.apply_impulse(away.normalized() * dealt * BLAST_PUSH, point - body.global_position)
		for item_structure in structures:
			var structure: Node = item_structure
			for spot in structure.blast(centre, radius, peak):
				_add_dust(spot)
		_hurt_player(centre, radius)
	spawner.damage_parts(damage)


## A blast from outside the build (a lava bomb, a lightning strike): damages
## and pushes this build's parts within `radius` of `centre` (world), as an
## explosive's blast does, but nothing else. disasters.gd deals with the
## buildings and the character once.
func damage_near(centre: Vector3, radius: float, peak: float) -> void:
	if spawner == null or not bool(spawner.spawned):
		return
	var damage: Dictionary = {}
	for key in spawner.live_parts():
		var uid: int = key
		var place: Array = spawner.part_place(uid)
		if place.is_empty():
			continue
		var point: Vector3 = place[0]
		var distance: float = point.distance_to(centre)
		if distance >= radius:
			continue
		var dealt: float = peak * (1.0 - distance / radius)
		damage[uid] = float(damage.get(uid, 0.0)) + dealt
		var body: RigidBody3D = place[1]
		if body != null and not body.freeze:
			var away: Vector3 = point - centre
			if away.length_squared() < 0.000001:
				away = Vector3.UP
			body.sleeping = false
			body.apply_impulse(away.normalized() * dealt * BLAST_PUSH, point - body.global_position)
	spawner.damage_parts(damage)


## A blast hurts the character too, out to half again its radius plus a
## metre: up to 120 HP at the middle.
func _hurt_player(centre: Vector3, radius: float) -> void:
	var someone: Node = get_tree().get_first_node_in_group("player")
	if someone == null or not someone.has_method("hurt"):
		return
	var body := someone as Node3D
	var reach := radius * 1.5 + 1.0
	var distance := (body.global_position + Vector3(0.0, 0.9, 0.0)).distance_to(centre)
	if distance < reach:
		someone.hurt(120.0 * (1.0 - distance / reach), "an explosion")


# --- Buildings and towers ------------------------------------------------------

## The towns or towers node a collider belongs to, or null.
func _structure_of(collider: Object) -> Node:
	if collider == null or not is_instance_valid(collider) or not collider.has_meta("structure"):
		return null
	return collider.get_meta("structure") as Node


func _damage_structure(collider: Object, shape: int, amount: float) -> void:
	var structure: Node = _structure_of(collider)
	if structure == null:
		return
	for spot in structure.damage_piece(collider, shape, amount):
		_add_dust(spot)


## A cloud of dust where something big came down.
func _add_dust(at: Vector3, size: float = 30.0) -> void:
	Sound.play_at("collapse", at, 4.0, 200.0, randf_range(0.85, 1.1))
	var node := MeshInstance3D.new()
	if _dust_mesh == null:
		var ball := SphereMesh.new()
		ball.radius = 0.5
		ball.height = 1.0
		ball.radial_segments = 12
		ball.rings = 6
		ball.material = _glow(Color(0.55, 0.50, 0.45, 0.55))
		_dust_mesh = ball
	node.mesh = _dust_mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = at
	_flashes.append([node, FLASH_LIFE * 5.0, size, FLASH_LIFE * 5.0])


# --- Effects -----------------------------------------------------------------

func _add_tracer(from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	if length < 0.01:
		return
	if _tracers.size() >= MAX_TRACERS:
		var oldest: Array = _tracers.pop_front()
		var old_node: Node = oldest[0]
		old_node.queue_free()
	if _tracer_mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		box.material = _glow(Color(1.0, 0.85, 0.3, 0.9))
		_tracer_mesh = box
	var direction: Vector3 = (to - from) / length
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var look := Basis.looking_at(direction, up)
	var node := MeshInstance3D.new()
	node.mesh = _tracer_mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_transform = Transform3D(Basis(look.x * 0.02, look.y * 0.02, look.z * length),
			(from + to) * 0.5)
	_tracers.append([node, TRACER_LIFE])


func _add_flash(at: Vector3, size: float) -> void:
	if _flash_mesh == null:
		var ball := SphereMesh.new()
		ball.radius = 0.5
		ball.height = 1.0
		ball.radial_segments = 16
		ball.rings = 8
		ball.material = _glow(Color(1.0, 0.55, 0.1, 0.6))
		_flash_mesh = ball
	var node := MeshInstance3D.new()
	node.mesh = _flash_mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = at
	node.scale = Vector3.ONE * size * 0.3
	_flashes.append([node, FLASH_LIFE, size, FLASH_LIFE])


func _fade_effects(delta: float) -> void:
	var tracers: Array = []
	for item in _tracers:
		var tracer: Array = item
		tracer[1] = float(tracer[1]) - delta
		var node: Node = tracer[0]
		if float(tracer[1]) <= 0.0:
			node.queue_free()
		else:
			tracers.append(tracer)
	_tracers = tracers
	var flashes: Array = []
	for item in _flashes:
		var flash: Array = item
		flash[1] = float(flash[1]) - delta
		var node: Node3D = flash[0]
		if float(flash[1]) <= 0.0:
			node.queue_free()
			continue
		# It swells to full size as it fades.
		var done: float = clampf(1.0 - float(flash[1]) / float(flash[3]), 0.0, 1.0)
		node.scale = Vector3.ONE * float(flash[2]) * lerpf(0.3, 1.0, sqrt(done))
		flashes.append(flash)
	_flashes = flashes


func _get_shell_mesh() -> Mesh:
	if _shell_mesh == null:
		var ball := SphereMesh.new()
		ball.radius = 0.5
		ball.height = 1.5
		ball.radial_segments = 10
		ball.rings = 5
		ball.material = _glow(Color(1.0, 0.7, 0.3, 1.0))
		_shell_mesh = ball
	return _shell_mesh


static func _glow(color: Color) -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.albedo_color = color
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return look
