extends Node3D
## The test stand, a second pad beside the hangar for testing a build
## without flying it. "Test stand" in the build bar spawns the build here,
## lifted onto the balance and held fixed in space (its heaviest body is
## held; wheels, shafts and control surfaces still move on their joints).
##
## Dyno. Start the engine or motor (hold its keys if it needs them) and press
## Run. The stand finds the fastest-turning shaft and brakes it, harder and
## harder, recording the torque (which the brake knows exactly, as it is the
## brake's own) and the rpm, and so the power, until the shaft all but
## stops. A torque curve and a power curve against rpm.
##
## Wind tunnel. Set an airspeed (0 to 750 m/s) and a range of angles of
## attack. The stand blows the air past the build at each angle in turn,
## lets it settle and reads the balance: lift (square to the airflow, up),
## drag (along it), side force and pitching moment (nose up positive, about
## the held body's centre of mass), and plots lift against drag. The build's
## front is the way its seat faces, or -Z with no seat.
##
## Both save their numbers as CSV in the "logs" folder beside "saves".

const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Weather = preload("res://scripts/weather.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Aero = preload("res://scripts/aero.gd")

const SIZE := 24.0                # metres across the slab
const LIFT := 1.5                 # metres the build is held above the slab
const TUNNEL_RADIUS := 70.0       # metres round the stand where the tunnel's air blows
const SPIN_UP := 2.0              # seconds the dyno watches before it picks a shaft
const SAMPLE := 0.1               # seconds between dyno samples
const SETTLE := 0.6               # seconds the tunnel waits at each angle before reading
const MEASURE := 0.5              # seconds it reads for
const MAX_AIRSPEED := 750.0

var spawner: Node = null          # spawner.gd
var controller: Node = null       # build_controller.gd
var grid: Node3D = null           # build_grid.gd
var terrain: Node = null          # terrain.gd
var game_hud: Node = null
var player: Node = null

var centre := Vector3.ZERO        # the middle of the slab's top, in main's space (set in setup)
var on_stand := false
var mode := ""                    # "", "dyno" or "tunnel"
var results: Array = []           # the last run's rows
var last_csv := ""

var _ui: CanvasLayer
var _status: Label
var _dyno_chart: Control
var _tunnel_chart: Control
var _speed_box: SpinBox
var _from_box: SpinBox
var _to_box: SpinBox
var _step_box: SpinBox
var _timer := 0.0
var _clock := 0.0
# Dyno
var _shaft: Dictionary = {}       # the turner being braked
var _shaft_body: RigidBody3D = null
var _brake := 0.0                 # N m
var _brake_rate := 1.0            # N m per second
var _free_rpm := 0.0
var _giving := false              # the shaft has begun to slow under the brake
var _hinted := false              # a motor's max torque set the pace
var _spin_sum := 0.0
var _spin_count := 0
# Tunnel
var _angles: Array = []
var _angle_index := 0
var _measuring := false


## Builds the slab beside the pad: `pad_size` is the build pad's size.
func setup(pad_size: Vector3) -> void:
	var middle := Vector2(pad_size.x + 8.0 + SIZE * 0.5, pad_size.z * 0.5)
	var highest := 0.0
	var lowest := 0.0
	if terrain != null:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
			var spot: Vector2 = middle + corner * SIZE * 0.5
			var ground: float = terrain.height_at(spot.x, spot.y)
			highest = maxf(highest, ground)
			lowest = minf(lowest, ground)
	var top := highest + 0.3
	centre = Vector3(middle.x, top, middle.y)
	_build_slab(top, lowest - 2.0)
	_build_ui()


func _build_slab(top: float, bottom: float) -> void:
	var slab := StaticBody3D.new()
	slab.name = "TestStandSlab"
	slab.collision_layer = Units.LAYER_WORLD
	add_child(slab)
	var depth := top - bottom
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE, depth, SIZE)
	shape.shape = box
	shape.position = Vector3(centre.x, top - depth * 0.5, centre.z)
	slab.add_child(shape)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.62, 0.62, 0.6)
	concrete.roughness = 0.95
	_box(slab, Vector3(SIZE, depth, SIZE), Vector3(centre.x, top - depth * 0.5, centre.z), concrete)
	# Yellow and black edges.
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.95, 0.78, 0.1)
	for side in 4:
		var along := Vector3(SIZE, 0.02, 0.4) if side < 2 else Vector3(0.4, 0.02, SIZE)
		var at := Vector3(0.0, 0.0, (SIZE * 0.5 - 0.3) * (1.0 if side == 0 else -1.0)) if side < 2 \
				else Vector3((SIZE * 0.5 - 0.3) * (1.0 if side == 2 else -1.0), 0.0, 0.0)
		_box(slab, along, centre + at + Vector3(0.0, 0.01, 0.0), stripe)
	# The balance: a steel column under where the build is held.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.35, 0.37, 0.4)
	steel.metallic = 0.8
	steel.roughness = 0.4
	_box(slab, Vector3(0.6, LIFT - 0.1, 0.6), centre + Vector3(0.0, (LIFT - 0.1) * 0.5, 0.0), steel)
	_box(slab, Vector3(1.6, 0.1, 1.6), centre + Vector3(0.0, 0.05, 0.0), steel)
	# The tunnel's fan, at the front edge, blowing back over the slab.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.0
	torus.outer_radius = 5.8
	torus.rings = 32
	ring.mesh = torus
	ring.material_override = steel
	ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	ring.position = centre + Vector3(0.0, 5.8, -SIZE * 0.5 + 0.6)
	slab.add_child(ring)
	var board := Label3D.new()
	board.text = "TEST STAND\nDyno and wind tunnel"
	board.font_size = 96
	board.pixel_size = 0.01
	board.outline_size = 16
	board.position = centre + Vector3(0.0, 12.5, -SIZE * 0.5 + 0.6)
	board.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	slab.add_child(board)


