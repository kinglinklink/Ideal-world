extends RefCounted
## A lakeshore with cottonwoods, summer and winter.

const Origin = preload("res://scripts/origin.gd")


func step(main: Node, frame: int, tree: SceneTree) -> bool:
	var weather: Node = main.get_node("Weather")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 10:
		var terrain: Node = main.get_node("Terrain")
		var spot := Vector2(-700.0, -500.0)
		# Walk out until the ground is just above the lake.
		for step_index in 200:
			var test := spot + Vector2(-20.0 * step_index, 0.0)
			if terrain.height_at(test.x, test.y) < -12.0:
				spot = test + Vector2(60.0, 0.0)
				break
		main._controller.respawn(Origin.to_world(Vector3(spot.x, terrain.height_at(spot.x, spot.y) + 2.0, spot.y)), 1.57)
		main.get_node("Player").set("zoom", 25.0)
	if frame == 70:
		tree.snap("shore_summer")
		weather.year_fraction = 0.95
	if frame == 130:
		tree.snap("shore_winter")
	return frame > 132
