extends Node3D
## Build-mode tools. First slice: Place (1) and Delete (2).
## Transform, Config and Paint are listed but not built yet.

signal tool_changed(new_tool: int)
signal part_changed(part_id: String)

const PartLibrary = preload("res://scripts/part_library.gd")

enum Tool { PLACE, DELETE, TRANSFORM, CONFIG, PAINT }

const TOOL_NAMES := ["Place", "Delete", "Transform", "Config", "Paint"]
const TOOLS_READY := [true, true, false, false, false]
const REACH := 80.0   # metres the tools can reach from the camera
const CELL := 0.1

var grid: Node3D = null              # build_grid.gd
var player: CharacterBody3D = null   # player.gd

var current_tool: int = Tool.PLACE
var part_id: String = "block"
var place_rotation: Basis = Basis.IDENTITY

var _ghost: MeshInstance3D
var _target_cell: Vector3i = Vector3i.ZERO
var _target_valid := false
var _hit_block: Node3D = null


func setup(p_grid: Node3D, p_player: CharacterBody3D) -> void:
	grid = p_grid
	player = p_player


func _ready() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func set_tool(new_tool: int) -> void:
	if new_tool < 0 or new_tool >= TOOLS_READY.size() or not TOOLS_READY[new_tool]:
		return
	current_tool = new_tool
	tool_changed.emit(current_tool)


## Picking a part from the menu also resets the placement rotation.
func set_part(new_part_id: String) -> void:
	part_id = new_part_id
	place_rotation = Basis.IDENTITY
	part_changed.emit(part_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.physical_keycode:
			KEY_1:
				set_tool(Tool.PLACE)
			KEY_2:
				set_tool(Tool.DELETE)
			KEY_R:
				_rotate_placement(Vector3(1.0, 0.0, 0.0))
			KEY_T:
				_rotate_placement(Vector3(0.0, 1.0, 0.0))
			KEY_Y:
				_rotate_placement(Vector3(0.0, 0.0, 1.0))
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_use_tool()


## R, T and Y turn the armed part 90 degrees about the world X, Y and Z axes.
func _rotate_placement(axis: Vector3) -> void:
	if current_tool != Tool.PLACE:
		return
	var turned := Basis(axis, PI * 0.5) * place_rotation
	# Snap back to exact 0 / +1 / -1 entries so quarter turns never drift.
	place_rotation = Basis(turned.x.round(), turned.y.round(), turned.z.round())


func _use_tool() -> void:
	if grid == null:
		return
	if current_tool == Tool.PLACE:
		if _target_valid:
			grid.add_block(_target_cell, part_id, place_rotation)
	elif current_tool == Tool.DELETE:
		if _hit_block != null and is_instance_valid(_hit_block):
			var cell: Vector3i = _hit_block.get_meta("cell")
			grid.remove_block(cell)
			_hit_block = null


func _physics_process(_delta: float) -> void:
	_update_target()
	_update_ghost()


## Casts the aim ray and works out which cell or block the tool points at.
func _update_target() -> void:
	_target_valid = false
	_hit_block = null
	if grid == null or player == null:
		return

	var ray: Array = player.get_pick_ray()
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * REACH)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var collider: Object = hit["collider"]
	if collider is Node3D and (collider as Node3D).has_meta("cell"):
		_hit_block = collider as Node3D

	if current_tool == Tool.PLACE:
		var hit_point: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit["normal"]
		var to_grid: Transform3D = grid.global_transform.affine_inverse()
		var local_point: Vector3 = to_grid * hit_point
		var local_normal: Vector3 = to_grid.basis * hit_normal
		# Step half a cell off the surface to land in the neighbouring cell.
		var cell: Vector3i = grid.point_to_cell(local_point + local_normal * (CELL * 0.5))
		var in_bounds: bool = grid.in_bounds(cell)
		var occupied: bool = grid.has_block(cell)
		if in_bounds and not occupied:
			_target_cell = cell
			_target_valid = true


## Shows a preview of the part to place, or a red marker on the block to delete.
func _update_ghost() -> void:
	if current_tool == Tool.PLACE and _target_valid:
		var center: Vector3 = grid.cell_center(_target_cell)
		_ghost.mesh = PartLibrary.get_mesh(part_id)
		_ghost.material_override = PartLibrary.ghost_material(false)
		_ghost.global_transform = grid.global_transform * Transform3D(place_rotation, center)
		_ghost.visible = true
	elif current_tool == Tool.DELETE and _hit_block != null and is_instance_valid(_hit_block):
		var hit_part: String = _hit_block.get_meta("part_id", "block")
		_ghost.mesh = PartLibrary.get_mesh(hit_part)
		_ghost.material_override = PartLibrary.ghost_material(true)
		_ghost.global_transform = _hit_block.global_transform.scaled_local(Vector3(1.04, 1.04, 1.04))
		_ghost.visible = true
	else:
		_ghost.visible = false
