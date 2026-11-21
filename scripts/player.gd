extends CharacterBody3D
## The blocky player character and its camera.
##
## Controls: WASD walk, Shift run, Space jump. The build tools sit the
## character in a seat (E) and stand it up again (Space).
## Scroll wheel zooms from first person out to a wide third-person view.
## In third person, hold the right mouse button to turn the camera.
## In first person the mouse always turns the camera; Esc frees the cursor.

const Units = preload("res://scripts/units.gd")
const MapInfo = preload("res://scripts/map_info.gd")
const Weather = preload("res://scripts/weather.gd")

const WALK_SPEED := 4.0       # m/s
const RUN_SPEED := 7.5        # m/s
const JUMP_SPEED := 4.0       # m/s, about a 0.8 m jump
const GRAVITY := 9.81         # m/s^2
const AIR_CONTROL := 3.0      # m/s^2 of steering in mid-air; 0 would be a pure throw
const MASS := 70.0            # kg; what the character weighs and pushes with
const PUSH_TIME := 0.25       # seconds over which a push hands over the character's momentum
const G_SMOOTHING := 0.2       # seconds; the g-force readout is averaged over about this long
const GROUND_GRIP := 1.0      # friction coefficient between the feet and the ground or any fixed surface
const SWIM_SPEED := 1.4       # m/s
const SWIM_SPRINT := 2.4      # m/s with Shift
const SWIM_PUSH := 3.0        # m/s^2 a swimmer can push itself through the water
const FLOAT_DEPTH := 1.2      # metres of the body under water when floating: head and shoulders out
const WATER_DRAG := 2.5       # 1/s; how fast the water slows the swimmer
const MOUSE_SENSITIVITY := 0.0025
const ZOOM_MAX := 80.0        # metres behind the character
const BODY_SCALE := 0.85      # the character model is built 1.8 m tall, then shrunk
const EYE_HEIGHT := 1.6 * BODY_SCALE    # metres
const PITCH_LIMIT := 1.5      # radians
const BODY_RADIUS := 0.3 * BODY_SCALE
const BODY_HEIGHT := 1.8 * BODY_SCALE
const HIP_HEIGHT := 0.75 * BODY_SCALE    # from the feet up to the hip joint
const THIGH_HALF := 0.11 * BODY_SCALE    # half the thickness of a leg
const MAX_HP := 100.0
const HURT_WINDOW := 12       # ticks (50 ms) over which a change of speed is measured for injury
const SAFE_G := 20.0          # average g over that window that does no harm
const HURT_RATE := 40.0       # HP per second per g over the safe level
const REGEN_DELAY := 6.0      # seconds after the last hurt before health comes back
const REGEN_RATE := 4.0       # HP per second coming back

## Whether the character can be hurt. The settings change it.
static var damage_enabled := true
## How hard the camera shakes, in metres (earthquakes, eruptions). Set by disasters.gd.
static var camera_shake := 0.0
const WIND_PUSH := 0.5 * 1.2 * 1.0 * 0.7 / MASS   # ½ ρ Cd A / m: how the wind pushes a standing person

signal died(cause: String)
signal hurt_taken(amount: float)

var yaw := 0.0
var pitch := -0.35
var zoom := 8.0               # 0 means first person
var cursor_free := false      # Esc toggles this in first person
var seated := false           # sitting in a seat: no walking until it stands up

