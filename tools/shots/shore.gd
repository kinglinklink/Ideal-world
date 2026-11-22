extends RefCounted
## A lakeshore near the hangar: the water's edge, cottonwoods.

const Origin = preload("res://scripts/origin.gd")
const MapInfo = preload("res://scripts/map_info.gd")


func step(main: Node, frame: int, tree: SceneTree) -> bool:
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 10:
		var terrain: Node = main.get_node("Terrain")
		# Search out from the hangar for ground a few metres above the lake.
		for ring in range(200, 3000, 50):
			var found := false
			for step_index in 32:
				var angle := TAU * step_index / 32.0
				var spot := Vector2(cos(angle), sin(angle)) * ring
				var ground: float = terrain.height_at(spot.x, spot.y)
				if ground > MapInfo.LAKE_Y + 3.0 and ground < MapInfo.LAKE_Y + 6.0:
					var toward := Vector2(cos(angle), sin(angle))
					var yaw := atan2(-toward.x, -toward.y)
					main._controller.respawn(Origin.to_world(Vector3(spot.x, ground + 1.0, spot.y) - Vector3(toward.x, 0, toward.y) * 15.0), yaw)
					print("SHOT: shore at ", spot)
					found = true
					break
			if found:
				break
		main.get_node("Player").set("zoom", 12.0)
	if frame == 80:
		tree.snap("shore_summer")
	return frame > 82
