extends SceneTree
## Headless test of the hit-scan gun: aimed at a target build in front of it
## it fires and hurts it; aimed behind it, it stays quiet.
##     godot --headless --path . -s tools/hitscan_test.gd

const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")

var main: Node = null
var frame := 0
var target: Node = null
var gun_uid := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var grid: Node = main.get_node("BuildGrid")
	var c := Units.UNITS_PER_CELL
	var h := Units.HALF_CELL_UNITS
	if frame == 5:
		main.get_node("Menus").start_game()
		for x in 3:
			for z in 3:
				grid.add_part(BuildGrid.make_record("block", Vector3i((60 + x) * c + h, h, (60 + z) * c + h),
						Basis.IDENTITY, Vector3i(c, c, c), "wood", Color.BROWN))
		SaveManager.save_build(grid, "hitscan-target")
		for uid in grid.all_uids():
			grid.remove_part(uid)
		grid.add_part(BuildGrid.make_record("block", Vector3i(100 * c + h, h, 100 * c + h), Basis.IDENTITY,
				Vector3i(c, c, c), "steel", Color.GRAY))
		var record := BuildGrid.make_record("hitscan_gun", Vector3i(100 * c + h, c + h, 100 * c), Basis.IDENTITY,
				Vector3i(c, c, 2 * c), "steel", Color.GRAY)
		record["props"]["trigger"] = "Fire input only"
		gun_uid = grid.add_part(record)
		main._controller.toggle_spawn()
	if frame == 8:
		var spawner: Node = main.get_node("Spawner")
		var muzzle: Array = main.get_node("Combat")._muzzle(gun_uid, spawner.record_of(gun_uid))
		var ahead: Vector3 = (muzzle[0] as Vector3) + (muzzle[1] as Vector3) * 30.0
		var made: Array = main.get_node("Fleet").spawn_save_at("hitscan-target", ahead, 0.0)
		target = made[1]
		print("HITSCAN: target spawned ", target != null, " at ", Origin.to_map(ahead).snapped(Vector3.ONE))
	if frame == 30:
		var spawner: Node = main.get_node("Spawner")
		var combat: Node = main.get_node("Combat")
		var record: Dictionary = spawner.record_of(gun_uid)
		var spot: Vector3 = target.where()
		var before := 0.0
		for uid in target.live_parts():
			before += target.health_of(int(uid))
		var wants: bool = combat._hitscan_wants(gun_uid, record, {"point": spot, "hit": true}, true)
		for shot in 20:
			combat._fire_at(gun_uid, record, spot)
		var after := 0.0
		for uid in target.live_parts():
			after += target.health_of(int(uid))
		print("HITSCAN: aimed ahead wants=", wants, " target health ", int(before), " -> ", int(after))
		var muzzle: Array = combat._muzzle(gun_uid, record)
		var behind: Vector3 = (muzzle[0] as Vector3) - (muzzle[1] as Vector3) * 30.0
		print("HITSCAN: aimed behind wants=", combat._hitscan_wants(gun_uid, record, {"point": behind, "hit": true}, true),
				" outputs ", spawner.outputs_of(gun_uid))
		var far: Vector3 = (muzzle[0] as Vector3) + (muzzle[1] as Vector3) * 900.0
		print("HITSCAN: aimed past range wants=", combat._hitscan_wants(gun_uid, record, {"point": far, "hit": true}, true))
		SaveManager.delete_save("hitscan-target")
	return frame > 32