var _turning := false         # right mouse button held
var _jump_locked := false     # Space was used to stand up; no jump until it is released
var _floor_body: RigidBody3D = null   # the loose body being stood on, if any
var _floor_point := Vector3.ZERO      # where the feet rest on it, in world space
var _floor_grip := GROUND_GRIP        # friction coefficient of whatever is underfoot
var ride_velocity := Vector3.ZERO     # while seated: the velocity of the seat, for the speed readout
var terrain: Node3D = null            # terrain.gd, for the height of the ground under the camera
var swimming := false                 # in the lake, deeper than standing height
var g_force := 1.0                    # the acceleration the character feels, in g: 1 standing still, 0 in free fall
var _g_velocity := Vector3.ZERO       # the velocity at the last tick, for measuring acceleration
# After a teleport: ticks left in which a platform the character last stood on
# (say a plane it walked onto, then flew away in) may not carry it off.
var _settle_ticks := 0
var _g_skip := true                   # skip one measurement after sitting down or standing up
var hp := MAX_HP                      # health: at 0 the character dies (see main.gd)
var dead := false
var _since_hurt := 100.0              # seconds since the character was last hurt
var _hurt_history: Array = []         # the last HURT_WINDOW + 1 velocities, for injuries
var last_hurt_cause := ""
var _step_offset := 0.0       # smooths the view after stepping up a ledge
var _step_height := 0.55      # tallest ledge the character walks straight up, in metres
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D
var _collider: CollisionShape3D
var _hips: Node3D             # the whole body hangs from here
var _leg_left: Node3D         # each limb hangs from a pivot at its hip or shoulder
var _leg_right: Node3D
var _knee_left: Node3D        # and bends again at the knee or elbow
var _knee_right: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _elbow_left: Node3D
var _elbow_right: Node3D
var _run_blend := 0.0         # 0 walking, 1 running
var _swim_blend := 0.0
var _swim_phase := 0.0
var _walk_phase := 0.0        # where the character is in its stride, in radians
var _walk_blend := 0.0        # 0 standing still, 1 walking
var _air_blend := 0.0         # 0 on the ground, 1 in the air


func _ready() -> void:
	add_to_group("player")
	# Always at least one grid cell, and never less than a tall stair.
	_step_height = maxf(Units.CELL * 1.05, 0.55)
	collision_layer = Units.LAYER_PLAYER
	collision_mask = Units.LAYER_WORLD | Units.LAYER_BODIES

	# A flat-bottomed cylinder stands on block edges more predictably than a capsule.
	var collider := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = BODY_RADIUS
	cylinder.height = BODY_HEIGHT
	collider.shape = cylinder
	collider.position = Vector3(0.0, BODY_HEIGHT * 0.5, 0.0)
	add_child(collider)
	_collider = collider

	_model = _build_model()
	_model.scale = Vector3(BODY_SCALE, BODY_SCALE, BODY_SCALE)
	add_child(_model)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(_pivot)

	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 60000.0   # the far side of the lake and the mountains beyond
	_camera.fov = 75.0
	_pivot.add_child(_camera)
	_camera.make_current()


func is_first_person() -> bool:
	return zoom < 0.5


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## The direction the character's body faces, as a turn about Y in radians.
func get_heading() -> float:
	return _model.rotation.y


## Sits the character down. `cushion` is the world point on top of the seat
## cushion, and `heading` is the way the seat faces, as a turn about Y.
func sit(cushion: Vector3, heading: float) -> void:
	seated = true
	velocity = Vector3.ZERO
	_step_offset = 0.0
	_g_skip = true
	_collider.set_deferred("disabled", true)   # the seat is solid; the sitter is not
	hold_seat(cushion, heading)


## Keeps a seated character on its seat, wherever the seat is.
func hold_seat(cushion: Vector3, heading: float) -> void:
	# The feet are the character's origin; the hips rest on the cushion.
	global_position = cushion - Vector3(0.0, HIP_HEIGHT - THIGH_HALF, 0.0)
	_model.rotation.y = heading


## Gets up. `exit_point` is where the feet go, in world space.
func stand_up(exit_point: Vector3) -> void:
	if not seated:
		return
	seated = false
	_g_skip = true
	_collider.set_deferred("disabled", false)
	global_position = exit_point
	velocity = Vector3.ZERO
	_jump_locked = true   # the Space press that stood us up is not also a jump


## Puts the character down at `at` (its feet, in world space), at rest,
## facing `heading`.
func teleport(at: Vector3, heading: float) -> void:
	global_position = at
	velocity = Vector3.ZERO
	# Godot remembers the last moving platform the character stood on and, on
	# the next step, carries the character along with it and adds its
	# velocity. After a teleport that platform is somewhere else entirely, so
	# for the first few steps the character is held where it was put.
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	_settle_ticks = 3
	yaw = heading
	_model.rotation.y = heading
	_g_skip = true
	_step_offset = 0.0


## The camera's orientation: -Z is where it looks, +X is to its right.
func get_camera_basis() -> Basis:
	return _camera.global_transform.basis


