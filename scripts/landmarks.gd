extends Node3D
## The built things on the map, placed by tools/bake_map.py (world.json):
##   Wild Horse Island airport  a 1,200 m asphalt runway at 90 degrees to
##                              Melita's, with an apron, hangar and tower
##   Melita Island bush strip   a gravel strip as long as the island allows,
##                              starting at the camp dock, with the camp
##                              lodge as its terminal
##   Cromwell Island villa      the unfinished four-storey stone mansion
##   the other islands          gravel airstrips as long as each allows, or a
##                              helipad where none fits, and the Shelter
##                              Island mansion
##   the aircraft carrier       at a random spot on open water each time
##
## Buildings are made of boxes and cylinders, merged into one mesh per colour,
## and are solid where you would expect. The ground under them was levelled
## by the bake. Local axes of each place: -Z is the way it faces (a runway's
## direction of travel), +X is to its right, +Y up.

const MapInfo = preload("res://scripts/map_info.gd")
const Units = preload("res://scripts/units.gd")
const Kit = preload("res://scripts/mesh_kit.gd")

const ASPHALT := Color(0.19, 0.19, 0.21)
const PAINT := Color(0.93, 0.93, 0.90)
const GRAVEL := Color(0.58, 0.53, 0.44)
const WOOD := Color(0.47, 0.33, 0.21)
const LOGS := Color(0.43, 0.29, 0.17)
const LOG_SEAM := Color(0.27, 0.18, 0.11)
const GREEN_ROOF := Color(0.20, 0.32, 0.22)
const STONE := Color(0.55, 0.54, 0.52)
const SANDSTONE := Color(0.80, 0.74, 0.62)
const PALE_STONE := Color(0.86, 0.83, 0.76)
const SLATE := Color(0.25, 0.27, 0.31)
const GLASS := Color(0.11, 0.15, 0.21)
const HANGAR := Color(0.70, 0.74, 0.78)
const HANGAR_ROOF := Color(0.55, 0.22, 0.18)
const CRANE := Color(0.86, 0.66, 0.12)
const NAVY_GREY := Color(0.42, 0.45, 0.48)
const DECK := Color(0.23, 0.24, 0.26)
const WINDSOCK := Color(0.95, 0.45, 0.10)
const TRAVERTINE := Color(0.87, 0.81, 0.69)
const TERRACOTTA := Color(0.71, 0.35, 0.22)
const MAHOGANY := Color(0.36, 0.17, 0.11)
const CARRIER_SCALE := 3.0     # times the size of a real Nimitz-class carrier

## Places for the mini map: [Vector2 x and z, label].
var map_points: Array = []


func setup(world: Dictionary) -> void:
	for item in world.get("runways", []):
		var runway: Dictionary = item
		if str(runway.get("surface", "")) == "asphalt":
			_paved_airport(runway)
		else:
			_bush_strip(runway)
		_runway_lights(runway)
	for item in world.get("docks", []):
		_dock(item)
	for item in world.get("buildings", []):
		var building: Dictionary = item
		match str(building.get("kind", "")):
			"melita_lodge":
				_lodge(building)
			"cromwell_mansion":
				_mansion(building)
			"cromwell_guest_villa":
				_guest_villa(building)
			"shelter_mansion":
				_shelter_mansion(building)
	for item in world.get("helipads", []):
		_helipad(item)
	_carrier(world.get("carrier_spots", []))


## A place's frame: its centre on the ground, facing along `heading` (degrees
## clockwise from north).
static func frame(centre: Vector2, height: float, heading: float) -> Transform3D:
	var a := deg_to_rad(heading)
	var along := Vector3(sin(a), 0.0, -cos(a))
	var across := Vector3(cos(a), 0.0, sin(a))
	return Transform3D(Basis(across, Vector3.UP, -along), Vector3(centre.x, height, centre.y))


static func _point(value: Variant) -> Vector2:
	var pair: Array = value
	return Vector2(float(pair[0]), float(pair[1]))


# --- Wild Horse Island airport -------------------------------------------------

## Lights along both edges of a runway, white every 60 m, and green across
## each end. They are in the "night_lights" group: daylight.gd shows them
## after dusk.
func _runway_lights(runway: Dictionary) -> void:
	var length := float(runway["length"])
	var width := float(runway["width"])
	var place := frame(_point(runway["centre"]), float(runway["height_mid"]), float(runway["heading"]))
	place.basis = place.basis * Basis(Vector3.RIGHT, atan(float(runway.get("slope", 0.0))))
	var spots: Array = []   # [position along the runway's own axes, colour]
	var half := length * 0.5
	var t := -half
	while t <= half + 0.1:
		for side in [-1.0, 1.0]:
			spots.append([Vector3(float(side) * (width * 0.5 + 1.5), 0.5, t), Color(1.0, 0.95, 0.8)])
		t += 60.0
	for end in [-1.0, 1.0]:
		var across := -width * 0.5
		while across <= width * 0.5 + 0.1:
			spots.append([Vector3(across, 0.5, float(end) * (half + 3.0)), Color(0.3, 1.0, 0.45)])
			across += 4.0
	var bulb := BoxMesh.new()
	bulb.size = Vector3(1.0, 1.0, 1.0)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	bulb.material = look
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = bulb
	batch.instance_count = spots.size()
	for index in spots.size():
		var spot: Array = spots[index]
		batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, spot[0]))
		batch.set_instance_color(index, spot[1])
	var lights := MultiMeshInstance3D.new()
	lights.name = str(runway.get("name", "Runway")).replace(" ", "") + "Lights"
	lights.multimesh = batch
	lights.transform = place
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lights.visible = false
	lights.add_to_group("night_lights")
	add_child(lights)


