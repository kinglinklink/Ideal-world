extends RefCounted
## Polson's streets from above, to check the buildings.

const Origin = preload("res://scripts/origin.gd")


func step(main: Node, frame: int, tree: SceneTree) -> bool:
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 10:
		var terrain: Node = main.get_node("Terrain")
		var spot := Vector2(4400.0, 17900.0)
		main._controller.respawn(Origin.to_world(Vector3(spot.x, terrain.height_at(spot.x, spot.y) + 30.0, spot.y)), 0.6)
	if frame == 12:
		main.get_node("Player").set("zoom", 40.0)
	if frame == 90:
		tree.snap("town")
	return frame > 92
