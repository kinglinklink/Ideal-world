extends RefCounted
## Definitions for every placeable part.
## First slice: a block and a wedge, each filling one grid cell.

const CELL := 0.1  # metres per grid cell (1 dm)

## Part ids in menu order, with their display names.
const PARTS := {
	"block": "Block",
	"wedge": "Wedge",
}

const BLOCK_COLOR := Color(0.80, 0.82, 0.86)
const GHOST_PLACE_COLOR := Color(0.35, 0.75, 1.0, 0.45)
const GHOST_DELETE_COLOR := Color(1.0, 0.25, 0.2, 0.55)

static var _mesh_cache: Dictionary = {}
static var _shape_cache: Dictionary = {}
static var _block_material: StandardMaterial3D = null
static var _ghost_place_material: StandardMaterial3D = null
static var _ghost_delete_material: StandardMaterial3D = null


static func part_ids() -> Array:
	return PARTS.keys()


static func part_name(part_id: String) -> String:
	return str(PARTS.get(part_id, part_id))


## The render mesh for a part, sized to one cell and centred on the cell centre.
static func get_mesh(part_id: String) -> Mesh:
	if not _mesh_cache.has(part_id):
		if part_id == "wedge":
			var prism := PrismMesh.new()
			prism.size = Vector3(CELL, CELL, CELL)
			prism.left_to_right = 0.0  # right-angle wedge
			_mesh_cache[part_id] = prism
		else:
			var box := BoxMesh.new()
			box.size = Vector3(CELL, CELL, CELL)
			_mesh_cache[part_id] = box
	return _mesh_cache[part_id]


## The collision shape for a part.
static func get_shape(part_id: String) -> Shape3D:
	if not _shape_cache.has(part_id):
		if part_id == "wedge":
			var h := CELL * 0.5
			var convex := ConvexPolygonShape3D.new()
			convex.points = PackedVector3Array([
				Vector3(-h, -h, -h), Vector3(h, -h, -h), Vector3(-h, h, -h),
				Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(-h, h, h),
			])
			_shape_cache[part_id] = convex
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(CELL, CELL, CELL)
			_shape_cache[part_id] = box
	return _shape_cache[part_id]


static func block_material() -> StandardMaterial3D:
	if _block_material == null:
		_block_material = StandardMaterial3D.new()
		_block_material.albedo_color = BLOCK_COLOR
		_block_material.roughness = 0.7
	return _block_material


static func ghost_material(for_delete: bool) -> StandardMaterial3D:
	if _ghost_place_material == null:
		_ghost_place_material = _make_ghost_material(GHOST_PLACE_COLOR)
		_ghost_delete_material = _make_ghost_material(GHOST_DELETE_COLOR)
	return _ghost_delete_material if for_delete else _ghost_place_material


static func _make_ghost_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	return mat


## A placed block: a static body with a mesh and a collider.
## Physics stays off in build mode; the collider is for clicking and walking.
static func make_block(part_id: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Block"

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = get_mesh(part_id)
	mesh_instance.material_override = block_material()
	body.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	collider.shape = get_shape(part_id)
	body.add_child(collider)
	return body