func _paved_airport(runway: Dictionary) -> void:
	var centre := _point(runway["centre"])
	var heading := float(runway["heading"])
	var length := float(runway["length"])
	var width := float(runway["width"])
	var mid := float(runway["height_mid"])
	var slope := float(runway.get("slope", 0.0))
	var airport_name := str(runway.get("name", "Airport"))
	if not airport_name.ends_with("airport"):
		airport_name = airport_name.trim_suffix(" Island") + " airport"
	map_points.append([centre, airport_name])

	# The runway follows the bake's straight grade.
	var place := frame(centre, mid, heading)
	place.basis = place.basis * Basis(Vector3.RIGHT, atan(slope))
	var strip := Builder.new(self, airport_name.replace(" ", "") + "Runway", place, 0.9)
	var half := length * 0.5
	strip.box(Vector3(0.0, -0.19, 0.0), Vector3(width, 0.5, length + 2.0), ASPHALT)
	strip.box(Vector3(-width * 0.5 + 1.0, 0.065, 0.0), Vector3(0.9, 0.02, length - 4.0), PAINT, false)
	strip.box(Vector3(width * 0.5 - 1.0, 0.065, 0.0), Vector3(0.9, 0.02, length - 4.0), PAINT, false)
	var t := -half + 90.0
	while t < half - 90.0:
		strip.box(Vector3(0.0, 0.065, t), Vector3(0.9, 0.02, 30.0), PAINT, false)
		t += 60.0
	for end in [-1.0, 1.0]:
		var sign_end: float = end
		for bar in maxi(2, int((width * 0.5 - 3.0) / 2.2)):   # as many stripes as the width holds
			for side in [-1.0, 1.0]:
				var x: float = side * (2.6 + bar * 2.2)
				strip.box(Vector3(x, 0.065, sign_end * (half - 22.0)), Vector3(1.6, 0.02, 30.0), PAINT, false)
		for side in [-1.0, 1.0]:
			strip.box(Vector3(side * 6.0, 0.065, sign_end * (half - 300.0)), Vector3(5.0, 0.02, 45.0), PAINT, false)
	strip.finish()
	# Runway numbers: the heading in tens of degrees, read on the way in.
	var landing_north := int(round(fposmod(heading, 360.0) / 10.0))
	if landing_north == 0:
		landing_north = 36
	var landing_south := int(round(fposmod(heading + 180.0, 360.0) / 10.0))
	if landing_south == 0:
		landing_south = 36
	_painted_number(strip.body, "%02d" % landing_north, Vector3(0.0, 0.08, half - 60.0), 0.0)
	_painted_number(strip.body, "%02d" % landing_south, Vector3(0.0, 0.08, -half + 60.0), PI)

	# The apron, hangar and tower, beside the middle of the runway.
	var apron: Dictionary = runway["apron"]
	var apron_place := frame(_point(apron["centre"]), mid, heading)
	var apron_side := float(apron.get("side", 1.0))
	var yard := Builder.new(self, airport_name.replace(" ", "") + "Apron", apron_place, 0.9)
	var apron_width := float(apron["width"])
	var apron_length := float(apron["length"])
	yard.box(Vector3(0.0, -0.19, 0.0), Vector3(apron_width, 0.5, apron_length), ASPHALT)
	# The hangar's back is at the far edge of the apron; its door faces the runway.
	var far := apron_side * (apron_width * 0.5)
	var back := far - apron_side * 4.0
	var front := back - apron_side * 30.0
	var hangar_mid := (back + front) * 0.5
	yard.box(Vector3(back, 6.0, 0.0), Vector3(0.5, 12.0, 44.0), HANGAR)
	yard.box(Vector3(hangar_mid, 6.0, -21.75), Vector3(30.0, 12.0, 0.5), HANGAR)
	yard.box(Vector3(hangar_mid, 6.0, 21.75), Vector3(30.0, 12.0, 0.5), HANGAR)
	yard.box(Vector3(hangar_mid, 12.3, 0.0), Vector3(31.0, 0.6, 45.0), HANGAR_ROOF)
	yard.box(Vector3(front, 10.5, 0.0), Vector3(0.5, 3.0, 44.0), HANGAR)
	# The tower.
	var tower := Vector3(hangar_mid, 0.0, 34.0)
	yard.box(tower + Vector3(0.0, 7.0, 0.0), Vector3(4.0, 14.0, 4.0), HANGAR)
	yard.box(tower + Vector3(0.0, 15.5, 0.0), Vector3(6.0, 3.0, 6.0), GLASS)
	yard.box(tower + Vector3(0.0, 17.2, 0.0), Vector3(7.0, 0.4, 7.0), HANGAR_ROOF)
	_windsock(yard, Vector3(-apron_side * (apron_width * 0.5 - 4.0), 0.0, -apron_length * 0.5 + 6.0))
	yard.finish()
	var sign_label := _label(yard.body, str(apron.get("label", "WILD HORSE ISLAND")), 0.03)
	sign_label.position = Vector3(front - apron_side * 0.3, 10.5, 0.0)
	sign_label.rotation = Vector3(0.0, -apron_side * PI * 0.5, 0.0)


