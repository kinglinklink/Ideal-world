extends RefCounted
## Definitions for every placeable part.
##
## Every part is described inside a 1 x 1 x 1 box centred on the origin. A
## part's real shape is that unit shape stretched to its size, so the volume
## and centre of mass below are given as fractions of the bounding box.

const MechModels = preload("res://scripts/mech_models.gd")

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
	"corner_wedge": ["Corner wedge", "Advanced", Vector3(1, 1, 1), 0.166667, Vector3(-0.25, -0.25, -0.25), "convex"],
	"inverse_corner": ["Inverse corner", "Advanced", Vector3(1, 1, 1), 0.833333, Vector3(-0.05, -0.05, -0.05), "convex"],
	"pyramid": ["Pyramid", "Advanced", Vector3(1, 1, 1), 0.333333, Vector3(0, -0.25, 0), "convex"],
	"cone": ["Cone", "Advanced", Vector3(1, 1, 1), 0.261799, Vector3(0, -0.25, 0), "convex"],
	"frustum": ["Tapered cylinder", "Advanced", Vector3(1, 1, 1), 0.458149, Vector3(0, -0.10714, 0), "convex"],
	"hemisphere": ["Hemisphere", "Advanced", Vector3(1, 0.5, 1), 0.523599, Vector3(0, -0.125, 0), "convex"],
	"half_cylinder": ["Half cylinder", "Advanced", Vector3(1, 0.5, 1), 0.785398, Vector3(0, -0.07559, 0), "convex"],
	"convex_curve": ["Convex curve", "Advanced", Vector3(1, 1, 1), 0.785398, Vector3(-0.07559, -0.07559, 0), "convex"],
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
	"aero_panel_triangle": ["Triangle aero panel", "Aero", Vector3(1, 0.125, 1), 0.5, Vector3(-0.1667, 0, 0.1667), "box"],
	"aero_panel_dragless": ["Dragless square panel", "Aero", Vector3(1, 0.125, 1), 1.0, Vector3(0, 0, 0), "box"],
	"aero_panel_triangle_dragless": ["Dragless triangle panel", "Aero", Vector3(1, 0.125, 1), 0.5, Vector3(-0.1667, 0, 0.1667), "box"],
	"propeller": ["Propeller", "Aero", Vector3(1, 0.25, 1), 0.3, Vector3(0, 0, 0), "box"],
	"lift_gas_tank": ["Lift-gas tank", "Aero", Vector3(1, 1, 1), 0.1, Vector3(0, 0, 0), "box"],
	"input_block": ["Input", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"mouse_click": ["Mouse click", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"boolean_gate": ["Boolean gate", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"number_gate": ["Number logic", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"pid_controller": ["PID controller", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"pwm_generator": ["PWM generator", "Logic", Vector3(1, 0.5, 1), 0.5, Vector3(0, 0, 0), "box"],
	"speed_sensor": ["Speed sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"altitude_sensor": ["Altitude sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"attitude_sensor": ["Attitude sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"distance_sensor": ["Distance sensor", "Logic", Vector3(1, 1, 1), 0.3, Vector3(0, 0, 0), "box"],
	"graph_display": ["Graph screen", "Logic", Vector3(4, 3, 0.25), 0.6, Vector3(0, 0, 0), "box"],
	"seat": ["Seat", "Misc", Vector3(3, 3, 3), 0.4, Vector3(0, 0, 0), "box"],
	"anchor_block": ["Anchor block", "Misc", Vector3(1, 1, 1), 0.9, Vector3(0, 0, 0), "box"],
	"dynamic_offsetter": ["Dynamic offsetter", "Misc", Vector3(1, 1, 1), 0.8, Vector3(0, 0, 0), "box"],
	"magnet": ["Electromagnet", "Misc", Vector3(2, 0.5, 2), 0.9, Vector3(0, 0, 0), "box"],
	"winch": ["Winch and hook", "Misc", Vector3(2, 1, 1), 0.6, Vector3(0, 0, 0), "box"],
	"coupler": ["Coupler", "Misc", Vector3(1, 1, 0.5), 0.8, Vector3(0, 0, 0), "box"],
}

## Parts that start in their own colour instead of the brush colour.
## They can still be repainted afterwards.
const DEFAULT_COLORS := {
	"vanish_block": Color(1.0, 1.0, 1.0),
	"light_panel": Color(0.20, 0.21, 0.23),
	"impact_detector": Color(0.95, 0.75, 0.15),
	"explosive_block": Color(0.78, 0.12, 0.10),
	"machine_gun": Color(0.30, 0.33, 0.27),
	"hitscan_gun": Color(0.22, 0.24, 0.30),
	"large_cannon": Color(0.30, 0.33, 0.27),
	"ammo_generator": Color(0.30, 0.33, 0.27),
	"lift_gas_tank": Color(0.88, 0.92, 0.96),
	"aero_panel_dragless": Color(0.55, 0.90, 1.0),
	"aero_panel_triangle_dragless": Color(0.55, 0.90, 1.0),
	"anchor_block": Color(0.55, 0.57, 0.60),
	"input_block": Color(0.20, 0.21, 0.23),
	"mouse_click": Color(0.20, 0.21, 0.23),
	"boolean_gate": Color(0.20, 0.21, 0.23),
	"number_gate": Color(0.20, 0.21, 0.23),
	"pid_controller": Color(0.20, 0.21, 0.23),
	"pwm_generator": Color(0.20, 0.21, 0.23),
	"speed_sensor": Color(0.20, 0.21, 0.23),
	"altitude_sensor": Color(0.20, 0.21, 0.23),
	"attitude_sensor": Color(0.20, 0.21, 0.23),
	"distance_sensor": Color(0.20, 0.21, 0.23),
	"graph_display": Color(0.16, 0.17, 0.19),
	"magnet": Color(0.62, 0.12, 0.10),
	"winch": Color(0.95, 0.72, 0.10),
	"coupler": Color(0.35, 0.37, 0.40),
}

const CATEGORIES := ["Basic", "Structural", "Advanced", "Mechanical", "Fluid and Engine", "Aero", "Logic", "Combat", "Misc"]
const RING_INNER_RADIUS := 0.3   # of a unit ring whose outer radius is 0.5
const PIPE_INNER_RADIUS := 0.4   # a thinner wall than the ring
const ARCH_RADIUS := 0.4         # of the opening cut into a unit arch
const CURVE_STEPS := 10

static var _mesh_cache: Dictionary = {}
static var _hull_cache: Dictionary = {}
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
			_mesh_cache[key] = _build_mesh(part_id)
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


## Pushes a flat outline in the XY plane through the box along Z.
static func _extrude(outline: PackedVector2Array) -> ArrayMesh:
	var surface := _new_surface()
	var turn := _orientation(outline)
	var count := outline.size()
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		var edge := q - p
		var side_out := Vector3(edge.y, -edge.x, 0.0) * turn
		var p_back := Vector3(p.x, p.y, -0.5)
		var p_front := Vector3(p.x, p.y, 0.5)
		var q_back := Vector3(q.x, q.y, -0.5)
		var q_front := Vector3(q.x, q.y, 0.5)
		_add_triangle(surface, p_back, p_front, q_front, side_out)
		_add_triangle(surface, p_back, q_front, q_back, side_out)
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
	var surface := _new_surface()
	var turn := _orientation(outline)
	var count := outline.size()
	for index in count:
		var p := outline[index]
		var q := outline[(index + 1) % count]
		if p.x < 0.00001 and q.x < 0.00001:
			continue   # this edge lies on the axis
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
