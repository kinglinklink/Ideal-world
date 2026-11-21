extends SceneTree
## Headless test of the docks, summer boats and a boat race course.
##     godot --headless --path . -s tools/boat_test.gd

const Origin = preload("res://scripts/origin.gd")

var main: Node = null
var frame := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var boats: Node = main.get_node("Boats")
	var races: Node = main.get_node("Races")
	if frame == 5:
		main.get_node("Menus").start_game()
		main.get_node("Weather").set_season("summer")
		for dock in boats.docks:
			print("BOAT: dock ", dock["name"], " shore ", (dock["shore"] as Vector3).snapped(Vector3.ONE), " heading ", snappedf(rad_to_deg(dock["heading"]), 1))
		var hosts := 0
		for host in races._hosts:
			if not (host.get("boat", []) as Array).is_empty():
				hosts += 1
				var course: Dictionary = races._boat_course(host["boat"][0], host)
				var wet := 0
				var path: PackedVector3Array = course["path"]
				for point in path:
					if main.get_node("Terrain").is_lake(point.x, point.z):
						wet += 1
				print("BOAT: ", host["name"], " course gates ", (course["rings"] as Array).size(), " path on water ", wet, " of ", path.size())
		print("BOAT: boat race hosts ", hosts)
		print("BOAT: fuel stations now ", main.get_node("Fuel").stations.size())
	if frame == 300:
		print("BOAT: boats on the lake after 5 s: ", boats.boat_count())
		for boat in boats._boats:
			print("BOAT:   ", boat["kind"], " at ", (boat["at"] as Vector3).snapped(Vector3.ONE), " speed ", snappedf(boat["speed"], 0.1),
					" on water ", main.get_node("Terrain").is_lake(boat["at"].x, boat["at"].z))
	if frame == 900:
		print("BOAT: after 15 s: ", boats.boat_count())
		for boat in boats._boats:
			print("BOAT:   ", boat["kind"], " at ", (boat["at"] as Vector3).snapped(Vector3.ONE), " speed ", snappedf(boat["speed"], 0.1))
		var first: Dictionary = boats._boats[0]
		boats.damage_piece(first["body"], 0, 1000.0)
		print("BOAT: shot the first: sinking ", first["sinking"])
		main.get_node("Weather").set_season("winter")
	if frame == 1100:
		print("BOAT: winter: boats ", boats.boat_count())
	return frame > 1102