func _painted_number(parent: Node3D, text: String, at: Vector3, turn: float) -> void:
	var number := _label(parent, text, 0.09)
	number.position = at
	number.rotation = Vector3(-PI * 0.5, turn, 0.0)
	number.modulate = PAINT
	number.outline_size = 0


# --- Melita Island bush strip, dock and lodge ----------------------------------

func _bush_strip(runway: Dictionary) -> void:
	var centre := _point(runway["centre"])
	var heading := float(runway["heading"])
	var length := float(runway["length"])
	var width := float(runway["width"])
	var profile: Array = runway["profile"]
	var step := float(runway["profile_step"])
	map_points.append([centre, "%s airstrip" % str(runway.get("name", "Island")).trim_suffix(" Island")])

	var a := deg_to_rad(heading)
	var along := Vector3(sin(a), 0.0, -cos(a))
	var across := Vector3(cos(a), 0.0, sin(a))
	var start := Vector3(centre.x, 0.0, centre.y) - along * (length * 0.5)
	var surface := Kit.new_surface()
	var faces := PackedVector3Array()
	var lift := 0.08
	for index in profile.size() - 1:
		var t0 := index * step
		var t1 := (index + 1) * step
		var p0 := start + along * t0 + Vector3.UP * (float(profile[index]) + lift)
		var p1 := start + along * t1 + Vector3.UP * (float(profile[index + 1]) + lift)
		var half := across * (width * 0.5)
		var quad := [p0 - half, p1 - half, p1 + half, p0 + half]
		Kit.add_triangle(surface, quad[0], quad[1], quad[2], Vector3.UP)
		Kit.add_triangle(surface, quad[0], quad[2], quad[3], Vector3.UP)
		faces.append_array(PackedVector3Array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]))
	surface.generate_normals()
	var mesh := surface.commit()
	var look := StandardMaterial3D.new()
	look.albedo_color = GRAVEL
	look.roughness = 1.0
	mesh.surface_set_material(0, look)
	var body := StaticBody3D.new()
	body.physics_material_override = Units.world_surface()
	body.name = "MelitaStrip"
	body.collision_layer = Units.LAYER_WORLD
	body.collision_mask = 0
	var grip := PhysicsMaterial.new()
	grip.friction = 0.7
	body.physics_material_override = grip
	add_child(body)
	var drawn := MeshInstance3D.new()
	drawn.mesh = mesh
	body.add_child(drawn)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	# White edge markers every 50 m, the way bush strips are marked.
	var markers := Builder.new(self, "MelitaMarkers", Transform3D.IDENTITY, 0.8)
	var t := 0.0
	while t <= length:
		var index := clampi(int(round(t / step)), 0, profile.size() - 1)
		var ground := float(profile[index])
		for side in [-1.0, 1.0]:
			var spot: Vector3 = start + along * t + across * (float(side) * (width * 0.5 + 1.5))
			markers.box(Vector3(spot.x, ground + 0.3, spot.z), Vector3(0.6, 0.6, 0.6), PAINT, false)
		t += 50.0
	var end := start + along * length
	_windsock(markers, Vector3(end.x, float(profile[profile.size() - 1]), end.z) + across * (width * 0.5 + 6.0))
	markers.finish()


