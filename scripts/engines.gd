extends Node3D
## Fluids, fuel and engines: what makes the "Fluid and Engine" parts work
## once a build is spawned.
##
## Networks. Fluid parts that touch face to face are joined: tanks, pipes,
## pumps, valves, cylinders and engine parts. A closed valve splits a network
## in two. Each network carries what is in it:
##   - fuel, from fuel tanks, to combustion cylinders (through a pump),
##     combustors and thrusters set to need fuel;
##   - hydraulic oil, pumped into hydraulic cylinders, which move at the
##     pumps' flow over their area and push with the pumps' pressure × area,
##     and hold where they are, locked, when the pumps stop;
##   - gas, in pressure tanks and gas cylinders, at one pressure across the
##     network by the ideal gas law (taken at constant temperature); a pump
##     in a gas network pumps outside air in. A gas cylinder pushes with
##     (pressure − outside air) × area, so it is an air spring.
##
## Combustion cylinders work as in the design document. Fuel the pump sends
## collects in each cylinder. With "Fires by itself" on (and no Spark link)
## it fires just past the top of its stroke; otherwise when Spark switches
## on. The fuel burns at once, as much as the air in it can burn (14.7 kg of
## air per kg of fuel), and the heat raises the pressure; the gas then
## expands adiabatically (γ = 1.4), pushing the rod out. Near the bottom it
## exhausts and takes in fresh air, which is squeezed on the way back up
## (compression ratio COMPRESSION). A crankshaft and linkage bar turn that
## into turning: that part is yours to build.
##
## A jet engine is a network holding a compressor, a combustor, a turbine and
## a nozzle. Its spool speeds up and slows down with the fuel flow; air flow
## is air density × compressor face area × DESIGN_AIR_SPEED × spool; the
## burnt fuel's heat, at the ideal Brayton efficiency for the compressor's
## pressure ratio, speeds that air up; thrust = air flow × (jet speed −
## flight speed), out of the back of the nozzle (along its +Z).
##
## A solid rocket burns for its burn time once Ignite switches on, losing its
## propellant's mass as it goes.

const Spawner = preload("res://scripts/spawner.gd")
const BuildGrid = preload("res://scripts/build_grid.gd")
const Units = preload("res://scripts/units.gd")
const Origin = preload("res://scripts/origin.gd")
const Aero = preload("res://scripts/aero.gd")
const Sound = preload("res://scripts/sound.gd")

const FLUID_TYPES := ["fluid_cylinder", "pump", "valve", "fluid_pipe", "fuel_tank", "pressure_tank",
		"combustion_cylinder", "compressor", "combustor", "turbine", "nozzle", "thruster"]
const GAS_CONSTANT := 8.314       # J/(mol K)
const AIR_TEMPERATURE := 288.0    # K
const SEA_LEVEL_PRESSURE := 101325.0
const SEA_LEVEL_AIR := 1.225
const GAMMA := 1.4
const COMPRESSION := 9.0          # a combustion cylinder's compression ratio
const AIR_PER_FUEL := 14.7        # kg of air to burn 1 kg of fuel
const HOLD_PRESSURE := 20000000.0 # Pa: what locked hydraulic oil holds against
const GAS_DEAD_SHARE := 0.1       # a gas cylinder's room when closed, as a share of its stroke
const TANK_SHELL := 0.15          # a fuel tank's empty mass, as a share of a solid block's
const ROCKET_SHELL := 0.25        # a solid rocket's empty mass, likewise
const ROCKET_EXHAUST_SPEED := 2000.0   # m/s: sets how much propellant a rocket burns
const THRUSTER_EXHAUST_SPEED := 2500.0 # m/s: sets how much fuel a fuel-fed thruster burns
const DESIGN_AIR_SPEED := 100.0   # m/s through a jet's compressor face at full spool
const DESIGN_RPM := 12000.0
const SPOOL_TIME := 2.5           # seconds for a jet's spool to come most of the way up to speed
const AIR_PER_JET_FUEL := 15.0

var spawner: Node3D = null    # spawner.gd

