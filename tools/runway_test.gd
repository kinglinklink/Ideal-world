extends SceneTree
## Headless test of To runway: loads a build, presses To runway from build
## mode (it spawns and goes), checks the build stands level at the start of
## a runway facing down it, presses again for the next runway, then runs
## the throttle up to see it roll the right way. Seated, then on foot.
##     godot --headless --path . -s tools/runway_test.gd -- <build.json> [throttle control]

const Origin = preload("res://scripts/origin.gd")
const Gamepad = preload("res://scripts/gamepad.gd")
const FailureLog = preload("res://scripts/failure_log.gd")
const SaveManager = preload("res://scripts/save_manager.gd")

var main: Node
var spawner: Node
var grid: Node
var controller: Node
var file := ""
var frame := 0
var step := 0
var wait := 0.0
var tick := 0.0
var seen_breaks := 0
var start_at := Vector3.ZERO


func _initialize() -> void:
	file = OS.get_cmdline_user_args()[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _report(label: String) -> void:
	var body: RigidBody3D = spawner.heaviest_body()
	var at: Vector3 = Origin.to_map(body.global_position)
	var forward: Vector3 = main._build_forward(body)
	var b := body.global_transform.basis.orthonormalized()
	var built: Basis = spawner.grid_basis()
	# How far the main body is from level: the angle between its up as
	# built and straight up.
	var tilt := rad_to_deg((b * (built.inverse() * Vector3.UP)).angle_to(Vector3.UP))
	var heading := fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)
	print("RUNWAY: %s | map (%.0f, %.1f, %.0f) heading %.1f tilt %.1f speed %.2f seated %s" % [
		label, at.x, at.y, at.z, heading, tilt, body.linear_velocity.length(), str(controller.seat_uid != 0)])
	var log_node = FailureLog.instance
	if log_node != null:
		var entries: Array = log_node._entries
		while seen_breaks < entries.size():
			print("RUNWAY:   BREAK ", entries[seen_breaks]["text"])
			seen_breaks += 1


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		spawner = main.get_node("Spawner")
		grid = main.get_node("BuildGrid")
		controller = main.get_node("BuildController")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		var save_name := "_runway_test"
		DirAccess.copy_absolute(file, SaveManager.path_for(save_name))
		print("RUNWAY: loaded ", SaveManager.load_build(grid, save_name))
		DirAccess.remove_absolute(SaveManager.path_for(save_name))
		main.get_node("Player").damage_enabled = false
	if frame < 10:
		return false
	if wait > 0.0:
		wait -= delta
		tick += delta
		if step == 3 and tick >= 0.5:
			tick = 0.0
			var body: RigidBody3D = spawner.heaviest_body()
			print("RUNWAY:   %.1fs left: map %s speed %.1f bodies %d" % [wait, str(Origin.to_map(body.global_position).round()), body.linear_velocity.length(), spawner.all_bodies().size()])
		return false
	match step:
		0:
			# From build mode, on foot: it spawns, goes, and brings the character.
			main.send_build_to_runway()
			_report("pressed, from build mode")
			print("RUNWAY: character at map ", Origin.to_map(main.get_node("Player").global_position).round())
			wait = 2.0
		1:
			_report("after 2 s")
			start_at = Origin.to_map(spawner.heaviest_body().global_position)
			print("RUNWAY: seated ", controller.sit_in(spawner))
			main.send_build_to_runway()
			_report("pressed again, seated")
			wait = 2.0
		2:
			_report("after 2 s")
			var args := OS.get_cmdline_user_args()
			var control: String = args[1] if args.size() > 1 else "RT / R2 trigger"
			Gamepad.fake = {control: 1.0}
			wait = 5.0
		3:
			_report("after 5 s of full throttle")
			Gamepad.fake = {}
			main.send_build_to_runway()
			_report("pressed while rolling")
			wait = 2.0
		4:
			_report("after 2 s")
			return true
	step += 1
	return false