## A dock. "landing" is the plain timber landing at the end of the Melita
## strip; "marina" is Camp Melita's main dock on the island's south face, a
## wide walkway on rock-filled cribbing with finger piers, a T-head and the
## camp's fleet; "yacht" is Cromwell's five-slip dock with a 70 ft yacht and
## the estate's 60 ft barge.
func _dock(dock: Dictionary) -> void:
	var start := _point(dock["start"])
	var deck := float(dock["deck"])
	var length := float(dock["length"])
	var width := float(dock["width"])
	var kind := str(dock.get("kind", "landing"))
	var pier := Builder.new(self, str(dock.get("name", "Dock")).replace(" ", ""), frame(start, deck, float(dock["heading"])), 0.6)
	# The walkway, from a few metres up the bank out over the water.
	pier.box(Vector3(0.0, -0.15, -(length * 0.5 - 4.0)), Vector3(width, 0.3, length + 8.0), WOOD)
	var z := 0.0
	while z <= length:
		for side in [-1.0, 1.0]:
			pier.cylinder(Vector3(float(side) * (width * 0.5 - 0.3), -5.0, -z), 0.18, 10.0, LOG_SEAM)
		z += 6.0
	if kind == "marina":
		map_points.append([start, "Melita dock"])
		# Rock-filled cribs under the first stretch.
		var crib := 0.0
		while crib <= 30.0:
			pier.box(Vector3(0.0, -2.0, -crib - 3.0), Vector3(width + 1.0, 3.4, 5.0), STONE)
			crib += 9.0
		# The T-head across the end, and finger piers along both sides.
		pier.box(Vector3(0.0, -0.15, -length - 4.0), Vector3(60.0, 0.3, 8.0), WOOD)
		var finger := 34.0
		while finger <= length - 10.0:
			for side in [-1.0, 1.0]:
				var sx: float = side
				pier.box(Vector3(sx * (width * 0.5 + 7.0), -0.15, -finger), Vector3(14.0, 0.3, 2.0), WOOD)
			finger += 9.0
		# The fleet: pontoon "arks" along the T-head, sailboats and fishing
		# boats in the slips, canoes racked on the T-head.
		for index in 3:
			_boat(pier, Vector3(-20.0 + index * 20.0, -0.9, -length - 13.0), Vector3(4.5, 1.2, 12.0), Color(0.82, 0.82, 0.80), true)
		var slip := 38.5
		var count := 0
		while slip <= length - 10.0:
			for side in [-1.0, 1.0]:
				var sx: float = side
				var sail := count % 2 == 0
				_boat(pier, Vector3(sx * (width * 0.5 + 7.0), -0.9, -slip), Vector3(12.0 if sail else 9.0, 1.0, 3.0),
						PAINT if sail else Color(0.70, 0.18, 0.15), false)
				if sail:
					pier.cylinder(Vector3(sx * (width * 0.5 + 7.0), 5.0, -slip), 0.1, 11.0, PAINT, false)
				count += 1
			slip += 9.0
		# Canoes racked side by side on the T-head.
		for index in 6:
			pier.box(Vector3(14.0 + index * 1.4, 0.25, -length - 4.0), Vector3(0.8, 0.4, 4.5),
					[Color(0.85, 0.35, 0.12), Color(0.15, 0.40, 0.70)][index % 2], false)
	elif kind == "yacht":
		map_points.append([start, "Cromwell dock"])
		# Five slips of different sizes along one side.
		var slip_z := 10.0
		for slip_size in [24.0, 16.0, 12.0, 10.0, 8.0]:
			var size: float = slip_size
			pier.box(Vector3(width * 0.5 + size * 0.5, -0.15, -slip_z - 4.0), Vector3(size, 0.3, 2.0), WOOD)
			slip_z += 13.0
		# A 70 ft yacht in the big slip, and the 60 ft barge with its crane.
		var yacht := Vector3(width * 0.5 + 12.0, -0.6, -16.5)
		pier.box(yacht, Vector3(5.5, 2.6, 21.0), PAINT)
		pier.box(yacht + Vector3(0.0, 2.2, 1.0), Vector3(4.6, 2.0, 11.0), PAINT)
		pier.box(yacht + Vector3(0.0, 2.2, -4.6), Vector3(4.7, 1.2, 0.2), GLASS, false)
		pier.box(yacht + Vector3(0.0, 3.5, 2.0), Vector3(4.0, 0.3, 7.0), Color(0.15, 0.17, 0.22), false)
		var barge := Vector3(-width * 0.5 - 4.5, -0.8, -40.0)
		pier.box(barge, Vector3(7.0, 1.6, 18.0), Color(0.45, 0.47, 0.42))
		pier.box(barge + Vector3(0.0, 2.0, 6.0), Vector3(3.0, 2.4, 3.0), Color(0.80, 0.80, 0.78))
		pier.box(barge + Vector3(0.0, 3.0, -5.0), Vector3(0.5, 4.5, 0.5), CRANE)
		pier.box(barge + Vector3(0.0, 5.0, -7.0), Vector3(0.4, 0.4, 4.5), CRANE)
		# The hospitality cabin by the shore end.
		pier.box(Vector3(-width * 0.5 - 6.0, 1.8, 6.0), Vector3(8.0, 3.6, 6.0), LOGS)
		pier.box(Vector3(-width * 0.5 - 6.0, 4.0, 6.0), Vector3(9.0, 0.6, 7.0), GREEN_ROOF)
	pier.finish()


## A moored boat: a hull, and for a pontoon ark a railing round its deck.
func _boat(pier: Builder, at: Vector3, size: Vector3, color: Color, ark: bool) -> void:
	pier.box(at, size, color)
	if ark:
		for side in [-1.0, 1.0]:
			pier.box(at + Vector3(float(side) * (size.x * 0.5 - 0.1), 1.1, 0.0), Vector3(0.1, 1.0, size.z), PAINT, false)


