extends SceneTree
## Headless flight test of a plane build file. Loads it, spawns it, sits in
## its first seat, lifts every body to 400 m at a forward speed, then flies
## a script of key presses and prints the plane's attitude and speed.
##     godot --headless --path . -s tools/plane_test.gd -- <file.json> [speed m/s]
## The plane's nose is taken as -Z (where its thrusters push).

const SaveManager = preload("res://scripts/save_manager.gd")
const Origin = preload("res://scripts/origin.gd")
const FailureLog = preload("res://scripts/failure_log.gd")

var main: Node = null
var frame := 0
var file := ""
var speed := 40.0
var step := 0
var clock := 0.0
var held: Array = []
var main_body: RigidBody3D = null
var nose_local := Vector3.FORWARD   # the nose, in the main body's own axes: the strongest thruster's push
var seen_breaks := 0
var no_fail := false
var ground := false
var cruise := 70.0                  # J is pressed only below this forward speed
const GROUND_SCRIPT := [
	[2.0, [], "sit on the ground"],
	[2.0, ["K"], "throttle"],
	[2.0, ["K", "W"], "rotate"],
	[4.0, ["K"], "climb out"],
	[1.0, ["K", "D"], "D"],
	[3.0, ["K"], "let go"],
]
const SCRIPT := [
	# [seconds, keys held, label]. J is a throttle held at the cruise speed.
	[4.0, ["K"], "level, throttle"],
	[1.0, ["K", "W"], "W"],
	[4.0, ["K"], "let go"],
	[1.0, ["K", "S"], "S"],
	[3.0, ["K"], "let go"],
	[1.0, ["K", "W"], "W"],
	[3.0, ["K"], "let go"],
	[1.0, ["K", "D"], "D"],
	[3.0, ["K"], "let go"],
	[1.0, ["K", "A"], "A"],
	[3.0, ["K"], "let go"],
	[1.0, ["K", "E"], "E"],
	[3.0, ["K"], "let go"],
	[1.0, ["K", "Q"], "Q"],
	[3.0, ["K"], "let go"],
	[1.5, ["K", "X"], "X"],
	[3.0, ["K"], "let go"],
	[1.5, ["K", "Z"], "Z"],
	[3.0, ["K"], "let go"],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	file = args[0] if args.size() > 0 else ""
	if args.size() > 1:
		speed = float(args[1])
	cruise = float(args[2]) if args.size() > 2 else speed
	no_fail = args.has("nofail")
	ground = args.has("ground")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _keys(names: Array) -> void:
	for key in ["J", "K", "W", "A", "S", "D", "Q", "E", "Z", "C", "X", "I"]:
		var event := InputEventKey.new()
		event.keycode = OS.find_keycode_from_string(key)
		event.physical_keycode = event.keycode
		event.pressed = names.has(key)
		Input.parse_input_event(event)


func _attitude() -> String:
	var b := main_body.global_transform.basis
	var nose := (b * nose_local).normalized()
	var up := b.y
	var right := nose.cross(up).normalized()
	var pitch := rad_to_deg(asin(clampf(nose.y, -1, 1)))
	# Roll: positive when the right wing is down.
	var roll := rad_to_deg(atan2(-right.y, up.y))
	var heading := rad_to_deg(atan2(nose.x, nose.z))
	var v := main_body.linear_velocity
	var forward := v.dot(nose)
	var alt := Origin.to_map(main_body.global_position).y
	return ("@%s " % str(Origin.to_map(main_body.global_position).snapped(Vector3.ONE))) + "pitch %6.1f roll %6.1f heading %7.1f | speed %5.1f (fwd %5.1f, climb %5.1f) | alt %6.0f | spin p %5.2f r %5.2f y %5.2f" % [
		pitch, roll, heading, v.length(), forward, v.y, alt,
		# pitch rate (nose up +), roll rate (right wing down +), yaw rate (nose right +)
		main_body.angular_velocity.dot(-right), main_body.angular_velocity.dot(nose), -main_body.angular_velocity.dot(up)]


func _physics_tick(delta: float) -> void:
	pass


func _process(delta: float) -> bool:
	frame += 1
	var spawner: Node = main.get_node("Spawner")
	var grid: Node = main.get_node("BuildGrid")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		if no_fail:
			load("res://scripts/stress.gd").failure = false
		if OS.get_environment("PLANE_STRESS") != "":
			load("res://scripts/stress.gd").view = true
		var name := "_plane_test"
		DirAccess.copy_absolute(file, SaveManager.path_for(name))
		var result: Dictionary = SaveManager.load_build(grid, name)
		DirAccess.remove_absolute(SaveManager.path_for(name))
		print("PLANE: loaded ", result)
		main.get_node("BuildController").toggle_spawn()
		var report_bodies: int = spawner.all_bodies().size()
		main_body = spawner.heaviest_body()
		var strongest := 0.0
		for item in spawner._thrusters:
			if float(item[2]) > strongest:
				strongest = float(item[2])
				var body: RigidBody3D = spawner.piece_body(item[0])
				var push: Vector3 = body.global_transform.basis * ((item[1] as Transform3D).basis * Vector3(0, 0, -1))
				nose_local = main_body.global_transform.basis.inverse() * push
		print("PLANE: nose (main body axes) ", nose_local.snapped(Vector3.ONE * 0.01))
		# What each body is made of.
		for body in spawner.all_bodies():
			var kinds := {}
			for piece in spawner._body_pieces.get(body, []):
				var type: String = spawner.record_of(spawner._uid_of(piece))["type"]
				kinds[type] = int(kinds.get(type, 0)) + 1
			print("PLANE: body %.0f kg: %s" % [(body as RigidBody3D).mass, str(kinds)])
			var pieces: Array = spawner._body_pieces.get(body, [])
			if pieces.size() == 1:
				var lone: int = pieces[0]
				var lone_box: AABB = spawner._boxes[lone]
				print("PLANE:   lone piece box ", lone_box)
				for other in spawner._boxes:
					if other != lone and spawner._touching(lone_box, spawner._boxes[other]):
						print("PLANE:   touches ", spawner.record_of(spawner._uid_of(other))["type"], " ", spawner._boxes[other], " welds ", spawner._welds(lone, other, spawner._boxes))
		var total := 0.0
		var centre := Vector3.ZERO
		for body in spawner.all_bodies():
			total += (body as RigidBody3D).mass
			centre += ((body as RigidBody3D).global_transform * (body as RigidBody3D).center_of_mass) * (body as RigidBody3D).mass
		centre /= total
		var local := main_body.global_transform.affine_inverse() * centre
		print("PLANE: %d bodies, %d joints, mass %.0f kg (main body %.0f kg), centre of mass %s from the main body's origin" % [
				report_bodies, spawner.counts()["joints"], total, main_body.mass, str(local.snapped(Vector3.ONE * 0.01))])
		# Sit in the seat on the main body (or any seat).
		var controller: Node = main.get_node("BuildController")
		print("PLANE: seated ", controller.sit_in(spawner))
		# The jump to altitude would count as a crash for the pilot.
		main.get_node("Player").damage_enabled = false
	if frame == 12 and ground:
		step = 0
	elif frame == 12:
		# Up into the air, flying forward.
		var lift := Vector3(0.0, 400.0, 0.0)
		for body in spawner.all_bodies():
			var b := body as RigidBody3D
			b.global_position += lift
			b.linear_velocity = (main_body.global_transform.basis * nose_local).normalized() * speed
			b.angular_velocity = Vector3.ZERO
		main.get_node("Player").global_position += lift
	var script: Array = GROUND_SCRIPT if ground else SCRIPT
	if frame > 12 and step < script.size():
		var phase: Array = script[step]
		if clock == 0.0:
			print("PLANE: --- ", phase[2])
		var wanted: Array = (phase[1] as Array).duplicate()
		if wanted.has("K") and is_instance_valid(main_body):
			if main_body.linear_velocity.dot((main_body.global_transform.basis * nose_local).normalized()) > cruise:
				wanted.erase("K")
		if wanted != held:
			held = wanted
			_keys(wanted)
		clock += delta
		if fmod(clock, 0.5) < delta:
			if not is_instance_valid(main_body):
				print("PLANE: the main body broke up"); print("PLANE: breaks ", FailureLog.instance._entries if FailureLog.instance else [])
				return true
			var extra := ""
			for item in spawner._thrusters:
				extra += " T%.0fk" % (float(spawner.outputs_of(spawner._uid_of(item[0])).get("thrust", 0.0)) / 1000.0)
			for uid in spawner._outputs:
				var out: Dictionary = spawner._outputs[uid]
				if out.size() == 1 and out.has("angle"):
					extra += " %.0f" % float(out["angle"])
			if OS.get_environment("PLANE_DEBUG") != "":
				var dbg := ""
				for uid in spawner._inputs:
					dbg += " in%d=%s/%s" % [uid, spawner._inputs[uid]["pressed"], spawner._inputs[uid]["value"]]
				for uid in spawner._outputs:
					var o: Dictionary = spawner._outputs[uid]
					if o.has("output"):
						dbg += " pid%d=%.1f" % [uid, float(o["output"])]
					if o.has("pitch_rate"):
						dbg += " att p%.1f r%.1f pr%.1f rr%.1f" % [float(o["pitch"]), float(o["roll"]), float(o["pitch_rate"]), float(o["roll_rate"])]
				print("PLANE: dbg", dbg, " held ", held, " seat ", spawner.occupied_seat, " J ", Input.is_key_pressed(KEY_J), " S ", Input.is_key_pressed(KEY_S))
			print("PLANE: %4.1fs %s |%s" % [clock, _attitude(), extra])
			if OS.get_environment("PLANE_STRESS") != "" and absf(clock - 3.0) < delta:
				var worst: Array = []
				for piece in spawner.stress._ratio:
					worst.append([float(spawner.stress._ratio[piece]), piece])
				worst.sort()
				worst.reverse()
				for item in worst.slice(0, 14):
					var rec: Dictionary = spawner.record_of(int(item[1]) >> 3)
					print("PLANE:   stress %.2f  %s %s at %s size %s" % [item[0], rec.get("material", "?"), rec.get("type", "?"), str(rec.get("pos")), str(rec.get("size"))])
			var log_node = FailureLog.instance
			if log_node != null:
				var entries: Array = log_node._entries
				while seen_breaks < entries.size():
					print("PLANE:   BREAK ", entries[seen_breaks]["text"])
					seen_breaks += 1
			if step == 0 and clock < 0.6:
				var pressed: Array = []
				for uid in spawner._inputs:
					pressed.append([uid, spawner._inputs[uid]["pressed"], spawner._inputs[uid]["value"]])
				var thrusts: Array = []
				for item in spawner._thrusters:
					thrusts.append(spawner.outputs_of(spawner._uid_of(item[0])))
				print("PLANE: inputs ", pressed, " thrusters ", thrusts, " J down ", Input.is_key_pressed(KEY_J))
		if clock >= float(phase[0]):
			clock = 0.0
			step += 1
	return step >= SCRIPT.size() or frame > 20000