## The ray the build tools aim along: through the cursor, or through the
## screen centre while the mouse is captured. Returns [origin, direction].
func get_pick_ray() -> Array:
	var viewport := get_viewport()
	var screen_point: Vector2 = viewport.get_mouse_position()
	if is_mouse_captured():
		screen_point = viewport.get_visible_rect().size * 0.5
	return [
		_camera.project_ray_origin(screen_point),
		_camera.project_ray_normal(screen_point),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_in()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_out()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_turning = button.pressed
	elif event is InputEventMouseMotion:
		if is_mouse_captured():
			var motion := event as InputEventMouseMotion
			yaw -= motion.relative.x * MOUSE_SENSITIVITY
			pitch = clampf(pitch - motion.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			cursor_free = not cursor_free


func _zoom_in() -> void:
	zoom = zoom / 1.15 - 0.3
	if zoom < 1.0:
		zoom = 0.0


func _zoom_out() -> void:
	if zoom < 1.0:
		zoom = 1.5
	else:
		zoom = minf(ZOOM_MAX, zoom * 1.15 + 0.3)


func _physics_process(delta: float) -> void:
	_run_regen(delta)
	if seated:
		# No walking while seated. The build tools hold the character on its seat.
		velocity = Vector3.ZERO
		_floor_body = null
		_measure_g(ride_velocity, delta)
		return
	ride_velocity = Vector3.ZERO
	if _jump_locked and not Input.is_physical_key_pressed(KEY_SPACE):
		_jump_locked = false

	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input.x += 1.0
	# Ctrl+A, Ctrl+C and friends are tool shortcuts, not walking.
	if Input.is_physical_key_pressed(KEY_CTRL):
		input = Vector2.ZERO
	# While a text box has the keyboard, typing must not walk the character.
	var typing := get_viewport().gui_get_focus_owner() != null
	if typing:
		input = Vector2.ZERO

	var direction := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	var speed := WALK_SPEED
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed = RUN_SPEED
	swimming = _in_deep_water()
	if swimming:
		_swim(direction, typing, delta)
		return
	var grounded := is_on_floor()
	_floor_body = null
	_floor_grip = GROUND_GRIP
	if grounded:
		_floor_body = _find_floor_body()
	# The speed the character is trying to reach. Pushing is worked out from this.
	var wanted := Vector3(direction.x, 0.0, direction.z) * speed
	# The hardest the feet can push sideways: grip x weight. In the air there
	# is nothing to push against, and a push is a plain collision instead.
	var grip_force := INF
	var speed_before := Vector3(velocity.x, 0.0, velocity.z)
	if grounded:
		grip_force = _floor_grip * MASS * GRAVITY
		# The feet change the character's speed only as fast as their grip
		# allows: at most grip x g. On ice that is slow; on a frictionless
		# surface it is nothing at all.
		var reached := speed_before.move_toward(wanted, _floor_grip * GRAVITY * delta)
		velocity.x = reached.x
		velocity.z = reached.z
		if Input.is_physical_key_pressed(KEY_SPACE) and not typing and not _jump_locked:
			velocity.y = JUMP_SPEED
			grounded = false
	else:
		# In the air the character keeps the speed it left the ground with.
		# Holding a direction only nudges it, so a standing jump stays in place.
		if direction.length() > 0.1:
			var flying := Vector2(velocity.x, velocity.z)
			var steer := Vector2(direction.x, direction.z) * speed
			flying = flying.move_toward(steer, AIR_CONTROL * delta)
			velocity.x = flying.x
			velocity.z = flying.y
		velocity.y -= GRAVITY * delta
		wanted = Vector3(velocity.x, 0.0, velocity.z)

	# The wind pushes on the body: nothing on a calm day, a stagger in a gale,
	# and a tornado picks you up.
	var air := Weather.wind_at(global_position + Vector3(0.0, 1.0, 0.0)) - velocity
	if air.length() > 12.0:
		velocity += air * air.length() * WIND_PUSH * delta
	var pushing := Vector3.ZERO   # the total force put on bodies this tick
	# Where the character stood before moving, for undoing a stale platform's
	# carry just after a teleport. Kept relative to this tick only, so it stays
	# right if the world re-centres in between.
	var before_move := global_position
	if grounded and _try_step_up(delta):
		# The step already moved us forward. Settle onto the new floor.
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		velocity = Vector3(0.0, -0.5, 0.0)
		move_and_slide()
		velocity = horizontal
	else:
		move_and_slide()
		pushing = _push_bodies(wanted, grip_force, delta)
	if _settle_ticks > 0:
		_settle_ticks -= 1
		global_position = Vector3(before_move.x, maxf(global_position.y, before_move.y - 0.5), before_move.z)
		velocity = Vector3.ZERO
		_floor_body = null
		pushing = Vector3.ZERO
		if _settle_ticks == 0:
			platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_ADD_VELOCITY
	if _floor_body != null:
		# Whatever the character stands on carries its weight.
		var feet := _floor_point - _floor_body.global_position
		_floor_body.sleeping = false
		_floor_body.apply_force(Vector3(0.0, -MASS * GRAVITY, 0.0), feet)
		# Newton's third law for the feet. Whatever sideways force the feet
		# made this tick, to speed the character up or to push on something,
		# the thing underfoot gets the same force the other way. This is what
		# stops a body being pushed along by someone standing on it.
		var speed_after := Vector3(velocity.x, 0.0, velocity.z)
		var feet_force := (speed_after - speed_before) * (MASS / delta) + pushing
		_floor_body.apply_force(-feet_force.limit_length(grip_force), feet)

	_measure_g(get_real_velocity(), delta)
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-14.0 * delta))

	# Turn the body: with the camera in first person, toward travel otherwise.
	if is_first_person():
		_model.rotation.y = yaw
	elif direction.length() > 0.1:
		var target := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - exp(-12.0 * delta))