func _box(parent: Node3D, size: Vector3, at: Vector3, look: Material) -> void:
	var shown := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	shown.mesh = mesh
	shown.material_override = look
	shown.position = at
	parent.add_child(shown)


# --- Putting a build on the stand ---------------------------------------------------

## Spawns the build on the stand and holds it. Returns false if it can't.
func open_stand() -> bool:
	if controller == null or grid == null or spawner == null or bool(controller.spawned):
		return false
	if grid.part_count() == 0:
		_say("There is nothing to test. Place some parts first.")
		return false
	var bounds := AABB()
	var first := true
	for uid in grid.all_uids():
		var part_bounds := BuildGrid.bounds_of(grid.get_part(uid))
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	var saved: Transform3D = grid.global_transform
	var bottom_middle := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var target: Vector3 = global_transform * (centre + Vector3(0.0, LIFT, 0.0))
	grid.global_transform = Transform3D(saved.basis, target - saved.basis * bottom_middle)
	controller.toggle_spawn()
	grid.global_transform = saved
	if not bool(controller.spawned):
		return false
	spawner.hold(spawner.heaviest_body())
	on_stand = true
	mode = ""
	_ui.visible = true
	_status.text = "On the stand. Choose a test."
	if player != null:
		player.cursor_free = true
	return true


## Ends any test and puts the build back on the pad.
func close_stand() -> void:
	_stop()
	on_stand = false
	_ui.visible = false
	if spawner != null:
		spawner.hold(null)
	if controller != null and bool(controller.spawned):
		controller.toggle_spawn()


func _stop() -> void:
	mode = ""
	Weather.tunnel_radius = 0.0
	Weather.tunnel_air = Vector3.ZERO
	_shaft = {}
	_shaft_body = null
	_brake = 0.0


# --- The dyno -------------------------------------------------------------------------

