extends Node3D
## Grass tufts and trees around the home area. Everything is placed from a
## fixed random seed, so the landscape is the same every time the game runs.
##
## Each kind of plant is drawn as one MultiMesh, which lets the graphics card
## draw thousands of copies in a single batch. Tree trunks are solid; grass
## and leaves are not.

const Kit = preload("res://scripts/mesh_kit.gd")

const SEED := 20261114
const GRASS_COUNT := 20000
const GRASS_REACH := 280.0    # metres from the home area's centre
const TREE_REACH := 1000.0
const GROVE_COUNT := 70
const GROVE_RADIUS := 35.0
const LONE_TREES := 250
const TREE_SIZES := [0.8, 1.0, 1.3, 1.7]   # trees come in four sizes

const ROUND := 0   # a leafy tree with a blocky crown
const PINE := 1    # a conifer with three tiers
const TRUNK_RADIUS := [0.25, 0.2]    # by kind, at size 1
const TRUNK_HEIGHT := [3.0, 2.0]

## Where every tree stands, as (x, z) points, for the mini map.
var tree_spots := PackedVector2Array()


## `home` is the footprint of the pad and garage in world X and Z. Grass
## starts `grass_margin` metres outside it and trees `tree_margin` metres.
func build(home: Rect2, grass_margin: float, tree_margin: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var centre := home.get_center()
	_scatter_grass(rng, centre, home.grow(grass_margin))
	_scatter_trees(rng, centre, home.grow(tree_margin))


## A random point within `reach` of the centre that is outside `keep_out`.
func _random_spot(rng: RandomNumberGenerator, centre: Vector2, reach: float, keep_out: Rect2) -> Vector2:
	var spot := centre + Vector2(reach, 0.0)
	for attempt in 40:
		spot = centre + Vector2.from_angle(rng.randf() * TAU) * (reach * sqrt(rng.randf()))
		if not keep_out.has_point(spot):
			return spot
	return spot


func _plant_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true   # each copy carries its own colour
	material.roughness = 1.0
	return material


func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.generate_normals()
	var mesh: ArrayMesh = surface.commit()
	mesh.surface_set_material(0, _plant_material())
	return mesh


func _new_batch(mesh: Mesh, count: int) -> MultiMesh:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = count
	return batch


func _show_batch(batch: MultiMesh, batch_name: String, shadows: bool) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = batch_name
	instance.multimesh = batch
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


# --- Grass -------------------------------------------------------------------

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
	return _finish(surface)


func _scatter_grass(rng: RandomNumberGenerator, centre: Vector2, keep_out: Rect2) -> void:
	var batch := _new_batch(_grass_mesh(), GRASS_COUNT)
	for index in GRASS_COUNT:
		var spot := _random_spot(rng, centre, GRASS_REACH, keep_out)
		var spread := rng.randf_range(0.7, 1.5)
		var tall := spread * rng.randf_range(0.8, 1.4)
		var turned := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(spread, tall, spread))
		batch.set_instance_transform(index, Transform3D(turned, Vector3(spot.x, 0.0, spot.y)))
		batch.set_instance_color(index, Color(
				rng.randf_range(0.24, 0.42), rng.randf_range(0.52, 0.72), rng.randf_range(0.18, 0.30)))
	_show_batch(batch, "Grass", false)


# --- Trees -------------------------------------------------------------------

func _trunk_mesh(kind: int) -> ArrayMesh:
	var surface := Kit.new_surface()
	var radius: float = TRUNK_RADIUS[kind]
	var height: float = TRUNK_HEIGHT[kind]
	Kit.add_cylinder(surface, Vector3(0.0, height * 0.5, 0.0), 1, radius, height, 8)
	return _finish(surface)


