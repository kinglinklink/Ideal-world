extends Node3D
## Smoke, fire and scorch marks on damaged builds.
##
## A few times a second every spawned build is looked over. A part below
## half its health smokes lightly and looks scorched; below a quarter it
## pours thick black smoke. Damaged engines (cylinders, turbines,
## combustors, thrusters, rockets) smoke sooner and cough. A fuel tank that
## is hit and still holds fuel catches fire: it burns its fuel, hurts the
## parts round it, and a tank still half full blows up when the fire has
## nearly eaten through it. Water puts fires out. Each part's fire and smoke
## ride on its body, so a burning plane trails smoke.

const Origin = preload("res://scripts/origin.gd")
const Sound = preload("res://scripts/sound.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const FailureLog = preload("res://scripts/failure_log.gd")
const Weather = preload("res://scripts/weather.gd")

const CHECK := 0.25
const MAX_EMITTERS := 32
const ENGINES := ["combustion_cylinder", "turbine", "combustor", "thruster", "compressor", "nozzle", "solid_rocket"]
const BURN_RATE := 0.04            # share of a tank's capacity a fire burns a second
const FIRE_HURT := 0.06            # share of their full health a second, for parts within FIRE_REACH
const FIRE_REACH := 1.6            # m

var _timer := 0.0
var _effects: Dictionary = {}      # "spawner id/uid" -> {"spawner", "uid", "smoke", "level", "fire", "sound", "sputter"}
var _scorch: Array = []            # three overlay materials, light to heavy
var _smoke_mesh: QuadMesh = null
var _fire_mesh: QuadMesh = null


func _ready() -> void:
	for strength in [0.25, 0.45, 0.65]:
		var mark := StandardMaterial3D.new()
		mark.albedo_color = Color(0.05, 0.04, 0.03, strength)
		mark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mark.roughness = 1.0
		_scorch.append(mark)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group("combat"):
		var spawner: Node = node.spawner
		if spawner == null or not bool(spawner.spawned):
			continue
		for key in spawner.live_parts():
			var uid := int(key)
			var full: float = spawner.full_health_of(uid)
			if is_inf(full) or full <= 0.0:
				continue
			var share: float = spawner.health_of(uid) / full
			var record: Dictionary = spawner.record_of(uid)
			var type := str(record.get("type", ""))
			var tank: Dictionary = spawner.engines.tank_of(uid) if spawner.engines != null and type == "fuel_tank" else {}
			var level := 0
			if share < 0.25:
				level = 2
			elif share < 0.5 or (ENGINES.has(type) and share < 0.6):
				level = 1
			var burning := not tank.is_empty() and share < 0.9 and float(tank.get("fuel", 0.0)) > 0.5
			if level == 0 and not burning:
				continue
			var id := "%d/%d" % [spawner.get_instance_id(), uid]
			seen[id] = true
			_update(id, spawner, node, uid, type, level, share, tank, burning, full)
	for id in _effects.keys():
		if not seen.has(id):
			_drop(id)


func _update(id: String, spawner: Node, combat: Node, uid: int, type: String, level: int, share: float,
		tank: Dictionary, burning: bool, full: float) -> void:
	var place: Array = spawner.part_place(uid)
	if place.is_empty():
		_drop(id)
		return
	var body: RigidBody3D = place[1]
	var at: Vector3 = place[0]
	if not _effects.has(id):
		_effects[id] = {"spawner": spawner, "uid": uid, "smoke": null, "level": 0, "fire": null, "sound": null,
				"sputter": randf_range(1.0, 3.0), "scorched": -1}
	var effect: Dictionary = _effects[id]
	# Scorch marks.
	var mark_level := clampi(int((1.0 - share) * 3.0), 0, 2)
	if int(effect["scorched"]) != mark_level:
		effect["scorched"] = mark_level
		for pair in spawner.part_nodes(uid):
			var mesh := (pair as Array)[0] as MeshInstance3D
			if mesh != null and is_instance_valid(mesh):
				mesh.material_overlay = _scorch[mark_level]
	# Smoke.
	if level > 0 and _effects.size() <= MAX_EMITTERS:
		var smoke: GPUParticles3D = effect["smoke"]
		if smoke == null or not is_instance_valid(smoke) or int(effect["level"]) != level:
			if smoke != null and is_instance_valid(smoke):
				smoke.queue_free()
			smoke = _make_smoke(level)
			body.add_child(smoke)
			effect["smoke"] = smoke
			effect["level"] = level
		_attach(smoke, body, at)
	# Engines cough.
	if ENGINES.has(type):
		effect["sputter"] = float(effect["sputter"]) - CHECK
		if float(effect["sputter"]) <= 0.0:
			effect["sputter"] = randf_range(1.5, 4.0)
			Sound.play_at("sputter", at, -2.0, 60.0, randf_range(0.85, 1.15))
	# Fire.
	var wet := at.y < Weather.water_height(at) - 0.2
	if burning and not wet:
		var fire: GPUParticles3D = effect["fire"]
		if fire == null or not is_instance_valid(fire):
			fire = _make_fire(float(tank.get("capacity", 100.0)))
			body.add_child(fire)
			effect["fire"] = fire
			var sound := Sound.make_loop("fire_loop")
			if sound != null:
				sound.unit_size = 8.0
				fire.add_child(sound)
				sound.play()
				effect["sound"] = sound
			Sound.play_at("fire_whoosh", at, 2.0, 120.0)
			FailureLog.note("Fuel tank (part %d) caught fire with %.0f L in it" % [uid, float(tank.get("fuel", 0.0))])
		_attach(fire, body, at)
		var capacity := float(tank.get("capacity", 100.0))
		spawner.engines.drain_tank(uid, capacity * BURN_RATE * CHECK)
		# The fire eats the tank and scorches what is round it.
		var hurt: Dictionary = {uid: full * FIRE_HURT * CHECK}
		for key in spawner.live_parts():
			var other := int(key)
			if other == uid:
				continue
			var other_place: Array = spawner.part_place(other)
			if not other_place.is_empty() and (other_place[0] as Vector3).distance_to(at) < FIRE_REACH + 0.5:
				var other_full: float = spawner.full_health_of(other)
				if not is_inf(other_full):
					hurt[other] = other_full * FIRE_HURT * CHECK
		var left: float = float(spawner.engines.tank_of(uid).get("fuel", 0.0))
		if share < 0.2 and left > capacity * 0.5:
			var radius := clampf(1.5 + capacity / 200.0, 1.5, 8.0)
			FailureLog.note("Fuel tank (part %d) exploded with %.0f L still in it (blast %.1f m)" % [uid, left, radius])
			spawner.engines.drain_tank(uid, left)
			spawner.destroy_part(uid)
			combat.add_blast(at, radius)
			_drop(id)
			return
		spawner.damage_parts(hurt)
	elif effect["fire"] != null:
		if is_instance_valid(effect["fire"]):
			(effect["fire"] as Node).queue_free()
		effect["fire"] = null
		if wet:
			FailureLog.note("Fire on fuel tank (part %d) put out by the water" % uid)


func _attach(node: Node3D, body: RigidBody3D, at: Vector3) -> void:
	if node.get_parent() != body:
		node.get_parent().remove_child(node)
		body.add_child(node)
	node.global_position = at


func _drop(id: String) -> void:
	var effect: Dictionary = _effects.get(id, {})
	for key in ["smoke", "fire"]:
		# Untyped: the node may already be gone along with its part, and a
		# freed node cannot be put in a typed variable.
		var node: Variant = effect.get(key)
		if is_instance_valid(node):
			(node as Node).queue_free()
	_effects.erase(id)


func _make_smoke(level: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 18 if level == 1 else 34
	particles.lifetime = 2.6 if level == 1 else 4.0
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 25.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.5
	process.gravity = Vector3(0.0, 1.2, 0.0)
	process.damping_min = 0.5
	process.damping_max = 1.0
	process.scale_min = 0.6
	process.scale_max = 1.2
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.4))
	growth.add_point(Vector2(1.0, 2.6 if level == 1 else 4.0))
	var growth_texture := CurveTexture.new()
	growth_texture.curve = growth
	process.scale_curve = growth_texture
	var fade := Gradient.new()
	var shade := Color(0.55, 0.55, 0.55) if level == 1 else Color(0.08, 0.08, 0.08)
	fade.set_color(0, Color(shade, 0.55))
	fade.set_color(1, Color(shade, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	particles.process_material = process
	if _smoke_mesh == null:
		_smoke_mesh = QuadMesh.new()
		_smoke_mesh.size = Vector2(1.0, 1.0)
		var look := StandardMaterial3D.new()
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.vertex_color_use_as_albedo = true
		look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_smoke_mesh.material = look
	particles.draw_pass_1 = _smoke_mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


func _make_fire(capacity: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 40
	particles.lifetime = 0.7
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 18.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 4.5
	process.gravity = Vector3(0.0, 3.0, 0.0)
	var size := clampf(0.6 + capacity / 800.0, 0.6, 3.0)
	process.scale_min = size * 0.6
	process.scale_max = size
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = size * 0.4
	var flame := Gradient.new()
	flame.set_color(0, Color(1.0, 0.9, 0.4, 0.95))
	flame.add_point(0.4, Color(1.0, 0.45, 0.08, 0.85))
	flame.set_color(flame.get_point_count() - 1, Color(0.5, 0.1, 0.02, 0.0))
	var flame_texture := GradientTexture1D.new()
	flame_texture.gradient = flame
	process.color_ramp = flame_texture
	particles.process_material = process
	if _fire_mesh == null:
		_fire_mesh = QuadMesh.new()
		_fire_mesh.size = Vector2(1.0, 1.0)
		var look := StandardMaterial3D.new()
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		look.vertex_color_use_as_albedo = true
		look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fire_mesh.material = look
	particles.draw_pass_1 = _fire_mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.0
	light.omni_range = size * 8.0
	light.shadow_enabled = false
	particles.add_child(light)
	return particles
