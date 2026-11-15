extends RefCounted
## The settings each kind of part carries, shown in the Config tool and
## written into save files. Settings are stored now and take effect once the
## Spawn milestone gives the parts their behaviour.
##
## A setting is a dictionary with: id, name, kind, default, and for
##   "number": unit, min, max, step
##   "choice": options (a list of strings)
##   "flag", "color" and "text" need nothing more.

const MaterialLibrary = preload("res://scripts/material_library.gd")

static var _table: Dictionary = {}


static func _number(id: String, title: String, unit: String, initial: float,
		low: float, high: float, step: float) -> Dictionary:
	return {"id": id, "name": title, "kind": "number", "unit": unit,
		"default": initial, "min": low, "max": high, "step": step}


static func _flag(id: String, title: String, initial: bool) -> Dictionary:
	return {"id": id, "name": title, "kind": "flag", "default": initial}


static func _choice(id: String, title: String, options: Array) -> Dictionary:
	return {"id": id, "name": title, "kind": "choice", "options": options, "default": options[0]}


static func _color(id: String, title: String, initial: Color) -> Dictionary:
	return {"id": id, "name": title, "kind": "color", "default": initial}


static func _text(id: String, title: String, initial: String) -> Dictionary:
	return {"id": id, "name": title, "kind": "text", "default": initial}


