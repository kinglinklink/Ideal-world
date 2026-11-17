extends SceneTree
## A headless smoke test: starts the game past the title screen, builds and
## spawns a small vehicle, and runs through the main features, printing any
## problems. Run from the project folder:
##     godot --headless --path . -s tools/smoke_test.gd
## Script errors show up in the output as SCRIPT ERROR lines.

const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Units = preload("res://scripts/units.gd")

var main: Node = null
var frame := 0
var steps: Array = []   # [frame, Callable]


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var plan := [
		[5, func() -> void: main.get_node("Menus").start_game()],
		[20, _build_test_vehicle],
		[30, func() -> void: main.get_node("BuildController").toggle_spawn()],
		[300, func() -> void: print("SMOKE: spawned bodies ", main.get_node("Spawner").body_motions().size())],
		[320, func() -> void: main.get_node("BuildController").toggle_spawn()],
		[340, func() -> void: print("SMOKE: done")],
	]
	for item in _extra_steps():
		plan.append(item)
	plan.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	steps = plan


## Steps for the later features.
func _extra_steps() -> Array:
	return [
		[100, func() -> void: print("SMOKE: replay start ", main.get_node("Replay").start("test"))],
		[130, func() -> void: main.get_node("Replay").stop()],
		[140, func() -> void: main.get_node("Player").hurt(500.0, "a test")],
		[200, func() -> void: main.get_node("Replay").stop()],
		[260, func() -> void: print("SMOKE: hp after death ", main.get_node("Player").hp)],
	]


func _process(_delta: float) -> bool:
	frame += 1
	while not steps.is_empty() and int(steps[0][0]) <= frame:
		var step: Array = steps.pop_front()
		(step[1] as Callable).call()
	return steps.is_empty() and frame > 345


func _build_test_vehicle() -> void:
	var grid: Node = main.get_node("BuildGrid") if main.has_node("BuildGrid") else null
	if grid == null:
		for child in main.get_children():
			if child.has_method("add_part") and child.has_method("all_uids"):
				grid = child
	if grid == null:
		print("SMOKE: no grid found")
		return
	var c := Units.UNITS_PER_CELL
	var h := Units.HALF_CELL_UNITS
	for x in 6:
		for z in 10:
			var record: Dictionary = BuildGrid.make_record("block", Vector3i((40 + x) * c + h, h, (40 + z) * c + h),
					Basis.IDENTITY, Vector3i(c, c, c), "steel", Color(0.6, 0.6, 0.6))
			grid.add_part(record)
	var seat: Dictionary = BuildGrid.make_record("seat", Vector3i(43 * c + h, 2 * c + h, 45 * c + h),
			Basis.IDENTITY, Vector3i(3 * c, 3 * c, 3 * c), "steel", Color(0.3, 0.3, 0.3))
	print("SMOKE: seat uid ", grid.add_part(seat))
	print("SMOKE: parts ", grid.part_count())
