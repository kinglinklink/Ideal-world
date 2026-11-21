extends RefCounted
## The lake from above the hangar at sunrise in autumn (mist over the
## water), then at noon in summer.

const Origin = preload("res://scripts/origin.gd")


func step(main: Node, frame: int, tree: SceneTree) -> bool:
	var daylight: Node = main.get_tree().get_first_node_in_group("daylight")
	var weather: Node = main.get_node("Weather")
	if frame == 5:
		main.get_node("Menus").start_game()
	if frame == 8:
		weather.year_fraction = 0.72
		daylight.day_fraction = 0.03
		var camera := Camera3D.new()
		camera.name = "ShotCamera"
		camera.far = 40000.0
		main.add_child(camera)
	if frame > 8:
		var camera: Camera3D = main.get_node("ShotCamera")
		camera.make_current()
		camera.look_at_from_position(Origin.to_world(Vector3(30.0, 180.0, 60.0)), Origin.to_world(Vector3(-400.0, -20.0, -1500.0)), Vector3.UP)
	if frame == 70:
		tree.snap("mist_morning")
		weather.year_fraction = 0.45
		daylight.day_fraction = 0.25
	if frame == 120:
		tree.snap("mist_noon")
	return frame > 122
