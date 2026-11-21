extends SceneTree
## Takes screenshots with a real renderer (run under xvfb with opengl3):
##     xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s tools/shot.gd -- <plan>
## Plans are small scripts in tools/shots/*.gd with steps(main, frame) -> bool.

var main: Node = null
var frame := 0
var plan: Object = null


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var args := OS.get_cmdline_user_args()
	var plan_name: String = args[0] if not args.is_empty() else "basic"
	plan = load("res://tools/shots/%s.gd" % plan_name).new()


func _process(_delta: float) -> bool:
	frame += 1
	return plan.step(main, frame, self)


func snap(name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("/tmp/shots/%s.png" % name)
	print("SHOT: saved ", name)
