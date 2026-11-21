extends SceneTree
## Headless test of the volcano's molten rocks: stands the character 3 km
## from the crater, starts an eruption and watches the rocks fly, land and
## burst, and a steel build in the open take hits.
##     godot --headless --path . -s tools/rock_test.gd

const Origin = preload("res://scripts/origin.gd")
const Terrain = preload("res://scripts/terrain.gd")

var main: Node = null
var frame := 0
var most := 0
var thrown := 0
var landed := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var disasters: Node = main.get_node("Disasters")
	var terrain: Node = main.get_node("Terrain")
	var player: Node3D = main.get_node("Player")
	match frame:
		5:
			main.get_node("Menus").start_game()
		10:
			var spot := Terrain.VOLCANO + Vector2(3000.0, 0.0)
			main._controller.respawn(Origin.to_world(Vector3(spot.x, terrain.height_at(spot.x, spot.y) + 2.0, spot.y)), 0.0)
		20:
			disasters.start_eruption()
	if frame > 20:
		most = maxi(most, disasters._rocks.size())
		for rock in disasters._rocks:
			if bool(rock["landed"]) and not rock.has("counted"):
				rock["counted"] = true
				landed += 1
	if frame % 600 == 0 and false:
		for rock in disasters._rocks.slice(0, 4):
			var body: RigidBody3D = rock["body"]
			var at := Origin.to_map(body.global_position)
			var space := body.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(body.global_position + Vector3(0, 3000, 0), body.global_position - Vector3(0, 5000, 0), 1)
			var hit := space.intersect_ray(query)
			var surface: float = Origin.to_map(hit["position"]).y if not hit.is_empty() else -9999.0
			print("  rock at %s ground %.0f surface %.0f (%s) speed %.0f life %.0f contacts %d" % [str(at.snapped(Vector3.ONE)), terrain.height_at(at.x, at.z), surface, str(hit.get("collider")), body.linear_velocity.length(), rock["life"], body.get_contact_count()])
	if frame % 1000 == 0:
		print("ROCKS: eruption %.0f s rocks now %d most %d landed %d | column %s | player hp %.0f" % [
			disasters._eruption, disasters._rocks.size(), most, landed, disasters._column != null, player.hp])
	return frame > 13000
