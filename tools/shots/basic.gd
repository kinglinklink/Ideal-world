extends RefCounted

func step(main: Node, frame: int, tree: SceneTree) -> bool:
	if frame % 10 == 0:
		print("SHOT: frame ", frame, " ", Time.get_ticks_msec())
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 60:
		tree.snap("basic")
	return frame > 62
