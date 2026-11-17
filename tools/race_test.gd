extends SceneTree
## Headless test of races, cargo runs and traffic.
##     godot --headless --path . -s tools/race_test.gd

const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")

var main: Node = null
var frame := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var races: Node = main.get_node("Races")
	match frame:
		5:
			main.get_node("Menus").start_game()
			var grid: Node = main.get_node("BuildGrid")
			var c := Units.UNITS_PER_CELL
			var h := Units.HALF_CELL_UNITS
			for x in 4:
				for z in 6:
					grid.add_part(BuildGrid.make_record("block", Vector3i((20 + x) * c + h, h, (20 + z) * c + h),
							Basis.IDENTITY, Vector3i(c, c, c), "aluminum", Color.RED))
			grid.add_part(BuildGrid.make_record("seat", Vector3i(21 * c + h + c / 2, 2 * c + h, 22 * c + h),
					Basis.IDENTITY, Vector3i(3 * c, 3 * c, 3 * c), "steel", Color.GRAY))
			print("RACE: save ", SaveManager.save_build(grid, "race-test"))
			print("RACE: hosts ", races._hosts.size(), " airports ", races._airports.size())
			for host in races._hosts:
				if not (host["car"] as Array).is_empty():
					print("RACE: car host ", host["name"], " at ", (host["at"] as Vector3).snapped(Vector3.ONE))
		10:
			var host: Dictionary = {}
			for item in races._hosts:
				if not (item["air"] as Array).is_empty():
					host = item
					break
			races._open_window(host)
			for index in races._vehicle_pick.item_count:
				if races._vehicle_pick.get_item_text(index) == "race-test":
					races._vehicle_pick.select(index)
			races._start_race(host["air"][0], host, true)
			print("RACE: air race on ", not races._race.is_empty(), " seated ", main.get_node("Player").seated)
		700:
			print("RACE: label ", races._race.get("label").text.replace("\n", " | ") if not races._race.is_empty() else "none")
			for racer in races._race.get("racers", []):
				print("RACE: racer ", racer["name"], " at ", int(racer["at"]), " m, ", int(racer["speed"]), " m/s")
			races._end_race("test over", false)
		720:
			var host: Dictionary = {}
			for item in races._hosts:
				if not (item["car"] as Array).is_empty():
					host = item
					break
			if host.is_empty():
				print("RACE: no car host")
			else:
				races._open_window(host)
				for index in races._vehicle_pick.item_count:
					if races._vehicle_pick.get_item_text(index) == "race-test":
						races._vehicle_pick.select(index)
				races._start_race(host["car"][0], host, false)
				print("RACE: car race on ", not races._race.is_empty())
		1400:
			print("RACE: label ", races._race.get("label").text.replace("\n", " | ") if not races._race.is_empty() else "none")
			for racer in races._race.get("racers", []):
				print("RACE: racer ", racer["name"], " at ", int(racer["at"]), " m, ", int(racer["speed"]), " m/s")
			races._end_race("test over", false)
		1420:
			var names: Array = races._airports.keys()
			races._take_job(names[0], names[1], 1)
			var polson: Vector3 = races._airports["Polson airport"]["centre"]
			main._controller.respawn(Origin.to_world(polson + Vector3(0, 3, 0)), 0.0)
			print("RACE: cargo ", races._job_text())
		1600:
			print("RACE: cargo ", races._job_text())
			races._end_job("test", 0)
			var traffic: Node = main.get_node("Traffic")
			print("RACE: traffic cars ", traffic._cars.size(), " planes ", traffic._planes.size())
			SaveManager.delete_save("race-test")
	return frame > 1610