## The Camp Melita lodge, serving as the airstrip's terminal: a log lodge with
## a green gabled roof, a porch facing the strip and a stone chimney.
func _lodge(lodge: Dictionary) -> void:
	var place := frame(_point(lodge["centre"]), float(lodge["ground"]), float(lodge["heading"]))
	var facing := float(lodge.get("facing", 1.0))   # +1: the porch is on the lodge's +X side
	map_points.append([_point(lodge["centre"]), "Camp Melita lodge"])
	var hall := Builder.new(self, "MelitaLodge", place, 0.8)
	hall.box(Vector3(0.0, 0.3, 0.0), Vector3(17.0, 0.6, 29.0), STONE)
	hall.box(Vector3(0.0, 2.7, 0.0), Vector3(16.0, 4.2, 28.0), LOGS)
	for course in range(1, 9):
		var y := 0.6 + course * 0.47
		for side in [-1.0, 1.0]:
			hall.box(Vector3(side * 8.02, y, 0.0), Vector3(0.06, 0.07, 28.0), LOG_SEAM, false)
	# A gable roof, ridge along the length, with gable ends filled in steps.
	for side in [-1.0, 1.0]:
		var slab: Basis = Basis(Vector3.BACK, -float(side) * deg_to_rad(30.0))
		hall.box(Vector3(side * 4.5, 7.4, 0.0), Vector3(10.4, 0.4, 30.0), GREEN_ROOF, true, slab)
	for end in [-1.0, 1.0]:
		for tier in 4:
			var tier_width := 15.0 - tier * 3.6
			hall.box(Vector3(0.0, 5.1 + tier * 1.1, end * 13.8), Vector3(tier_width, 1.1, 0.4), LOGS)
	# The porch on the strip side.
	var porch_x := facing * 9.6
	hall.box(Vector3(porch_x, 0.75, 0.0), Vector3(3.2, 0.3, 24.0), WOOD)
	for post in [-11.0, -5.5, 0.0, 5.5, 11.0]:
		hall.box(Vector3(facing * 10.9, 2.7, float(post)), Vector3(0.3, 3.6, 0.3), LOGS)
	hall.box(Vector3(facing * 9.8, 4.6, 0.0), Vector3(4.0, 0.25, 25.0), GREEN_ROOF, false)
	# Door and windows on the porch side.
	hall.box(Vector3(facing * 8.03, 1.9, 0.0), Vector3(0.06, 2.6, 2.4), LOG_SEAM, false)
	for window in [-10.0, -6.0, 6.0, 10.0]:
		hall.box(Vector3(facing * 8.03, 2.6, float(window)), Vector3(0.06, 1.4, 1.8), GLASS, false)
	# The chimney at the back.
	hall.box(Vector3(-facing * 3.0, 5.5, 12.5), Vector3(2.2, 11.0, 2.2), STONE)
	hall.finish()
	var sign_label := _label(hall.body, "CAMP MELITA", 0.025)
	sign_label.position = Vector3(facing * 11.2, 4.1, 0.0)
	sign_label.rotation = Vector3(0.0, facing * PI * 0.5, 0.0)


# --- Cromwell Island villa ---------------------------------------------------

## The unfinished villa at the centre of Cromwell Island, built from the
## sale listing's description: a 16th-century French château in battered
## travertine with terracotta tile roofs, round towers with conical roofs (a
## helical stair winds up the north one), mahogany windows, and twin
## symmetrical staircases curving up to the main entrance. Built much larger
## than life. It faces east, toward Wild Horse Island, and a tower crane still
## stands behind it. The real one is 45,000 sq ft; this one is several times that.
func _mansion(villa: Dictionary) -> void:
	var place := frame(_point(villa["centre"]), float(villa["ground"]), float(villa["heading"]))
	map_points.append([_point(villa["centre"]), "Cromwell villa"])
	var house := Builder.new(self, "CromwellVilla", place, 0.8)
	var floors := 4
	var storey := 6.5
	var wall_top := 2.0 + floors * storey      # the eaves, above the terrace
	# The terrace it all stands on, with tile decks in front.
	house.box(Vector3(0.0, 1.0, -4.0), Vector3(176.0, 2.0, 120.0), PALE_STONE)
	house.box(Vector3(0.0, 2.02, -52.0), Vector3(120.0, 0.06, 20.0), Color(0.76, 0.66, 0.52), false)
	# The main block and its steep terracotta roof.
	house.box(Vector3(0.0, 2.0 + floors * storey * 0.5, 0.0), Vector3(120.0, floors * storey, 40.0), TRAVERTINE)
	_hip_roof(house, Vector3(0.0, wall_top, 0.0), 124.0, 44.0, 22.0)
	# The centre pavilion, standing forward of the block and above it.
	house.box(Vector3(0.0, 2.0 + 16.5, -24.0), Vector3(34.0, 33.0, 12.0), TRAVERTINE)
	_hip_roof(house, Vector3(0.0, 35.0, -24.0), 36.0, 14.0, 12.0)
	# Corner pavilions, each with a round tower on its outer corner.
	for side in [-1.0, 1.0]:
		var sx: float = side
		house.box(Vector3(sx * 68.0, 2.0 + 15.0, -4.0), Vector3(28.0, 30.0, 52.0), TRAVERTINE)
		_hip_roof(house, Vector3(sx * 68.0, 32.0, -4.0), 30.0, 54.0, 18.0)
		for end in [-1.0, 1.0]:
			var tower := Vector3(sx * 82.0, 2.0, -4.0 + float(end) * 26.0)
			house.cylinder(tower + Vector3(0.0, 19.0, 0.0), 9.0, 38.0, TRAVERTINE)
			house.cone(tower + Vector3(0.0, 38.0, 0.0), 10.5, 20.0, TERRACOTTA)
			for ring in 4:
				house.box(tower + Vector3(0.0, 8.0 + ring * 7.5, -9.05), Vector3(2.0, 3.4, 0.2), GLASS, false)
	# Chimneys and dormers on the main roof.
	for x in [-45.0, -15.0, 15.0, 45.0]:
		house.box(Vector3(float(x), wall_top + 20.0, 6.0), Vector3(3.0, 14.0, 3.0), TRAVERTINE)
	for x in [-50.0, -38.0, -26.0, 26.0, 38.0, 50.0]:
		house.box(Vector3(float(x), wall_top + 4.0, -17.5), Vector3(4.0, 5.0, 4.0), TRAVERTINE)
		house.box(Vector3(float(x), wall_top + 4.0, -19.56), Vector3(2.2, 3.0, 0.12), GLASS, false)
	# Tall windows in mahogany frames on every floor, front and back.
	for floor_index in floors:
		var y := 2.0 + storey * 0.55 + floor_index * storey
		var x := -54.0
		while x <= 54.0:
			if absf(x) > 18.0:
				_window(house, Vector3(x, y, -20.06), false)
			_window(house, Vector3(x, y, 20.06), false)
			x += 6.0
		for x2 in [-12.0, -6.0, 6.0, 12.0]:
			_window(house, Vector3(float(x2), y, -30.06), false)
		for side in [-1.0, 1.0]:
			var sx: float = side
			for x3 in [62.0, 68.0, 74.0]:
				_window(house, Vector3(sx * x3, y, -30.06), false)
	# The main entrance: tall doors, and twin staircases that curve up from
	# either side to a landing at the first floor.
	house.box(Vector3(0.0, 2.0 + 4.5, -30.06), Vector3(6.0, 9.0, 0.12), MAHOGANY, false)
	house.box(Vector3(0.0, 2.0 + storey - 0.3, -33.0), Vector3(14.0, 0.6, 6.0), PALE_STONE)
	for side in [-1.0, 1.0]:
		var sx: float = side
		var climb := Basis(Vector3.BACK, -sx * atan2(storey, 18.0))
		house.box(Vector3(sx * 16.0, 2.0 + storey * 0.5, -38.0), Vector3(19.0, 0.6, 4.0), PALE_STONE, true, climb)
		house.box(Vector3(sx * 16.0, 2.0 + storey * 0.5 + 1.0, -40.0), Vector3(19.0, 1.2, 0.3), MAHOGANY, false, climb)
	# Still under construction: a tower crane behind the house.
	var crane := Vector3(70.0, 2.0, 50.0)
	house.box(crane + Vector3(0.0, 40.0, 0.0), Vector3(3.0, 80.0, 3.0), CRANE)
	house.box(crane + Vector3(-30.0, 81.2, 0.0), Vector3(70.0, 2.4, 2.4), CRANE)
	house.box(crane + Vector3(14.0, 81.2, 0.0), Vector3(20.0, 2.4, 2.4), CRANE)
	house.box(crane + Vector3(18.0, 78.5, 0.0), Vector3(5.0, 3.0, 3.6), STONE)
	house.box(crane + Vector3(0.0, 78.0, 0.0), Vector3(3.6, 3.6, 3.6), GLASS)
	house.finish()


