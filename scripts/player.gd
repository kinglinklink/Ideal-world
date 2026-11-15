extends CharacterBody3D
## The blocky player character and its camera.
##
## Controls: WASD walk, Shift run, Space jump. The build tools sit the
## character in a seat (E) and stand it up again (Space or E).
## Scroll wheel zooms from first person out to a wide third-person view.
## In third person, hold the right mouse button to turn the camera.
## In first person the mouse always turns the camera; Esc frees the cursor.

const Units = preload("res://scripts/units.gd")

const WALK_SPEED := 4.0       # m/s
const RUN_SPEED := 7.5        # m/s
const JUMP_SPEED := 4.0       # m/s, about a 0.8 m jump
const GRAVITY := 9.81         # m/s^2
const AIR_CONTROL := 3.0      # m/s^2 of steering in mid-air; 0 would be a pure throw
const MOUSE_SENSITIVITY := 0.0025
const ZOOM_MAX := 80.0        # metres behind the character
const BODY_SCALE := 0.85      # the character model is built 1.8 m tall, then shrunk
const EYE_HEIGHT := 1.6 * BODY_SCALE    # metres
const PITCH_LIMIT := 1.5      # radians
const BODY_RADIUS := 0.3 * BODY_SCALE
const BODY_HEIGHT := 1.8 * BODY_SCALE
const HIP_HEIGHT := 0.75 * BODY_SCALE    # from the feet up to the hip joint
const THIGH_HALF := 0.11 * BODY_SCALE    # half the thickness of a leg

var yaw := 0.0
var pitch := -0.35
var zoom := 8.0               # 0 means first person
var cursor_free := false      # Esc toggles this in first person
var seated := false           # sitting in a seat: no walking until it stands up

var _turning := false         # right mouse button held
var _jump_locked := false     # Space was used to stand up; no jump until it is released
var _step_offset := 0.0       # smooths the view after stepping up a ledge
var _step_height := 0.55      # tallest ledge the character walks straight up, in metres
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D
var _collider: CollisionShape3D
var _leg_left: Node3D         # each limb hangs from a pivot at its hip or shoulder
var _leg_right: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _walk_phase := 0.0        # where the character is in its stride, in radians
var _walk_blend := 0.0        # 0 standing still, 1 walking
var _air_blend := 0.0         # 0 on the ground, 1 in the air


func _ready() -> void:
	# Always at least one grid cell, and never less than a tall stair.
	_step_height = maxf(Units.CELL * 1.05, 0.55)

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
	_camera.far = 6000.0
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
	_collider.set_deferred("disabled", false)
	global_position = exit_point
	velocity = Vector3.ZERO
	_jump_locked = true   # the Space press that stood us up is not also a jump


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
	if seated:
		# No walking while seated. The build tools hold the character on its seat.
		velocity = Vector3.ZERO
		return
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
	var grounded := is_on_floor()
	if grounded:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if Input.is_physical_key_pressed(KEY_SPACE) and not typing and not _jump_locked:
			velocity.y = JUMP_SPEED
			grounded = false
	else:
		# In the air the character keeps the speed it left the ground with.
		# Holding a direction only nudges it, so a standing jump stays in place.
		if direction.length() > 0.1:
			var flying := Vector2(velocity.x, velocity.z)
			var wanted := Vector2(direction.x, direction.z) * speed
			flying = flying.move_toward(wanted, AIR_CONTROL * delta)
			velocity.x = flying.x
			velocity.z = flying.y
		velocity.y -= GRAVITY * delta

	if grounded and _try_step_up(delta):
		# The step already moved us forward. Settle onto the new floor.
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		velocity = Vector3(0.0, -0.5, 0.0)
		move_and_slide()
		velocity = horizontal
	else:
		move_and_slide()

	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-14.0 * delta))

	# Turn the body: with the camera in first person, toward travel otherwise.
	if is_first_person():
		_model.rotation.y = yaw
	elif direction.length() > 0.1:
		var target := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - exp(-12.0 * delta))