var _generation := -1
var _parts: Dictionary = {}       # uid -> {"type", "box"}
var _neighbours: Dictionary = {}  # uid -> Array of touching fluid parts
var _tanks: Dictionary = {}       # fuel tank uid -> {"fuel" L, "capacity" L, "density" kg/L, "energy" J/L, "shell" kg, "shown" kg}
var _gas: Dictionary = {}         # pressure tank or gas cylinder uid -> {"n" mol}
var _cylinders: Dictionary = {}   # cylinder uid -> its state, see _start
var _drives: Dictionary = {}      # hydraulic cylinder uid -> [m/s, N]
var _pressure: Dictionary = {}    # uid -> Pa, for gas parts
var _network: Dictionary = {}     # uid -> index into _networks, this tick
var _networks: Array = []
var _spools: Dictionary = {}      # first compressor uid of a jet -> spool speed, 0 to 1
var _jet_flames: Dictionary = {}  # nozzle uid -> flame
var _rockets: Dictionary = {}     # solid rocket uid -> state
var _mass_timer := 0.0


func setup(the_spawner: Node3D) -> void:
	spawner = the_spawner
	spawner.engines = self


func _physics_process(delta: float) -> void:
	if spawner == null:
		return
	if not bool(spawner.spawned):
		if _generation != -1:
			_clear()
		return
	if int(spawner.generation) != _generation:
		_clear()
		_start()
	_find_networks()
	for index in _networks.size():
		_run_network(_networks[index], delta)
	_run_rockets(delta)
	_mass_timer -= delta
	if _mass_timer <= 0.0:
		_mass_timer = 0.25
		_update_tank_masses()


func _clear() -> void:
	_generation = -1
	_parts.clear()
	_neighbours.clear()
	_tanks.clear()
	_gas.clear()
	_cylinders.clear()
	_drives.clear()
	_pressure.clear()
	_network.clear()
	_networks.clear()
	_spools.clear()
	_jet_flames.clear()
	_rockets.clear()


func _start() -> void:
	_generation = int(spawner.generation)
	var records: Dictionary = spawner.all_records()
	var ambient := _ambient_pressure(Vector3.ZERO)
	for key in records:
		var uid: int = key
		var record: Dictionary = records[uid]
		var type: String = record["type"]
		var props: Dictionary = record.get("props", {})
		if type == "solid_rocket":
			_start_rocket(uid, record, props)
			continue
		if not FLUID_TYPES.has(type):
			continue
		if type == "thruster" and bool(props.get("ideal", true)):
			continue   # needs no fuel, so joins nothing
		var box := AABB()
		for index in Spawner.piece_count(record):
			var piece_box: AABB = Spawner._piece_box(uid * Spawner.PIECES + index, record)
			box = piece_box if index == 0 else box.merge(piece_box)
		_parts[uid] = {"type": type, "box": box}
		var size_m: Vector3 = Units.to_metres(record["size"] as Vector3i)
		match type:
			"fuel_tank":
				var capacity := size_m.x * size_m.y * size_m.z * 1000.0
				var density := maxf(float(props.get("fuel_density", 0.75)), 0.01)
				_tanks[uid] = {
					"capacity": capacity,
					"fuel": capacity * clampf(float(props.get("fill", 100.0)), 0.0, 100.0) / 100.0,
					"density": density, "energy": float(props.get("energy_density", 34.0)) * 1000000.0,
					"shell": BuildGrid.mass_of(record) * TANK_SHELL, "shown": -1.0,
				}
			"pressure_tank":
				var volume := size_m.x * size_m.y * size_m.z
				var start := float(props.get("pressure", 101.3)) * 1000.0
				_gas[uid] = {"n": start * volume / (GAS_CONSTANT * AIR_TEMPERATURE), "volume": volume}
			"fluid_cylinder", "combustion_cylinder":
				var bore := float(props.get("bore", 0.6)) * Units.CELL
				var stroke := maxf(float(props.get("stroke", 1.0)) * Units.CELL, 0.01)
				var area := PI * bore * bore * 0.25
				var kind := "combustion"
				if type == "fluid_cylinder":
					kind = "hydraulic" if str(props.get("fluid", "Hydraulic oil")) == "Hydraulic oil" else "gas"
				var clearance := stroke / (COMPRESSION - 1.0)
				_cylinders[uid] = {
					"kind": kind, "area": area, "stroke": stroke, "x": 0.0, "clearance": clearance,
					"auto": bool(props.get("auto_spark", true)),
					# Combustion: "charge" (fresh air, squeezed going in) or "power"
					# (burnt gas, expanding); p0 and v0 fix the curve it is on.
					"phase": "charge", "p0": ambient, "v0": area * clearance,   # as built: closed, at the outside pressure
					"fuel": 0.0, "spark_was": false, "pressure": ambient, "outward": 0.0,
				}
				if kind == "gas":
					var dead := stroke * GAS_DEAD_SHARE
					_gas[uid] = {"n": ambient * area * dead / (GAS_CONSTANT * AIR_TEMPERATURE), "volume": area * dead}
	# Which fluid parts touch which.
	var uids: Array = _parts.keys()
	for uid in uids:
		_neighbours[uid] = []
	for i in uids.size():
		for j in range(i + 1, uids.size()):
			var a: int = uids[i]
			var b: int = uids[j]
			if Spawner._touching(_parts[a]["box"], _parts[b]["box"]):
				(_neighbours[a] as Array).append(b)
				(_neighbours[b] as Array).append(a)


