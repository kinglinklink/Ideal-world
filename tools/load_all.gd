extends SceneTree
## Loads every script, so parse and type errors show up even in scripts
## the scene would only load later.     godot --headless --path . -s tools/load_all.gd

func _initialize() -> void:
	var dir := DirAccess.open("res://scripts")
	var failed := 0
	for file in dir.get_files():
		if file.ends_with(".gd"):
			var script: Script = load("res://scripts/" + file)
			if script == null or not script.can_instantiate():
				print("LOAD: failed ", file)
				failed += 1
	print("LOAD: done, failed ", failed)
	quit()
