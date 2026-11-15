extends Node3D
## The build pad's block storage: one entry per occupied grid cell.
## The grid's minimum corner sits at this node's origin. Y is up.

signal block_count_changed(count: int)

const PartLibrary = preload("res://scripts/part_library.gd")

const CELL := 0.1                       # metres per grid cell (1 dm)
const SIZE := Vector3i(128, 128, 256)   # cells: X width, Y height, Z length

var _blocks: Dictionary = {}            # Vector3i -> StaticBody3D


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 \
			and cell.x < SIZE.x and cell.y < SIZE.y and cell.z < SIZE.z


func has_block(cell: Vector3i) -> bool:
	return _blocks.has(cell)


func block_count() -> int:
	return _blocks.size()


## Centre of a cell in this node's local space, in metres.
func cell_center(cell: Vector3i) -> Vector3:
	return (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * CELL


## The cell containing a point given in this node's local space.
func point_to_cell(local_point: Vector3) -> Vector3i:
	return Vector3i((local_point / CELL).floor())


## Size of the whole pad in metres.
func size_metres() -> Vector3:
	return Vector3(SIZE) * CELL


func add_block(cell: Vector3i, part_id: String, rot: Basis) -> bool:
	if not in_bounds(cell) or _blocks.has(cell):
		return false
	var body: StaticBody3D = PartLibrary.make_block(part_id)
	body.transform = Transform3D(rot, cell_center(cell))
	body.set_meta("cell", cell)
	body.set_meta("part_id", part_id)
	add_child(body)
	_blocks[cell] = body
	block_count_changed.emit(_blocks.size())
	return true


func remove_block(cell: Vector3i) -> bool:
	if not _blocks.has(cell):
		return false
	var body: Node = _blocks[cell]
	_blocks.erase(cell)
	body.queue_free()
	block_count_changed.emit(_blocks.size())
	return true