# --- Networks ------------------------------------------------------------------

func _alive(uid: int) -> bool:
	return not spawner.record_of(uid).is_empty()


func _valve_open(uid: int) -> bool:
	var record: Dictionary = spawner.record_of(uid)
	var links: Dictionary = record.get("links", {})
	var props: Dictionary = record.get("props", {})
	if links.has("amount"):
		return spawner.input_value(links, "amount", 0.0) > 0.01
	return spawner.input_value(links, "open", 1.0 if bool(props.get("open", false)) else 0.0) != 0.0


## Groups the fluid parts still there into networks, through open valves.
func _find_networks() -> void:
	_network.clear()
	_networks.clear()
	var open: Dictionary = {}
	for key in _parts:
		var uid: int = key
		if str(_parts[uid]["type"]) == "valve":
			open[uid] = _alive(uid) and _valve_open(uid)
	for key in _parts:
		var first: int = key
		if _network.has(first) or not _alive(first):
			continue
		if open.has(first) and not bool(open[first]):
			continue   # a closed valve belongs to no network
		var members: Array = [first]
		_network[first] = _networks.size()
		var index := 0
		while index < members.size():
			var uid: int = members[index]
			index += 1
			for item in _neighbours[uid]:
				var other: int = item
				if _network.has(other) or not _alive(other):
					continue
				if open.has(other) and not bool(open[other]):
					continue
				_network[other] = _networks.size()
				members.append(other)
		_networks.append(members)


