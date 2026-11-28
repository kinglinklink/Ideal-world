extends RefCounted
## Definitions for every placeable part.
##
## Every part is described inside a 1 x 1 x 1 box centred on the origin. A
## part's real shape is that unit shape stretched to its size, so the volume
## and centre of mass below are given as fractions of the bounding box.

const MechModels = preload("res://scripts/mech_models.gd")
const Units = preload("res://scripts/units.gd")

## id -> [name, category, default size in cells, volume fraction,
##        centre of mass in unit-box coordinates, collision kind]
const PARTS := {
	"block": ["Block", "Basic", Vector3(1, 1, 1), 1.0, Vector3(0, 0, 0), "box"],
	"wedge": ["Wedge", "Basic", Vector3(1, 1, 1), 0.5, Vector3(-0.16667, -0.16667, 0), "convex"],
	"triangle_wedge": ["Triangle wedge", "Basic", Vector3(1, 1, 1), 0.5, Vector3(0, -0.16667, 0), "convex"],
	"cylinder": ["Cylinder", "Basic", Vector3(1, 1, 1), 0.785398, Vector3(0, 0, 0), "convex"],
	"sphere": ["Sphere", "Basic", Vector3(1, 1, 1), 0.523599, Vector3(0, 0, 0), "convex"],
	"slab": ["Half block", "Structural", Vector3(1, 0.5, 1), 1.0, Vector3(0, 0, 0), "box"],
	"plate": ["Plate", "Structural", Vector3(1, 0.25, 1), 1.0, Vector3(0, 0, 0), "box"],
	"post": ["Post", "Structural", Vector3(0.5, 1, 0.5), 1.0, Vector3(0, 0, 0), "box"],
	"rod": ["Rod", "Structural", Vector3(0.25, 1, 0.25), 0.785398, Vector3(0, 0, 0), "convex"],
	"ladder": ["Ladder", "Structural", Vector3(1, 4, 0.25), 0.3, Vector3(0, 0, 0), "box"],
	"corner_wedge": ["Corner wedge", "Advanced", Vector3(1, 1, 1), 0.166667, Vector3(-0.25, -0.25, -0.25), "convex"],
	"inverse_corner": ["Inverse corner", "Advanced", Vector3(1, 1, 1), 0.833333, Vector3(-0.05, -0.05, -0.05), "convex"],
	"pyramid": ["Pyramid", "Advanced", Vector3(1, 1, 1), 0.333333, Vector3(0, -0.25, 0), "convex"],
	"cone": ["Cone", "Advanced", Vector3(1, 1, 1), 0.261799, Vector3(0, -0.25, 0), "convex"],
	"frustum": ["Tapered cylinder", "Advanced", Vector3(1, 1, 1), 0.458149, Vector3(0, -0.10714, 0), "convex"],
	"hemisphere": ["Hemisphere", "Advanced", Vector3(1, 0.5, 1), 0.523599, Vector3(0, -0.125, 0), "convex"],
	"half_cylinder": ["Half cylinder", "Advanced", Vector3(1, 0.5, 1), 0.785398, Vector3(0, -0.07559, 0), "convex"],
	"convex_curve": ["Convex curve", "Advanced", Vector3(1, 1, 1), 0.785398, Vector3(-0.07559, -0.07559, 0), "convex"],
	"curved_wedge": ["Curved wedge", "Advanced", Vector3(1, 1, 1), 0.666667, Vector3(-0.125, -0.1, 0), "convex"],
	"rounded_wedge": ["Rounded wedge", "Advanced", Vector3(1, 1, 1), 0.523599, Vector3(-0.125, -0.16047, 0), "convex"],
	"half_cone": ["Half cone", "Advanced", Vector3(1, 0.5, 1), 0.261799, Vector3(0, -0.18169, -0.25), "convex"],
	"half_frustum": ["Tapered half cylinder", "Advanced", Vector3(1, 0.5, 1), 0.458149, Vector3(0, -0.15895, -0.10714), "convex"],
	"concave_curve": ["Concave curve", "Advanced", Vector3(1, 1, 1), 0.214602, Vector3(-0.27665, -0.27665, 0), "concave"],
	"arch": ["Arch", "Advanced", Vector3(1, 1, 1), 0.748673, Vector3(0, 0.11086, 0), "concave"],
	"ring": ["Ring", "Advanced", Vector3(1, 1, 1), 0.502655, Vector3(0, 0, 0), "concave"],
	"pipe": ["Pipe", "Advanced", Vector3(1, 1, 1), 0.282743, Vector3(0, 0, 0), "concave"],
	"torus": ["Torus", "Advanced", Vector3(1, 0.25, 1), 0.462637, Vector3(0, 0, 0), "concave"],
	# Mechanical parts are models only for now. Their volume share (0.5) and
	# centre of mass are placeholders until the Spawn milestone defines them.
	"motor": ["Motor", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"servo": ["Servo", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"door_hinge_servo": ["Door hinge servo", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"hinge": ["Hinge", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"ball_joint": ["Ball joint", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"bearing": ["Bearing block", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"piston": ["Piston", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"solenoid": ["Solenoid", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"spring": ["Spring", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"gear": ["Gear", "Mechanical", Vector3(1, 0.375, 1), 0.5, Vector3(0, 0, 0), "box"],
	"bevel_gear": ["Bevel gear", "Mechanical", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"rack": ["Rack", "Mechanical", Vector3(1, 0.5, 0.5), 0.5, Vector3(0, 0, 0), "box"],
	"pulley": ["Belt pulley", "Mechanical", Vector3(1, 0.375, 1), 0.5, Vector3(0, 0, 0), "box"],
	"crankshaft": ["Crankshaft", "Mechanical", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"wheel": ["Wheel", "Mechanical", Vector3(0.5, 1, 1), 0.5, Vector3(0, 0, 0), "convex"],
	"linkage_bar": ["Linkage bar", "Mechanical", Vector3(1, 0.25, 0.25), 0.5, Vector3(0, 0, 0), "box"],
	"clutch": ["Clutch", "Mechanical", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"brake": ["Brake", "Mechanical", Vector3(1, 0.375, 1), 0.5, Vector3(0, 0, 0), "box"],
	"light_panel": ["Light panel", "Logic", Vector3(1, 0.125, 1), 0.5, Vector3(0, 0, 0), "box"],
	"vanish_block": ["Vanishing block", "Logic", Vector3(1, 1, 1), 1.0, Vector3(0, 0, 0), "box"],
	"impact_detector": ["Impact detector", "Logic", Vector3(1, 1, 1), 0.4, Vector3(0, 0, 0), "box"],
	"explosive_block": ["Explosive block", "Combat", Vector3(1, 1, 1), 0.8, Vector3(0, 0, 0), "box"],
	"machine_gun": ["Machine gun", "Combat", Vector3(1, 1, 2), 0.3, Vector3(0, 0, 0), "box"],
	"hitscan_gun": ["Hit-scan gun", "Combat", Vector3(1, 1, 2), 0.3, Vector3(0, 0, 0), "box"],
	"large_cannon": ["Large cannon", "Combat", Vector3(1, 1, 4), 0.3, Vector3(0, 0, 0), "box"],
	"ammo_generator": ["Ammo generator", "Combat", Vector3(2, 2, 2), 0.7, Vector3(0, 0, 0), "box"],
	"reload_gate": ["Reload gate", "Combat", Vector3(1, 0.5, 2), 0.8, Vector3(0, 0, 0), "box"],
	"fluid_cylinder": ["Fluid cylinder", "Fluid and Engine", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"pump": ["Pump", "Fluid and Engine", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"valve": ["Valve", "Fluid and Engine", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"fluid_pipe": ["Fluid pipe", "Fluid and Engine", Vector3(1, 1, 1), 0.1, Vector3(0, 0, 0), "box"],
	"fuel_tank": ["Fuel tank", "Fluid and Engine", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"pressure_tank": ["Pressure tank", "Fluid and Engine", Vector3(1, 1, 1), 0.4, Vector3(0, 0, 0), "box"],
	"combustion_cylinder": ["Combustion cylinder", "Fluid and Engine", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"compressor": ["Compressor", "Fluid and Engine", Vector3(1, 1, 1), 0.6, Vector3(0, 0, 0), "box"],
	"combustor": ["Combustor", "Fluid and Engine", Vector3(1, 1, 1), 0.4, Vector3(0, 0, 0), "box"],
	"turbine": ["Turbine", "Fluid and Engine", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"nozzle": ["Nozzle", "Fluid and Engine", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"thruster": ["Thruster", "Fluid and Engine", Vector3(1, 1, 1), 0.4, Vector3(0, 0, 0), "box"],
	"solid_rocket": ["Solid rocket", "Fluid and Engine", Vector3(1, 1, 2), 0.5, Vector3(0, 0, 0), "box"],
	"aero_panel": ["Square aero panel", "Aero", Vector3(1, 0.125, 1), 1.0, Vector3(0, 0, 0), "box"],
	"aero_panel_triangle": ["Triangle aero panel", "Aero", Vector3(1, 0.125, 1), 0.5, Vector3(-0.1667, 0, 0.1667), "convex"],
	"aero_panel_dragless": ["Dragless square panel", "Aero", Vector3(1, 0.125, 1), 1.0, Vector3(0, 0, 0), "box"],
	"aero_panel_triangle_dragless": ["Dragless triangle panel", "Aero", Vector3(1, 0.125, 1), 0.5, Vector3(-0.1667, 0, 0.1667), "convex"],
	"propeller": ["Propeller", "Aero", Vector3(1, 0.25, 1), 0.3, Vector3(0, 0, 0), "box"],
	"lift_gas_tank": ["Lift-gas tank", "Aero", Vector3(1, 1, 1), 0.1, Vector3(0, 0, 0), "box"],
	"input_block": ["Input", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"mouse_click": ["Mouse click", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"gamepad_input": ["Controller input", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"boolean_gate": ["Boolean gate", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"number_gate": ["Number logic", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"pid_controller": ["PID controller", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"pwm_generator": ["PWM generator", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"speed_sensor": ["Speed sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"altitude_sensor": ["Altitude sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"attitude_sensor": ["Attitude sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"distance_sensor": ["Distance sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"graph_display": ["Graph screen", "Logic", Vector3(4, 3, 0.25), 0.6, Vector3(0, 0, 0), "box"],
	"instrument": ["Instrument", "Logic", Vector3(2, 2, 0.25), 0.6, Vector3(0, 0, 0), "box"],
	"seat": ["Seat", "Misc", Vector3(3, 3, 3), 0.4, Vector3(0, 0, 0), "box"],
	"camera": ["Camera", "Misc", Vector3(1, 1, 1), 0.5, Vector3(0, 0, 0), "box"],
	"anchor_block": ["Anchor block", "Misc", Vector3(1, 1, 1), 0.9, Vector3(0, 0, 0), "box"],
	"dynamic_offsetter": ["Dynamic offsetter", "Misc", Vector3(1, 1, 1), 0.8, Vector3(0, 0, 0), "box"],
	"magnet": ["Electromagnet", "Misc", Vector3(2, 0.5, 2), 0.9, Vector3(0, 0, 0), "box"],
	"winch": ["Winch and hook", "Misc", Vector3(2, 1, 1), 0.6, Vector3(0, 0, 0), "box"],
	"coupler": ["Coupler", "Misc", Vector3(1, 1, 0.5), 0.8, Vector3(0, 0, 0), "box"],
}

## Parts that start in their own colour instead of the brush colour.
## They can still be repainted afterwards.
const DEFAULT_COLORS := {
	"camera": Color(0.16, 0.17, 0.19),
	"vanish_block": Color(1.0, 1.0, 1.0),
	"light_panel": Color(0.20, 0.21, 0.23),
	"impact_detector": Color(0.95, 0.75, 0.15),
	"explosive_block": Color(0.78, 0.12, 0.10),
	"machine_gun": Color(0.30, 0.33, 0.27),
	"hitscan_gun": Color(0.22, 0.24, 0.30),
	"large_cannon": Color(0.30, 0.33, 0.27),
	"ammo_generator": Color(0.30, 0.33, 0.27),
	"reload_gate": Color(0.30, 0.33, 0.27),
	"ladder": Color(0.55, 0.57, 0.60),
	"lift_gas_tank": Color(0.88, 0.92, 0.96),
	"aero_panel_dragless": Color(0.55, 0.90, 1.0),
	"aero_panel_triangle_dragless": Color(0.55, 0.90, 1.0),
	"anchor_block": Color(0.55, 0.57, 0.60),
	"input_block": Color(0.20, 0.21, 0.23),
	"mouse_click": Color(0.20, 0.21, 0.23),
	"gamepad_input": Color(0.20, 0.21, 0.23),
	"boolean_gate": Color(0.20, 0.21, 0.23),
	"number_gate": Color(0.20, 0.21, 0.23),
	"pid_controller": Color(0.20, 0.21, 0.23),
	"pwm_generator": Color(0.20, 0.21, 0.23),
	"speed_sensor": Color(0.20, 0.21, 0.23),
	"altitude_sensor": Color(0.20, 0.21, 0.23),
	"attitude_sensor": Color(0.20, 0.21, 0.23),
	"distance_sensor": Color(0.20, 0.21, 0.23),
	"graph_display": Color(0.16, 0.17, 0.19),
	"instrument": Color(0.12, 0.12, 0.13),
	"magnet": Color(0.62, 0.12, 0.10),
	"winch": Color(0.95, 0.72, 0.10),
	"coupler": Color(0.35, 0.37, 0.40),
}

const CATEGORIES := ["Basic", "Structural", "Advanced", "Mechanical", "Fluid and Engine", "Aero", "Logic", "Combat", "Misc"]
const RING_INNER_RADIUS := 0.3   # of a unit ring whose outer radius is 0.5
const PIPE_INNER_RADIUS := 0.4   # a thinner wall than the ring
const ARCH_RADIUS := 0.4         # of the opening cut into a unit arch
const CURVE_STEPS := 10
const RAMP_STEPS := 16           # along the curved and rounded wedges' slope
const SMOOTH_TURN := 30.0        # degrees: an outline turning less than this at a corner is a curve, shaded smooth

static var _mesh_cache: Dictionary = {}
static var _hull_cache: Dictionary = {}
static var _recipe: Array = []          # how the mesh being built is made: ["extrude", outline] or ["lathe", outline, segments]
static var _recipes: Dictionary = {}    # part id -> its recipe, for splitting hollow shapes into solid pieces
static var _pieces_cache: Dictionary = {}
static var _planes_cache: Dictionary = {}
static var _overlay_cache: Dictionary = {}


static func part_ids() -> Array:
	return PARTS.keys()


static func _row(part_id: String) -> Array:
	if PARTS.has(part_id):
		return PARTS[part_id]
	return PARTS["block"]


static func part_name(part_id: String) -> String:
	return _row(part_id)[0]


static func category(part_id: String) -> String:
	return _row(part_id)[1]


## The colour a newly placed part gets: its own default, or the brush colour.
static func placement_color(part_id: String, brush_color: Color) -> Color:
	if DEFAULT_COLORS.has(part_id):
		return DEFAULT_COLORS[part_id]
	return brush_color


## True for parts that are placed in the middle of the cell under the cursor
## instead of being pushed against the surface: the thin aero panels, whose
## thickness then lies evenly either side of the cell's centre line.
static func sits_mid_cell(part_id: String) -> bool:
	return is_aero_panel(part_id)


## True for the flat panels that make lift once spawned.
static func is_aero_panel(part_id: String) -> bool:
	return part_id.begins_with("aero_panel")


static func is_triangle_panel(part_id: String) -> bool:
	return part_id.begins_with("aero_panel_triangle")


## True for the ideal panels, which make lift and no drag.
static func is_dragless(part_id: String) -> bool:
	return part_id.ends_with("_dragless")


static func default_size_cells(part_id: String) -> Vector3:
	return _row(part_id)[2]


static func volume_fraction(part_id: String) -> float:
	return _row(part_id)[3]


static func unit_centroid(part_id: String) -> Vector3:
	return _row(part_id)[4]


# --- Meshes ------------------------------------------------------------------

## The unit-size render mesh for a part. Scale it by the part's size in metres.
## `options` picks a variant of a model whose shape depends on its settings
## (see mech_models.gd). Empty means the standard model.
static func get_mesh(part_id: String, options: Dictionary = {}) -> Mesh:
	var key := part_id
	if not options.is_empty():
		key = part_id + str(options)
	if not _mesh_cache.has(key):
		if options.is_empty():
			_recipe = []
			_mesh_cache[key] = _build_mesh(part_id)
			_recipes[part_id] = _recipe
		else:
			_mesh_cache[key] = MechModels.build(part_id, options)
	return _mesh_cache[key]


## The model for one particular part. Gears show their tooth count and the
## propeller its blade count and pitch, taken from the part's settings.
static func mesh_for_record(record: Dictionary) -> Mesh:
	var type: String = record["type"]
	var props: Dictionary = record.get("props", {})
	if type == "gear" or type == "bevel_gear":
		return get_mesh(type, {"teeth": clampi(int(props.get("teeth", 12)), 4, 120)})
	if type == "propeller":
		return get_mesh(type, {
			"blades": clampi(int(props.get("blades", 4)), 2, 12),
			"pitch": int(round(float(props.get("pitch", 20.0)))),
		})
	if type == "ladder":
		# A rung about every 30 cm, however long the ladder is.
		var length := Units.to_metres(record["size"] as Vector3i).y
		return get_mesh(type, {"rungs": clampi(int(round(length / 0.3)), 1, 64)})
	return get_mesh(type)


## The captions for a part's three dimensions in the Config tool. Most parts
## are plain X, Y, Z; the cannon's dimensions are its bore and barrel.
static func size_captions(part_id: String) -> Array:
	if part_id == "large_cannon":
		return ["Bore size X (blocks)", "Bore size Y (blocks)", "Barrel length (blocks)"]
	return ["Size X (blocks)", "Size Y (blocks)", "Size Z (blocks)"]


static func _build_mesh(part_id: String) -> Mesh:
	if MechModels.has_model(part_id):
		return MechModels.build(part_id)
	match part_id:
		"wedge":
			var wedge := PrismMesh.new()
			wedge.size = Vector3.ONE
			wedge.left_to_right = 0.0
			return wedge
		"triangle_wedge":
			var triangle := PrismMesh.new()
			triangle.size = Vector3.ONE
			triangle.left_to_right = 0.5
			return triangle
		"cylinder", "rod":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 32
			cylinder.rings = 1
			return cylinder
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.radial_segments = 32
			cone.rings = 1
			return cone
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 24
			sphere.rings = 12
			return sphere
		"hemisphere":
			var dome := PackedVector2Array([Vector2(0.0, -0.5)])
			for step in CURVE_STEPS + 1:
				var angle := float(step) / float(CURVE_STEPS) * PI * 0.5
				dome.append(Vector2(0.5 * cos(angle), -0.5 + sin(angle)))
			return _lathe(dome, 24)
		"ring":
			return _lathe(PackedVector2Array([
				Vector2(RING_INNER_RADIUS, -0.5), Vector2(0.5, -0.5),
				Vector2(0.5, 0.5), Vector2(RING_INNER_RADIUS, 0.5),
			]), 32)
		"convex_curve":
			# A quarter disc: the round is centred on the (-X, -Y) corner.
			var quarter := PackedVector2Array([Vector2(-0.5, -0.5)])
			for step in CURVE_STEPS + 1:
				var angle := float(step) / float(CURVE_STEPS) * PI * 0.5
				quarter.append(Vector2(-0.5 + cos(angle), -0.5 + sin(angle)))
			return _extrude(quarter)
		"curved_wedge":
			# A wedge whose slope is a curve: level at the tall (-X) end, so it
			# runs on smoothly from a flat top, and down to a thin edge at +X.
			var ramp := PackedVector2Array([Vector2(-0.5, -0.5)])
			for step in range(RAMP_STEPS, -1, -1):
				var t := float(step) / float(RAMP_STEPS)
				ramp.append(Vector2(-0.5 + t, -0.5 + (1.0 - t * t)))
			return _extrude(ramp)
		"rounded_wedge":
			return _rounded_ramp()
		"half_cone":
			return _taper_half(0.0)
		"half_frustum":
			return _taper_half(0.5)
		"camera":
			# A small box with its lens on the -Z face, the way it looks.
			var camera_model := SurfaceTool.new()
			camera_model.begin(Mesh.PRIMITIVE_TRIANGLES)
			var camera_body := BoxMesh.new()
			camera_body.size = Vector3(0.8, 0.6, 0.6)
			camera_model.append_from(camera_body, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.18)))
			var lens := CylinderMesh.new()
			lens.top_radius = 0.2
			lens.bottom_radius = 0.28
			lens.height = 0.32
			lens.radial_segments = 16
			lens.rings = 1
			camera_model.append_from(lens, 0, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -0.28)))
			return camera_model.commit()
		"concave_curve":
			# A block with a quarter disc scooped out of its (+X, +Y) corner.
			var fillet := PackedVector2Array([Vector2(-0.5, -0.5)])
			for step in CURVE_STEPS + 1:
				var angle := float(step) / float(CURVE_STEPS) * PI * 0.5
				fillet.append(Vector2(0.5 - sin(angle), 0.5 - cos(angle)))
			return _extrude(fillet)
		"frustum":
			var taper := CylinderMesh.new()
			taper.top_radius = 0.25
			taper.bottom_radius = 0.5
			taper.height = 1.0
			taper.radial_segments = 32
			taper.rings = 1
			return taper
		"pipe":
			return _lathe(PackedVector2Array([
				Vector2(PIPE_INNER_RADIUS, -0.5), Vector2(0.5, -0.5),
				Vector2(0.5, 0.5), Vector2(PIPE_INNER_RADIUS, 0.5),
			]), 32)
		"torus":
			# An oval outline that becomes a true circle at the default 1 x 0.25 x 1 size.
			var tube := PackedVector2Array()
			for step in 16:
				var angle := float(step) / 16.0 * TAU
				tube.append(Vector2(0.375 + 0.125 * cos(angle), 0.5 * sin(angle)))
			return _lathe(tube, 32)
		"half_cylinder":
			# Round side up, flat side down, running along Z.
			var half_disc := PackedVector2Array()
			for step in CURVE_STEPS * 2 + 1:
				var angle := float(step) / float(CURVE_STEPS * 2) * PI
				half_disc.append(Vector2(0.5 * cos(angle), -0.5 + sin(angle)))
			return _extrude(half_disc)
		"arch":
			# A block with a half-round opening cut up into its underside.
			var arch_outline := PackedVector2Array([Vector2(-0.5, -0.5), Vector2(-ARCH_RADIUS, -0.5)])
			for step in range(1, CURVE_STEPS * 2):
				var angle := PI - float(step) / float(CURVE_STEPS * 2) * PI
				arch_outline.append(Vector2(ARCH_RADIUS * cos(angle), -0.5 + ARCH_RADIUS * sin(angle)))
			arch_outline.append(Vector2(ARCH_RADIUS, -0.5))
			arch_outline.append(Vector2(0.5, -0.5))
			arch_outline.append(Vector2(0.5, 0.5))
			arch_outline.append(Vector2(-0.5, 0.5))
			return _extrude(arch_outline)
		"inverse_corner":
			# A block with its (+X, +Y, +Z) corner sliced off.
			var c000 := Vector3(-0.5, -0.5, -0.5)
			var c100 := Vector3(0.5, -0.5, -0.5)
			var c010 := Vector3(-0.5, 0.5, -0.5)
			var c001 := Vector3(-0.5, -0.5, 0.5)
			var c110 := Vector3(0.5, 0.5, -0.5)
			var c101 := Vector3(0.5, -0.5, 0.5)
			var c011 := Vector3(-0.5, 0.5, 0.5)
			return _from_triangles([
				c000, c010, c011, c000, c011, c001,
				c000, c100, c101, c000, c101, c001,
				c000, c100, c110, c000, c110, c010,
				c100, c110, c101, c010, c110, c011, c001, c101, c011,
				c110, c101, c011,
			])
		"corner_wedge":
			var a := Vector3(-0.5, -0.5, -0.5)
			var b := Vector3(0.5, -0.5, -0.5)
			var c := Vector3(-0.5, 0.5, -0.5)
			var d := Vector3(-0.5, -0.5, 0.5)
			return _from_triangles([a, c, b, a, b, d, a, d, c, b, c, d])
		"pyramid":
			var p0 := Vector3(-0.5, -0.5, -0.5)
			var p1 := Vector3(0.5, -0.5, -0.5)
			var p2 := Vector3(0.5, -0.5, 0.5)
			var p3 := Vector3(-0.5, -0.5, 0.5)
			var apex := Vector3(0.0, 0.5, 0.0)
			return _from_triangles([
				p0, p1, p2, p0, p2, p3,
				p0, apex, p1, p1, apex, p2, p2, apex, p3, p3, apex, p0,
			])
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	return box


static func _new_surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)   # flat shading: one normal per face
	return surface


static func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.generate_normals()
	return surface.commit()


## Adds one triangle, wound so that its front face points along `outward`.
static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	# The front-face normal Godot gives the winding a, b, c.
	var normal := (a - c).cross(a - b)
	if normal.length() < 0.0000001:
		return   # a sliver with no area
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


## +1 when a flat outline runs anticlockwise, -1 when it runs clockwise.
static func _orientation(outline: PackedVector2Array) -> float:
	var doubled_area := 0.0
	var count := outline.size()
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		doubled_area += p.x * q.y - q.x * p.y
	return 1.0 if doubled_area >= 0.0 else -1.0


## A closed convex solid from a flat list of triangle corners.
static func _from_triangles(points: Array) -> ArrayMesh:
	var middle := Vector3.ZERO
	for point in points:
		var corner: Vector3 = point
		middle += corner
	middle /= float(points.size())

	var surface := _new_surface()
	for index in range(0, points.size(), 3):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var c: Vector3 = points[index + 2]
		_add_triangle(surface, a, b, c, (a + b + c) / 3.0 - middle)
	return _finish(surface)


## The rounded wedge: the curved wedge's slope (level at -X, down to a thin
## edge at +X), rounded across Z as well, half an ellipse in section, so its
## tall end matches a half cylinder of the same size. Shaded smooth.
static func _rounded_ramp() -> ArrayMesh:
	_recipe = []
	var surface := _new_surface()
	var rows := RAMP_STEPS
	var cols := CURVE_STEPS * 2
	var inside := Vector3(-0.25, -0.45, 0.0)
	var grid: Array = []
	for i in rows + 1:
		var t := float(i) / float(rows)
		var height := 1.0 - t * t
		var row: Array = []
		for j in cols + 1:
			var angle := float(j) / float(cols) * PI
			row.append(Vector3(-0.5 + t, -0.5 + height * sin(angle), 0.5 * cos(angle)))
		grid.append(row)
	surface.set_smooth_group(1)
	for i in rows:
		for j in cols:
			var p00: Vector3 = grid[i][j]
			var p10: Vector3 = grid[i + 1][j]
			var p11: Vector3 = grid[i + 1][j + 1]
			var p01: Vector3 = grid[i][j + 1]
			_add_triangle(surface, p00, p10, p11, (p00 + p10 + p11) / 3.0 - inside)
			_add_triangle(surface, p00, p11, p01, (p00 + p11 + p01) / 3.0 - inside)
	surface.set_smooth_group(-1)
	var back_middle := Vector3(-0.5, -0.5, 0.0)
	for j in cols:
		_add_triangle(surface, back_middle, grid[0][j], grid[0][j + 1], Vector3(-1.0, 0.0, 0.0))
	var b0 := Vector3(-0.5, -0.5, -0.5)
	var b1 := Vector3(0.5, -0.5, -0.5)
	var b2 := Vector3(0.5, -0.5, 0.5)
	var b3 := Vector3(-0.5, -0.5, 0.5)
	_add_triangle(surface, b0, b1, b2, Vector3.DOWN)
	_add_triangle(surface, b0, b2, b3, Vector3.DOWN)
	return _finish(surface)


## A half cylinder (flat side down, round side up, running along Z) that
## tapers toward +Z to `top` of its size there: 0 for the half cone, whose
## tip lies on the middle of its flat face's front edge, 0.5 for the tapered
## half cylinder. The round is shaded smooth with true normals (worked out,
## not averaged, so the tip shades cleanly too).
static func _taper_half(top: float) -> ArrayMesh:
	_recipe = []
	var surface := _new_surface()
	var rows := 12
	var cols := CURVE_STEPS * 2
	var grid: Array = []
	var normals: Array = []
	for i in rows + 1:
		var t := float(i) / float(rows)
		var k := 1.0 - (1.0 - top) * t
		var row: Array = []
		var row_normals: Array = []
		for j in cols + 1:
			var angle := float(j) / float(cols) * PI
			row.append(Vector3(0.5 * k * cos(angle), -0.5 + k * sin(angle), -0.5 + t))
			# The gradient of (x / 0.5k)^2 + ((y + 0.5) / k)^2 with k falling along z.
			row_normals.append(Vector3(4.0 * cos(angle), 2.0 * sin(angle), 2.0 * (1.0 - top)).normalized())
		grid.append(row)
		normals.append(row_normals)
	var inside := Vector3(0.0, -0.4, -0.25)
	for i in rows:
		for j in cols:
			var p00: Vector3 = grid[i][j]
			var p10: Vector3 = grid[i + 1][j]
			var p11: Vector3 = grid[i + 1][j + 1]
			var p01: Vector3 = grid[i][j + 1]
			var n00: Vector3 = normals[i][j]
			var n10: Vector3 = normals[i + 1][j]
			var n11: Vector3 = normals[i + 1][j + 1]
			var n01: Vector3 = normals[i][j + 1]
			# (At a point, the first of the two is a sliver and is left out.)
			_add_shaded(surface, [p00, p10, p11], [n00, n10, n11], (p00 + p10 + p11) / 3.0 - inside)
			_add_shaded(surface, [p00, p11, p01], [n00, n11, n01], (p00 + p11 + p01) / 3.0 - inside)
	# The flat bottom, the back and (when it doesn't come to a point) the front.
	var down := Vector3.DOWN
	var b0 := Vector3(-0.5, -0.5, -0.5)
	var b1 := Vector3(0.5, -0.5, -0.5)
	var b2 := Vector3(0.5 * top, -0.5, 0.5)
	var b3 := Vector3(-0.5 * top, -0.5, 0.5)
	_add_shaded(surface, [b0, b1, b2], [down, down, down], down)
	if top > 0.0:
		_add_shaded(surface, [b0, b2, b3], [down, down, down], down)
	var back := Vector3(0.0, 0.0, -1.0)
	var back_middle := Vector3(0.0, -0.5, -0.5)
	for j in cols:
		_add_shaded(surface, [back_middle, grid[0][j], grid[0][j + 1]], [back, back, back], back)
	if top > 0.0:
		var front := Vector3(0.0, 0.0, 1.0)
		var front_middle := Vector3(0.0, -0.5, 0.5)
		for j in cols:
			_add_shaded(surface, [front_middle, grid[rows][j], grid[rows][j + 1]], [front, front, front], front)
	return surface.commit()


## Adds one triangle with its own normals, wound to face along `outward`.
static func _add_shaded(surface: SurfaceTool, corners: Array, corner_normals: Array, outward: Vector3) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var na: Vector3 = corner_normals[0]
	var nb: Vector3 = corner_normals[1]
	var nc: Vector3 = corner_normals[2]
	var normal := (a - c).cross(a - b)
	if normal.length() < 0.0000001:
		return
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		var swap_n := nb
		nb = nc
		nc = swap_n
	surface.set_normal(na)
	surface.add_vertex(a)
	surface.set_normal(nb)
	surface.add_vertex(b)
	surface.set_normal(nc)
	surface.add_vertex(c)


## Which smooth group each edge of a closed outline shades in (edge i runs
## from point i to point i + 1): edges meeting at a corner that turns less
## than SMOOTH_TURN are one curve and share a group; a lone straight edge
## between two sharp corners gets -1 (flat) unless `lone_smooth`.
static func _smooth_groups(outline: PackedVector2Array, lone_smooth: bool = false) -> PackedInt32Array:
	var count := outline.size()
	var smooth_at := []   # at point i: do edges i - 1 and i join smoothly?
	for index in count:
		var before := outline[index] - outline[(index - 1 + count) % count]
		var after := outline[(index + 1) % count] - outline[index]
		var joined := false
		if before.length() > 0.000001 and after.length() > 0.000001:
			joined = rad_to_deg(absf(before.angle_to(after))) < SMOOTH_TURN
		smooth_at.append(joined)
	var groups := PackedInt32Array()
	groups.resize(count)
	# Start each run of joined edges at an edge whose start is a sharp corner.
	var first := -1
	for index in count:
		if not bool(smooth_at[index]):
			first = index
			break
	var next_group := 1
	if first == -1:
		groups.fill(next_group)   # one smooth loop all round (a disc)
		return groups
	var run: Array = []
	for offset in count + 1:
		var index := (first + offset) % count
		if offset == count or not bool(smooth_at[index]):
			if not run.is_empty():
				var group := next_group if (run.size() > 1 or lone_smooth) else -1
				if group != -1:
					next_group += 1
				for edge in run:
					groups[int(edge)] = group
			run = []
		if offset < count:
			run.append(index)
	return groups


## Pushes a flat outline in the XY plane through the box along Z. Its
## curved stretches are shaded smooth, its flat faces and caps flat.
static func _extrude(outline: PackedVector2Array) -> ArrayMesh:
	_recipe = ["extrude", outline]
	var surface := _new_surface()
	var turn := _orientation(outline)
	var count := outline.size()
	var groups := _smooth_groups(outline)
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		var edge := q - p
		var side_out := Vector3(edge.y, -edge.x, 0.0) * turn
		var p_back := Vector3(p.x, p.y, -0.5)
		var p_front := Vector3(p.x, p.y, 0.5)
		var q_back := Vector3(q.x, q.y, -0.5)
		var q_front := Vector3(q.x, q.y, 0.5)
		surface.set_smooth_group(groups[index])
		_add_triangle(surface, p_back, p_front, q_front, side_out)
		_add_triangle(surface, p_back, q_front, q_back, side_out)
	surface.set_smooth_group(-1)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for index in range(0, triangles.size(), 3):
		var a := outline[triangles[index]]
		var b := outline[triangles[index + 1]]
		var c := outline[triangles[index + 2]]
		_add_triangle(surface, Vector3(a.x, a.y, 0.5), Vector3(b.x, b.y, 0.5), Vector3(c.x, c.y, 0.5), Vector3(0.0, 0.0, 1.0))
		_add_triangle(surface, Vector3(a.x, a.y, -0.5), Vector3(b.x, b.y, -0.5), Vector3(c.x, c.y, -0.5), Vector3(0.0, 0.0, -1.0))
	return _finish(surface)


## Spins a closed outline of (radius, height) points around the Y axis.
static func _lathe(outline: PackedVector2Array, segments: int) -> ArrayMesh:
	_recipe = ["lathe", outline, segments]
	var surface := _new_surface()
	var turn := _orientation(outline)
	var count := outline.size()
	# Spun round, every stretch of the outline is curved; corners stay sharp.
	var groups := _smooth_groups(outline, true)
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		if p.x < 0.00001 and q.x < 0.00001:
			continue   # this edge lies on the axis
		surface.set_smooth_group(groups[index])
		var edge := q - p
		var out_radial := edge.y * turn    # outward direction, away from the axis
		var out_height := -edge.x * turn   # outward direction, along Y
		for segment in segments:
			var angle_a := float(segment) / float(segments) * TAU
			var angle_b := float(segment + 1) / float(segments) * TAU
			var angle_mid := (angle_a + angle_b) * 0.5
			var outward := Vector3(out_radial * cos(angle_mid), out_height, out_radial * sin(angle_mid))
			var p_a := Vector3(p.x * cos(angle_a), p.y, p.x * sin(angle_a))
			var p_b := Vector3(p.x * cos(angle_b), p.y, p.x * sin(angle_b))
			var q_a := Vector3(q.x * cos(angle_a), q.y, q.x * sin(angle_a))
			var q_b := Vector3(q.x * cos(angle_b), q.y, q.x * sin(angle_b))
			_add_triangle(surface, p_a, q_a, q_b, outward)
			_add_triangle(surface, p_a, q_b, p_b, outward)
	return _finish(surface)


# --- Collision ---------------------------------------------------------------

## The distinct corner points of a part's unit mesh.
static func _unit_hull(part_id: String) -> PackedVector3Array:
	if not _hull_cache.has(part_id) and part_id == "rounded_wedge":
		# A coarser grid than the drawn one: plenty to bump into, and a much
		# smaller hull for the physics.
		var coarse := PackedVector3Array([Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5, 0.5),
				Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5)])
		for i in 6:
			var t := float(i) / 6.0
			for j in range(1, 8):
				var angle := float(j) / 8.0 * PI
				coarse.append(Vector3(-0.5 + t, -0.5 + (1.0 - t * t) * sin(angle), 0.5 * cos(angle)))
		_hull_cache[part_id] = coarse
	if not _hull_cache.has(part_id) and (part_id == "half_cone" or part_id == "half_frustum"):
		# Straight along its length, so its two end sections fix its hull.
		var top := 0.0 if part_id == "half_cone" else 0.5
		var ends := PackedVector3Array()
		for j in 11:
			var angle := float(j) / 10.0 * PI
			ends.append(Vector3(0.5 * cos(angle), -0.5 + sin(angle), -0.5))
			if top > 0.0:
				ends.append(Vector3(0.5 * top * cos(angle), -0.5 + top * sin(angle), 0.5))
		if top == 0.0:
			ends.append(Vector3(0.0, -0.5, 0.5))
		_hull_cache[part_id] = ends
	if not _hull_cache.has(part_id):
		var seen: Dictionary = {}
		var points := PackedVector3Array()
		for vertex in get_mesh(part_id).get_faces():
			var key: Vector3 = vertex.snapped(Vector3(0.0001, 0.0001, 0.0001))
			if not seen.has(key):
				seen[key] = true
				points.append(vertex)
		_hull_cache[part_id] = points
	return _hull_cache[part_id]


## The collision shape for a part at a given size in metres.
## `moving` is for spawned parts: a moving body cannot use a hollow (concave)
## shape, so those parts get their convex outline instead, hollows filled in.
static func make_shape(part_id: String, size_m: Vector3, moving: bool = false) -> Shape3D:
	var kind: String = _row(part_id)[5]
	if kind == "box":
		var box := BoxShape3D.new()
		box.size = size_m
		return box
	if kind == "concave" and not moving:
		var faces := get_mesh(part_id).get_faces()
		for index in faces.size():
			faces[index] = faces[index] * size_m
		var concave := ConcavePolygonShape3D.new()
		concave.backface_collision = true
		concave.set_faces(faces)
		return concave
	var hull := _unit_hull(part_id).duplicate()
	for index in hull.size():
		hull[index] = hull[index] * size_m
	var convex := ConvexPolygonShape3D.new()
	convex.points = hull
	return convex


## The collision shapes for a part, as a list: one shape for most parts.
## A hollow part (concave curve, arch, ring, pipe, torus) on a moving body
## can't use one hollow shape, so it is split into solid convex pieces that
## follow its real outline: the hole in a ring stays a hole.
static func make_shapes(part_id: String, size_m: Vector3, moving: bool = false) -> Array:
	var kind: String = _row(part_id)[5]
	if kind != "concave" or not moving:
		return [make_shape(part_id, size_m, moving)]
	var shapes: Array = []
	for item in convex_pieces(part_id):
		var points: PackedVector3Array = (item as PackedVector3Array).duplicate()
		for index in points.size():
			points[index] = points[index] * size_m
		var convex := ConvexPolygonShape3D.new()
		convex.points = points
		shapes.append(convex)
	return shapes


## A hollow part's solid convex pieces at unit size: an extruded outline is
## cut into convex outlines, each extruded; a lathed one into 16 wedges
## round its axis.
static func convex_pieces(part_id: String) -> Array:
	if _pieces_cache.has(part_id):
		return _pieces_cache[part_id]
	get_mesh(part_id)
	var recipe: Array = _recipes.get(part_id, [])
	var pieces: Array = []
	if not recipe.is_empty() and str(recipe[0]) == "extrude":
		for polygon in Geometry2D.decompose_polygon_in_convex(recipe[1]):
			var points := PackedVector3Array()
			for corner in (polygon as PackedVector2Array):
				points.append(Vector3(corner.x, corner.y, -0.5))
				points.append(Vector3(corner.x, corner.y, 0.5))
			pieces.append(points)
	elif not recipe.is_empty() and str(recipe[0]) == "lathe":
		var outline: PackedVector2Array = recipe[1]
		var wedges := mini(int(recipe[2]), 16)
		for wedge in wedges:
			var points := PackedVector3Array()
			for side in 2:
				var angle := float(wedge + side) / float(wedges) * TAU
				for corner in outline:
					points.append(Vector3(corner.x * cos(angle), corner.y, corner.x * sin(angle)))
			pieces.append(points)
	if pieces.is_empty():
		pieces = [_unit_hull(part_id)]
	_pieces_cache[part_id] = pieces
	return pieces


## Whether a point (in the part's unit space, -0.5 to 0.5 on each axis) is
## inside the part's real shape, give or take `slack`. Box parts fill their
## box; others are tested against their faces (hollow ones against their
## convex pieces).
static func contains_unit_point(part_id: String, point: Vector3, slack: float = 0.02) -> bool:
	var kind: String = _row(part_id)[5]
	if kind == "box":
		return absf(point.x) <= 0.5 + slack and absf(point.y) <= 0.5 + slack and absf(point.z) <= 0.5 + slack
	if not _planes_cache.has(part_id):
		var sets: Array = []
		for item in (convex_pieces(part_id) if kind == "concave" else [_unit_hull(part_id)]):
			var hull := _hull_planes(item as PackedVector3Array)
			sets.append(hull)
		_planes_cache[part_id] = sets
	for planes in _planes_cache[part_id]:
		var inside := true
		for plane in planes:
			if (plane as Plane).distance_to(point) > slack:
				inside = false
				break
		if inside:
			return true
	return false


## The outward faces of the convex hull of some points.
static func _hull_planes(points: PackedVector3Array) -> Array:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var mesh := shape.get_debug_mesh()
	var planes: Array = []
	var centre := Vector3.ZERO
	for point in points:
		centre += point
	centre /= maxf(points.size(), 1)
	var faces := mesh.get_faces()
	for index in range(0, faces.size(), 3):
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		var normal := (b - a).cross(c - a)
		if normal.length() < 1e-9:
			continue
		var plane := Plane(normal.normalized(), a)
		if plane.distance_to(centre) > 0.0:
			plane = -plane
		var known := false
		for other in planes:
			if (other as Plane).normal.dot(plane.normal) > 0.9999 and absf((other as Plane).d - plane.d) < 1e-5:
				known = true
				break
		if not known:
			planes.append(plane)
	return planes


# --- Overlays ----------------------------------------------------------------

## A see-through, unlit material for previews and highlights.
static func overlay_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if not _overlay_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_overlay_cache[key] = material
	return _overlay_cache[key]
