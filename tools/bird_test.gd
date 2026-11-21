extends SceneTree
## Headless test of the birds: every species can be put down and moves
## sensibly, the areas roll by rarity, nests are planned, and the guide and
## camera checks work.     godot --headless --path . -s tools/bird_test.gd

const Origin = preload("res://scripts/origin.gd")
const BirdData = preload("res://scripts/bird_data.gd")
const Profile = preload("res://scripts/profile.gd")

var main: Node = null
var frame := 0
var groups: Array = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var birds: Node = main.get_node("Birds")
	if frame == 5:
		main.get_node("Menus").start_game()
		print("BIRDS: nests planned ", birds.nest_count())
		var kinds := {}
		for nest in birds._nests:
			kinds[nest["kind"]] = int(kinds.get(nest["kind"], 0)) + 1
		print("BIRDS: nest kinds ", kinds)
		var here := Origin.to_map(main.get_node("Player").global_position)
		var habitats := {}
		for i in 200:
			var x := here.x + (i % 20 - 10) * 150.0
			var z := here.z + (i / 20 - 5) * 150.0
			var h: String = birds.habitat_at(x, z)
			habitats[h] = int(habitats.get(h, 0)) + 1
		print("BIRDS: habitats round the hangar ", habitats)
	if frame == 10:
		var here := Origin.to_map(main.get_node("Player").global_position)
		for species in BirdData.SPECIES:
			var spot := here + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
			groups.append(birds.spawn_group(str(species), Vector3(spot.x, main.get_node("Terrain").height_at(spot.x, spot.z), spot.z)))
		print("BIRDS: groups ", birds._groups.size(), " birds ", birds._bird_count())
	if frame == 400:
		var bad := 0
		var moved := 0
		for group in groups:
			for bird in group["birds"]:
				var at: Vector3 = bird["at"]
				if is_nan(at.x) or is_nan(at.y) or absf(at.y) > 5000.0:
					bad += 1
					print("BIRDS: bad ", group["species"], " ", at)
				if (bird["velocity"] as Vector3).length() > 0.01 or bird["mode"] != "perch":
					moved += 1
		print("BIRDS: after 6.5 s: bad positions ", bad, ", moving or busy ", moved)
		var modes := {}
		for group in groups:
			for bird in group["birds"]:
				modes[bird["mode"]] = int(modes.get(bird["mode"], 0)) + 1
		print("BIRDS: modes ", modes)
		var camera: Camera3D = root.get_viewport().get_camera_3d()
		print("BIRDS: in the frame of the player camera ", birds.birds_in_frame(camera) if camera != null else "no camera")
		birds.startle(main.get_node("Player").global_position, 500.0)
		var fleeing := 0
		for group in groups:
			for bird in group["birds"]:
				if float(bird["flee"]) > 0.0:
					fleeing += 1
		print("BIRDS: startled ", fleeing)
		Profile.spot_bird("osprey")
		Profile.photograph_bird("osprey", "/tmp/x.png")
		print("BIRDS: unphotographed ", birds.unphotographed().size(), " of ", birds.species_count())
		var guide: Node = null
		for child in main.get_node("GameHud").root.get_children():
			if child.has_method("refresh") and child.get_script().resource_path.ends_with("bird_guide.gd"):
				guide = child
		guide.toggle()
		print("BIRDS: guide rows ", guide._list.get_child_count(), " page parts ", guide._page.get_child_count())
		guide._show("osprey")
		print("BIRDS: osprey page parts ", guide._page.get_child_count())
	if frame == 700:
		birds._plan_areas()
		print("BIRDS: after rolling areas, groups ", birds._groups.size(), " ", birds._groups.map(func(g): return g["species"]))
	return frame > 702