## True when the character is in the lake deep enough to float.
func _in_deep_water() -> bool:
	if terrain == null:
		return false
	var depth := Weather.water_height(global_position) - global_position.y
	if depth < FLOAT_DEPTH * 0.8:
		return false
	return terrain.lake_at(global_position)


## Swimming. The body floats with its head and shoulders out (a person is
## about as dense as water, a little less with air in the lungs), the water
## slows every movement, and the arms push at most SWIM_PUSH. Space swims up
## out of the water, for climbing onto a dock or a boat.
func _swim(direction: Vector3, typing: bool, delta: float) -> void:
	_floor_body = null
	var depth := Weather.water_height(global_position) - global_position.y
	# Buoyancy: the deeper the body, the harder the water pushes it up,
	# balancing gravity at FLOAT_DEPTH.
	var lift := GRAVITY * clampf(depth / FLOAT_DEPTH, 0.0, 2.0)
	velocity.y += (lift - GRAVITY) * delta
	if Input.is_physical_key_pressed(KEY_SPACE) and not typing:
		velocity.y += SWIM_PUSH * 2.0 * delta
	velocity *= exp(-WATER_DRAG * delta)
	var top := SWIM_SPRINT if Input.is_physical_key_pressed(KEY_SHIFT) else SWIM_SPEED
	var flat := Vector2(velocity.x, velocity.z)
	flat = flat.move_toward(Vector2(direction.x, direction.z) * top, SWIM_PUSH * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	move_and_slide()
	_measure_g(get_real_velocity(), delta)
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-14.0 * delta))
	if direction.length() > 0.1:
		var target := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - exp(-6.0 * delta))


## Updates the g-force readout from the character's velocity this tick.
## What is felt is acceleration measured against free fall, so standing
## still reads 1 g, falling freely reads 0 g, and a hard turn or pull-up
## reads more. It is smoothed a little so the number can be read.
func _measure_g(moving: Vector3, delta: float) -> void:
	if _g_skip:
		_g_skip = false
		_g_velocity = moving
		_hurt_history.clear()
		return
	var acceleration := (moving - _g_velocity) / delta
	_g_velocity = moving
	var felt := (acceleration + Vector3(0.0, GRAVITY, 0.0)).length() / GRAVITY
	g_force = lerpf(g_force, felt, 1.0 - exp(-delta / G_SMOOTHING))
	_check_injury(moving, delta)


