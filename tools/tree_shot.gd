extends SceneTree
## Renders every kind of tree in summer, autumn and winter (run under xvfb
## with opengl3): /tmp/shots/trees_summer.png and so on.

const Forest = preload("res://scripts/forest.gd")

var camera: Camera3D
var forest: Node
var frame := 0
const SEASONS := [["summer", 0.0, 0.0], ["autumn", 1.0, 0.1], ["winter", 0.0, 1.0]]


func _initialize() -> void:
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.7, 0.8, 0.0)
	light.shadow_enabled = true
	root.add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.62, 0.72, 0.82)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.5, 0.52, 0.56)
	root.add_child(world)
	forest = Forest.new()
	forest._make_meshes()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 60)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.35, 0.45, 0.25)
	ground.material_override = grass
	root.add_child(ground)
	for kind in Forest.SPECIES.size():
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = forest._meshes[kind]
		batch.instance_count = 1
		batch.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.4), Vector3(kind * 6.5 - 45.5, 0, 0)))
		batch.set_instance_color(0, Color.WHITE)
		var shown := MultiMeshInstance3D.new()
		shown.multimesh = batch
		root.add_child(shown)
		var label := Label3D.new()
		label.text = Forest.SPECIES[kind][0]
		label.font_size = 40
		label.pixel_size = 0.02
		label.position = Vector3(kind * 6.5 - 45.5, -0.3, -4.0)
		label.rotation = Vector3(-0.3, PI, 0.0)
		root.add_child(label)
	camera = Camera3D.new()
	camera.fov = 45.0
	root.add_child(camera)


func _process(_delta: float) -> bool:
	frame += 1
	camera.make_current()
	camera.look_at_from_position(Vector3(0, 9, -58), Vector3(0, 5, 0), Vector3.UP)
	var index := frame / 6
	if index >= SEASONS.size():
		return true
	forest.set_season(SEASONS[index][1], 99999.0, SEASONS[index][2])
	if frame % 6 == 5:
		root.get_viewport().get_texture().get_image().save_png("/tmp/shots/trees_%s.png" % SEASONS[index][0])
	return false