func _run_network(members: Array, delta: float) -> void:
	var by_type: Dictionary = {}
	for item in members:
		var uid: int = item
		var type: String = _parts[uid]["type"]
		if not by_type.has(type):
			by_type[type] = []
		(by_type[type] as Array).append(uid)
	var ambient := _ambient_pressure(_position_of(members[0]))

	# Pumps: litres a second (less than 0 runs them backward), and the most pressure they make.
	var flow := 0.0
	var pump_pressure := 0.0
	for item in by_type.get("pump", []):
		var uid: int = item
		var record: Dictionary = spawner.record_of(uid)
		var links: Dictionary = record.get("links", {})
		var props: Dictionary = record.get("props", {})
		var on: bool = spawner.input_value(links, "on", 1.0) != 0.0
		var rate: float = clampf(spawner.input_value(links, "rate", 1.0), -1.0, 1.0)
		var pumped: float = float(props.get("max_flow", 1.0)) * rate if on else 0.0
		flow += pumped
		pump_pressure = maxf(pump_pressure, float(props.get("max_pressure", 10.0)) * 1000000.0)
		spawner.set_outputs(uid, {"flow": pumped})

	# Hydraulic oil: cylinders move at the flow over their whole area.
	var hydraulic: Array = []
	var gas_parts: Array = []
	for item in by_type.get("fluid_cylinder", []):
		var uid: int = item
		var cylinder: Dictionary = _cylinders[uid]
		if str(cylinder["kind"]) == "hydraulic":
			hydraulic.append(uid)
		else:
			gas_parts.append(uid)
	gas_parts.append_array(by_type.get("pressure_tank", []))
	if not hydraulic.is_empty():
		var total_area := 0.0
		for uid in hydraulic:
			total_area += float(_cylinders[uid]["area"])
		var speed := flow / 1000.0 / maxf(total_area, 1e-6)
		var pressure := pump_pressure if absf(flow) > 0.0 else HOLD_PRESSURE
		for item in hydraulic:
			var uid: int = item
			var area: float = _cylinders[uid]["area"]
			_drives[uid] = [speed, pressure * area]
			var cylinder: Dictionary = _cylinders[uid]
			spawner.set_outputs(uid, {"pressure": (pump_pressure if absf(flow) > 0.0 else 0.0) / 1000.0,
					"length": float(cylinder["x"]) / Units.CELL})
		flow = 0.0   # the pumps' oil went here

	# Gas: one pressure through the network.
	if not gas_parts.is_empty():
		var amount := 0.0
		var volume := 0.0
		for item in gas_parts:
			var uid: int = item
			amount += float(_gas[uid]["n"])
			volume += _gas_volume(uid)
		if flow != 0.0 and by_type.get("fuel_tank", []).is_empty():
			var now := amount * GAS_CONSTANT * AIR_TEMPERATURE / maxf(volume, 1e-9)
			if flow < 0.0 or now < pump_pressure:
				amount = maxf(amount + flow / 1000.0 * ambient / (GAS_CONSTANT * AIR_TEMPERATURE) * delta, 0.0)
			flow = 0.0
		var pressure := amount * GAS_CONSTANT * AIR_TEMPERATURE / maxf(volume, 1e-9)
		for item in gas_parts:
			var uid: int = item
			var share := _gas_volume(uid) / maxf(volume, 1e-9)
			_gas[uid]["n"] = amount * share
			_pressure[uid] = pressure
			if _cylinders.has(uid):
				spawner.set_outputs(uid, {"pressure": pressure / 1000.0,
						"length": float(_cylinders[uid]["x"]) / Units.CELL})
			else:
				spawner.set_outputs(uid, {"pressure": pressure / 1000.0})

	# Fuel to combustion cylinders, at the pumps' rate.
	var burners: Array = by_type.get("combustion_cylinder", [])
	if not burners.is_empty() and flow > 0.0:
		# Each takes no more than a full charge of air can burn; the rest stays in the tank.
		var density: float = _fuel_of(members).y
		var rooms: Array = []
		var total_room := 0.0
		for item in burners:
			var cylinder: Dictionary = _cylinders[item]
			var full: float = float(cylinder["area"]) * (float(cylinder["stroke"]) + float(cylinder["clearance"]))
			var burnable: float = ambient * full / (287.0 * AIR_TEMPERATURE) / AIR_PER_FUEL / maxf(density, 1e-6)
			var room := maxf(burnable - float(cylinder["fuel"]), 0.0)
			rooms.append(room)
			total_room += room
		var sent := _draw_fuel(members, minf(flow * delta, total_room))
		for index in burners.size():
			var uid: int = burners[index]
			if total_room > 0.0:
				_cylinders[uid]["fuel"] = float(_cylinders[uid]["fuel"]) + sent * float(rooms[index]) / total_room
	for item in burners:
		var uid: int = item
		spawner.set_outputs(uid, {"pressure": float(_cylinders[uid]["pressure"]) / 1000.0})

	for item in by_type.get("fuel_tank", []):
		var uid: int = item
		var tank: Dictionary = _tanks[uid]
		spawner.set_outputs(uid, {"level": 100.0 * float(tank["fuel"]) / maxf(float(tank["capacity"]), 1e-9)})

	_run_jet(members, by_type, delta)


func _gas_volume(uid: int) -> float:
	if _cylinders.has(uid):
		var cylinder: Dictionary = _cylinders[uid]
		return float(cylinder["area"]) * (clampf(float(cylinder["x"]), 0.0, float(cylinder["stroke"]))
				+ float(cylinder["stroke"]) * GAS_DEAD_SHARE)
	return float(_gas[uid]["volume"])


## Takes up to `litres` of fuel from the tanks among `members`, evenly by
## what each holds. Returns the litres taken.
func _draw_fuel(members: Array, litres: float) -> float:
	if litres <= 0.0:
		return 0.0
	var held := 0.0
	for item in members:
		if _tanks.has(item):
			held += float(_tanks[item]["fuel"])
	if held <= 0.0:
		return 0.0
	var taken := minf(litres, held)
	for item in members:
		if _tanks.has(item):
			var tank: Dictionary = _tanks[item]
			tank["fuel"] = maxf(float(tank["fuel"]) - taken * float(tank["fuel"]) / held, 0.0)
	return taken


## Joules in a litre of the fuel among `members` (from the first tank), and its kg/L.
func _fuel_of(members: Array) -> Vector2:
	for item in members:
		if _tanks.has(item):
			return Vector2(float(_tanks[item]["energy"]), float(_tanks[item]["density"]))
	return Vector2(34000000.0, 0.75)


