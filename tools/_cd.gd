extends SceneTree
const PartLibrary = preload("res://scripts/part_library.gd")
func _initialize() -> void:
	for id in ["concave_curve", "arch", "ring", "pipe", "torus"]:
		var mesh: Mesh = PartLibrary.get_mesh(id)
		var settings := MeshConvexDecompositionSettings.new()
		var t := Time.get_ticks_msec()
		var parts: Array = mesh.convex_decompose(settings)
		print("CD ", id, " pieces ", parts.size(), " ms ", Time.get_ticks_msec() - t)
	quit()