func start_dyno() -> void:
	if not on_stand:
		return
	_stop()
	mode = "dyno"
	results = []
	_timer = 0.0
	_status.text = "Watching for a turning shaft..."
	_dyno_chart.set("series", [])
	_dyno_chart.queue_redraw()


func _run_dyno(delta: float) -> void:
	var held: RigidBody3D = spawner.held_body
	if _shaft.is_empty():
		_timer += delta
		if _timer < SPIN_UP:
			return
		# The fastest-turning joint with the held body on one side.
		var best_spin := 0.0
		for item in spawner.turners():
			var turner: Dictionary = item
			var a: RigidBody3D = spawner.piece_body(turner["a"])
			var b: RigidBody3D = spawner.piece_body(turner["b"])
			if a == null or b == null or (a != held and b != held):
				continue
			if absf(float(turner["spin"])) > best_spin:
				best_spin = absf(float(turner["spin"]))
				_shaft = turner
				_shaft_body = b if a == held else a
		_free_rpm = best_spin * 60.0 / TAU
		if _shaft.is_empty() or _free_rpm < 5.0:
			_say("Nothing is turning. Start the engine or motor (hold its keys if it needs them), then Run again.")
			_status.text = "No turning shaft found."
			_stop()
			return
		# Brake slowly enough to read the curve: a motor's own limit sets the pace.
		var strongest := 0.0
		for item in spawner.turners():
			if str(item["role"]) in ["motor", "servo"]:
				strongest = maxf(strongest, float(item["grip"]))
		_hinted = strongest > 0.0
		_brake_rate = strongest / 15.0 if _hinted else 2.0
		_brake = 0.0
		_giving = false
		_timer = 0.0
		_spin_sum = 0.0
		_spin_count = 0
		_status.text = "Braking part %d from %.0f rpm..." % [int(_shaft["uid"]), _free_rpm]
		return
	if _shaft_body == null or not is_instance_valid(_shaft_body):
		_finish_dyno("The shaft broke off.")
		return
	var a_body: RigidBody3D = spawner.piece_body(_shaft["a"])
	if a_body == null:
		_finish_dyno("The shaft broke off.")
		return
	var axis: Vector3 = (a_body.global_transform.basis * (_shaft["axis"] as Vector3)).normalized()
	var spin := _shaft_body.angular_velocity.dot(axis)
	# The brake: against the turning, on the shaft; its other half is the stand.
	_shaft_body.apply_torque(-axis * signf(spin) * _brake)
	_shaft_body.sleeping = false
	_spin_sum += absf(spin)
	_spin_count += 1
	_timer += delta
	if _timer < SAMPLE:
		return
	var rpm := _spin_sum / maxi(_spin_count, 1) * 60.0 / TAU
	results.append([rpm, _brake, _brake * rpm * TAU / 60.0])
	_timer = 0.0
	_spin_sum = 0.0
	_spin_count = 0
	_dyno_chart.set("series", [_column(results, 0, 1), _column(results, 0, 2)])
	_dyno_chart.queue_redraw()
	_status.text = "%.0f rpm at %.1f N·m (%.2f kW)" % [rpm, _brake, _brake * rpm * TAU / 60.0 / 1000.0]
	# Speed up the sweep while nothing gives, and slow it right down once the
	# shaft starts to give, so the curve is read close to steady running.
	# Stop when the shaft all but stops.
	if rpm > 0.97 * _free_rpm:
		if not _hinted and results.size() % 15 == 0:
			_brake_rate *= 2.0
	elif not _giving:
		_giving = true
		_brake_rate *= 0.2
	_brake += _brake_rate * SAMPLE
	if rpm < maxf(0.05 * _free_rpm, 2.0) or results.size() > 900:
		_finish_dyno("")