func _crown_mesh(kind: int) -> ArrayMesh:
	var surface := Kit.new_surface()
	if kind == PINE:
		Kit.add_frustum(surface, Vector3(0.0, 3.0, 0.0), 1, 1.8, 0.6, 2.4, 8)
		Kit.add_frustum(surface, Vector3(0.0, 4.9, 0.0), 1, 1.3, 0.3, 2.2, 8)
		Kit.add_frustum(surface, Vector3(0.0, 6.6, 0.0), 1, 0.8, 0.0, 1.8, 8)
	else:
		Kit.add_box(surface, Vector3(0.0, 4.2, 0.0), Vector3(3.4, 2.4, 3.4))
		Kit.add_box(surface, Vector3(0.0, 5.9, 0.0), Vector3(2.2, 1.2, 2.2))
		Kit.add_box(surface, Vector3(1.0, 3.3, 0.6), Vector3(1.6, 1.0, 1.6))
	return _finish(surface)


func _scatter_trees(rng: RandomNumberGenerator, centre: Vector2, keep_out: Rect2) -> void:
	# Decide where every tree goes: mostly in groves, plus some on their own.
	var trees: Array = []   # each is [spot, size index, kind]
	for grove in GROVE_COUNT:
		var heart := _random_spot(rng, centre, TREE_REACH, keep_out.grow(GROVE_RADIUS * 0.5))
		var grove_kind := rng.randi_range(0, 1)
		var members := rng.randi_range(8, 22)
		for member in members:
			var spot := heart + Vector2.from_angle(rng.randf() * TAU) * (GROVE_RADIUS * sqrt(rng.randf()))
			if keep_out.has_point(spot):
				continue
			var kind := grove_kind
			if rng.randf() > 0.85:
				kind = 1 - grove_kind   # the odd one out
			trees.append([spot, rng.randi_range(0, TREE_SIZES.size() - 1), kind])
	for loner in LONE_TREES:
		var lone_spot := _random_spot(rng, centre, TREE_REACH, keep_out)
		trees.append([lone_spot, rng.randi_range(0, TREE_SIZES.size() - 1), rng.randi_range(0, 1)])

	# One solid body holds every trunk's collision shape.
	var trunks := StaticBody3D.new()
	trunks.name = "TreeTrunks"
	add_child(trunks)
	var shapes: Dictionary = {}   # "kind:size index" -> shared CylinderShape3D

	for kind in 2:
		var mine: Array = []
		for tree in trees:
			if tree[2] == kind:
				mine.append(tree)
		if mine.is_empty():
			continue
		var trunk_batch := _new_batch(_trunk_mesh(kind), mine.size())
		var crown_batch := _new_batch(_crown_mesh(kind), mine.size())
		for index in mine.size():
			var tree: Array = mine[index]
			var spot: Vector2 = tree[0]
			var size_index: int = tree[1]
			var size: float = TREE_SIZES[size_index]
			var turned := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(size, size, size))
			var placed := Transform3D(turned, Vector3(spot.x, 0.0, spot.y))
			trunk_batch.set_instance_transform(index, placed)
			crown_batch.set_instance_transform(index, placed)
			var bark := rng.randf_range(0.85, 1.1)
			trunk_batch.set_instance_color(index, Color(0.40 * bark, 0.28 * bark, 0.18 * bark))
			if kind == PINE:
				crown_batch.set_instance_color(index, Color(
						rng.randf_range(0.10, 0.20), rng.randf_range(0.34, 0.48), rng.randf_range(0.16, 0.26)))
			else:
				crown_batch.set_instance_color(index, Color(
						rng.randf_range(0.20, 0.36), rng.randf_range(0.50, 0.70), rng.randf_range(0.14, 0.28)))

			var shape_key := "%d:%d" % [kind, size_index]
			if not shapes.has(shape_key):
				var cylinder := CylinderShape3D.new()
				var base_radius: float = TRUNK_RADIUS[kind]
				var base_height: float = TRUNK_HEIGHT[kind]
				cylinder.radius = base_radius * size
				cylinder.height = base_height * size
				shapes[shape_key] = cylinder
			var trunk_shape: CylinderShape3D = shapes[shape_key]
			var collider := CollisionShape3D.new()
			collider.shape = trunk_shape
			collider.position = Vector3(spot.x, trunk_shape.height * 0.5, spot.y)
			trunks.add_child(collider)
			tree_spots.append(spot)

		var kind_name := "Pine" if kind == PINE else "Round"
		_show_batch(trunk_batch, kind_name + "Trunks", true)
		_show_batch(crown_batch, kind_name + "Crowns", true)
