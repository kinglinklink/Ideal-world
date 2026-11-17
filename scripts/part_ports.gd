extends RefCounted
## The signals each kind of part can receive and send. The Config tool links
## an input on one part to an output on another. Links are stored now and
## start carrying signals once the Spawn and Logic milestones are built.
##
## A port is [id, name, kind]. Kinds:
##   "bool"    on or off
##   "number"  any number; an on/off signal reads as 1 or 0 where a number is wanted
##   "ammo"    an ammo supply, which only connects to other ammo ports

const KIND_NAMES := {"bool": "on/off", "number": "number", "ammo": "ammo"}

const SPEED_OUT := [["speed", "Speed", "number"]]
const SERVO_IN := [
	["go_positive", "Go to positive target", "bool"],
	["go_negative", "Go to negative target", "bool"],
	["angle", "Angle", "number"],
]
const ANGLE_OUT := [["angle", "Angle", "number"]]
const GUN_IN := [["fire", "Fire", "bool"], ["ammo", "Ammo supply", "ammo"]]

## part id -> {"inputs": [...], "outputs": [...]}. Parts not listed have neither.
const PORTS := {
	# Mechanical
	"motor": {
		"inputs": [
			["clockwise", "Clockwise", "bool"],
			["counterclockwise", "Counterclockwise", "bool"],
			["speed", "Speed", "number"],
		],
		"outputs": [["shaft_speed", "Shaft speed", "number"]],
	},
	"servo": {"inputs": SERVO_IN, "outputs": ANGLE_OUT},
	"door_hinge_servo": {"inputs": SERVO_IN, "outputs": ANGLE_OUT},
	"hinge": {"inputs": [], "outputs": ANGLE_OUT},
	"bearing": {"inputs": [], "outputs": SPEED_OUT},
	"piston": {
		"inputs": [["extend", "Go to target length", "bool"], ["length", "Length", "number"]],
		"outputs": [["length", "Length", "number"], ["pressure", "Pressure", "number"]],
	},
	"solenoid": {"inputs": [["on", "On", "bool"]], "outputs": [["state", "State", "bool"]]},
	"spring": {"inputs": [], "outputs": [["length", "Length", "number"]]},
	"gear": {"inputs": [], "outputs": SPEED_OUT},
	"bevel_gear": {"inputs": [], "outputs": SPEED_OUT},
	"rack": {"inputs": [], "outputs": [["position", "Position", "number"]]},
	"pulley": {"inputs": [], "outputs": SPEED_OUT},
	"crankshaft": {"inputs": [], "outputs": [
		["angle", "Angle", "number"], ["speed", "Speed", "number"],
		["position", "Rod end position (m)", "number"], ["near_top", "Near the top", "bool"],
	]},
	"wheel": {"inputs": [], "outputs": SPEED_OUT},
	"clutch": {"inputs": [["engage", "Engage", "bool"], ["amount", "Amount", "number"]], "outputs": []},
	"brake": {"inputs": [["brake", "Brake", "bool"], ["amount", "Amount", "number"]], "outputs": []},
	# Fluid and engine
	"fluid_cylinder": {
		"inputs": [],
		"outputs": [["pressure", "Pressure", "number"], ["length", "Length", "number"]],
	},
	"pump": {
		"inputs": [["on", "On", "bool"], ["rate", "Rate", "number"]],
		"outputs": [["flow", "Flow", "number"]],
	},
	"valve": {"inputs": [["open", "Open", "bool"], ["amount", "Amount", "number"]], "outputs": []},
	"fuel_tank": {"inputs": [], "outputs": [["level", "Level", "number"]]},
	"pressure_tank": {"inputs": [], "outputs": [["pressure", "Pressure", "number"]]},
	"combustion_cylinder": {
		"inputs": [["spark", "Spark", "bool"]],
		"outputs": [["pressure", "Pressure", "number"]],
	},
	"compressor": {"inputs": [], "outputs": [["shaft_speed", "Shaft speed", "number"]]},
	"combustor": {"inputs": [["fuel_rate", "Fuel rate", "number"]], "outputs": []},
	"turbine": {"inputs": [], "outputs": [["shaft_speed", "Shaft speed", "number"]]},
	"nozzle": {"inputs": [], "outputs": [["thrust", "Thrust", "number"]]},
	"thruster": {
		"inputs": [["on", "On", "bool"], ["throttle", "Throttle", "number"]],
		"outputs": [["thrust", "Thrust", "number"]],
	},
	"solid_rocket": {"inputs": [["ignite", "Ignite", "bool"]], "outputs": [["thrust", "Thrust", "number"]]},
	# Aero
	"propeller": {"inputs": [], "outputs": SPEED_OUT},
	"lift_gas_tank": {"inputs": [["amount", "Amount (0 to 1)", "number"]], "outputs": []},
	# Logic
	"input_block": {
		"inputs": [],
		"outputs": [["pressed", "Pressed", "bool"], ["value", "Value", "number"]],
	},
	"boolean_gate": {
		"inputs": [["a", "A", "bool"], ["b", "B", "bool"]],
		"outputs": [["result", "Result", "bool"]],
	},
	"number_gate": {
		"inputs": [["a", "A", "number"], ["b", "B", "number"], ["c", "C", "number"]],
		"outputs": [["result", "Result", "number"], ["is_true", "Comparison is true", "bool"]],
	},
	"pid_controller": {
		"inputs": [["setpoint", "Setpoint", "number"], ["measurement", "Measurement", "number"]],
		"outputs": [["output", "Output", "number"]],
	},
	"pwm_generator": {
		"inputs": [["enable", "Enable", "bool"], ["duty", "Duty (0 to 1)", "number"],
				["frequency", "Frequency (Hz)", "number"]],
		"outputs": [["output", "Output", "bool"], ["phase", "Phase (0 to 1)", "number"]],
	},
	"speed_sensor": {"inputs": [], "outputs": SPEED_OUT},
	"altitude_sensor": {"inputs": [], "outputs": [["altitude", "Altitude", "number"]]},
	"attitude_sensor": {
		"inputs": [],
		"outputs": [
			["pitch", "Pitch", "number"], ["roll", "Roll", "number"], ["yaw", "Yaw", "number"],
			["pitch_rate", "Pitch rate", "number"], ["roll_rate", "Roll rate", "number"],
			["yaw_rate", "Yaw rate", "number"],
		],
	},
	"distance_sensor": {"inputs": [], "outputs": [["distance", "Distance", "number"]]},
	"graph_display": {
		"inputs": [["a", "Line A", "number"], ["b", "Line B", "number"],
				["c", "Line C", "number"], ["d", "Line D", "number"]],
		"outputs": [],
	},
	"impact_detector": {
		"inputs": [],
		"outputs": [["triggered", "Triggered", "bool"], ["acceleration", "Acceleration", "number"]],
	},
	"light_panel": {
		"inputs": [
			["on", "On", "bool"], ["red", "Red (0 to 255)", "number"],
			["green", "Green (0 to 255)", "number"], ["blue", "Blue (0 to 255)", "number"],
		],
		"outputs": [],
	},
	"vanish_block": {"inputs": [["vanish", "Vanish", "bool"]], "outputs": []},
	# Combat
	"explosive_block": {"inputs": [["detonate", "Detonate", "bool"]], "outputs": []},
	"machine_gun": {"inputs": GUN_IN, "outputs": []},
	"large_cannon": {"inputs": GUN_IN, "outputs": []},
	"ammo_generator": {
		"inputs": [],
		"outputs": [["ammo", "Ammo supply", "ammo"], ["stored", "Ammo stored", "number"]],
	},
	# Misc
	"seat": {"inputs": [], "outputs": [["occupied", "Occupied", "bool"]]},
	"magnet": {"inputs": [["on", "On", "bool"]], "outputs": [["holding", "Holding", "bool"]]},
	"winch": {
		"inputs": [["reel", "Reel (+1 in, -1 out)", "number"], ["grab", "Hook grabs", "bool"]],
		"outputs": [["length", "Rope length (m)", "number"], ["tension", "Tension (N)", "number"],
				["holding", "Hook holding", "bool"]],
	},
	"coupler": {
		"inputs": [["couple", "Couple", "bool"]],
		"outputs": [["coupled", "Coupled", "bool"], ["fuel_moved", "Fuel moved (L)", "number"]],
	},
}


static func inputs_of(type: String) -> Array:
	if PORTS.has(type):
		return PORTS[type]["inputs"]
	return []


static func outputs_of(type: String) -> Array:
	if PORTS.has(type):
		return PORTS[type]["outputs"]
	return []


## The port with the given id from a list of ports, or an empty list.
static func find_port(ports: Array, port_id: String) -> Array:
	for port in ports:
		if port[0] == port_id:
			return port
	return []


## "Shaft speed (number)"
static func label(port: Array) -> String:
	return "%s (%s)" % [port[1], KIND_NAMES.get(port[2], port[2])]


## Any signal can feed any signal input. Ammo only connects to ammo.
static func compatible(input_port: Array, output_port: Array) -> bool:
	return (input_port[2] == "ammo") == (output_port[2] == "ammo")


## The outputs of a part that may be linked to the given input.
static func outputs_for(input_port: Array, source_type: String) -> Array:
	var fitting: Array = []
	for output_port in outputs_of(source_type):
		if compatible(input_port, output_port):
			fitting.append(output_port)
	return fitting