func _finish_dyno(problem: String) -> void:
	var peak_torque := 0.0
	var peak_power := 0.0
	var power_rpm := 0.0
	for row in results:
		peak_torque = maxf(peak_torque, float(row[1]))
		if float(row[2]) > peak_power:
			peak_power = float(row[2])
			power_rpm = float(row[0])
	last_csv = _save_csv("dyno", ["rpm", "torque_Nm", "power_W"], results)
	_status.text = "%sPeak torque %.1f N·m, peak power %.2f kW at %.0f rpm. Saved %s" % [
			problem + " " if problem != "" else "", peak_torque, peak_power / 1000.0, power_rpm, last_csv.get_file()]
	_stop()


# --- The wind tunnel ------------------------------------------------------------------

func start_tunnel(airspeed: float = -1.0, from_deg: float = NAN, to_deg: float = NAN, step_deg: float = NAN) -> void:
	if not on_stand:
		return
	_stop()
	if airspeed >= 0.0:
		_speed_box.value = airspeed
	if not is_nan(from_deg):
		_from_box.value = from_deg
	if not is_nan(to_deg):
		_to_box.value = to_deg
	if not is_nan(step_deg):
		_step_box.value = step_deg
	_angles = []
	var angle := _from_box.value
	var step := maxf(absf(_step_box.value), 0.5)
	while angle <= _to_box.value + 0.001:
		_angles.append(angle)
		angle += step
	mode = "tunnel"
	results = []
	_angle_index = 0
	_timer = 0.0
	_measuring = false
	_tunnel_chart.set("series", [])
	_tunnel_chart.queue_redraw()


## The build's own axes: [forward, up, right], in the world.
func build_axes() -> Array:
	var held: RigidBody3D = spawner.held_body
	var basis: Basis = held.global_transform.basis if held != null else Basis.IDENTITY
	var forward := -basis.z
	for key in spawner.all_records():
		var record: Dictionary = spawner.record_of(key)
		if not record.is_empty() and str(record["type"]) == "seat":
			forward = basis * -((record["rot"] as Basis).z)
			break
	var up := basis.y
	forward = (forward - up * forward.dot(up)).normalized()
	return [forward, up, forward.cross(up).normalized()]


## The air's velocity at an angle of attack: from in front, and from below
## for a positive angle.
func air_at(angle_deg: float, airspeed: float) -> Vector3:
	var axes := build_axes()
	var a := deg_to_rad(angle_deg)
	return (-(axes[0] as Vector3) * cos(a) + (axes[1] as Vector3) * sin(a)) * airspeed


## Lift, drag, side force and pitching moment from a balance reading.
func resolve(force: Vector3, moment: Vector3, angle_deg: float) -> Array:
	var axes := build_axes()
	var forward: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var right: Vector3 = axes[2]
	var a := deg_to_rad(angle_deg)
	var along_air := -forward * cos(a) + up * sin(a)
	var lift_way := up * cos(a) + forward * sin(a)
	return [force.dot(lift_way), force.dot(along_air), force.dot(right), moment.dot(right)]


func _run_tunnel(delta: float) -> void:
	if _angle_index >= _angles.size():
		_finish_tunnel()
		return
	var angle: float = _angles[_angle_index]
	Weather.tunnel_centre = Origin.to_map(global_transform * centre)
	Weather.tunnel_radius = TUNNEL_RADIUS
	Weather.tunnel_air = air_at(angle, _speed_box.value)
	_timer += delta
	if not _measuring:
		if _timer >= SETTLE:
			spawner.read_balance()   # start the reading afresh
			_measuring = true
			_timer = 0.0
		return
	if _timer < MEASURE:
		return
	var reading: Array = spawner.read_balance()
	var parts := resolve(reading[0], reading[1], angle)
	var lift: float = parts[0]
	var drag: float = parts[1]
	results.append([angle, _speed_box.value, lift, drag, parts[2], parts[3], lift / drag if absf(drag) > 1e-6 else 0.0])
	_tunnel_chart.set("series", [_column(results, 3, 2)])
	_tunnel_chart.set("tags", _column(results, 3, 0))
	_tunnel_chart.queue_redraw()
	_status.text = "%.1f°: lift %.0f N, drag %.0f N" % [angle, lift, drag]
	_angle_index += 1
	_measuring = false
	_timer = 0.0