func _position_of(uid: int) -> Vector3:
	var frame: Array = spawner.part_frame(uid)
	return (frame[0] as Transform3D).origin if not frame.is_empty() else Vector3.ZERO


func _ambient_pressure(at: Vector3) -> float:
	return SEA_LEVEL_PRESSURE * Aero.air_density(Origin.to_map(at).y) / SEA_LEVEL_AIR


func _update_tank_masses() -> void:
	for key in _tanks:
		var uid: int = key
		var tank: Dictionary = _tanks[uid]
		var mass: float = float(tank["shell"]) + float(tank["fuel"]) * float(tank["density"])
		if absf(mass - float(tank["shown"])) > 0.05 and _alive(uid):
			tank["shown"] = mass
			spawner.set_part_mass(uid, mass)


# --- Fuel for couplers (rigging.gd) -------------------------------------------------

## Litres of fuel in every tank of the build.
func total_fuel() -> float:
	var held := 0.0
	for key in _tanks:
		if _alive(key):
			held += float(_tanks[key]["fuel"])
	return held


## Takes up to `litres` from every tank alike. Returns what it took.
func take_fuel(litres: float) -> float:
	var live: Array = []
	for key in _tanks:
		if _alive(key):
			live.append(key)
	return _draw_fuel(live, litres)


## Pours up to `litres` into tanks with room. Returns what went in.
func add_fuel(litres: float) -> float:
	var left := maxf(litres, 0.0)
	for key in _tanks:
		if left <= 0.0:
			break
		if not _alive(key):
			continue
		var tank: Dictionary = _tanks[key]
		var room := maxf(float(tank["capacity"]) - float(tank["fuel"]), 0.0)
		var poured := minf(room, left)
		tank["fuel"] = float(tank["fuel"]) + poured
		left -= poured
	return maxf(litres, 0.0) - left


# --- Called by the spawner -------------------------------------------------------

## A hydraulic cylinder's drive: [speed out in m/s, most force in N]. `out`
## is how far its rod is out, in metres.
func hydraulic_drive(uid: int, out: float) -> Array:
	if _cylinders.has(uid):
		_cylinders[uid]["x"] = maxf(out, 0.0)
	if _drives.has(uid):
		return _drives[uid]
	if _cylinders.has(uid):
		return [0.0, HOLD_PRESSURE * float(_cylinders[uid]["area"])]
	return [0.0, 1000.0]


## The force pushing a gas or combustion cylinder's rod out, in newtons, with
## the rod `out` metres from closed and moving out at `moving` m/s.
func cylinder_force(uid: int, out: float, moving: float, _delta: float) -> float:
	if not _cylinders.has(uid):
		return 0.0
	var cylinder: Dictionary = _cylinders[uid]
	var stroke: float = cylinder["stroke"]
	var x := clampf(out, 0.0, stroke)
	cylinder["x"] = x
	var area: float = cylinder["area"]
	var ambient := _ambient_pressure(_position_of(uid))
	if str(cylinder["kind"]) == "gas":
		# Between network updates the gas in this cylinder follows its own volume.
		var n: float = _gas[uid]["n"]
		var gas_pressure := n * GAS_CONSTANT * AIR_TEMPERATURE / maxf(_gas_volume(uid), 1e-9)
		return (gas_pressure - ambient) * area
	if str(cylinder["kind"]) != "combustion":
		return 0.0

	var clearance: float = cylinder["clearance"]
	var volume := area * (x + clearance)
	var phase: String = cylinder["phase"]
	# Out near the bottom, or turned back early after firing: blow the burnt gas
	# out and take in fresh air.
	if x >= stroke * 0.92 or (phase == "power" and moving < -0.05 and float(cylinder["outward"]) > 0.0):
		cylinder["phase"] = "charge"
		cylinder["p0"] = ambient
		cylinder["v0"] = volume
		phase = "charge"
	cylinder["outward"] = moving
	var pressure: float = float(cylinder["p0"]) * pow(float(cylinder["v0"]) / volume, GAMMA)

	# The spark: by itself just past the top, or when Spark switches on.
	var record: Dictionary = spawner.record_of(uid)
	var links: Dictionary = record.get("links", {})
	var fire := false
	if links.has("spark"):
		var spark: bool = spawner.input_value(links, "spark", 0.0) != 0.0
		fire = spark and not bool(cylinder["spark_was"])
		cylinder["spark_was"] = spark
	elif bool(cylinder["auto"]):
		fire = phase == "charge" and x < stroke * 0.08 and moving > 0.0
	if fire and phase == "charge":
		var fuel_litres: float = cylinder["fuel"]
		cylinder["fuel"] = 0.0
		var members: Array = _networks[_network[uid]] if _network.has(uid) else []
		var fuel: Vector2 = _fuel_of(members)
		# As much as the air in it can burn; the rest goes out unburnt.
		var air_kg: float = float(cylinder["p0"]) * float(cylinder["v0"]) / (287.0 * AIR_TEMPERATURE)
		var burnt_kg := minf(fuel_litres * fuel.y, air_kg / AIR_PER_FUEL)
		var heat := burnt_kg / maxf(fuel.y, 1e-6) * fuel.x
		if heat > 0.0:
			Sound.play_at("piston_pop", _position_of(uid), clampf(linear_to_db(maxf(area / 0.0177, 0.1)), -14.0, 6.0) - 4.0,
					6.0 + sqrt(area) * 20.0, randf_range(0.9, 1.1) * clampf(sqrt(0.0177 / maxf(area, 1e-4)), 0.5, 2.0))
			pressure += heat * (GAMMA - 1.0) / volume
			cylinder["phase"] = "power"
			cylinder["p0"] = pressure
			cylinder["v0"] = volume
	cylinder["pressure"] = pressure
	return (pressure - ambient) * area