## The guest villa, a short way down the road toward the dock: a smaller
## château of the same stone and tile, two storeys, with two towers.
func _guest_villa(villa: Dictionary) -> void:
	var place := frame(_point(villa["centre"]), float(villa["ground"]), float(villa["heading"]))
	map_points.append([_point(villa["centre"]), "Cromwell guest villa"])
	var house := Builder.new(self, "CromwellGuestVilla", place, 0.8)
	house.box(Vector3(0.0, 0.5, 0.0), Vector3(56.0, 1.0, 40.0), PALE_STONE)
	house.box(Vector3(0.0, 1.0 + 6.5, 0.0), Vector3(44.0, 13.0, 22.0), TRAVERTINE)
	_hip_roof(house, Vector3(0.0, 14.0, 0.0), 46.0, 24.0, 11.0)
	for side in [-1.0, 1.0]:
		var tower := Vector3(float(side) * 23.0, 1.0, -11.0)
		house.cylinder(tower + Vector3(0.0, 9.0, 0.0), 4.5, 18.0, TRAVERTINE)
		house.cone(tower + Vector3(0.0, 18.0, 0.0), 5.5, 10.0, TERRACOTTA)
	for floor_index in 2:
		var y := 1.0 + 3.6 + floor_index * 6.5
		var x := -18.0
		while x <= 18.0:
			_window(house, Vector3(x, y, -11.06), true)
			_window(house, Vector3(x, y, 11.06), true)
			x += 6.0
	house.box(Vector3(0.0, 1.0 + 2.8, -11.06), Vector3(3.0, 5.6, 0.12), MAHOGANY, false)
	house.finish()


## A tall window: glass in a mahogany frame, set in a wall facing -Z (or +Z).
func _window(house: Builder, at: Vector3, small: bool) -> void:
	var height := 3.2 if small else 4.2
	var facing := -1.0 if at.z < 0.0 else 1.0
	house.box(at, Vector3(2.6, height + 0.5, 0.12), MAHOGANY, false)
	house.box(at + Vector3(0.0, 0.0, facing * 0.03), Vector3(2.0, height, 0.12), GLASS, false)


## A steep hipped roof of terracotta tile over a block `width` (X) by `depth`
## (Z), starting at `base`, rising `height`: built as stepped tiers that
## narrow toward the ridge.
func _hip_roof(house: Builder, base: Vector3, width: float, depth: float, height: float) -> void:
	var tiers := 6
	for tier in tiers:
		var share := float(tier) / tiers
		var tier_width := width - (depth * 0.9) * share
		var tier_depth := depth * (1.0 - share * 0.92)
		house.box(base + Vector3(0.0, height * (share + 0.5 / tiers), 0.0),
				Vector3(maxf(tier_width, 1.0), height / tiers, maxf(tier_depth, 1.0)), TERRACOTTA)