func _finish_tunnel() -> void:
	var best := -INF
	var best_angle := 0.0
	for row in results:
		if float(row[6]) > best:
			best = float(row[6])
			best_angle = float(row[0])
	last_csv = _save_csv("tunnel", ["angle_deg", "airspeed_ms", "lift_N", "drag_N", "side_N", "pitch_moment_Nm", "lift_over_drag"], results)
	_status.text = "Best L/D %.1f at %.1f°. Saved %s" % [best, best_angle, last_csv.get_file()]
	_stop()


# --- Every tick -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	if not on_stand:
		return
	if spawner == null or not bool(spawner.spawned):
		# Put back on the pad some other way (Build, a respawn).
		_stop()
		on_stand = false
		_ui.visible = false
		return
	if mode == "dyno":
		_run_dyno(delta)
	elif mode == "tunnel":
		_run_tunnel(delta)


# --- Results ----------------------------------------------------------------------------

static func logs_dir() -> String:
	return SaveManager.saves_dir().get_base_dir().path_join("logs")


func _save_csv(kind: String, header: Array, rows: Array) -> String:
	DirAccess.make_dir_recursive_absolute(logs_dir())
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := logs_dir().path_join("%s_%s.csv" % [kind, stamp])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_line(",".join(header))
	for row in rows:
		var cells: Array = []
		for value in row:
			cells.append("%.4f" % float(value))
		file.store_line(",".join(cells))
	file.close()
	return path


static func _column(rows: Array, x: int, y: int) -> Array:
	var points: Array = []
	for row in rows:
		points.append(Vector2(float(row[x]), float(row[y])))
	return points


func _say(text: String) -> void:
	if game_hud != null:
		game_hud.announce("", text, 3.0)


# --- The panel --------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 40
	_ui.visible = false
	add_child(_ui)
	var panel := PanelContainer.new()
	panel.offset_left = 12
	panel.offset_right = 452
	panel.offset_top = 150
	_ui.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Test stand"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(420, 380)
	column.add_child(tabs)

	var dyno := VBoxContainer.new()
	dyno.name = "Dyno"
	tabs.add_child(dyno)
	dyno.add_child(_words("Start the engine or motor (hold its keys if it needs them), then Run. The stand brakes the fastest-turning shaft harder and harder and records torque and power against rpm."))
	var run_dyno := Button.new()
	run_dyno.text = "Run the dyno"
	run_dyno.pressed.connect(start_dyno)
	dyno.add_child(run_dyno)
	_dyno_chart = Chart.new()
	_dyno_chart.set("x_name", "rpm")
	_dyno_chart.set("names", ["torque (N·m)", "power (W)"])
	_dyno_chart.custom_minimum_size = Vector2(400, 220)
	dyno.add_child(_dyno_chart)

	var tunnel := VBoxContainer.new()
	tunnel.name = "Wind tunnel"
	tabs.add_child(tunnel)
	tunnel.add_child(_words("Blows air past the build at each angle of attack in turn and reads lift, drag, side force and pitching moment."))
	var settings := GridContainer.new()
	settings.columns = 4
	tunnel.add_child(settings)
	_speed_box = _number_box(settings, "Airspeed m/s", 0.0, MAX_AIRSPEED, 50.0, 1.0)
	_step_box = _number_box(settings, "Step °", 0.5, 10.0, 2.0, 0.5)
	_from_box = _number_box(settings, "From °", -45.0, 45.0, -6.0, 0.5)
	_to_box = _number_box(settings, "To °", -45.0, 60.0, 20.0, 0.5)
	var run_tunnel := Button.new()
	run_tunnel.text = "Run the sweep"
	run_tunnel.pressed.connect(func() -> void: start_tunnel())
	tunnel.add_child(run_tunnel)
	_tunnel_chart = Chart.new()
	_tunnel_chart.set("x_name", "drag (N)")
	_tunnel_chart.set("names", ["lift (N)"])
	_tunnel_chart.custom_minimum_size = Vector2(400, 200)
	tunnel.add_child(_tunnel_chart)

	_status = _words("")
	column.add_child(_status)
	var row := HBoxContainer.new()
	column.add_child(row)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(func() -> void:
		_stop()
		_status.text = "Stopped.")
	row.add_child(stop)
	var leave := Button.new()
	leave.text = "Back to the pad"
	leave.pressed.connect(close_stand)
	row.add_child(leave)
	var folder := Button.new()
	folder.text = "Open logs folder"
	folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(logs_dir())
		OS.shell_open(logs_dir()))
	row.add_child(folder)


