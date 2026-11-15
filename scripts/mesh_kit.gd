extends RefCounted
## Helpers for building flat-shaded meshes out of boxes, cylinders, spheres
## and gear discs. Axes are numbered 0 = X, 1 = Y, 2 = Z.

const TOOTH_STEPS := [0.0, 0.25, 0.5, 0.75]       # where a tooth's four corners sit, in tooth pitches
const TOOTH_AT_TIP := [false, true, true, false]  # which of those corners are on the tip circle

static var _detail_material: StandardMaterial3D = null
static var _lens_material: StandardMaterial3D = null
static var _tint_cache: Dictionary = {}


static func new_surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)   # flat shading: one normal per face
	return surface


## Adds one triangle, wound so that its front face points along `outward`.
static func add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	# The front-face normal Godot gives the winding a, b, c.
	var normal := (a - c).cross(a - b)
	if normal.length() < 0.0000001:
		return   # a sliver with no area
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


static func axis_vector(axis: int) -> Vector3:
	var direction := Vector3.ZERO
	direction[axis] = 1.0
	return direction


static func add_box(surface: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var half := size * 0.5
	for axis in 3:
		var normal := axis_vector(axis)
		var u := axis_vector((axis + 1) % 3) * half[(axis + 1) % 3]
		var v := axis_vector((axis + 2) % 3) * half[(axis + 2) % 3]
		for facing in [-1.0, 1.0]:
			var side: float = facing
			var out := normal * side
			var face := center + out * half[axis]
			add_triangle(surface, face - u - v, face + u - v, face + u + v, out)
			add_triangle(surface, face - u - v, face + u + v, face - u + v, out)


## A solid cylinder whose length runs along the given axis.
static func add_cylinder(surface: SurfaceTool, center: Vector3, axis: int, radius: float,
		length: float, segments: int = 16) -> void:
	var along := axis_vector(axis) * (length * 0.5)
	var u := axis_vector((axis + 1) % 3)
	var v := axis_vector((axis + 2) % 3)
	for segment in segments:
		var angle_a := float(segment) / float(segments) * TAU
		var angle_b := float(segment + 1) / float(segments) * TAU
		var rim_a := (u * cos(angle_a) + v * sin(angle_a)) * radius
		var rim_b := (u * cos(angle_b) + v * sin(angle_b)) * radius
		var outward := rim_a + rim_b
		add_triangle(surface, center + rim_a - along, center + rim_a + along, center + rim_b + along, outward)
		add_triangle(surface, center + rim_a - along, center + rim_b + along, center + rim_b - along, outward)
		add_triangle(surface, center + along, center + rim_a + along, center + rim_b + along, along)
		add_triangle(surface, center - along, center + rim_a - along, center + rim_b - along, -along)


## A cone section along the given axis: `radius_low` at the end toward the
## negative direction, `radius_high` at the end toward the positive direction.
static func add_frustum(surface: SurfaceTool, center: Vector3, axis: int, radius_low: float,
		radius_high: float, length: float, segments: int = 16) -> void:
	var along := axis_vector(axis) * (length * 0.5)
	var u := axis_vector((axis + 1) % 3)
	var v := axis_vector((axis + 2) % 3)
	for segment in segments:
		var angle_a := float(segment) / float(segments) * TAU
		var angle_b := float(segment + 1) / float(segments) * TAU
		var spoke_a := u * cos(angle_a) + v * sin(angle_a)
		var spoke_b := u * cos(angle_b) + v * sin(angle_b)
		var low_a := center - along + spoke_a * radius_low
		var low_b := center - along + spoke_b * radius_low
		var high_a := center + along + spoke_a * radius_high
		var high_b := center + along + spoke_b * radius_high
		var outward := spoke_a + spoke_b
		add_triangle(surface, low_a, high_a, high_b, outward)
		add_triangle(surface, low_a, high_b, low_b, outward)
		add_triangle(surface, center + along, high_a, high_b, along)
		add_triangle(surface, center - along, low_a, low_b, -along)


## A flat convex outline pushed along `offset` into a solid.
static func add_extruded_polygon(surface: SurfaceTool, points: Array, offset: Vector3) -> void:
	var count := points.size()
	var middle := Vector3.ZERO
	for point in points:
		var corner: Vector3 = point
		middle += corner
	middle /= float(count)
	for index in range(1, count - 1):
		var a: Vector3 = points[0]
		var b: Vector3 = points[index]
		var c: Vector3 = points[index + 1]
		add_triangle(surface, a, b, c, -offset)
		add_triangle(surface, a + offset, b + offset, c + offset, offset)
	for index in count:
		var p: Vector3 = points[index]
		var q: Vector3 = points[(index + 1) % count]
		var outward := (p + q) * 0.5 - middle
		add_triangle(surface, p, p + offset, q + offset, outward)
		add_triangle(surface, p, q + offset, q, outward)


static func _sphere_point(center: Vector3, radius: float, polar: float, azimuth: float) -> Vector3:
	return center + Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth)) * radius