## Injury from hard knocks and crushing turns. The change of speed is
## measured over HURT_WINDOW ticks (50 ms), which irons out jolts from the
## physics; past SAFE_G on average, health drains at HURT_RATE per g over.
## So a fall of about 20 m or a crash at about 25 m/s hurts badly, a fall of
## 60 m or a crash at 35 m/s kills, and a sustained turn past 20 g drains
## health fast.
func _check_injury(moving: Vector3, delta: float) -> void:
	_hurt_history.append(moving)
	if _hurt_history.size() > HURT_WINDOW + 1:
		_hurt_history.pop_front()
	if _hurt_history.size() <= HURT_WINDOW:
		return
	var span := HURT_WINDOW * delta
	var change: Vector3 = (_hurt_history[_hurt_history.size() - 1] as Vector3) - (_hurt_history[0] as Vector3)
	# What is felt: the change of speed less what gravity alone would do.
	var felt: float = (change / span + Vector3(0.0, GRAVITY, 0.0)).length() / GRAVITY
	if felt > SAFE_G:
		hurt((felt - SAFE_G) * HURT_RATE * delta, "a crash" if felt > SAFE_G * 2.0 else "too many g")


## Takes health. At none the character dies: `died` goes out once.
func hurt(amount: float, cause: String) -> void:
	if dead or amount <= 0.0 or not damage_enabled:
		return
	hp = maxf(hp - amount, 0.0)
	_since_hurt = 0.0
	last_hurt_cause = cause
	hurt_taken.emit(amount)
	if hp <= 0.0:
		dead = true
		died.emit(cause)


## Full health again, alive: after a respawn.
func heal_full() -> void:
	hp = MAX_HP
	dead = false
	_since_hurt = 100.0
	_hurt_history.clear()
	_g_skip = true


func _run_regen(delta: float) -> void:
	_since_hurt += delta
	if not dead and _since_hurt > REGEN_DELAY and hp < MAX_HP:
		hp = minf(hp + REGEN_RATE * delta, MAX_HP)


## The model's place in the world, for the replay.
func model_transform() -> Transform3D:
	return _model.global_transform


## A copy of the character's model, for the replay to move about.
func model_copy() -> Node3D:
	var copy: Node3D = _model.duplicate()
	copy.visible = true
	return copy


## The loose (spawned, unanchored) body under the character's feet, or null.
## Also notes how much grip the surface underfoot gives.
func _find_floor_body() -> RigidBody3D:
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, Vector3(0.0, -0.1, 0.0), hit):
		return null
	var body := hit.get_collider() as RigidBody3D
	if body == null:
		return null   # the ground or something else fixed
	if body.physics_material_override != null:
		_floor_grip = body.physics_material_override.friction
	if body.freeze:
		return null   # a spawned body that is fixed in place
	_floor_point = hit.get_position()
	return body


## Pushes the loose bodies the character walked into this tick. Returns the
## total force it put on them.
##
## The push comes from the character's momentum: its mass times the speed at
## which it is closing on the body. Handing that over across PUSH_TIME gives
## the force: 70 kg x 4 m/s / 0.25 s = 1120 N at a walk.
##
## The feet set the limit. A push can never be harder than the grip of the
## feet on whatever is underfoot, `grip_force`: about 687 N on the ground,
## next to nothing on ice. The physics engine then weighs the push against
## the body's own friction, so a light body slides away, a heavy one creeps,
## and one whose friction beats the push stays put. The character is held
## back to the body's speed by the collision itself.
func _push_bodies(wanted: Vector3, grip_force: float, delta: float) -> Vector3:
	var pushed: Array = []
	var total := Vector3.ZERO
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var body := collision.get_collider() as RigidBody3D
		if body == null or body.freeze or body == _floor_body or pushed.has(body):
			continue
		var normal := collision.get_normal()   # points from the body toward the character
		if normal.y > 0.7:
			continue   # standing on it, not pushing it
		var into := Vector3(-normal.x, 0.0, -normal.z)
		if into.length() < 0.2:
			continue
		into = into.normalized()
		# Compare speeds at the point of contact, so a spinning body counts too.
		var arm := collision.get_position() - body.global_position
		var body_velocity := body.linear_velocity + body.angular_velocity.cross(arm)
		var closing := (wanted - body_velocity).dot(into)
		if closing <= 0.0:
			continue   # it is already moving away as fast as the character walks
		var force := MASS * closing / PUSH_TIME
		# Never hand over more in one tick than a dead-stop collision would,
		# or a light body would shoot off faster than the character walks.
		var shared_mass := MASS * body.mass / (MASS + body.mass)
		force = minf(force, 0.5 * shared_mass * closing / delta)
		force = minf(force, grip_force)
		pushed.append(body)
		body.sleeping = false
		body.apply_force(into * force, arm)
		total += into * force
	return total


