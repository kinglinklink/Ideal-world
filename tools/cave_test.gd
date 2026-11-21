extends SceneTree
## Headless test of the caves: rays from deep inside every cave must all hit
## rock (no holes to the outside), and a character dropped in each cavern
## must land on its floor.     godot --headless --path . -s tools/cave_test.gd

const Origin = preload("res://scripts/origin.gd")
const Units = preload("res://scripts/units.gd")

var main: Node = null
var frame := 0
var cave_index := 0
var drop_frame := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var caves: Node = main.get_node("Terrain").caves
	if frame == 5:
		main.get_node("Menus").start_game()
		for item in caves.caves:
			var cave: Dictionary = item
			var hole: Array = cave.get("hole", [])
			print("CAVE: ", cave["name"], " hole ", hole, " faces ", (main.get_node("Terrain/Caves/CaveRock%d" % caves.caves.find(cave)).get_child(0).shape as ConcavePolygonShape3D).get_faces().size() / 3 if main.has_node("Terrain/Caves/CaveRock%d" % caves.caves.find(cave)) else -1)
	if frame == 8:
		var space := root.get_world_3d().direct_space_state
		var random := RandomNumberGenerator.new()
		random.seed = 5
		for item in caves.caves:
			var cave: Dictionary = item
			var starts: Array = [cave["cavern"], cave["deep"]]
			var passage: PackedVector3Array = cave["passage"]
			for k in [0.25, 0.5, 0.75]:
				starts.append(passage[int(passage.size() * k)])
			var tunnel: PackedVector3Array = cave["tunnel"]
			for k in [0.6, 0.8, 0.95]:
				starts.append(tunnel[int(tunnel.size() * k)])
			var escaped := 0
			var total := 0
			for start in starts:
				for ray in 200:
					var direction := Vector3(random.randf_range(-1, 1), random.randf_range(-1, 1), random.randf_range(-1, 1)).normalized()
					var from: Vector3 = Origin.to_world(start)
					var query := PhysicsRayQueryParameters3D.create(from, from + direction * 3000.0, Units.LAYER_WORLD)
					var hit := space.intersect_ray(query)
					total += 1
					if hit.is_empty():
						escaped += 1
			print("CAVE: ", cave["name"], " rays escaped ", escaped, " of ", total)
	if frame == 10:
		_drop()
	if frame == drop_frame + 360 and frame > 10:
		var cave: Dictionary = caves.caves[cave_index]
		var player: Node3D = main.get_node("Player")
		var at := Origin.to_map(player.global_position)
		var floor_y: float = (cave["deep"] as Vector3).y - 85.0 * 0.6
		print("CAVE: ", cave["name"], " dropped player now at ", at.snapped(Vector3.ONE), " deep floor about ", int(floor_y),
				" ok " if at.y > floor_y - 5.0 else " FELL THROUGH")
		cave_index += 1
		if cave_index < caves.caves.size():
			_drop()
		else:
			return true
	return frame > 20000


func _drop() -> void:
	var caves: Node = main.get_node("Terrain").caves
	var cave: Dictionary = caves.caves[cave_index]
	var deep: Vector3 = cave["deep"]
	main._controller.respawn(Origin.to_world(deep + Vector3(20.0, 0.0, 10.0)), 0.0)
	drop_frame = frame
