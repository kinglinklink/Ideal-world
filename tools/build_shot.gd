extends SceneTree
## Renders a build file from several angles on a plain apron, without the
## world around it, so it is quick (run under xvfb with opengl3):
##     xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##         -s tools/build_shot.gd -- <build.json> <out prefix> [lit]
## Writes <out prefix>_<view>.png. With "lit" the light panels glow.

const SaveManager = preload("res://scripts/save_manager.gd")
const PartLibrary = preload("res://scripts/part_library.gd")
const MaterialLibrary = preload("res://scripts/material_library.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Units = preload("res://scripts/units.gd")

var camera: Camera3D
var frame := 0
var views: Array = []
var prefix := ""
var centre := Vector3.ZERO
var span := 10.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	prefix = args[1]
	var lit := args.has("lit")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var low := Vector3.INF
	var high := -Vector3.INF
	var holder := Node3D.new()
	root.add_child(holder)
	for entry in data["parts"]:
		var record: Dictionary = SaveManager._entry_to_record(entry)
		if record.is_empty() or BuildGrid.is_hidden_control(record):
			continue
		var size_m := Units.to_metres(record["size"])
		var place := Transform3D(record["rot"] as Basis, Vector3(record["pos"] as Vector3i) * Units.UNIT)
		var mesh := MeshInstance3D.new()
		mesh.mesh = PartLibrary.mesh_for_record(record)
		mesh.transform = place
		mesh.scale = size_m
		var look: Material = MaterialLibrary.surface(record["material"], record["color"])
		if lit and str(record["type"]) == "light_panel":
			var glow := StandardMaterial3D.new()
			glow.albedo_color = record["color"]
			glow.emission_enabled = true
			glow.emission = record["color"]
			glow.emission_energy_multiplier = 3.0
			look = glow
			# And a little light of its own, as in the game.
			var lamp := OmniLight3D.new()
			lamp.light_color = record["color"]
			lamp.light_energy = 2.0
			lamp.omni_range = 3.0
			lamp.position = place.origin + (place.basis * Vector3(0, 0, -0.3))
			holder.add_child(lamp)
		mesh.set_surface_override_material(0, look)
		if lit and str(record["type"]) == "light_panel":
			for surface in range(1, mesh.mesh.get_surface_count()):
				mesh.set_surface_override_material(surface, look)
		holder.add_child(mesh)
		var bounds := BuildGrid.bounds_of(record)
		low = low.min(bounds.position)
		high = high.max(bounds.end)
	centre = (low + high) * 0.5
	span = (high - low).length()
	print("SHOT: bounds ", low, " ", high)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.85, 0.75, 0.0)
	sun.light_energy = 1.3 if not lit else 0.35
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, -2.4, 0.0)
	fill.light_energy = 0.35 if not lit else 0.1
	root.add_child(fill)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.62, 0.72, 0.84) if not lit else Color(0.12, 0.13, 0.18)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.55, 0.57, 0.62) if not lit else Color(0.3, 0.3, 0.36)
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment.glow_enabled = lit
	root.add_child(world)
	var apron := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	apron.mesh = plane
	var tarmac := StandardMaterial3D.new()
	tarmac.albedo_color = Color(0.24, 0.25, 0.27)
	tarmac.roughness = 0.9
	apron.material_override = tarmac
	apron.position = Vector3(centre.x, -0.01, centre.z)
	root.add_child(apron)
	camera = Camera3D.new()
	camera.fov = 35.0
	camera.far = 2000.0
	root.add_child(camera)
	camera.make_current()
	# Each view: name, direction from the centre to the camera, distance factor.
	views = [
		["front_quarter", Vector3(-0.9, 0.55, 1.0), 1.05],
		["left_quarter", Vector3(0.95, 0.3, 0.8), 0.85],
		["under", Vector3(0.25, -1.0, 0.35), 0.9],
		["rear_quarter", Vector3(0.9, 0.5, -1.0), 1.05],
		["side", Vector3(-1.0, 0.08, 0.0), 1.15],
		["top", Vector3(0.0, 1.0, 0.0001), 1.35],
		["front", Vector3(0.0, 0.12, 1.0), 1.1],
		["low_front", Vector3(-0.7, 0.05, 1.0), 0.9],
		["rear", Vector3(0.25, 0.12, -1.0), 0.8],
	]


func _process(_delta: float) -> bool:
	frame += 1
	var index := frame / 3 - 1
	if index >= views.size():
		return true
	if index < 0:
		return false
	var view: Array = views[index]
	var direction: Vector3 = (view[1] as Vector3).normalized()
	var distance: float = span * float(view[2]) * 1.15
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
	camera.look_at_from_position(centre + direction * distance, centre, up)
	if frame % 3 == 2:
		var image := root.get_viewport().get_texture().get_image()
		image.save_png("%s_%s.png" % [prefix, view[0]])
		print("SHOT: saved ", view[0])
	return false