## True for a spawned body that can be pushed around.
static func _is_loose(thing: Object) -> bool:
	var body := thing as RigidBody3D
	return body != null and not body.freeze


## Climbs a ledge up to _step_height tall when walking into it.
## Works by testing the move in three legs: up, forward, then back down.
func _try_step_up(delta: float) -> bool:
	var forward := Vector3(velocity.x, 0.0, velocity.z) * delta
	if forward.length() < 0.0005:
		return false
	var here := global_transform
	var blocker := KinematicCollision3D.new()
	if not test_move(here, forward, blocker):
		return false   # nothing in the way
	var blocking: Object = blocker.get_collider()
	if _is_loose(blocking) and blocking != _floor_body:
		return false   # a loose body is pushed, not climbed
	var up := Vector3(0.0, _step_height, 0.0)
	if test_move(here, up):
		return false   # no head room
	var raised := here.translated(up)
	if test_move(raised, forward):
		return false   # the obstacle is taller than a step
	var over_ledge := raised.translated(forward)
	var landing := KinematicCollision3D.new()
	if not test_move(over_ledge, -up, landing):
		return false   # nothing to stand on
	if landing.get_normal().y < 0.7:
		return false   # too steep to stand on
	var settled: Vector3 = over_ledge.origin + landing.get_travel()
	var climbed := settled.y - here.origin.y
	if climbed < 0.01:
		return false   # not actually a step; let the normal slide handle it
	global_position = settled
	_step_offset -= climbed
	return true


## Swings the legs and arms in time with the distance covered, so the feet
## keep pace at any speed: knees and elbows bend, and the body leans into a
## run. Sitting folds the knees; in the water the body lies flat and swims a
## crawl, or treads water upright; in the air it holds a spread pose.
## Returns how far the body dips this frame.
func _animate(delta: float) -> float:
	var blend_rate := 1.0 - exp(-10.0 * delta)
	if seated:
		# Thighs forward and level, shins down, hands resting forward.
		_pose(1.45, 1.45, -1.45, -1.45, 0.45, 0.45, 0.7, 0.7, 0.0, 0.95)
		_walk_blend = 0.0
		_air_blend = 0.0
		_swim_blend = 0.0
		return 0.0
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if swimming:
		_swim_blend = lerpf(_swim_blend, 1.0, blend_rate)
		var stroking := clampf(ground_speed / SWIM_SPEED, 0.0, 1.0)
		_swim_phase = fmod(_swim_phase + delta * (1.2 + 2.2 * stroking), TAU)
		var kick := sin(_swim_phase * 3.0) * 0.3
		var lie := lerpf(-0.25, -1.35, stroking)
		# A crawl when moving: each arm goes round in turn. Treading water:
		# the arms scull and the legs pedal.
		var left_arm := lerpf(0.6 + sin(_swim_phase) * 0.5, _swim_phase + PI, stroking)
		var right_arm := lerpf(0.6 - sin(_swim_phase) * 0.5, _swim_phase, stroking)
		_pose(0.2 + kick, 0.2 - kick, -0.4 - kick * (1.0 - stroking), -0.4 + kick * (1.0 - stroking),
				left_arm, right_arm, 0.3, 0.3, lie, lerpf(0.95, 1.35, stroking))
		return 0.0
	_swim_blend = 0.0
	var grounded := is_on_floor()
	var walking := grounded and ground_speed > 0.2
	_walk_blend = lerpf(_walk_blend, 1.0 if walking else 0.0, blend_rate)
	_air_blend = lerpf(_air_blend, 0.0 if grounded else 1.0, 1.0 - exp(-8.0 * delta))
	_run_blend = lerpf(_run_blend, smoothstep(3.0, 6.0, ground_speed) if walking else 0.0, blend_rate)

	# One full stride covers more ground the faster the character moves.
	var stride_length := 1.6 + 0.25 * ground_speed
	_walk_phase = fmod(_walk_phase + ground_speed * delta / stride_length * TAU, TAU)
	var reach := minf(0.35 + 0.05 * ground_speed, 0.9)
	var swing := sin(_walk_phase) * reach * _walk_blend
	# A knee bends as its leg comes forward, more in a run.
	var bend := (0.35 + 0.95 * _run_blend) * _walk_blend
	var knee_left := -0.05 - maxf(cos(_walk_phase), 0.0) * bend
	var knee_right := -0.05 - maxf(-cos(_walk_phase), 0.0) * bend
	var elbow := 0.2 + 1.1 * _run_blend

	# A positive turn about X swings a hanging limb forward.
	_pose(lerpf(swing, 0.45, _air_blend), lerpf(-swing, -0.3, _air_blend),
			lerpf(knee_left, -0.6, _air_blend), lerpf(knee_right, -0.2, _air_blend),
			lerpf(-swing * 0.8, -0.5, _air_blend), lerpf(swing * 0.8, 0.5, _air_blend),
			lerpf(elbow, 0.3, _air_blend), lerpf(elbow, 0.3, _air_blend),
			-0.22 * _run_blend, 0.95)

	# The body dips slightly twice per stride.
	return -absf(sin(_walk_phase)) * (0.04 + 0.03 * _run_blend) * _walk_blend