static func _build_table() -> void:
	var idle_linear := ["Hold position", "Return to starting length"]
	var idle_angular := ["Return to default angle", "Hold position"]

	# --- Mechanical ---
	_table["motor"] = [
		_number("max_torque", "Max torque", "N·m", 100.0, 0.0, 1000000.0, 1.0),
		_number("max_speed", "Max speed", "RPM", 600.0, 0.0, 100000.0, 1.0),
		_number("acceleration", "Acceleration", "RPM/s", 600.0, 0.0, 1000000.0, 1.0),
		_choice("when_idle", "With no input", ["Hold still", "Spin freely"]),
	]
	var servo := [
		_number("default_angle", "Default angle", "°", 0.0, -180.0, 180.0, 1.0),
		_number("positive_angle", "Positive target", "°", 90.0, -180.0, 180.0, 1.0),
		_number("negative_angle", "Negative target", "°", -90.0, -180.0, 180.0, 1.0),
		_number("speed", "Speed", "°/s", 90.0, 0.0, 10000.0, 1.0),
		_number("easing", "Easing", "°/s²", 360.0, 0.0, 100000.0, 1.0),
		_number("max_torque", "Max torque", "N·m", 100.0, 0.0, 1000000.0, 1.0),
		_choice("when_idle", "With no input", idle_angular),
	]
	_table["servo"] = servo
	_table["door_hinge_servo"] = servo
	_table["hinge"] = [
		_flag("limited", "Use angle limits", false),
		_number("min_angle", "Lowest angle", "°", -90.0, -180.0, 180.0, 1.0),
		_number("max_angle", "Highest angle", "°", 90.0, -180.0, 180.0, 1.0),
		_number("friction", "Friction torque", "N·m", 0.0, 0.0, 100000.0, 0.1),
	]
	_table["ball_joint"] = [
		_flag("limited", "Use angle limit", false),
		_number("max_angle", "Largest tilt", "°", 45.0, 0.0, 180.0, 1.0),
		_flag("carries_rotation", "Carries rotation through", false),
	]
	_table["bearing"] = [
		_number("friction", "Friction torque", "N·m", 0.0, 0.0, 100000.0, 0.1),
	]
	_table["piston"] = [
		_number("current_length", "Current length", "blocks", 0.0, 0.0, 64.0, 0.005),
		_number("target_length", "Target length", "blocks", 1.0, 0.0, 64.0, 0.005),
		_number("max_length", "Longest reach", "blocks", 1.0, 0.0, 64.0, 0.005),
		_number("speed", "Speed", "m/s", 0.5, 0.0, 1000.0, 0.01),
		_number("easing", "Easing speed", "m/s²", 2.0, 0.0, 10000.0, 0.01),
		_number("max_force", "Max force", "N", 1000.0, 0.0, 100000000.0, 1.0),
		_choice("when_idle", "With no input", idle_linear),
		_flag("sensor_mode", "Sensor mode (outputs pressure)", false),
	]
	_table["solenoid"] = [
		_number("stroke", "Stroke", "blocks", 0.5, 0.0, 16.0, 0.005),
		_number("force", "Force", "N", 500.0, 0.0, 100000000.0, 1.0),
	]
	_table["spring"] = [
		_number("rest_length", "Rest length", "blocks", 1.0, 0.0, 64.0, 0.005),
		_number("stiffness", "Stiffness", "N/m", 1000.0, 0.0, 100000000.0, 1.0),
		_number("damping", "Damping", "N·s/m", 10.0, 0.0, 1000000.0, 0.1),
	]
	_table["gear"] = [_number("teeth", "Teeth", "", 12.0, 4.0, 400.0, 1.0)]
	_table["bevel_gear"] = [_number("teeth", "Teeth", "", 12.0, 4.0, 400.0, 1.0)]
	_table["rack"] = [_number("teeth_per_block", "Teeth per block", "", 5.0, 1.0, 100.0, 1.0)]
	_table["crankshaft"] = [
		_number("throw_radius", "Throw radius", "blocks", 0.35, 0.005, 16.0, 0.005),
		_number("rod_length", "Rod length", "blocks", 1.5, 0.005, 64.0, 0.005),
	]
	_table["clutch"] = [
		_number("max_torque", "Max torque", "N·m", 200.0, 0.0, 1000000.0, 1.0),
		_flag("engaged", "Engaged with no input", true),
	]
	_table["brake"] = [_number("max_torque", "Max torque", "N·m", 200.0, 0.0, 1000000.0, 1.0)]

	# --- Fluid and engine ---
	_table["fluid_cylinder"] = [
		_number("bore", "Bore", "blocks", 0.6, 0.005, 16.0, 0.005),
		_number("stroke", "Stroke", "blocks", 1.0, 0.005, 64.0, 0.005),
		_choice("fluid", "Fluid", ["Hydraulic oil", "Gas"]),
		_flag("sensor_mode", "Sensor mode (outputs pressure)", false),
	]
	_table["pump"] = [
		_number("max_flow", "Max flow", "L/s", 1.0, 0.0, 10000.0, 0.01),
		_number("max_pressure", "Max pressure", "MPa", 10.0, 0.0, 1000.0, 0.1),
	]
	_table["valve"] = [_flag("open", "Open with no input", false)]
	_table["fuel_tank"] = [
		_number("energy_density", "Energy per volume", "MJ/L", 34.0, 0.0, 1000.0, 0.1),
		_number("fuel_density", "Fuel density", "kg/L", 0.75, 0.0, 30.0, 0.01),
		_number("fill", "Starting fill", "%", 100.0, 0.0, 100.0, 1.0),
	]
	_table["pressure_tank"] = [
		_number("pressure", "Starting pressure", "kPa", 101.3, 0.0, 1000000.0, 0.1),
	]
	_table["combustion_cylinder"] = [
		_number("bore", "Bore", "blocks", 0.6, 0.005, 16.0, 0.005),
		_number("stroke", "Stroke", "blocks", 0.6, 0.005, 64.0, 0.005),
	]
	_table["compressor"] = [_number("pressure_ratio", "Pressure ratio", "", 8.0, 1.0, 100.0, 0.1)]
	_table["combustor"] = [_number("max_fuel_flow", "Max fuel flow", "L/s", 0.1, 0.0, 1000.0, 0.001)]
	_table["thruster"] = [
		_number("thrust", "Thrust", "N", 1000.0, 0.0, 1000000000.0, 1.0),
		_flag("ideal", "Runs without fuel", true),
	]
	_table["solid_rocket"] = [
		_number("thrust", "Thrust", "N", 5000.0, 0.0, 1000000000.0, 1.0),
		_number("burn_time", "Burn time", "s", 10.0, 0.0, 100000.0, 0.1),
		_flag("ideal", "Never burns out", false),
	]

	# --- Aero ---
	_table["propeller"] = [
		_number("blades", "Blade count", "", 4.0, 2.0, 12.0, 1.0),
		_number("pitch", "Blade pitch", "°", 20.0, 0.0, 90.0, 1.0),
	]
	_table["lift_gas_tank"] = [
		_number("lift_per_block", "Lift at sea level", "N per block", 1.0, 0.0, 1000000.0, 0.1),
	]

	# --- Logic ---
	_table["input_block"] = [
		_text("key", "Key", "W"),
		_choice("mode", "Mode", ["Hold", "Toggle"]),
		_choice("output", "Output", ["Boolean", "Number from two keys"]),
		_text("second_key", "Second key", "S"),
	]
	_table["boolean_gate"] = [
		_choice("operation", "Gate", ["AND", "OR", "NOT", "XOR", "NAND", "NOR", "Latch", "Timer"]),
		_number("seconds", "Timer length", "s", 1.0, 0.0, 100000.0, 0.01),
	]
	_table["number_gate"] = [
		_choice("operation", "Operation", [
			"Constant", "Add", "Subtract", "Multiply", "Divide", "Absolute value",
			"Min", "Max", "Clamp", "Compare", "Select", "Map range",
		]),
		_number("value", "Constant", "", 0.0, -1000000000.0, 1000000000.0, 0.001),
	]
	_table["pid_controller"] = [
		_number("kp", "Kp", "", 1.0, -1000000.0, 1000000.0, 0.001),
		_number("ki", "Ki", "", 0.0, -1000000.0, 1000000.0, 0.001),
		_number("kd", "Kd", "", 0.0, -1000000.0, 1000000.0, 0.001),
		_number("output_min", "Lowest output", "", -1.0, -1000000000.0, 1000000000.0, 0.001),
		_number("output_max", "Highest output", "", 1.0, -1000000000.0, 1000000000.0, 0.001),
	]
	_table["distance_sensor"] = [_number("range", "Range", "m", 100.0, 0.0, 100000.0, 0.1)]
	_table["impact_detector"] = [
		_number("threshold", "Trigger above", "g", 10.0, 0.0, 100000.0, 0.1),
		_number("pulse", "Signal length", "s", 0.1, 0.0, 1000.0, 0.01),
	]
	_table["light_panel"] = [
		_color("color", "Light color", Color(1.0, 1.0, 1.0)),
		_number("brightness", "Brightness", "", 1.0, 0.0, 100.0, 0.1),
	]
	_table["vanish_block"] = [_flag("returns", "Comes back when the signal ends", false)]

	# --- Combat ---
	_table["explosive_block"] = [_number("blast_radius", "Blast radius", "m", 2.0, 0.0, 1000.0, 0.05)]
	_table["machine_gun"] = [
		_number("fire_rate", "Fire rate", "rounds/s", 10.0, 0.0, 1000.0, 0.1),
		_flag("unlimited_ammo", "Unlimited ammo", true),
	]
	var material_names: Array = []
	for material_id in MaterialLibrary.ids():
		material_names.append(MaterialLibrary.display_name(material_id))
	var projectile := _choice("projectile_material", "Projectile material", material_names)
	projectile["default"] = "Steel"
	_table["large_cannon"] = [
		_number("barrel_length", "Barrel length", "m", 3.0, 0.05, 1000.0, 0.05),
		_number("bore", "Bore", "m", 0.1, 0.005, 10.0, 0.005),
		projectile,
		_flag("unlimited_ammo", "Unlimited ammo", true),
	]
	_table["ammo_generator"] = [
		_choice("ammo_type", "Ammo type", ["Machine gun rounds", "Cannon shells"]),
		_number("rate", "Made per second", "", 5.0, 0.0, 10000.0, 0.1),
		_number("storage", "Total storage", "", 200.0, 0.0, 10000000.0, 1.0),
	]

	# --- Misc ---
	_table["dynamic_offsetter"] = [
		_number("shift_x", "Shift X", "blocks", 0.0, -5.0, 5.0, 0.005),
		_number("shift_y", "Shift Y", "blocks", 0.0, -5.0, 5.0, 0.005),
		_number("shift_z", "Shift Z", "blocks", 0.0, -5.0, 5.0, 0.005),
		_number("turn_x", "Turn about X", "°", 0.0, -180.0, 180.0, 1.0),
		_number("turn_y", "Turn about Y", "°", 0.0, -180.0, 180.0, 1.0),
		_number("turn_z", "Turn about Z", "°", 0.0, -180.0, 180.0, 1.0),
	]


