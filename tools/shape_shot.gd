extends SceneTree
## Checks and pictures the curved shapes (run under xvfb with opengl3):
##     xvfb-run -a godot --rendering-driver opengl3 --path . -s tools/shape_shot.gd
## Prints each one's volume, worked out from its mesh, against the volume
## share in the part table, and how many points its collision hull has; then
## renders them large, smooth shaded, beside a canopy made of a rounded wedge
## in front of a half cylinder. Pictures go to /tmp/shots/shapes_*.png.

const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")

const SHAPES := ["wedge", "curved_wedge", "rounded_wedge", "half_cylinder", "half_cone", "half_frustum", "hemisphere", "convex_curve",
		"concave_curve", "cylinder", "torus"]
var camera: Camera3D
var frame := 0


func _mesh_volume(mesh: Mesh) -> float:
	var faces := mesh.get_faces()
	var total := 0.0
	for index in range(0, faces.size(), 3):
		total += faces[index].dot(faces[index + 1].cross(faces[index + 2])) / 6.0
	return absf(total)


func _initialize() -> void:
	for id in SHAPES:
		var mesh := PartLibrary.get_mesh(id)
		var hull := PartLibrary.make_shape(id, Vector3.ONE) as ConvexPolygonShape3D
		print("SHAPE: %-14s mesh volume %.4f, table %.4f, hull points %s" % [
				id, _mesh_volume(mesh), PartLibrary.volume_fraction(id),
				str(hull.points.size()) if hull != null else "-"])
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, 0.9, 0)
	root.add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.55, 0.62, 0.7)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.45, 0.45, 0.5)
	root.add_child(world)
	var look := MaterialLibrary.surface("aluminum", Color(0.35, 0.37, 0.42))
	for index in SHAPES.size():
		var id: String = SHAPES[index]
		var shown := MeshInstance3D.new()
		shown.mesh = PartLibrary.get_mesh(id)
		shown.scale = Vector3(1.0, 1.0, 1.0)
		shown.position = Vector3((index % 5) * 1.6, 0.0, (index / 5) * 1.8)
		shown.set_surface_override_material(0, look)
		root.add_child(shown)
	# A canopy: the rounded wedge's tall end against a half cylinder of the
	# same section, running along -X behind it.
	var glass := MaterialLibrary.surface("glass", Color(0.08, 0.16, 0.26))
	var front := MeshInstance3D.new()
	front.mesh = PartLibrary.get_mesh("rounded_wedge")
	front.scale = Vector3(1.6, 0.7, 1.0)
	front.position = Vector3(4.0, 0.0, 4.0)
	front.set_surface_override_material(0, glass)
	root.add_child(front)
	var back := MeshInstance3D.new()
	back.mesh = PartLibrary.get_mesh("half_cylinder")
	back.basis = Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.0))
	back.scale = Vector3(1.0, 0.7, 1.6)
	back.rotation = Vector3(0.0, PI * 0.5, 0.0)
	back.position = Vector3(4.0 - 1.6, 0.0, 4.0)
	back.set_surface_override_material(0, glass)
	root.add_child(back)
	camera = Camera3D.new()
	camera.fov = 45
	root.add_child(camera)


func _process(_delta: float) -> bool:
	frame += 1
	camera.make_current()
	var views := [[Vector3(3.2, 4.5, -3.5), Vector3(3.2, 0.0, 2.0)], [Vector3(6.5, 1.6, 6.5), Vector3(3.0, 0.2, 4.0)]]
	var view: Array = views[mini(frame / 8, views.size() - 1)]
	camera.look_at_from_position(view[0], view[1], Vector3.UP)
	if frame % 8 == 7:
		DirAccess.make_dir_recursive_absolute("/tmp/shots")
		root.get_viewport().get_texture().get_image().save_png("/tmp/shots/shapes_%d.png" % (frame / 8))
	return frame >= 16
