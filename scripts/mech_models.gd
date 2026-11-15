extends RefCounted
## Display models for the mechanical, logic and combat parts. Looks only: none of these parts
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
	"light_panel", "explosive_block", "machine_gun", "large_cannon", "ammo_generator",
]


static func has_model(part_id: String) -> bool:
	return IDS.has(part_id)


static func build(part_id: String) -> ArrayMesh:
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
			# A socket, a ball, a stud and a mounting plate.
			Kit.add_box(body, Vector3(0.0, -0.3125, 0.0), Vector3(0.75, 0.375, 0.75))
			Kit.add_sphere(detail, Vector3.ZERO, 0.22)
			Kit.add_cylinder(detail, Vector3(0.0, 0.3125, 0.0), Y, 0.09, 0.25)
			Kit.add_box(body, Vector3(0.0, 0.46875, 0.0), Vector3(0.5, 0.0625, 0.5))
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
			Kit.add_gear(body, Vector3.ZERO, Y, 0.4, 0.5, 0.8, 12)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.15, 1.0)
		"bevel_gear":
			# A toothed base stepping in toward the shaft.
			Kit.add_gear(body, Vector3(0.0, -0.3, 0.0), Y, 0.4, 0.5, 0.3, 12)
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
		_:
			Kit.add_box(body, Vector3.ZERO, Vector3.ONE)
			Kit.add_cylinder(detail, Vector3.ZERO, Y, 0.1, 1.0)
	return Kit.commit(body, detail, detail_look)