static func add_sphere(surface: SurfaceTool, center: Vector3, radius: float,
		segments: int = 12, rings: int = 6) -> void:
	for ring in rings:
		var polar_a := float(ring) / float(rings) * PI
		var polar_b := float(ring + 1) / float(rings) * PI
		for segment in segments:
			var azimuth_a := float(segment) / float(segments) * TAU
			var azimuth_b := float(segment + 1) / float(segments) * TAU
			var p_aa := _sphere_point(center, radius, polar_a, azimuth_a)
			var p_ab := _sphere_point(center, radius, polar_a, azimuth_b)
			var p_ba := _sphere_point(center, radius, polar_b, azimuth_a)
			var p_bb := _sphere_point(center, radius, polar_b, azimuth_b)
			var outward := (p_aa + p_ab + p_ba + p_bb) * 0.25 - center
			add_triangle(surface, p_aa, p_ab, p_bb, outward)
			add_triangle(surface, p_aa, p_bb, p_ba, outward)


## A toothed disc. Teeth are drawn for looks only; meshing is worked out from
## tooth counts, never from the shape.
static func add_gear(surface: SurfaceTool, center: Vector3, axis: int, root_radius: float,
		tip_radius: float, thickness: float, teeth: int) -> void:
	var axis_unit := axis_vector(axis)
	var along := axis_unit * (thickness * 0.5)
	var u := axis_vector((axis + 1) % 3)
	var v := axis_vector((axis + 2) % 3)
	var pitch := TAU / float(teeth)

	var rim: Array = []   # the outline, anticlockwise about the axis
	for tooth in teeth:
		for corner in 4:
			var fraction: float = TOOTH_STEPS[corner]
			var at_tip: bool = TOOTH_AT_TIP[corner]
			var angle := (float(tooth) + fraction) * pitch
			var radius := tip_radius if at_tip else root_radius
			rim.append((u * cos(angle) + v * sin(angle)) * radius)

	var count := rim.size()
	for index in count:
		var p: Vector3 = rim[index]
		var q: Vector3 = rim[(index + 1) % count]
		var outward := (q - p).cross(axis_unit)
		add_triangle(surface, center + p - along, center + p + along, center + q + along, outward)
		add_triangle(surface, center + p - along, center + q + along, center + q - along, outward)
		add_triangle(surface, center + along, center + p + along, center + q + along, along)
		add_triangle(surface, center - along, center + p - along, center + q - along, -along)


## The fixed dark-metal look used for shafts, pins and other details.
static func detail_material() -> StandardMaterial3D:
	if _detail_material == null:
		_detail_material = StandardMaterial3D.new()
		_detail_material.albedo_color = Color(0.24, 0.25, 0.28)
		_detail_material.metallic = 0.7
		_detail_material.roughness = 0.45
	return _detail_material


## A plain coloured look for details that mark what kind of part this is,
## such as the chip on a logic block.
static func tinted_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if not _tint_cache.has(key):
		var tint := StandardMaterial3D.new()
		tint.albedo_color = color
		tint.roughness = 0.5
		_tint_cache[key] = tint
	return _tint_cache[key]


## The glossy black look of a light panel that is switched off.
static func lens_material() -> StandardMaterial3D:
	if _lens_material == null:
		_lens_material = StandardMaterial3D.new()
		_lens_material.albedo_color = Color(0.02, 0.02, 0.03)
		_lens_material.metallic = 0.0
		_lens_material.roughness = 0.12
	return _lens_material


## Joins a paintable body and a fixed-colour detail into one mesh.
## Surface 0 is the body, which takes the part's material and colour.
## Surface 1 is the detail, which keeps its own look: dark metal unless
## another material is given.
static func commit(body: SurfaceTool, detail: SurfaceTool, detail_look: Material = null) -> ArrayMesh:
	body.generate_normals()
	var mesh: ArrayMesh = body.commit()
	detail.generate_normals()
	if detail_look == null:
		detail.set_material(detail_material())
	else:
		detail.set_material(detail_look)
	detail.commit(mesh)
	return mesh
