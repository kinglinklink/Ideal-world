extends SceneTree
## Headless test: carries a raced vehicle along the course and checks every
## ring counts.     godot --headless --path . -s tools/ring_test.gd

const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")
const Roads = preload("res://scripts/roads.gd")
const Ghosts = preload("res://scripts/ghosts.gd")
const Profile = preload("res://scripts/profile.gd")

var main: Node = null
var frame := 0
var carried := 0.0
var is_air := true
var ghost_round := false


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _start(air: bool) -> void:
	var races: Node = main.get_node("Races")
	var host: Dictionary = {}
	for item in races._hosts:
		if not (item["air" if air else "car"] as Array).is_empty():
			host = item
			break
	races._open_window(host)
	for index in races._vehicle_pick.item_count:
		if races._vehicle_pick.get_item_text(index) == "ring-test":
			races._vehicle_pick.select(index)
	races._start_race(host["air" if air else "car"][0], host, air, ghost_round)
	carried = 0.0
	is_air = air
	print("RING: ", "air" if air else "car", " race on ", not races._race.is_empty(), " rings ", races._race.get("rings", []).size())


func _process(delta: float) -> bool:
	frame += 1
	var races: Node = main.get_node("Races")
	if frame == 5:
		main.get_node("Menus").start_game()
		var grid: Node = main.get_node("BuildGrid")
		var c := Units.UNITS_PER_CELL
		var h := Units.HALF_CELL_UNITS
		for x in 4:
			for z in 6:
				grid.add_part(BuildGrid.make_record("block", Vector3i((20 + x) * c + h, h, (20 + z) * c + h),
						Basis.IDENTITY, Vector3i(c, c, c), "aluminum", Color.RED))
		grid.add_part(BuildGrid.make_record("seat", Vector3i(21 * c + h + c / 2, 2 * c + h, 22 * c + h),
				Basis.IDENTITY, Vector3i(3 * c, 3 * c, 3 * c), "steel", Color.GRAY))
		SaveManager.save_build(grid, "ring-test")
	elif frame == 10:
		_start(true)
	elif frame > 10 and not races._race.is_empty() and float(races._race["clock"]) > 0.0:
		# Carry the vehicle along the course at 150 m/s (cars 40 m/s).
		var path: PackedVector3Array = races._race["path"]
		var along: PackedFloat32Array = races._race["along"]
		carried += (150.0 if is_air else 40.0) * delta
		var index: int = races._index_at(along, carried)
		var point: Vector3 = path[mini(index, path.size() - 1)]
		var vehicle: Node = races._race["vehicle"]
		for body in vehicle.all_bodies():
			(body as RigidBody3D).freeze = true
		var first: RigidBody3D = vehicle.all_bodies()[0]
		var shift: Vector3 = Origin.to_world(point) - first.global_position
		for body in vehicle.all_bodies():
			(body as RigidBody3D).global_position += shift
		if frame % 60 == 0:
			print("RING: at ", int(carried), " m of ", int(along[along.size() - 1]), " next ", races._race["next"],
				" player ", Origin.to_map(main.get_node("Player").global_position).snapped(Vector3.ONE), " body ", point.snapped(Vector3.ONE))
	if frame > 12 and not races._race.is_empty() and ghost_round and frame % 120 == 0:
		var ghost: Dictionary = races._race["ghost"]
		if not ghost.is_empty() and float(races._race["clock"]) > 0.0:
			var vehicle: Node = races._race["vehicle"]
			print("RING: ghost body at ", Origin.to_map((ghost["nodes"][0] as Node3D).global_position).snapped(Vector3.ONE),
					" vehicle at ", Origin.to_map(vehicle.where()).snapped(Vector3.ONE))
	if frame > 12 and races._race.is_empty() and is_air and not ghost_round:
		print("RING: air race ended at frame ", frame, " won ", Profile.has_won("rookie"), " ghost ", Ghosts.about("rookie"))
		ghost_round = true
		_start(true)
		print("RING: racing with ghost: ", not (races._race["ghost"] as Dictionary).is_empty())
	elif frame > 12 and races._race.is_empty() and is_air and ghost_round:
		print("RING: ghost race ended at frame ", frame)
		ghost_round = false
		_start(false)
	elif frame > 12 and races._race.is_empty() and not is_air:
		print("RING: car race ended at frame ", frame)
		SaveManager.delete_save("ring-test")
		return true
	return frame > 30000
