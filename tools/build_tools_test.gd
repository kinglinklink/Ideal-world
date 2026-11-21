extends SceneTree
## Headless test of the Scale tool, grabbing, sub-assemblies and hidden
## control parts.     godot --headless --path . -s tools/build_tools_test.gd

const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Units = preload("res://scripts/units.gd")

var main: Node = null
var frame := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var grid: Node = main.get_node("BuildGrid")
	var controller: Node = main._controller
	var c := Units.UNITS_PER_CELL
	var h := Units.HALF_CELL_UNITS
	if frame == 5:
		main.get_node("Menus").start_game()
		var ids: Array = []
		for x in 3:
			ids.append(grid.add_part(BuildGrid.make_record("block", Vector3i((20 + x) * c + h, h, 20 * c + h),
					Basis.IDENTITY, Vector3i(c, c, c), "aluminum", Color.RED)))
		# Scale one block: pull its +X face out by one block.
		controller.set_tool(5)
		controller.selection = [ids[2]]
		controller._drag = {"bounds": controller._selection_bounds(), "records": {ids[2]: grid.get_part(ids[2])}}
		var updates: Dictionary = controller._scaled(c, 0, 1, false)
		print("TOOLS: scale one +X by a block -> size ", updates[ids[2]]["size"], " pos ", updates[ids[2]]["pos"],
				" (was ", grid.get_part(ids[2])["pos"], ") ok ", controller._apply(updates))
		var low_face: float = float(grid.get_part(ids[2])["pos"].x) - float(grid.get_part(ids[2])["size"].x) * 0.5
		print("TOOLS: its -X face stays at ", low_face, " (expected ", (22 * c), ")")
		# Scale the row of three on Z from both sides.
		controller.selection = ids.duplicate()
		var records: Dictionary = {}
		for uid in ids:
			records[uid] = grid.get_part(uid)
		controller._drag = {"bounds": controller._selection_bounds(), "records": records}
		var both: Dictionary = controller._scaled(c, 2, 1, true)
		print("TOOLS: row stretched on Z both sides -> sizes ", both.values().map(func(r): return r["size"]), " ok ", controller._apply(both))
		# Grab two and put them back.
		controller.set_tool(3)
		controller.selection = [ids[0], ids[1]]
		var before: int = grid.part_count()
		controller.grab_selection()
		print("TOOLS: grabbed -> parts on grid ", grid.part_count(), " of ", before, " carrying ", controller._clipboard.size(), " armed ", controller.paste_armed)
		controller._drop_grab_back()
		print("TOOLS: put back -> parts ", grid.part_count())
		# Sub-assembly: save two blocks and list it.
		controller.selection = [ids[0], ids[1]]
		print("TOOLS: save sub-assembly -> '", controller.save_selection_as_module("tools-test"), "' listed ", SaveManager.list_modules().has("tools-test"))
		var menu: Node = main.get_node("Hud")._modules_panel
		menu.toggle()
		print("TOOLS: menu cards ", menu._cards.get_child_count(), " models ", menu._models.size())
		menu._pick_up("tools-test", false)
		print("TOOLS: picked up -> armed ", controller.paste_armed, " tool ", controller.current_tool, " menu open ", menu.visible)
		controller.paste_armed = false
		# Hidden control parts: an input block and a PID on top.
		var key: int = grid.add_part(BuildGrid.make_record("input_block", Vector3i(20 * c + h, c + c / 4, 20 * c + h),
				Basis.IDENTITY, Vector3i(c, c / 2, c), "steel", Color.GRAY))
		var pid: int = grid.add_part(BuildGrid.make_record("pid_controller", Vector3i(21 * c + h, c + c / 4, 20 * c + h),
				Basis.IDENTITY, Vector3i(c, c / 2, c), "steel", Color.GRAY))
		print("TOOLS: control part mass in build mode ", BuildGrid.mass_of(grid.get_part(key)), " ", BuildGrid.mass_of(grid.get_part(pid)))
	if frame == 8:
		var spawner: Node = main.get_node("Spawner")
		var result: Dictionary = spawner.spawn(grid)
		var hidden := 0
		for uid in spawner.all_records():
			if BuildGrid.is_hidden_control(spawner.all_records()[uid]) and spawner.part_place(uid).is_empty():
				hidden += 1
		print("TOOLS: spawned ", result, " hidden control parts ", hidden)
		spawner.despawn()
		SaveManager.delete_module("tools-test")
	return frame > 10