## The modern lake house on Shelter Island: two long storeys of stone and
## timber in an L, a tall glass great room where the wings meet, low dark
## roofs with deep eaves, and a deck toward the water.
func _shelter_mansion(house_info: Dictionary) -> void:
	var place := frame(_point(house_info["centre"]), float(house_info["ground"]), float(house_info["heading"]))
	map_points.append([_point(house_info["centre"]), "Shelter mansion"])
	var house := Builder.new(self, "ShelterMansion", place, 0.8)
	var timber := Color(0.52, 0.38, 0.25)
	var dark_roof := Color(0.20, 0.21, 0.23)
	house.box(Vector3(0.0, 0.4, 0.0), Vector3(58.0, 0.8, 44.0), STONE)
	# The long wing, along the strip.
	house.box(Vector3(-6.0, 4.8, 8.0), Vector3(16.0, 8.0, 46.0), PALE_STONE)
	house.box(Vector3(-6.0, 9.2, 8.0), Vector3(20.0, 0.6, 50.0), dark_roof)
	# The cross wing.
	house.box(Vector3(10.0, 4.4, -12.0), Vector3(28.0, 7.2, 14.0), timber)
	house.box(Vector3(10.0, 8.4, -12.0), Vector3(32.0, 0.6, 18.0), dark_roof)
	# The great room: glass most of the way up, under a raised roof.
	house.box(Vector3(-6.0, 6.0, -12.0), Vector3(16.0, 10.4, 16.0), GLASS)
	house.box(Vector3(-6.0, 11.6, -12.0), Vector3(20.0, 0.8, 20.0), dark_roof)
	for corner in [Vector3(-13.8, 6.0, -19.8), Vector3(1.8, 6.0, -19.8), Vector3(-13.8, 6.0, -4.2), Vector3(1.8, 6.0, -4.2)]:
		house.box(corner, Vector3(0.6, 10.4, 0.6), timber)
	# Windows along both storeys of the long wing.
	for storey in 2:
		var y := 2.8 + storey * 3.8
		var z := -12.0
		while z <= 28.0:
			house.box(Vector3(2.06, y, z), Vector3(0.12, 2.4, 3.0), GLASS, false)
			house.box(Vector3(-14.06, y, z), Vector3(0.12, 2.4, 3.0), GLASS, false)
			z += 5.0
	# Stone chimneys, and a deck along the outer side.
	house.box(Vector3(-6.0, 7.5, 30.0), Vector3(3.0, 15.0, 3.0), STONE)
	house.box(Vector3(22.0, 6.5, -12.0), Vector3(3.0, 13.0, 3.0), STONE)
	house.box(Vector3(7.0, 1.0, 8.0), Vector3(10.0, 0.3, 40.0), WOOD)
	house.finish()


## A helipad: a concrete square with an H, on the island's most inland spot.
func _helipad(pad: Dictionary) -> void:
	var centre := _point(pad["centre"])
	map_points.append([centre, "%s helipad" % str(pad.get("name", "")).trim_suffix(" Island")])
	var deck := Builder.new(self, "Helipad", frame(centre, float(pad["ground"]), 0.0), 0.8)
	deck.box(Vector3(0.0, -0.19, 0.0), Vector3(22.0, 0.5, 22.0), Color(0.62, 0.62, 0.60))
	deck.box(Vector3(0.0, 0.065, 0.0), Vector3(20.0, 0.02, 20.0), Color(0.30, 0.30, 0.32), false)
	deck.box(Vector3(-3.0, 0.08, 0.0), Vector3(1.4, 0.02, 9.0), PAINT, false)
	deck.box(Vector3(3.0, 0.08, 0.0), Vector3(1.4, 0.02, 9.0), PAINT, false)
	deck.box(Vector3(0.0, 0.08, 0.0), Vector3(6.0, 0.02, 1.4), PAINT, false)
	for x in [-10.0, 10.0]:
		for z in [-10.0, 10.0]:
			deck.box(Vector3(float(x), 0.2, float(z)), Vector3(0.4, 0.4, 0.4), Color(0.95, 0.85, 0.2), false)
	deck.finish()


# --- Aircraft carrier ----------------------------------------------------------