## Sets every joint: thighs, knees, upper arms, elbows (radians about X),
## then how far the body leans forward and how high the hips are.
func _pose(thigh_l: float, thigh_r: float, knee_l: float, knee_r: float, arm_l: float, arm_r: float,
		elbow_l: float, elbow_r: float, lean: float, hip_height: float) -> void:
	_leg_left.rotation.x = thigh_l
	_leg_right.rotation.x = thigh_r
	_knee_left.rotation.x = knee_l
	_knee_right.rotation.x = knee_r
	_arm_left.rotation.x = arm_l
	_arm_right.rotation.x = arm_r
	_elbow_left.rotation.x = elbow_l
	_elbow_right.rotation.x = elbow_r
	_hips.rotation.x = lean
	_hips.position.y = hip_height


func _process(delta: float) -> void:
	var bob := _animate(delta)
	_model.position.y = _step_offset + bob
	_pivot.position.y = EYE_HEIGHT + _step_offset
	_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, zoom)
	if camera_shake > 0.001:
		_camera.position += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)) * camera_shake
	# Keep a third-person camera from dipping under the ground (but not in a
	# cave, where the ground is overhead).
	if not is_first_person():
		var lifted := _camera.global_position
		var ground := 0.0
		if terrain != null:
			ground = terrain.ground_at(lifted)
		var in_cave: bool = terrain != null and global_position.y < terrain.ground_at(global_position) - 2.0
		if lifted.y < ground + 0.2 and not in_cave:
			lifted.y = ground + 0.2
			_camera.global_position = lifted

	_model.visible = not is_first_person()

	# A release can be missed if it lands on the interface; re-check the button.
	if _turning and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_turning = false

	var want_capture := (is_first_person() and not cursor_free) or _turning
	var wanted_mode := Input.MOUSE_MODE_CAPTURED if want_capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted_mode:
		Input.mouse_mode = wanted_mode