## The share (0 to 1) of a fuel-fed thruster's thrust its fuel allows this
## tick; it takes the fuel. 1 for one that needs none.
func thruster_fuel(uid: int, thrust: float, delta: float) -> float:
	if not _parts.has(uid):
		return 1.0
	if not _network.has(uid):
		return 0.0
	var members: Array = _networks[_network[uid]]
	var fuel: Vector2 = _fuel_of(members)
	var wanted := thrust / THRUSTER_EXHAUST_SPEED / maxf(fuel.y, 1e-6) * delta   # litres
	if wanted <= 0.0:
		return 1.0
	return _draw_fuel(members, wanted) / wanted


# --- Jet engines -----------------------------------------------------------------

func _run_jet(members: Array, by_type: Dictionary, delta: float) -> void:
	var compressors: Array = by_type.get("compressor", [])
	var combustors: Array = by_type.get("combustor", [])
	var turbines: Array = by_type.get("turbine", [])
	var nozzles: Array = by_type.get("nozzle", [])
	if compressors.is_empty() or combustors.is_empty() or nozzles.is_empty():
		for item in nozzles:
			_show_flame(item, 0.0)
		return
	var key: int = compressors[0]
	# Fuel the combustors ask for: their fuel rate (0 to 1, full if not linked) × their most.
	var asked := 0.0
	var most := 0.0
	for item in combustors:
		var record: Dictionary = spawner.record_of(item)
		var props: Dictionary = record.get("props", {})
		var rate: float = clampf(spawner.input_value(record.get("links", {}), "fuel_rate", 1.0), 0.0, 1.0)
		most += float(props.get("max_fuel_flow", 0.1))
		asked += float(props.get("max_fuel_flow", 0.1)) * rate
	var burning := _draw_fuel(members, asked * delta) / maxf(delta, 1e-6)   # L/s
	# The spool follows the fuel, with a lag; with no turbine nothing turns the compressor.
	var spool: float = _spools.get(key, 0.0)
	var wanted := sqrt(clampf(burning / maxf(most, 1e-9), 0.0, 1.0)) if not turbines.is_empty() else 0.0
	spool += (wanted - spool) * clampf(delta / SPOOL_TIME, 0.0, 1.0)
	_spools[key] = spool
	var face := 0.0
	var pressure_ratio := 0.0
	for item in compressors:
		var record: Dictionary = spawner.record_of(item)
		var size_m: Vector3 = Units.to_metres(record["size"] as Vector3i)
		var diameter := minf(size_m.x, size_m.y)
		face += PI * diameter * diameter * 0.25
		pressure_ratio += float(record.get("props", {}).get("pressure_ratio", 8.0))
	pressure_ratio /= compressors.size()
	var at := _position_of(key)
	var air := Aero.air_density(Origin.to_map(at).y) * face * DESIGN_AIR_SPEED * spool   # kg/s
	var fuel: Vector2 = _fuel_of(members)
	var burnt_kg := minf(burning * fuel.y, air / AIR_PER_JET_FUEL)
	var heat := burnt_kg * fuel.x / maxf(fuel.y, 1e-6)   # W
	var efficiency := 1.0 - pow(maxf(pressure_ratio, 1.0), -(GAMMA - 1.0) / GAMMA)
	var rpm := spool * DESIGN_RPM
	for item in compressors + turbines:
		spawner.set_outputs(item, {"shaft_speed": rpm})
	for item in nozzles:
		var uid: int = item
		var frame_and_body: Array = spawner.part_frame(uid)
		if frame_and_body.is_empty():
			continue
		var frame: Transform3D = frame_and_body[0]
		var body: RigidBody3D = frame_and_body[1]
		var forward := -frame.basis.z.normalized()
		var flight := maxf(Spawner.velocity_at(body, frame.origin - body.global_position).dot(forward), 0.0)
		var thrust := 0.0
		if air > 0.01:
			var share := air / nozzles.size()
			var jet := sqrt(flight * flight + 2.0 * efficiency * heat / air)
			thrust = maxf(share * (jet - flight), 0.0)
		spawner.set_outputs(uid, {"thrust": thrust})
		_show_flame(uid, thrust)
		if thrust > 0.0 and not body.freeze:
			body.sleeping = false
			body.apply_force(forward * thrust, frame.origin - body.global_position)
			spawner.note_force(uid * 8, forward * thrust)