## The aircraft carrier: shaped like a Nimitz-class ship but three times the
## size, far larger than any real one. Its flight deck is a kilometre long,
## 230 m wide and 54 m above the water. It is moored at a random spot on open
## water each time the game starts.
func _carrier(spots: Array) -> void:
	if spots.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spot := _point(spots[rng.randi_range(0, spots.size() - 1)])
	var heading := rng.randf_range(0.0, 360.0)
	map_points.append([spot, "Carrier"])
	var k := CARRIER_SCALE
	var ship := Builder.new(self, "Carrier", frame(spot, MapInfo.LAKE_Y, heading), 0.8)
	ship.box(Vector3(0.0, 3.5, 0.0) * k, Vector3(40.0, 29.0, 320.0) * k, NAVY_GREY)
	ship.box(Vector3(0.0, 5.0, -168.0) * k, Vector3(28.0, 26.0, 18.0) * k, NAVY_GREY)
	ship.box(Vector3(0.0, 7.0, -181.0) * k, Vector3(14.0, 22.0, 10.0) * k, NAVY_GREY)
	ship.box(Vector3(-6.0, 18.5, -8.0) * k, Vector3(76.0, 1.0, 333.0) * k, DECK)
	# The island, on the starboard side.
	ship.box(Vector3(27.0, 27.0, 30.0) * k, Vector3(10.0, 16.0, 30.0) * k, NAVY_GREY)
	ship.box(Vector3(27.0, 33.0, 22.0) * k, Vector3(10.4, 2.0, 12.0) * k, GLASS, false)
	ship.cylinder(Vector3(27.0, 41.0, 32.0) * k, 0.6 * k, 12.0 * k, NAVY_GREY)
	ship.box(Vector3(27.0, 45.0, 32.0) * k, Vector3(6.0, 1.5, 1.5) * k, NAVY_GREY)
	# Deck markings: the bow line, the angled landing deck and its centre line,
	# and four elevators along the edges.
	var deck_top := 19.0 * k + 0.02
	ship.box(Vector3(4.0 * k, deck_top, -60.0 * k), Vector3(0.8 * k, 0.04, 200.0 * k), PAINT, false)
	var angled := Basis(Vector3.UP, deg_to_rad(9.0))
	ship.box(Vector3(-16.0 * k, deck_top - 0.01, 40.0 * k), Vector3(24.0 * k, 0.04, 230.0 * k), Color(0.26, 0.27, 0.29), false, angled)
	ship.box(Vector3(-16.0 * k, deck_top + 0.01, 40.0 * k), Vector3(0.8 * k, 0.04, 230.0 * k), Color(0.95, 0.85, 0.20), false, angled)
	for spot_z in [-100.0, -40.0, 60.0]:
		ship.box(Vector3(30.0 * k, deck_top, float(spot_z) * k), Vector3(16.0 * k, 0.04, 16.0 * k), Color(0.30, 0.31, 0.33), false)
	ship.box(Vector3(-40.0 * k, deck_top, 90.0 * k), Vector3(14.0 * k, 0.04, 16.0 * k), Color(0.30, 0.31, 0.33), false)
	_painted_number(ship.body, "77", Vector3(-6.0 * k, deck_top + 0.02, -140.0 * k), PI)
	ship.finish()


# --- Small pieces --------------------------------------------------------------

func _windsock(builder: Builder, at: Vector3) -> void:
	builder.cylinder(at + Vector3(0.0, 3.5, 0.0), 0.08, 7.0, PAINT)
	builder.box(at + Vector3(1.2, 6.6, 0.0), Vector3(2.4, 0.6, 0.6), WINDSOCK, false)


func _label(parent: Node3D, text: String, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 256
	label.pixel_size = pixel
	label.outline_size = 24
	label.double_sided = true
	label.shaded = true
	label.modulate = Color(0.1, 0.1, 0.12)
	parent.add_child(label)
	return label


## Collects boxes and cylinders for one place, in its own frame, and turns
## them into one mesh per colour and one solid body.
class Builder:
	const MeshKit = preload("res://scripts/mesh_kit.gd")
	const Layers = preload("res://scripts/units.gd")
	const SHINY := Color(0.11, 0.15, 0.21)   # glass: the one colour drawn glossy

	var body: StaticBody3D
	var _surfaces: Dictionary = {}   # colour -> SurfaceTool

	func _init(owner: Node3D, body_name: String, place: Transform3D, friction: float) -> void:
		body = StaticBody3D.new()
		body.physics_material_override = Units.world_surface()
		body.name = body_name
		body.transform = place
		body.collision_layer = Layers.LAYER_WORLD
		body.collision_mask = 0
		var grip := PhysicsMaterial.new()
		grip.friction = friction
		body.physics_material_override = grip
		owner.add_child(body)

	func _surface(color: Color) -> SurfaceTool:
		if not _surfaces.has(color):
			_surfaces[color] = MeshKit.new_surface()
		return _surfaces[color]

	func box(centre: Vector3, size: Vector3, color: Color, solid: bool = true, turn: Basis = Basis.IDENTITY) -> void:
		MeshKit.add_box_placed(_surface(color), Transform3D(turn, centre), size)
		if solid:
			var shape := BoxShape3D.new()
			shape.size = size
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.transform = Transform3D(turn, centre)
			body.add_child(collider)

	## A cone standing on `base`, as for a tower roof.
	func cone(base: Vector3, radius: float, height: float, color: Color, solid: bool = true) -> void:
		MeshKit.add_frustum(_surface(color), base + Vector3(0.0, height * 0.5, 0.0), 1, radius, 0.0, height, 16)
		if solid:
			var shape := CylinderShape3D.new()
			shape.radius = radius * 0.55
			shape.height = height * 0.8
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = base + Vector3(0.0, height * 0.4, 0.0)
			body.add_child(collider)

	func cylinder(centre: Vector3, radius: float, height: float, color: Color, solid: bool = true) -> void:
		MeshKit.add_cylinder(_surface(color), centre, 1, radius, height, 12)
		if solid:
			var shape := CylinderShape3D.new()
			shape.radius = radius
			shape.height = height
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = centre
			body.add_child(collider)

	func finish() -> void:
		for key in _surfaces:
			var color: Color = key
			var surface: SurfaceTool = _surfaces[key]
			surface.generate_normals()
			var mesh := surface.commit()
			var look := StandardMaterial3D.new()
			look.albedo_color = color
			look.roughness = 0.35 if color == SHINY else 0.9
			mesh.surface_set_material(0, look)
			var drawn := MeshInstance3D.new()
			drawn.mesh = mesh
			body.add_child(drawn)