func _words(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(400, 0)
	return label


func _number_box(parent: Control, caption: String, lowest: float, highest: float, start: float, step: float) -> SpinBox:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var box := SpinBox.new()
	box.min_value = lowest
	box.max_value = highest
	box.step = step
	box.value = start
	parent.add_child(box)
	return box


## A small line chart: one or two series against a shared x, each on its own
## scale (the second on the right), with points tagged if tags are given.
class Chart:
	extends Control
	var series: Array = []      # Arrays of Vector2
	var names: Array = []
	var tags: Array = []        # Vector2(x, tag) for the first series' points
	var x_name := ""
	const COLOURS := [Color(0.35, 0.75, 1.0), Color(1.0, 0.6, 0.25)]

	func _draw() -> void:
		var area := Rect2(Vector2(44, 8), size - Vector2(88, 34))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09, 0.9))
		draw_rect(area, Color(0.4, 0.4, 0.45), false)
		var font := get_theme_default_font()
		if series.is_empty() or (series[0] as Array).size() < 1:
			draw_string(font, area.position + Vector2(10, 20), "No data yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			return
		var low_x := INF
		var high_x := -INF
		for points in series:
			for point in points:
				low_x = minf(low_x, (point as Vector2).x)
				high_x = maxf(high_x, (point as Vector2).x)
		if high_x - low_x < 1e-6:
			high_x = low_x + 1.0
		draw_string(font, Vector2(area.position.x, size.y - 4), "%.0f" % low_x, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, Vector2(area.end.x - 40, size.y - 4), "%.0f" % high_x, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(font, Vector2(area.get_center().x - 20, size.y - 4), x_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		for index in series.size():
			var points: Array = series[index]
			var low_y := 0.0
			var high_y := 0.0
			for point in points:
				low_y = minf(low_y, (point as Vector2).y)
				high_y = maxf(high_y, (point as Vector2).y)
			if high_y - low_y < 1e-6:
				high_y = low_y + 1.0
			var colour: Color = COLOURS[index % COLOURS.size()]
			var drawn := PackedVector2Array()
			for point in points:
				var p: Vector2 = point
				drawn.append(Vector2(area.position.x + (p.x - low_x) / (high_x - low_x) * area.size.x,
						area.end.y - (p.y - low_y) / (high_y - low_y) * area.size.y))
			if drawn.size() > 1:
				draw_polyline(drawn, colour, 2.0, true)
			for spot in drawn:
				draw_circle(spot, 2.5, colour)
			var label_x := 2.0 if index == 0 else area.end.x + 4.0
			draw_string(font, Vector2(label_x, area.position.y + 10), "%.0f" % high_y, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colour)
			draw_string(font, Vector2(label_x, area.end.y), "%.0f" % low_y, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colour)
			if index < names.size():
				draw_string(font, area.position + Vector2(8 + 130 * index, 16), str(names[index]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, colour)
			if index == 0 and tags.size() == drawn.size():
				for tag_index in drawn.size():
					draw_string(font, drawn[tag_index] + Vector2(4, -4), "%.0f°" % (tags[tag_index] as Vector2).y,
							HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8))