## An original low-poly figure, 1.8 m tall, feet at the origin, facing -Z:
## jointed at the hips, knees, shoulders and elbows, with a simple face.
## Everything hangs from the hips, so leaning or lying flat to swim turns
## the whole body.
func _build_model() -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var jacket := Color(0.95, 0.55, 0.22)
	var trousers := Color(0.20, 0.22, 0.27)
	var skin := Color(0.87, 0.71, 0.58)
	var hair := Color(0.30, 0.21, 0.14)
	var dark := Color(0.08, 0.08, 0.1)
	var boots := Color(0.16, 0.13, 0.11)

	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0.0, 0.95, 0.0)
	model.add_child(_hips)
	_hips.add_child(_box(Vector3(0.34, 0.16, 0.22), Vector3(0.0, 0.0, 0.0), trousers))
	_hips.add_child(_box(Vector3(0.36, 0.05, 0.24), Vector3(0.0, 0.07, 0.0), dark))   # belt

	# Torso: a tapered eight-sided chest, flattened front to back.
	var chest := _part(_tapered(0.2, 0.16, 0.5), Vector3(0.0, 0.33, 0.0), jacket)
	chest.scale = Vector3(1.0, 1.0, 0.62)
	_hips.add_child(chest)
	_hips.add_child(_box(Vector3(0.03, 0.4, 0.02), Vector3(0.0, 0.33, -0.125), jacket.darkened(0.3)))   # zip
	_hips.add_child(_part(_capsule(0.05, 0.12), Vector3(0.0, 0.62, 0.0), skin))   # neck

	# Head, with hair and a face on the front (-Z).
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.66, 0.0)
	_hips.add_child(head)
	var skull := _part(_ball(0.13), Vector3(0.0, 0.13, 0.0), skin)
	skull.scale = Vector3(1.0, 1.12, 1.04)
	head.add_child(skull)
	var top := _part(_ball(0.138), Vector3(0.0, 0.165, 0.018), hair)
	top.scale = Vector3(1.02, 0.95, 1.05)
	head.add_child(top)
	for side in [-1.0, 1.0]:
		head.add_child(_part(_ball(0.018), Vector3(0.046 * side, 0.14, -0.125), dark))             # eyes
		head.add_child(_box(Vector3(0.05, 0.012, 0.01), Vector3(0.048 * side, 0.172, -0.128), hair))  # brows
		head.add_child(_part(_ball(0.03), Vector3(0.132 * side, 0.12, 0.0), skin))                # ears
	head.add_child(_box(Vector3(0.028, 0.045, 0.03), Vector3(0.0, 0.11, -0.14), skin.darkened(0.08)))   # nose
	head.add_child(_box(Vector3(0.06, 0.01, 0.01), Vector3(0.0, 0.065, -0.128), Color(0.45, 0.2, 0.18)))   # mouth

	# Legs: thigh from the hip, shin from the knee, boot.
	_leg_left = _joint(_hips, Vector3(-0.1, -0.04, 0.0))
	_leg_right = _joint(_hips, Vector3(0.1, -0.04, 0.0))
	for leg in [_leg_left, _leg_right]:
		(leg as Node3D).add_child(_part(_capsule(0.08, 0.46), Vector3(0.0, -0.21, 0.0), trousers))
	_knee_left = _joint(_leg_left, Vector3(0.0, -0.43, 0.0))
	_knee_right = _joint(_leg_right, Vector3(0.0, -0.43, 0.0))
	for knee in [_knee_left, _knee_right]:
		(knee as Node3D).add_child(_part(_capsule(0.065, 0.46), Vector3(0.0, -0.21, 0.0), trousers))
		(knee as Node3D).add_child(_box(Vector3(0.11, 0.08, 0.24), Vector3(0.0, -0.44, -0.04), boots))

	# Arms: upper arm from the shoulder, forearm from the elbow, hand.
	_arm_left = _joint(_hips, Vector3(-0.235, 0.53, 0.0))
	_arm_right = _joint(_hips, Vector3(0.235, 0.53, 0.0))
	for arm in [_arm_left, _arm_right]:
		(arm as Node3D).add_child(_part(_ball(0.07), Vector3(0.0, 0.0, 0.0), jacket))   # shoulder
		(arm as Node3D).add_child(_part(_capsule(0.058, 0.34), Vector3(0.0, -0.15, 0.0), jacket))
	_elbow_left = _joint(_arm_left, Vector3(0.0, -0.3, 0.0))
	_elbow_right = _joint(_arm_right, Vector3(0.0, -0.3, 0.0))
	for elbow in [_elbow_left, _elbow_right]:
		(elbow as Node3D).add_child(_part(_capsule(0.05, 0.3), Vector3(0.0, -0.13, 0.0), jacket))
		(elbow as Node3D).add_child(_part(_ball(0.045), Vector3(0.0, -0.3, 0.0), skin))   # hand
	return model


## A joint: a pivot the limb below it turns about.
func _joint(parent: Node3D, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	parent.add_child(pivot)
	return pivot


func _capsule(radius: float, height: float) -> Mesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 2
	return mesh


func _ball(radius: float) -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	return mesh


func _tapered(top: float, bottom: float, height: float) -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	return mesh


func _part(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	return instance


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(mesh, at, color)
