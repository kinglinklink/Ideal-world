extends CharacterBody3D
## The blocky player character and its camera.
##
## Controls: WASD walk, Shift run, Space jump.
## Scroll wheel zooms from first person out to a wide third-person view.
## In third person, hold the right mouse button to turn the camera.
## In first person the mouse always turns the camera; Esc frees the cursor.

const WALK_SPEED := 5.0       # m/s
const RUN_SPEED := 9.0        # m/s
const JUMP_SPEED := 4.5       # m/s, about a 1 m jump
const GRAVITY := 9.81         # m/s^2
const MOUSE_SENSITIVITY := 0.0025
const ZOOM_MAX := 40.0        # metres behind the character
const EYE_HEIGHT := 1.6       # metres
const PITCH_LIMIT := 1.5      # radians

var yaw := 0.0
var pitch := -0.35
var zoom := 6.0               # 0 means first person
var cursor_free := false      # Esc toggles this in first person

var _turning := false         # right mouse button held
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D


func _ready() -> void:
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collider.shape = capsule
	collider.position = Vector3(0.0, 0.9, 0.0)
	add_child(collider)

	_model = _build_model()
	add_child(_model)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(_pivot)

	_camera = Camera3D.new()
	_camera.near = 0.05
	_camera.far = 4000.0
	_camera.fov = 75.0
	_pivot.add_child(_camera)
	_camera.make_current()


func is_first_person() -> bool:
	return zoom < 0.5


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


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
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input.x += 1.0

	var direction := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	var speed := WALK_SPEED
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed = RUN_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if is_on_floor():
		if Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()

	# Turn the body: with the camera in first person, toward travel otherwise.
	if is_first_person():
		_model.rotation.y = yaw
	elif direction.length() > 0.1:
		var target := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target, 1.0 - exp(-12.0 * delta))


func _process(_delta: float) -> void:
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

	model.add_child(_box(Vector3(0.22, 0.75, 0.22), Vector3(-0.13, 0.375, 0.0), trousers))
	model.add_child(_box(Vector3(0.22, 0.75, 0.22), Vector3(0.13, 0.375, 0.0), trousers))
	model.add_child(_box(Vector3(0.52, 0.65, 0.28), Vector3(0.0, 1.075, 0.0), jacket))
	model.add_child(_box(Vector3(0.17, 0.62, 0.20), Vector3(-0.36, 1.09, 0.0), jacket))
	model.add_child(_box(Vector3(0.17, 0.62, 0.20), Vector3(0.36, 1.09, 0.0), jacket))
	model.add_child(_box(Vector3(0.36, 0.36, 0.36), Vector3(0.0, 1.60, 0.0), head))
	model.add_child(_box(Vector3(0.30, 0.10, 0.04), Vector3(0.0, 1.63, -0.19), visor))
	return model


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	var instance := MeshInstance3D.new()
	mesh.material = material
	instance.mesh = mesh
	instance.position = at
	return instance