## The settings for one kind of part, in display order. Empty for plain shapes.
static func for_type(type: String) -> Array:
	if _table.is_empty():
		_build_table()
	return _table.get(type, [])


## A fresh set of default values for one kind of part.
static func defaults(type: String) -> Dictionary:
	var values: Dictionary = {}
	for setting in for_type(type):
		values[setting["id"]] = setting["default"]
	return values


## Forces one value into the form its setting allows.
static func clean_value(setting: Dictionary, value: Variant) -> Variant:
	var kind: String = setting["kind"]
	if kind == "number":
		if not (value is float or value is int):
			return setting["default"]
		var low: float = setting["min"]
		var high: float = setting["max"]
		return clampf(float(value), low, high)
	if kind == "flag":
		if value is bool:
			return value
		return setting["default"]
	if kind == "choice":
		var options: Array = setting["options"]
		if value is String and options.has(value):
			return value
		return setting["default"]
	if kind == "color":
		if value is Color:
			return value
		if value is String and Color.html_is_valid(value):
			return Color.html(value)
		return setting["default"]
	if value is String:
		return (value as String).substr(0, 24)
	return setting["default"]


## Turns settings read from a save file (or from anywhere) into a complete,
## valid set: missing values get defaults and unknown ones are dropped.
static func sanitize(type: String, raw: Variant) -> Dictionary:
	var given: Dictionary = {}
	if raw is Dictionary:
		given = raw
	var values: Dictionary = {}
	for setting in for_type(type):
		var id: String = setting["id"]
		if given.has(id):
			values[id] = clean_value(setting, given[id])
		else:
			values[id] = setting["default"]
	return values


## The same settings in a form that can be written to a save file.
static func to_plain(props: Dictionary) -> Dictionary:
	var plain: Dictionary = {}
	for id in props:
		var value: Variant = props[id]
		if value is Color:
			plain[id] = "#" + (value as Color).to_html(false)
		else:
			plain[id] = value
	return plain