func _show_flame(uid: int, thrust: float) -> void:
	if not _jet_flames.has(uid):
		if thrust <= 0.0:
			return
		_jet_flames[uid] = spawner.attach_extra(uid, Callable(spawner, "_new_flame"))
	if is_instance_valid(_jet_flames[uid]):
		var flame: Node3D = _jet_flames[uid]
		flame.visible = thrust > 0.0


# --- Solid rockets ---------------------------------------------------------------

func _start_rocket(uid: int, record: Dictionary, props: Dictionary) -> void:
	var thrust := maxf(float(props.get("thrust", 5000.0)), 0.0)
	var burn := maxf(float(props.get("burn_time", 10.0)), 0.01)
	var ideal := bool(props.get("ideal", false))
	var shell := BuildGrid.mass_of(record) * ROCKET_SHELL
	var propellant := 0.0 if ideal else thrust * burn / ROCKET_EXHAUST_SPEED
	_rockets[uid] = {"thrust": thrust, "burn": burn, "left": burn, "ideal": ideal, "lit": false,
			"shell": shell, "propellant": propellant, "flame": null, "shown": -1.0}


func _run_rockets(delta: float) -> void:
	for key in _rockets:
		var uid: int = key
		var rocket: Dictionary = _rockets[uid]
		var record: Dictionary = spawner.record_of(uid)
		if record.is_empty():
			continue
		if not bool(rocket["lit"]) and spawner.input_value(record.get("links", {}), "ignite", 0.0) != 0.0:
			rocket["lit"] = true
			rocket["flame"] = spawner.attach_extra(uid, Callable(spawner, "_new_flame"))
		var burning: bool = bool(rocket["lit"]) and (bool(rocket["ideal"]) or float(rocket["left"]) > 0.0)
		if is_instance_valid(rocket["flame"]):
			var flame: Node3D = rocket["flame"]
			flame.visible = burning
		var thrust: float = rocket["thrust"] if burning else 0.0
		spawner.set_outputs(uid, {"thrust": thrust})
		var mass: float = float(rocket["shell"]) + float(rocket["propellant"]) * clampf(float(rocket["left"]) / float(rocket["burn"]), 0.0, 1.0)
		if absf(mass - float(rocket["shown"])) > 0.5:
			rocket["shown"] = mass
			spawner.set_part_mass(uid, mass)
		if not burning:
			continue
		if not bool(rocket["ideal"]):
			rocket["left"] = float(rocket["left"]) - delta
		var frame_and_body: Array = spawner.part_frame(uid)
		if frame_and_body.is_empty():
			continue
		var frame: Transform3D = frame_and_body[0]
		var body: RigidBody3D = frame_and_body[1]
		if body.freeze:
			continue
		body.sleeping = false
		body.apply_force(-frame.basis.z.normalized() * thrust, frame.origin - body.global_position)
		spawner.note_force(uid * 8, -frame.basis.z.normalized() * thrust)
