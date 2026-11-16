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

## Places for the mini map: [Vector2 x and z, label].
var map_points: Array = []


func setup(world: Dictionary) -> void:
	for item in world.get("runways", []):
		var runway: Dictionary = item
		if str(runway.get("surface", "")) == "asphalt":
			_wild_horse_airport(runway)
		else:
			_bush_strip(runway)
	for item in world.get("docks", []):
		_dock(item)
	for item in world.get("buildings", []):
		var building: Dictionary = item
		match str(building.get("kind", "")):
			"melita_lodge":
				_lodge(building)
			"cromwell_mansion":
				_mansion(building)
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

func _wild_horse_airport(runway: Dictionary) -> void:
	var centre := _point(runway["centre"])
	var heading := float(runway["heading"])
	var length := float(runway["length"])
	var width := float(runway["width"])
	var mid := float(runway["height_mid"])
	var slope := float(runway.get("slope", 0.0))
	map_points.append([centre, "Wild Horse airport"])

	# The runway follows the bake's straight grade.
	var place := frame(centre, mid, heading)
	place.basis = place.basis * Basis(Vector3.RIGHT, atan(slope))
	var strip := Builder.new(self, "WildHorseRunway", place, 0.9)
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
		for bar in 6:
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
	var yard := Builder.new(self, "WildHorseApron", apron_place, 0.9)
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
	var sign_label := _label(yard.body, "WILD HORSE ISLAND", 0.03)
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


func _dock(dock: Dictionary) -> void:
	var start := _point(dock["start"])
	var deck := float(dock["deck"])
	var length := float(dock["length"])
	var width := float(dock["width"])
	var pier := Builder.new(self, "MelitaDock", frame(start, deck, float(dock["heading"])), 0.6)
	# The deck runs from a few metres up the bank out over the water.
	pier.box(Vector3(0.0, -0.15, -(length * 0.5 - 4.0)), Vector3(width, 0.3, length + 8.0), WOOD)
	var z := 0.0
	while z <= length:
		for side in [-1.0, 1.0]:
			pier.cylinder(Vector3(side * (width * 0.5 - 0.2), -5.0, -z), 0.15, 10.0, LOG_SEAM)
		z += 6.0
	pier.finish()


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

## The unfinished four-storey stone villa at the centre of Cromwell Island,
## facing east across the lake toward Wild Horse Island. A tower crane still
## stands behind it.
func _mansion(villa: Dictionary) -> void:
	var place := frame(_point(villa["centre"]), float(villa["ground"]), float(villa["heading"]))
	map_points.append([_point(villa["centre"]), "Cromwell villa"])
	var house := Builder.new(self, "CromwellVilla", place, 0.8)
	var base := 1.2
	house.box(Vector3(0.0, base * 0.5, -2.0), Vector3(70.0, base, 42.0), PALE_STONE)
	# Main block, centre pavilion and two end pavilions, all flush at the back.
	house.box(Vector3(0.0, base + 9.0, 0.0), Vector3(56.0, 18.0, 24.0), SANDSTONE)
	house.box(Vector3(0.0, base + 10.5, -3.0), Vector3(18.0, 21.0, 30.0), SANDSTONE)
	for side in [-1.0, 1.0]:
		house.box(Vector3(side * 23.0, base + 9.75, -2.0), Vector3(10.0, 19.5, 28.0), SANDSTONE)
	# Slate mansard roofs.
	house.box(Vector3(0.0, base + 20.5, 0.0), Vector3(54.0, 5.0, 22.0), SLATE)
	house.box(Vector3(0.0, base + 24.5, -3.0), Vector3(16.0, 7.0, 28.0), SLATE)
	for side in [-1.0, 1.0]:
		house.box(Vector3(side * 23.0, base + 22.0, -2.0), Vector3(9.0, 5.0, 26.0), SLATE)
	# Windows on every floor.
	for floor_index in 4:
		var y := base + 2.4 + floor_index * 4.4
		for x in [-16.5, -13.0, -10.5, 10.5, 13.0, 16.5]:
			house.box(Vector3(float(x), y, -12.06), Vector3(1.6, 2.6, 0.12), GLASS, false)
		for x in [-6.0, -2.0, 2.0, 6.0]:
			if floor_index == 0 and absf(float(x)) < 3.0:
				continue
			house.box(Vector3(float(x), y, -18.06), Vector3(1.6, 2.6, 0.12), GLASS, false)
		for side in [-1.0, 1.0]:
			for x in [20.5, 23.0, 25.5]:
				house.box(Vector3(side * float(x), y, -16.06), Vector3(1.6, 2.6, 0.12), GLASS, false)
		var bx := -26.0
		while bx <= 26.0:
			house.box(Vector3(bx, y, 12.06), Vector3(1.6, 2.6, 0.12), GLASS, false)
			bx += 4.0
		for side in [-1.0, 1.0]:
			var bz := -12.0
			while bz <= 10.0:
				house.box(Vector3(side * 28.06, y, bz), Vector3(0.12, 2.6, 1.6), GLASS, false)
				bz += 4.0
	# The entrance: a columned portico and steps.
	var column := -6.0
	while column <= 6.0:
		house.cylinder(Vector3(column, base + 4.75, -19.6), 0.55, 9.5, PALE_STONE)
		column += 2.4
	house.box(Vector3(0.0, base + 10.0, -19.8), Vector3(16.0, 1.0, 4.2), PALE_STONE)
	house.box(Vector3(0.0, 2.2, -18.1), Vector3(3.0, 4.4, 0.12), GLASS, false)
	house.box(Vector3(0.0, 0.6, -24.0), Vector3(14.0, 1.2, 4.0), PALE_STONE)
	# Still under construction: a tower crane behind the house.
	var crane := Vector3(34.0, 0.0, 12.0)
	house.box(crane + Vector3(0.0, 24.0, 0.0), Vector3(2.0, 48.0, 2.0), CRANE)
	house.box(crane + Vector3(-17.0, 48.8, 0.0), Vector3(40.0, 1.6, 1.6), CRANE)
	house.box(crane + Vector3(8.0, 48.8, 0.0), Vector3(12.0, 1.6, 1.6), CRANE)
	house.box(crane + Vector3(11.0, 47.0, 0.0), Vector3(3.0, 2.0, 2.4), STONE)
	house.box(crane + Vector3(0.0, 46.5, 0.0), Vector3(2.4, 2.4, 2.4), GLASS)
	house.finish()