## Climbs a ledge up to _step_height tall when walking into it.
## Works by testing the move in three legs: up, forward, then back down.
func _try_step_up(delta: float) -> bool:
	var forward := Vector3(velocity.x, 0.0, velocity.z) * delta
	if forward.length() < 0.0005:
		return false
	var here := global_transform
	if not test_move(here, forward):
		return false   # nothing in the way
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
## keep pace at any speed, and holds a spread pose in the air.
func _animate(delta: float) -> float:
	if seated:
		# Thighs forward and level, hands resting forward.
		_leg_left.rotation.x = 1.45
		_leg_right.rotation.x = 1.45
		_arm_left.rotation.x = 0.5
		_arm_right.rotation.x = 0.5
		_walk_blend = 0.0
		_air_blend = 0.0
		return 0.0
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()
	var walking := grounded and ground_speed > 0.2
	_walk_blend = lerpf(_walk_blend, 1.0 if walking else 0.0, 1.0 - exp(-10.0 * delta))
	_air_blend = lerpf(_air_blend, 0.0 if grounded else 1.0, 1.0 - exp(-8.0 * delta))

	# One full stride covers more ground the faster the character moves.
	var stride_length := 1.6 + 0.25 * ground_speed
	_walk_phase = fmod(_walk_phase + ground_speed * delta / stride_length * TAU, TAU)
	var reach := minf(0.35 + 0.05 * ground_speed, 0.9)
	var swing := sin(_walk_phase) * reach * _walk_blend

	# A positive turn about X swings a hanging limb forward.
	_leg_left.rotation.x = lerpf(swing, 0.45, _air_blend)
	_leg_right.rotation.x = lerpf(-swing, -0.3, _air_blend)
	_arm_left.rotation.x = lerpf(-swing * 0.8, -0.5, _air_blend)
	_arm_right.rotation.x = lerpf(swing * 0.8, 0.5, _air_blend)

	# The body dips slightly twice per stride.
	return -absf(sin(_walk_phase)) * 0.04 * _walk_blend


func _process(delta: float) -> void:
	var bob := _animate(delta)
	_model.position.y = _step_offset + bob
	_pivot.position.y = EYE_HEIGHT + _step_offset
	_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_camera.position = Vector3(0.0, 0.0, zoom)
	# Keep a third-person camera from dipping under the ground plane.
	if not is_first_person() and _camera.global_position.y < 0.2:
		var lifted := _camera.global_position
		lifted.y = 0.2
		_camera.global_position = lifted

	_model.visible = not is_first_person()

	# A release can be missed if it lands on the interface; re-check the button.
	if _turning and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_turning = false

	var want_capture := (is_first_person() and not cursor_free) or _turning
	var wanted_mode := Input.MOUSE_MODE_CAPTURED if want_capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != wanted_mode:
		Input.mouse_mode = wanted_mode


## An original blocky figure, 1.8 m tall, feet at the origin, facing -Z.
func _build_model() -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var jacket := Color(0.95, 0.55, 0.22)
	var trousers := Color(0.20, 0.22, 0.27)
	var head := Color(0.86, 0.88, 0.92)
	var visor := Color(0.10, 0.13, 0.18)

	_leg_left = _limb(model, Vector3(-0.13, 0.75, 0.0), Vector3(0.22, 0.75, 0.22), trousers)
	_leg_right = _limb(model, Vector3(0.13, 0.75, 0.0), Vector3(0.22, 0.75, 0.22), trousers)
	model.add_child(_box(Vector3(0.52, 0.65, 0.28), Vector3(0.0, 1.075, 0.0), jacket))
	_arm_left = _limb(model, Vector3(-0.36, 1.40, 0.0), Vector3(0.17, 0.62, 0.20), jacket)
	_arm_right = _limb(model, Vector3(0.36, 1.40, 0.0), Vector3(0.17, 0.62, 0.20), jacket)
	model.add_child(_box(Vector3(0.36, 0.36, 0.36), Vector3(0.0, 1.60, 0.0), head))
	model.add_child(_box(Vector3(0.30, 0.10, 0.04), Vector3(0.0, 1.63, -0.19), visor))
	return model


## A limb that hangs from a joint and swings about it.
func _limb(model: Node3D, joint: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = joint
	pivot.add_child(_box(size, Vector3(0.0, -size.y * 0.5, 0.0), color))
	model.add_child(pivot)
	return pivot


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	return instance
