extends SceneTree
## Headless test of the volcano's crater: the character and a build dropped
## into it must die or break within a few seconds.
##     godot --headless --path . -s tools/crater_test.gd

const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")
const Terrain = preload("res://scripts/terrain.gd")

var main: Node = null
var frame := 0
var vehicle: Node = null
var parts_at_start := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var player: Node3D = main.get_node("Player")
	var terrain: Node = main.get_node("Terrain")
	var centre: Vector2 = Terrain.VOLCANO
	match frame:
		5:
			main.get_node("Menus").start_game()
			var grid: Node = main.get_node("BuildGrid")
			var c := Units.UNITS_PER_CELL
			var h := Units.HALF_CELL_UNITS
			for x in 4:
				for z in 4:
					grid.add_part(BuildGrid.make_record("block", Vector3i((20 + x) * c + h, h, (20 + z) * c + h),
							Basis.IDENTITY, Vector3i(c, c, c), "steel" if x < 2 else "plastic", Color.RED))
			SaveManager.save_build(grid, "crater-test")
		10:
			var floor_y: float = terrain.height_at(centre.x + 60.0, centre.y)
			var made: Array = main.get_node("Fleet").spawn_save_at("crater-test", Origin.to_world(Vector3(centre.x + 60.0, floor_y + 1.0, centre.y)), 0.0)
			vehicle = made[1]
			parts_at_start = vehicle.live_parts().size() if vehicle != null else 0
			var ledge_y: float = terrain.height_at(centre.x - 120.0, centre.y + 80.0)
			main._controller.respawn(Origin.to_world(Vector3(centre.x - 120.0, ledge_y + 1.0, centre.y + 80.0)), 0.0)
			print("CRATER: build parts ", parts_at_start, " player hp ", player.hp)
	if frame > 10 and frame % 30 == 0 and frame < 1000:
		var parts: int = vehicle.live_parts().size() if is_instance_valid(vehicle) else 0
		print("CRATER: t=%.1f s player hp %.0f dead %s | build parts %d of %d | heat %.2f" % [
			(frame - 10) / 60.0, player.hp, player.dead, parts, parts_at_start, main.get_node("GameHud").heat])
	if frame == 1000:
		SaveManager.delete_save("crater-test")
	return frame > 1002
