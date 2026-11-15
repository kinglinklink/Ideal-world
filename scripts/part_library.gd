extends RefCounted
## Definitions for every placeable part.
##
## Every part is described inside a 1 x 1 x 1 box centred on the origin. A
## part's real shape is that unit shape stretched to its size, so the volume
## and centre of mass below are given as fractions of the bounding box.

## id -> [name, category, default size in cells, volume fraction,
##        centre of mass in unit-box coordinates, collision kind]
const PARTS := {
	"block": ["Block", "Basic", Vector3(1, 1, 1), 1.0, Vector3(0, 0, 0), "box"],
	"wedge": ["Wedge", "Basic", Vector3(1, 1, 1), 0.5, Vector3(-0.16667, -0.16667, 0), "convex"],
	"triangle_wedge": ["Triangle wedge", "Basic", Vector3(1, 1, 1), 0.5, Vector3(0, -0.16667, 0), "convex"],
	"cylinder": ["Cylinder", "Basic", Vector3(1, 1, 1), 0.785398, Vector3(0, 0, 0), "convex"],
	"sphere": ["Sphere", "Basic", Vector3(1, 1, 1), 0.523599, Vector3(0, 0, 0), "convex"],
	"corner_wedge": ["Corner wedge", "Advanced", Vector3(1, 1, 1), 0.166667, Vector3(-0.25, -0.25, -0.25), "convex"],
	"pyramid": ["Pyramid", "Advanced", Vector3(1, 1, 1), 0.333333, Vector3(0, -0.25, 0), "convex"],
	"cone": ["Cone", "Advanced", Vector3(1, 1, 1), 0.261799, Vector3(0, -0.25, 0), "convex"],
	"hemisphere": ["Hemisphere", "Advanced", Vector3(1, 0.5, 1), 0.523599, Vector3(0, -0.125, 0), "convex"],
	"convex_curve": ["Convex curve", "Advanced", Vector3(1, 1, 1), 0.785398, Vector3(-0.07559, -0.07559, 0), "convex"],
	"concave_curve": ["Concave curve", "Advanced", Vector3(1, 1, 1), 0.214602, Vector3(-0.27665, -0.27665, 0), "concave"],
	"ring": ["Ring", "Advanced", Vector3(1, 1, 1), 0.502655, Vector3(0, 0, 0), "concave"],
}

const CATEGORIES := ["Basic", "Advanced"]
const RING_INNER_RADIUS := 0.3   # of a unit ring whose outer radius is 0.5
const CURVE_STEPS := 10

static var _mesh_cache: Dictionary = {}
static var _hull_cache: Dictionary = {}
static var _overlay_cache: Dictionary = {}


static func part_ids() -> Array:
	return PARTS.keys()


static func _row(part_id: String) -> Array:
	if PARTS.has(part_id):
		return PARTS[part_id]
	return PARTS["block"]


static func part_name(part_id: String) -> String:
	return _row(part_id)[0]


static func category(part_id: String) -> String:
	return _row(part_id)[1]


static func default_size_cells(part_id: String) -> Vector3:
	return _row(part_id)[2]


static func volume_fraction(part_id: String) -> float:
	return _row(part_id)[3]


static func unit_centroid(part_id: String) -> Vector3:
	return _row(part_id)[4]


# --- Meshes ------------------------------------------------------------------

## The unit-size render mesh for a part. Scale it by the part's size in metres.
static func get_mesh(part_id: String) -> Mesh:
	if not _mesh_cache.has(part_id):
		_mesh_cache[part_id] = _build_mesh(part_id)
	return _mesh_cache[part_id]


