extends Node3D
## Grass tufts around the home area, standing on the ground of the map.
## Everything is placed from a fixed random seed, so the landscape is the same
## every time the game runs. The trees are in forest.gd.
##
## The tufts are drawn as one MultiMesh, which lets the graphics card draw
## thousands of copies in a single batch. They are not solid.

const Kit = preload("res://scripts/mesh_kit.gd")

const SEED := 20261114
const GRASS_COUNT := 20000
const GRASS_REACH := 280.0    # metres from the home area's centre


## `home` is the footprint of the pad and garage in world X and Z. Grass
## starts `grass_margin` metres outside it. `ground` is terrain.gd, which
## gives the height of the ground and where the lake is.
func build(home: Rect2, grass_margin: float, ground: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_scatter_grass(rng, home.get_center(), home.grow(grass_margin), ground)


## A random point within `reach` of the centre that is outside `keep_out`.
func _random_spot(rng: RandomNumberGenerator, centre: Vector2, reach: float, keep_out: Rect2) -> Vector2:
	var spot := centre + Vector2(reach, 0.0)
	for attempt in 40:
		spot = centre + Vector2.from_angle(rng.randf() * TAU) * (reach * sqrt(rng.randf()))
		if not keep_out.has_point(spot):
			return spot
	return spot


## One tuft: five pointed blades of different heights.
func _grass_mesh() -> ArrayMesh:
	var surface := Kit.new_surface()
	var blades := [
		[0.0, 0.0, 0.55], [0.25, 0.1, 0.4], [-0.2, 0.2, 0.45], [0.1, -0.25, 0.35], [-0.25, -0.15, 0.5],
	]
	for blade in blades:
		var blade_x: float = blade[0]
		var blade_z: float = blade[1]
		var height: float = blade[2]
		Kit.add_frustum(surface, Vector3(blade_x, height * 0.5, blade_z), 1, 0.07, 0.0, height, 3)
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true   # each copy carries its own colour
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	return mesh


func _scatter_grass(rng: RandomNumberGenerator, centre: Vector2, keep_out: Rect2, ground: Node3D) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = _grass_mesh()
	batch.instance_count = GRASS_COUNT
	var placed := 0
	for index in GRASS_COUNT:
		var spot := _random_spot(rng, centre, GRASS_REACH, keep_out)
		var spread := rng.randf_range(0.7, 1.5)
		var tall := spread * rng.randf_range(0.8, 1.4)
		var turn := rng.randf() * TAU
		var tint := Color(rng.randf_range(0.24, 0.42), rng.randf_range(0.52, 0.72), rng.randf_range(0.18, 0.30))
		if ground.is_lake(spot.x, spot.y):
			continue   # no grass in the water
		var turned := Basis(Vector3.UP, turn) * Basis.from_scale(Vector3(spread, tall, spread))
		var height: float = ground.height_at(spot.x, spot.y)
		batch.set_instance_transform(placed, Transform3D(turned, Vector3(spot.x, height, spot.y)))
		batch.set_instance_color(placed, tint)
		placed += 1
	batch.visible_instance_count = placed
	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass"
	instance.multimesh = batch
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
