extends RefCounted
## Display models for every part that is more than a plain shape. Looks only: none of these parts
## does anything until the Spawn milestone gives them behaviour.
##
## Every model is drawn inside a 1 x 1 x 1 box centred on the origin, with
## pieces sized in sixteenths where practical. "body" pieces take the part's
## material and colour; "detail" pieces (shafts, pins, teeth) stay dark metal.
## Shafts point along +Y unless noted.

const Kit = preload("res://scripts/mesh_kit.gd")

const X := 0
const Y := 1
const Z := 2

const IDS := [
	"motor", "servo", "door_hinge_servo", "hinge", "ball_joint", "bearing",
	"piston", "solenoid", "spring", "gear", "bevel_gear", "rack", "pulley",
	"crankshaft", "wheel", "linkage_bar", "clutch", "brake",
	"light_panel", "impact_detector", "explosive_block", "machine_gun", "large_cannon", "ammo_generator",
	"fluid_cylinder", "pump", "valve", "fluid_pipe", "fuel_tank", "pressure_tank",
	"combustion_cylinder", "compressor", "combustor", "turbine", "nozzle", "thruster", "solid_rocket",
	"aero_panel", "aero_panel_triangle", "propeller", "lift_gas_tank",
	"seat", "anchor_block", "dynamic_offsetter",
	"input_block", "boolean_gate", "number_gate", "pid_controller",
	"speed_sensor", "altitude_sensor", "attitude_sensor", "distance_sensor",
]


static func has_model(part_id: String) -> bool:
	return IDS.has(part_id)