static func _build_mesh(part_id: String) -> Mesh:
	match part_id:
		"wedge":
			var wedge := PrismMesh.new()
			wedge.size = Vector3.ONE
			wedge.left_to_right = 0.0
			return wedge
		"triangle_wedge":
			var triangle := PrismMesh.new()
			triangle.size = Vector3.ONE
			triangle.left_to_right = 0.5
			return triangle
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 32
			cylinder.rings = 1
			return cylinder
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.radial_segments = 32
			cone.rings = 1
			return cone
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 24
			sphere.rings = 12
			return sphere
		"hemisphere":
			var dome := PackedVector2Array([Vector2(0.0, -0.5)])
			for step in CURVE_STEPS + 1:
				var angle := float(step) / float(CURVE_STEPS) * PI * 0.5
				dome.append(Vector2(0.5 * cos(angle), -0.5 + sin(angle)))
			return _lathe(dome, 24)
		"ring":
			return _lathe(PackedVector2Array([
				Vector2(RING_INNER_RADIUS, -0.5), Vector2(0.5, -0.5),
				Vector2(0.5, 0.5), Vector2(RING_INNER_RADIUS, 0.5),
			]), 32)
		"convex_curve":
			# A quarter disc: the round is centred on the (-X, -Y) corner.
			var quarter := PackedVector2Array([Vector2(-0.5, -0.5)])
			for step in CURVE_STEPS + 1:
				var angle := float(step) / float(CURVE_STEPS) * PI * 0.5
				quarter.append(Vector2(-0.5 + cos(angle), -0.5 + sin(angle)))
			return _extrude(quarter)
		"concave_curve":
			# A block with a quarter disc scooped out of its (+X, +Y) corner.
			var fillet := PackedVector2Array([Vector2(-0.5, -0.5)])
			for step in CURVE_STEPS + 1:
				var angle := float(step) / float(CURVE_STEPS) * PI * 0.5
				fillet.append(Vector2(0.5 - sin(angle), 0.5 - cos(angle)))
			return _extrude(fillet)
		"corner_wedge":
			var a := Vector3(-0.5, -0.5, -0.5)
			var b := Vector3(0.5, -0.5, -0.5)
			var c := Vector3(-0.5, 0.5, -0.5)
			var d := Vector3(-0.5, -0.5, 0.5)
			return _from_triangles([a, c, b, a, b, d, a, d, c, b, c, d])
		"pyramid":
			var p0 := Vector3(-0.5, -0.5, -0.5)
			var p1 := Vector3(0.5, -0.5, -0.5)
			var p2 := Vector3(0.5, -0.5, 0.5)
			var p3 := Vector3(-0.5, -0.5, 0.5)
			var apex := Vector3(0.0, 0.5, 0.0)
			return _from_triangles([
				p0, p1, p2, p0, p2, p3,
				p0, apex, p1, p1, apex, p2, p2, apex, p3, p3, apex, p0,
			])
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box


static func _new_surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)   # flat shading: one normal per face
	return surface


static func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.generate_normals()
	return surface.commit()


## Adds one triangle, wound so that its front face points along `outward`.
static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
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


## +1 when a flat outline runs anticlockwise, -1 when it runs clockwise.
static func _orientation(outline: PackedVector2Array) -> float:
	var doubled_area := 0.0
	var count := outline.size()
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		doubled_area += p.x * q.y - q.x * p.y
	return 1.0 if doubled_area >= 0.0 else -1.0


## A closed convex solid from a flat list of triangle corners.
static func _from_triangles(points: Array) -> ArrayMesh:
	var middle := Vector3.ZERO
	for point in points:
		var corner: Vector3 = point
		middle += corner
	middle /= float(points.size())

	var surface := _new_surface()
	for index in range(0, points.size(), 3):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var c: Vector3 = points[index + 2]
		_add_triangle(surface, a, b, c, (a + b + c) / 3.0 - middle)
	return _finish(surface)