# --- Shelter Island mansion and helipads ---------------------------------------

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

## A carrier the size of a Nimitz-class ship, moored at a random spot on open
## water: 333 m flight deck, 18 m above the water.
func _carrier(spots: Array) -> void:
	if spots.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var spot := _point(spots[rng.randi_range(0, spots.size() - 1)])
	var heading := rng.randf_range(0.0, 360.0)
	map_points.append([spot, "Carrier"])
	var ship := Builder.new(self, "Carrier", frame(spot, MapInfo.LAKE_Y, heading), 0.8)
	ship.box(Vector3(0.0, 3.5, 0.0), Vector3(40.0, 29.0, 320.0), NAVY_GREY)
	ship.box(Vector3(0.0, 5.0, -168.0), Vector3(28.0, 26.0, 18.0), NAVY_GREY)
	ship.box(Vector3(0.0, 7.0, -181.0), Vector3(14.0, 22.0, 10.0), NAVY_GREY)
	ship.box(Vector3(-6.0, 18.5, -8.0), Vector3(76.0, 1.0, 333.0), DECK)
	# The island, on the starboard side.
	ship.box(Vector3(27.0, 27.0, 30.0), Vector3(10.0, 16.0, 30.0), NAVY_GREY)
	ship.box(Vector3(27.0, 33.0, 22.0), Vector3(10.4, 2.0, 12.0), GLASS, false)
	ship.cylinder(Vector3(27.0, 41.0, 32.0), 0.6, 12.0, NAVY_GREY)
	ship.box(Vector3(27.0, 45.0, 32.0), Vector3(6.0, 1.5, 1.5), NAVY_GREY)
	# Deck markings: the bow line and the angled landing deck.
	ship.box(Vector3(4.0, 19.02, -60.0), Vector3(0.8, 0.02, 200.0), PAINT, false)
	ship.box(Vector3(-16.0, 19.02, 40.0), Vector3(0.8, 0.02, 230.0), Color(0.95, 0.85, 0.20), false,
			Basis(Vector3.UP, deg_to_rad(9.0)))
	ship.box(Vector3(-16.0, 19.02, 40.0), Vector3(24.0, 0.02, 230.0), Color(0.26, 0.27, 0.29), false,
			Basis(Vector3.UP, deg_to_rad(9.0)))
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