## `teeth` only matters for gears: it sets how many teeth the model shows.
static func build(part_id: String, teeth: int = 12) -> ArrayMesh:
	var body := Kit.new_surface()
	var detail := Kit.new_surface()
	var detail_look: Material = null   # null means the usual dark metal
	match part_id:
		"motor":
			# A housing with a collar and an output shaft on top.
			Kit.add_box(body, Vector3(0.0, -0.1875, 0.0), Vector3(0.875, 0.625, 0.875))
			Kit.add_cylinder(detail, Vector3(0.0, 0.1875, 0.0), Y, 0.28, 0.125)
			Kit.add_cylinder(detail, Vector3(0.0, 0.375, 0.0), Y, 0.1, 0.25)
		"servo":
			# A slim housing with an off-centre output disc and a horn.
			Kit.add_box(body, Vector3(0.0, -0.1875, 0.0), Vector3(0.875, 0.625, 0.625))
			Kit.add_cylinder(detail, Vector3(0.15, 0.171875, 0.0), Y, 0.2, 0.09375)
			Kit.add_box(detail, Vector3(0.15, 0.25, 0.0), Vector3(0.15, 0.0625, 0.6))
		"door_hinge_servo":
			# A base, an upright leaf, the hinge barrel along their shared edge, and a drive unit.
			Kit.add_box(body, Vector3(0.0, -0.4375, 0.0), Vector3(1.0, 0.125, 1.0))
			Kit.add_box(body, Vector3(0.0, 0.0625, -0.4375), Vector3(1.0, 0.875, 0.125))
			Kit.add_cylinder(detail, Vector3(0.0, -0.3125, -0.3125), X, 0.125, 0.9375)
			Kit.add_box(detail, Vector3(0.3125, -0.25, 0.0), Vector3(0.25, 0.25, 0.375))
		"hinge":
			# Two leaves with a pin between them, running along X.
			Kit.add_box(body, Vector3(0.0, -0.3125, 0.0), Vector3(1.0, 0.375, 1.0))
			Kit.add_box(body, Vector3(0.0, 0.3125, 0.0), Vector3(1.0, 0.375, 1.0))
			Kit.add_cylinder(detail, Vector3.ZERO, X, 0.125, 0.9375)
		"ball_joint":
			# Two matching halves, like the hinge, with a ball held between them.
			Kit.add_box(body, Vector3(0.0, -0.3125, 0.0), Vector3(1.0, 0.375, 1.0))
			Kit.add_box(body, Vector3(0.0, 0.3125, 0.0), Vector3(1.0, 0.375, 1.0))
			Kit.add_sphere(detail, Vector3.ZERO, 0.27, 16, 8)
		"bearing":
			# Flat on four sides; the shaft passes through top to bottom.
			Kit.add_box(body, Vector3.ZERO, Vector3(1.0, 0.875, 1.0))
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.32, 0.9375)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.14, 1.0)
		"piston":
			# A flange, a barrel, a rod and a rod-end plate.
			Kit.add_box(body, Vector3(0.0, -0.4375, 0.0), Vector3(0.875, 0.125, 0.875))
			Kit.add_cylinder(body, Vector3(0.0, -0.0625, 0.0), Y, 0.34, 0.625)
			Kit.add_cylinder(detail, Vector3(0.0, 0.34375, 0.0), Y, 0.11, 0.1875)
			Kit.add_box(detail, Vector3(0.0, 0.46875, 0.0), Vector3(0.4, 0.0625, 0.4))
		"solenoid":
			# A frame around a coil, with a plunger out of the top.
			Kit.add_box(body, Vector3(0.0, -0.1875, 0.0), Vector3(0.625, 0.625, 0.625))
			Kit.add_cylinder(detail, Vector3(0.0, -0.1875, 0.0), Y, 0.38, 0.4375)
			Kit.add_cylinder(detail, Vector3(0.0, 0.3125, 0.0), Y, 0.1, 0.375)
		"spring":
			# Two end plates with six coils on a thin core.
			Kit.add_box(body, Vector3(0.0, -0.46875, 0.0), Vector3(0.75, 0.0625, 0.75))
			Kit.add_box(body, Vector3(0.0, 0.46875, 0.0), Vector3(0.75, 0.0625, 0.75))
			for coil in 6:
				Kit.add_cylinder(detail, Vector3(0.0, -0.3125 + 0.125 * float(coil), 0.0), Y, 0.3, 0.0625)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.07, 0.875)
		"gear":
			Kit.add_gear(body, Vector3.ZERO, Y, 0.4, 0.5, 0.8, teeth)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.15, 1.0)
		"bevel_gear":
			# A toothed base stepping in toward the shaft.
			Kit.add_gear(body, Vector3(0.0, -0.3, 0.0), Y, 0.4, 0.5, 0.3, teeth)
			Kit.add_cylinder(body, Vector3(0.0, -0.05, 0.0), Y, 0.33, 0.2)
			Kit.add_cylinder(body, Vector3(0.0, 0.15, 0.0), Y, 0.22, 0.2)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.12, 1.0)
		"rack":
			# A bar along X with teeth on top.
			Kit.add_box(body, Vector3(0.0, -0.2, 0.0), Vector3(1.0, 0.6, 1.0))
			for tooth in 5:
				Kit.add_box(detail, Vector3(-0.4 + 0.2 * float(tooth), 0.3, 0.0), Vector3(0.1, 0.4, 1.0))
		"pulley":
			# Two flanges and a groove for the belt.
			Kit.add_cylinder(body, Vector3(0.0, -0.375, 0.0), Y, 0.5, 0.2, 24)
			Kit.add_cylinder(body, Vector3(0.0, 0.375, 0.0), Y, 0.5, 0.2, 24)
			Kit.add_cylinder(body, Vector3.ZERO, Y, 0.36, 0.55, 24)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.14, 1.0)
		"crankshaft":
			# Runs along X: two journals, two webs and an offset crank pin.
			Kit.add_cylinder(detail, Vector3(-0.375, 0.0, 0.0), X, 0.12, 0.25)
			Kit.add_cylinder(detail, Vector3(0.375, 0.0, 0.0), X, 0.12, 0.25)
			Kit.add_box(body, Vector3(-0.1875, 0.0625, 0.0), Vector3(0.125, 0.75, 0.35))
			Kit.add_box(body, Vector3(0.1875, 0.0625, 0.0), Vector3(0.125, 0.75, 0.35))
			Kit.add_cylinder(detail, Vector3(0.0, 0.3, 0.0), X, 0.1, 0.25)
		"wheel":
			# The axle runs along X. The body is the tyre; the detail is the rim.
			Kit.add_cylinder(body, Vector3.ZERO, X, 0.5, 0.9, 24)
			Kit.add_cylinder(detail, Vector3.ZERO, X, 0.3, 1.0)
		"linkage_bar":
			# A bar along X with a band at each end where its joints go.
			Kit.add_box(body, Vector3.ZERO, Vector3(1.0, 0.7, 0.7))
			Kit.add_box(detail, Vector3(-0.42, 0.0, 0.0), Vector3(0.08, 1.0, 1.0))
			Kit.add_box(detail, Vector3(0.42, 0.0, 0.0), Vector3(0.08, 1.0, 1.0))
		"clutch":
			# Two plates with a friction disc between them.
			Kit.add_cylinder(body, Vector3(0.0, -0.3, 0.0), Y, 0.45, 0.35, 24)
			Kit.add_cylinder(body, Vector3(0.0, 0.3, 0.0), Y, 0.45, 0.35, 24)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.38, 0.25, 24)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.12, 1.0)
		"brake":
			# A disc on a hub, with a caliper gripping one side.
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.5, 0.3, 24)
			Kit.add_box(body, Vector3(0.3, 0.0, 0.0), Vector3(0.4, 0.9, 0.45))
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.14, 1.0)
		"light_panel":
			# A thin frame holding a lens that is black while the light is off.
			Kit.add_box(body, Vector3(0.0, -0.2, 0.0), Vector3(1.0, 0.6, 1.0))
			Kit.add_box(detail, Vector3(0.0, 0.3, 0.0), Vector3(0.875, 0.4, 0.875))
			detail_look = Kit.lens_material()
		"impact_detector":
			# A sensor housing with a collar and a domed sensing head.
			Kit.add_box(body, Vector3(0.0, -0.25, 0.0), Vector3(0.75, 0.5, 0.75))
			Kit.add_cylinder(detail, Vector3(0.0, 0.03125, 0.0), Y, 0.3, 0.0625)
			Kit.add_sphere(detail, Vector3(0.0, 0.15, 0.0), 0.22)
		"explosive_block":
			# A charge wrapped in two bands, with a detonator cap on top.
			Kit.add_box(body, Vector3.ZERO, Vector3(0.9375, 0.9375, 0.9375))
			Kit.add_box(detail, Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.125, 1.0))
			Kit.add_box(detail, Vector3(0.0, -0.25, 0.0), Vector3(1.0, 0.125, 1.0))
			Kit.add_cylinder(detail, Vector3(0.0, 0.484375, 0.0), Y, 0.15, 0.03125)
		"machine_gun":
			# Fires along -Z: receiver, barrel, muzzle, mount and ammo feed.
			Kit.add_box(body, Vector3(0.0, 0.0, 0.2), Vector3(0.45, 0.45, 0.6))
			Kit.add_cylinder(detail, Vector3(0.0, 0.05, -0.275), Z, 0.07, 0.35)
			Kit.add_cylinder(detail, Vector3(0.0, 0.05, -0.475), Z, 0.1, 0.05)
			Kit.add_box(detail, Vector3(0.0, -0.3625, 0.2), Vector3(0.3, 0.275, 0.3))
			Kit.add_box(detail, Vector3(0.3125, 0.0, 0.3), Vector3(0.175, 0.35, 0.25))
		"large_cannon":
			# Fires along -Z, styled on a tank gun: breech block, breech ring,
			# a plain barrel with a fume extractor, and a muzzle collar.
			Kit.add_box(body, Vector3(0.0, 0.0, 0.35), Vector3(0.8, 0.8, 0.3))
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, 0.17), Z, 0.24, 0.06, 20)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, -0.145), Z, 0.15, 0.69, 20)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, -0.1), Z, 0.21, 0.12, 20)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, -0.48), Z, 0.18, 0.04, 20)
		"ammo_generator":
			# A strapped crate with a lid and a feed chute on top.
			Kit.add_box(body, Vector3(0.0, -0.09, 0.0), Vector3(0.9375, 0.78, 0.9375))
			Kit.add_box(detail, Vector3(-0.25, -0.1, 0.0), Vector3(0.125, 0.8, 1.0))
			Kit.add_box(detail, Vector3(0.25, -0.1, 0.0), Vector3(0.125, 0.8, 1.0))
			Kit.add_box(detail, Vector3(0.0, 0.35, 0.0), Vector3(1.0, 0.1, 1.0))
			Kit.add_box(detail, Vector3(0.0, 0.45, 0.0), Vector3(0.3, 0.1, 0.3))
		# --- Fluid and engine parts. Gas flows toward +Z; exhaust leaves at +Z. ---
		"fluid_cylinder":
			# A hydraulic or gas cylinder: end cap, barrel, rod, rod end and a side port.
			Kit.add_box(body, Vector3(0.0, -0.46875, 0.0), Vector3(0.7, 0.0625, 0.7))
			Kit.add_cylinder(body, Vector3(0.0, -0.15, 0.0), Y, 0.3, 0.575)
			Kit.add_cylinder(detail, Vector3(0.0, 0.2875, 0.0), Y, 0.1, 0.3)
			Kit.add_box(detail, Vector3(0.0, 0.46875, 0.0), Vector3(0.35, 0.0625, 0.35))
			Kit.add_cylinder(detail, Vector3(0.35, -0.3, 0.0), X, 0.07, 0.2)
		"pump":
			# A housing with a drive cap on top and a pipe running through along X.
			Kit.add_box(body, Vector3(0.0, -0.1875, 0.0), Vector3(0.75, 0.625, 0.75))
			Kit.add_cylinder(detail, Vector3(0.0, 0.25, 0.0), Y, 0.25, 0.25)
			Kit.add_cylinder(detail, Vector3(0.0, -0.2, 0.0), X, 0.1, 1.0)
		"valve":
			# A pipe along X with a valve body, a stem and a handle.
			Kit.add_cylinder(detail, Vector3.ZERO, X, 0.14, 1.0)
			Kit.add_box(body, Vector3.ZERO, Vector3(0.4, 0.4, 0.4))
			Kit.add_cylinder(detail, Vector3(0.0, 0.3, 0.0), Y, 0.05, 0.2)
			Kit.add_box(body, Vector3(0.0, 0.43125, 0.0), Vector3(0.5, 0.0625, 0.12))
		"fluid_pipe":
			# A straight pipe along X with a flange near each end.
			Kit.add_cylinder(body, Vector3.ZERO, X, 0.15, 1.0)
			Kit.add_cylinder(detail, Vector3(-0.44, 0.0, 0.0), X, 0.22, 0.08)
			Kit.add_cylinder(detail, Vector3(0.44, 0.0, 0.0), X, 0.22, 0.08)
		"fuel_tank":
			# A tank lying along X, with two straps, two feet and a filler cap.
			Kit.add_cylinder(body, Vector3.ZERO, X, 0.42, 0.9, 24)
			Kit.add_cylinder(detail, Vector3(-0.25, 0.0, 0.0), X, 0.45, 0.06, 24)
			Kit.add_cylinder(detail, Vector3(0.25, 0.0, 0.0), X, 0.45, 0.06, 24)
			Kit.add_cylinder(detail, Vector3(0.0, 0.44, 0.0), Y, 0.08, 0.1)
			Kit.add_box(detail, Vector3(-0.3, -0.44, 0.0), Vector3(0.1, 0.12, 0.7))
			Kit.add_box(detail, Vector3(0.3, -0.44, 0.0), Vector3(0.1, 0.12, 0.7))
		"pressure_tank":
			# An upright vessel with rounded ends, a band and a side valve.
			Kit.add_cylinder(body, Vector3.ZERO, Y, 0.38, 0.24, 20)
			Kit.add_sphere(body, Vector3(0.0, 0.12, 0.0), 0.38, 20, 10)
			Kit.add_sphere(body, Vector3(0.0, -0.12, 0.0), 0.38, 20, 10)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.4, 0.05, 20)
			Kit.add_cylinder(detail, Vector3(0.42, 0.0, 0.0), X, 0.06, 0.12)
		"combustion_cylinder":
			# A finned block, a cylinder head, a spark plug on top and a rod below.
			Kit.add_box(body, Vector3(0.0, -0.1, 0.0), Vector3(0.7, 0.5, 0.7))
			for fin in 3:
				Kit.add_box(detail, Vector3(0.0, -0.25 + 0.15 * float(fin), 0.0), Vector3(0.8, 0.04, 0.8))
			Kit.add_box(body, Vector3(0.0, 0.225, 0.0), Vector3(0.6, 0.15, 0.6))
			Kit.add_cylinder(detail, Vector3(0.0, 0.4, 0.0), Y, 0.05, 0.2)
			Kit.add_cylinder(detail, Vector3(0.0, -0.425, 0.0), Y, 0.09, 0.15)
		"compressor":
			# A round casing with a dark blade disc showing at each face.
			Kit.add_cylinder(body, Vector3.ZERO, Z, 0.45, 0.9, 24)
			Kit.add_cylinder(detail, Vector3.ZERO, Z, 0.36, 0.94, 24)
			Kit.add_cylinder(detail, Vector3.ZERO, Z, 0.12, 1.0)
		"combustor":
			# A burner can with two bands and fuel injectors through it.
			Kit.add_cylinder(body, Vector3.ZERO, Z, 0.4, 0.8, 24)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, -0.25), Z, 0.43, 0.08, 24)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, 0.25), Z, 0.43, 0.08, 24)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.05, 0.94)
			Kit.add_cylinder(detail, Vector3.ZERO, X, 0.05, 0.94)
		"turbine":
			# A casing around a bladed wheel on a through shaft.
			Kit.add_cylinder(body, Vector3(0.0, 0.0, -0.1), Z, 0.45, 0.6, 24)
			Kit.add_gear(detail, Vector3(0.0, 0.0, -0.1), Z, 0.3, 0.4, 0.66, 16)
			Kit.add_cylinder(detail, Vector3.ZERO, Z, 0.1, 1.0)
		"nozzle":
			# A bell that widens toward its exit at +Z.
			Kit.add_frustum(body, Vector3(0.0, 0.0, -0.015), Z, 0.25, 0.45, 0.97, 24)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, 0.48), Z, 0.38, 0.04, 24)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, -0.44), Z, 0.3, 0.06, 24)
		"thruster":
			# A mounting block with a bell behind it. Pushes toward -Z.
			Kit.add_box(body, Vector3(0.0, 0.0, -0.35), Vector3(0.6, 0.6, 0.3))
			Kit.add_frustum(body, Vector3(0.0, 0.0, 0.125), Z, 0.2, 0.42, 0.65, 24)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, 0.475), Z, 0.34, 0.05, 24)
		"solid_rocket":
			# A casing with a tapered nose at -Z and a nozzle at +Z.
			Kit.add_cylinder(body, Vector3(0.0, 0.0, -0.05), Z, 0.4, 0.7, 24)
			Kit.add_frustum(body, Vector3(0.0, 0.0, -0.45), Z, 0.15, 0.4, 0.1, 24)
			Kit.add_frustum(detail, Vector3(0.0, 0.0, 0.4), Z, 0.18, 0.32, 0.2, 24)
			Kit.add_cylinder(detail, Vector3(0.0, 0.0, 0.1), Z, 0.42, 0.05, 24)
		# --- Aero parts. The leading edge faces -Z. ---
		"aero_panel":
			Kit.add_box(body, Vector3(0.0, 0.0, 0.03), Vector3(1.0, 0.9, 0.94))
			Kit.add_box(detail, Vector3(0.0, 0.0, -0.47), Vector3(1.0, 1.0, 0.06))
		"aero_panel_triangle":
			# A right triangle: root along the +Z edge, tip at the (-X, -Z) corner.
			Kit.add_extruded_polygon(body, [
				Vector3(-0.5, -0.45, 0.44), Vector3(0.5, -0.45, 0.44), Vector3(-0.5, -0.45, -0.5),
			], Vector3(0.0, 0.9, 0.0))
			Kit.add_box(detail, Vector3(0.0, 0.0, 0.47), Vector3(1.0, 1.0, 0.06))
		"propeller":
			# Four blades on a hub; the shaft runs along Y.
			Kit.add_cylinder(body, Vector3.ZERO, Y, 0.16, 0.6)
			Kit.add_box(body, Vector3(0.31, 0.0, 0.0), Vector3(0.38, 0.3, 0.14))
			Kit.add_box(body, Vector3(-0.31, 0.0, 0.0), Vector3(0.38, 0.3, 0.14))
			Kit.add_box(body, Vector3(0.0, 0.0, 0.31), Vector3(0.14, 0.3, 0.38))
			Kit.add_box(body, Vector3(0.0, 0.0, -0.31), Vector3(0.14, 0.3, 0.38))
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.12, 1.0)
		"lift_gas_tank":
			# A gas ball on a base ring, with a band round its middle.
			Kit.add_sphere(body, Vector3(0.0, 0.03, 0.0), 0.45, 20, 10)
			Kit.add_cylinder(detail, Vector3(0.0, -0.45, 0.0), Y, 0.3, 0.1, 20)
			Kit.add_cylinder(detail, Vector3(0.0, 0.03, 0.0), Y, 0.46, 0.05, 20)
		# --- Misc parts ---
		"seat":
			# Faces -Z: a cushion, a backrest, two armrests and a pedestal.
			Kit.add_box(body, Vector3(0.0, -0.25, 0.05), Vector3(0.8, 0.2, 0.7))
			Kit.add_box(body, Vector3(0.0, 0.175, 0.375), Vector3(0.8, 0.65, 0.15))
			Kit.add_box(detail, Vector3(0.0, -0.425, 0.05), Vector3(0.4, 0.15, 0.4))
			Kit.add_box(detail, Vector3(-0.44, -0.02, 0.1), Vector3(0.08, 0.08, 0.5))
			Kit.add_box(detail, Vector3(0.44, -0.02, 0.1), Vector3(0.08, 0.08, 0.5))
		"anchor_block":
			# A block clamped by a band, with a bolt through it top to bottom.
			Kit.add_box(body, Vector3.ZERO, Vector3(0.9375, 0.9375, 0.9375))
			Kit.add_box(detail, Vector3.ZERO, Vector3(1.0, 0.15, 1.0))
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.2, 1.0)
		"dynamic_offsetter":
			# Two halves joined by a core and four guide posts.
			Kit.add_box(body, Vector3(0.0, -0.29, 0.0), Vector3(0.9, 0.42, 0.9))
			Kit.add_box(body, Vector3(0.0, 0.29, 0.0), Vector3(0.9, 0.42, 0.9))
			Kit.add_box(detail, Vector3.ZERO, Vector3(0.5, 0.16, 0.5))
			for corner in 4:
				var post_x := 0.35 if corner % 2 == 0 else -0.35
				var post_z := 0.35 if corner < 2 else -0.35
				Kit.add_cylinder(detail, Vector3(post_x, 0.0, post_z), Y, 0.05, 0.16)
		# --- Logic parts. The detail colour says what kind of block it is. ---
		"input_block":
			# A base with a key cap.
			Kit.add_box(body, Vector3(0.0, -0.2, 0.0), Vector3(0.9375, 0.6, 0.9375))
			Kit.add_box(detail, Vector3(0.0, 0.225, 0.0), Vector3(0.5, 0.25, 0.5))
			detail_look = Kit.tinted_material(Color(0.95, 0.55, 0.15))
		"boolean_gate":
			# A board with a square chip, two input studs and an output stud.
			Kit.add_box(body, Vector3(0.0, -0.25, 0.0), Vector3(0.9375, 0.5, 0.9375))
			Kit.add_box(detail, Vector3(0.0, 0.1, 0.0), Vector3(0.45, 0.2, 0.6))
			Kit.add_box(detail, Vector3(-0.36, 0.06, 0.2), Vector3(0.12, 0.12, 0.12))
			Kit.add_box(detail, Vector3(-0.36, 0.06, -0.2), Vector3(0.12, 0.12, 0.12))
			Kit.add_box(detail, Vector3(0.36, 0.06, 0.0), Vector3(0.12, 0.12, 0.12))
			detail_look = Kit.tinted_material(Color(0.25, 0.75, 0.35))
		"number_gate":
			# The same board with a round chip.
			Kit.add_box(body, Vector3(0.0, -0.25, 0.0), Vector3(0.9375, 0.5, 0.9375))
			Kit.add_cylinder(detail, Vector3(0.0, 0.1, 0.0), Y, 0.26, 0.2)
			Kit.add_box(detail, Vector3(-0.38, 0.06, 0.2), Vector3(0.12, 0.12, 0.12))
			Kit.add_box(detail, Vector3(-0.38, 0.06, -0.2), Vector3(0.12, 0.12, 0.12))
			Kit.add_box(detail, Vector3(0.38, 0.06, 0.0), Vector3(0.12, 0.12, 0.12))
			detail_look = Kit.tinted_material(Color(0.25, 0.5, 0.95))
		"pid_controller":
			# A board with three bars, one each for P, I and D.
			Kit.add_box(body, Vector3(0.0, -0.25, 0.0), Vector3(0.9375, 0.5, 0.9375))
			for bar in 3:
				Kit.add_box(detail, Vector3(-0.28 + 0.28 * float(bar), 0.125, 0.0), Vector3(0.2, 0.25, 0.6))
			detail_look = Kit.tinted_material(Color(0.65, 0.35, 0.9))
		"speed_sensor":
			# A base with a pitot tube pointing along -Z.
			Kit.add_box(body, Vector3(0.0, -0.3, 0.0), Vector3(0.75, 0.4, 0.75))
			Kit.add_box(detail, Vector3(0.0, 0.0, 0.2), Vector3(0.12, 0.2, 0.12))
			Kit.add_cylinder(detail, Vector3(0.0, 0.05, -0.05), Z, 0.06, 0.9)
			detail_look = Kit.tinted_material(Color(0.95, 0.8, 0.2))
		"altitude_sensor":
			# A base with a dome and a mast.
			Kit.add_box(body, Vector3(0.0, -0.3, 0.0), Vector3(0.75, 0.4, 0.75))
			Kit.add_sphere(detail, Vector3(0.0, -0.05, 0.0), 0.25)
			Kit.add_cylinder(detail, Vector3(0.0, 0.3, 0.0), Y, 0.04, 0.35)
			detail_look = Kit.tinted_material(Color(0.95, 0.8, 0.2))
		"attitude_sensor":
			# A base with two crossed rings, like a gyroscope.
			Kit.add_box(body, Vector3(0.0, -0.3, 0.0), Vector3(0.75, 0.4, 0.75))
			Kit.add_cylinder(detail, Vector3(0.0, 0.2, 0.0), X, 0.3, 0.08, 20)
			Kit.add_cylinder(detail, Vector3(0.0, 0.2, 0.0), Z, 0.3, 0.08, 20)
			detail_look = Kit.tinted_material(Color(0.95, 0.8, 0.2))
		"distance_sensor":
			# A housing with two lenses looking along -Z.
			Kit.add_box(body, Vector3(0.0, -0.25, 0.1), Vector3(0.75, 0.5, 0.6))
			Kit.add_cylinder(detail, Vector3(-0.1, -0.2, -0.3), Z, 0.16, 0.25)
			Kit.add_cylinder(detail, Vector3(0.22, -0.2, -0.28), Z, 0.08, 0.2)
			detail_look = Kit.tinted_material(Color(0.95, 0.8, 0.2))
		_:
			Kit.add_box(body, Vector3.ZERO, Vector3.ONE)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.1, 1.0)
	return Kit.commit(body, detail, detail_look)