## Pushes a flat outline in the XY plane through the box along Z.
static func _extrude(outline: PackedVector2Array) -> ArrayMesh:
	var surface := _new_surface()
	var turn := _orientation(outline)
	var count := outline.size()
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		var edge := q - p
		var side_out := Vector3(edge.y, -edge.x, 0.0) * turn
		var p_back := Vector3(p.x, p.y, -0.5)
		var p_front := Vector3(p.x, p.y, 0.5)
		var q_back := Vector3(q.x, q.y, -0.5)
		var q_front := Vector3(q.x, q.y, 0.5)
		_add_triangle(surface, p_back, p_front, q_front, side_out)
		_add_triangle(surface, p_back, q_front, q_back, side_out)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for index in range(0, triangles.size(), 3):
		var a := outline[triangles[index]]
		var b := outline[triangles[index + 1]]
		var c := outline[triangles[index + 2]]
		_add_triangle(surface, Vector3(a.x, a.y, 0.5), Vector3(b.x, b.y, 0.5), Vector3(c.x, c.y, 0.5), Vector3(0.0, 0.0, 1.0))
		_add_triangle(surface, Vector3(a.x, a.y, -0.5), Vector3(b.x, b.y, -0.5), Vector3(c.x, c.y, -0.5), Vector3(0.0, 0.0, -1.0))
	return _finish(surface)


## Spins a closed outline of (radius, height) points around the Y axis.
static func _lathe(outline: PackedVector2Array, segments: int) -> ArrayMesh:
	var surface := _new_surface()
	var turn := _orientation(outline)
	var count := outline.size()
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		if p.x < 0.00001 and q.x < 0.00001:
			continue   # this edge lies on the axis
		var edge := q - p
		var out_radial := edge.y * turn    # outward direction, away from the axis
		var out_height := -edge.x * turn   # outward direction, along Y
		for segment in segments:
			var angle_a := float(segment) / float(segments) * TAU
			var angle_b := float(segment + 1) / float(segments) * TAU
			var angle_mid := (angle_a + angle_b) * 0.5
			var outward := Vector3(out_radial * cos(angle_mid), out_height, out_radial * sin(angle_mid))
			var p_a := Vector3(p.x * cos(angle_a), p.y, p.x * sin(angle_a))
			var p_b := Vector3(p.x * cos(angle_b), p.y, p.x * sin(angle_b))
			var q_a := Vector3(q.x * cos(angle_a), q.y, q.x * sin(angle_a))
			var q_b := Vector3(q.x * cos(angle_b), q.y, q.x * sin(angle_b))
			_add_triangle(surface, p_a, q_a, q_b, outward)
			_add_triangle(surface, p_a, q_b, p_b, outward)
	return _finish(surface)


# --- Collision ---------------------------------------------------------------

## The distinct corner points of a part's unit mesh.
static func _unit_hull(part_id: String) -> PackedVector3Array:
	if not _hull_cache.has(part_id):
		var seen: Dictionary = {}
		var points := PackedVector3Array()
		for vertex in get_mesh(part_id).get_faces():
			var key: Vector3 = vertex.snapped(Vector3(0.0001, 0.0001, 0.0001))
			if not seen.has(key):
				seen[key] = true
				points.append(vertex)
		_hull_cache[part_id] = points
	return _hull_cache[part_id]


## The collision shape for a part at a given size in metres.
static func make_shape(part_id: String, size_m: Vector3) -> Shape3D:
	var kind: String = _row(part_id)[5]
	if kind == "box":
		var box := BoxShape3D.new()
		box.size = size_m
		return box
	if kind == "concave":
		var faces := get_mesh(part_id).get_faces()
		for index in faces.size():
			faces[index] = faces[index] * size_m
		var concave := ConcavePolygonShape3D.new()
		concave.backface_collision = true
		concave.set_faces(faces)
		return concave
	var hull := _unit_hull(part_id).duplicate()
	for index in hull.size():
		hull[index] = hull[index] * size_m
	var convex := ConvexPolygonShape3D.new()
	convex.points = hull
	return convex


# --- Overlays ----------------------------------------------------------------

## A see-through, unlit material for previews and highlights.
static func overlay_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if not _overlay_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_overlay_cache[key] = material
	return _overlay_cache[key]
