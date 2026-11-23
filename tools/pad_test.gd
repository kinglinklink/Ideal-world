extends SceneTree
## Checks the controller: walking on the left stick, looking with the right
## stick, and a Controller input block's reading while seated.
##     godot --headless --path . -s tools/pad_test.gd

const Gamepad = preload("res://scripts/gamepad.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Units = preload("res://scripts/units.gd")

var main: Node
var frame := 0
var start := Vector3.ZERO
var yaw0 := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var player: Node = main.get_node("Player")
	var controller: Node = main.get_node("BuildController")
	var spawner: Node = main.get_node("Spawner")
	var grid: Node = main.get_node("BuildGrid")
	var c := Units.UNITS_PER_CELL
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 30:
		start = player.global_position
		yaw0 = player.yaw
		Gamepad.fake = {"Left stick Y (up +)": 1.0, "Right stick X (right +)": 0.6}
	if frame == 90:
		var moved: Vector3 = player.global_position - start
		print("PAD: walked %.2f m, turned %.2f rad" % [Vector3(moved.x, 0, moved.z).length(), player.yaw - yaw0])
		Gamepad.fake = {}
		var seat := BuildGrid.make_record("seat", Vector3i(40 * c, 2 * c - c / 2, 40 * c), Basis.IDENTITY, Vector3i(3 * c, 3 * c, 3 * c), "wood", Color.BROWN)
		var seat_uid: int = grid.add_part(seat)
		var pad := BuildGrid.make_record("gamepad_input", Vector3i(45 * c, c / 4, 40 * c), Basis.IDENTITY, Vector3i(c, c / 2, c), "plastic", Color.GRAY)
		pad["props"]["control"] = "RT / R2 trigger"
		pad["props"]["scale"] = 100.0
		var pad_uid: int = grid.add_part(pad)
		var dpad := BuildGrid.make_record("gamepad_input", Vector3i(47 * c, c / 4, 40 * c), Basis.IDENTITY, Vector3i(c, c / 2, c), "plastic", Color.GRAY)
		dpad["props"]["control"] = "D-pad right"
		dpad["props"]["output"] = "Number from two controls"
		dpad["props"]["second_control"] = "D-pad left"
		grid.add_part(dpad)
		var tog := BuildGrid.make_record("gamepad_input", Vector3i(49 * c, c / 4, 40 * c), Basis.IDENTITY, Vector3i(c, c / 2, c), "plastic", Color.GRAY)
		tog["props"]["control"] = "Y / Triangle"
		tog["props"]["mode"] = "Toggle"
		grid.add_part(tog)
		controller.toggle_spawn()
	if frame == 120:
		print("PAD: seated ", controller.sit_in(spawner))
		Gamepad.fake = {"RT / R2 trigger": 0.5, "D-pad left": 1.0, "Y / Triangle": 1.0}
	if frame == 130:
		Gamepad.fake = {"RT / R2 trigger": 1.0, "D-pad left": 0.0, "Y / Triangle": 0.0}
	if frame == 125 or frame == 135:
		for uid in spawner._pads:
			var state: Dictionary = spawner._pads[uid]
			print("PAD: %s value %.3f pressed %.0f" % [state["control"], state["value"], state["pressed"]])
	return frame > 140
