extends SceneTree
## Headless test of fuel stations, fire on a hit fuel tank, and the failure
## log.     godot --headless --path . -s tools/fuel_test.gd

const BuildGrid = preload("res://scripts/build_grid.gd")
const SaveManager = preload("res://scripts/save_manager.gd")
const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")
const Profile = preload("res://scripts/profile.gd")

var main: Node = null
var frame := 0
var vehicle: Node = null
var tank_uid := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var fuel: Node = main.get_node("Fuel")
	var c := Units.UNITS_PER_CELL
	var h := Units.HALF_CELL_UNITS
	if frame == 5:
		main.get_node("Menus").start_game()
		print("FUEL: stations ", fuel.stations.size(), " e.g. ", fuel.stations.slice(0, 4).map(func(s): return s["name"]))
		var grid: Node = main.get_node("BuildGrid")
		for x in 3:
			for z in 3:
				grid.add_part(BuildGrid.make_record("block", Vector3i((20 + x) * c + h, h, (20 + z) * c + h),
						Basis.IDENTITY, Vector3i(c, c, c), "steel", Color.GRAY))
		var tank := BuildGrid.make_record("fuel_tank", Vector3i(21 * c + h, c + c, 21 * c + h), Basis.IDENTITY,
				Vector3i(2 * c, 2 * c, 2 * c), "aluminum", Color.WHITE)
		tank["props"]["fill"] = 20.0
		grid.add_part(tank)
		SaveManager.save_build(grid, "fuel-test")
		for uid in grid.all_uids():
			grid.remove_part(uid)
		var station: Dictionary = fuel.stations[0]
		var made: Array = main.get_node("Fleet").spawn_save_at("fuel-test", Origin.to_world((station["at"] as Vector3) + Vector3(0, 1.5, 0)), 0.0)
		vehicle = made[1]
		main._controller.respawn(Origin.to_world((station["pump"] as Vector3) + Vector3(1.0, 1.0, 0.0)), 0.0)
		Profile.add_cash(5000)
	if frame == 30:
		for uid in vehicle.all_records():
			if vehicle.all_records()[uid]["type"] == "fuel_tank":
				tank_uid = uid
		var engines: Node = vehicle.engines
		print("FUEL: tank holds ", snappedf(engines.total_fuel(), 0.1), " of ", engines.total_capacity(), " L; near pump ", not fuel._near.is_empty())
		var station: Dictionary = fuel.stations[0]
		print("FUEL: vehicles in circle ", fuel._vehicles_in(station).size(), " price/L ", fuel.price_per_litre(station, engines))
		var cash_before := Profile.cash()
		fuel._open(station)
		fuel._buy(station, engines, 1.0e9)
		print("FUEL: paid ", cash_before - Profile.cash())
	if frame == 120:
		print("FUEL: after pouring ", snappedf(vehicle.engines.total_fuel(), 0.1), " L")
		vehicle.damage_part(tank_uid, vehicle.full_health_of(tank_uid) * 0.5)
		print("FUEL: tank hit, health ", int(vehicle.health_of(tank_uid)), " of ", int(vehicle.full_health_of(tank_uid)))
	if frame == 400:
		print("FUEL: after 4.5 s of fire: fuel ", snappedf(vehicle.engines.total_fuel(), 0.1), " L, tank alive ", vehicle.live_parts().has(tank_uid),
				" parts ", vehicle.live_parts().size(), " effects ", main.get_node("DamageFx")._effects.size())
		print("FUEL: failure log entries ", main.get_node("FailureLog").entry_count(), ": ",
				main.get_node("FailureLog")._entries.map(func(e): return e["text"]))
		SaveManager.delete_save("fuel-test")
	return frame > 402
