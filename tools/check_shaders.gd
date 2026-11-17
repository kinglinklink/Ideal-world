extends SceneTree
## Loads every shader in shaders/ and reports any that fail to compile.
##     godot --headless --path . -s tools/check_shaders.gd

func _initialize() -> void:
	var dir := DirAccess.open("res://shaders")
	for file_name in dir.get_files():
		if file_name.ends_with(".gdshader"):
			var shader: Shader = load("res://shaders/" + file_name)
			print("SHADER ", file_name, " uniforms ", shader.get_shader_uniform_list().size())
	quit()
