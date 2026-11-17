extends SceneTree
## Headless test of the weather and disasters: starts each one and runs
## the game long enough for them to play out, printing what happens.
##     godot --headless --path . -s tools/disaster_test.gd

var main: Node = null
var frame := 0
var clock := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	frame += 1
	clock += delta
	var disasters: Node = main.get_node("Disasters")
	var weather: Node = main.get_node("Weather")
	match frame:
		5:
			main.get_node("Menus").start_game()
		20:
			weather.set_mode("storm")
			weather.set_season("winter")
			disasters.start_tornado()
			disasters.start_tsunami()
			disasters.start_eruption()
		40:
			disasters.start_earthquake()
			disasters.start_hurricane()
	if frame % 120 == 0:
		var player: Node3D = main.get_node("Player")
		print("TEST t=%.1f %s | wind here %s | water %.2f | bombs %d flows %d tornadoes %d | hp %.0f" % [
			clock, weather.describe(), str(weather._wind_at(player.global_position).snapped(Vector3(0.1, 0.1, 0.1))),
			weather.water_height(player.global_position), disasters._bombs.size(), disasters._flows.size(),
			disasters._tornadoes.size(), player.hp])
	if frame == 1500:
		disasters.calm_everything()
	return frame > 1530
