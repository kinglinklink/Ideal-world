extends RefCounted
## Building materials, lightest first. Densities are real. Friction and strength are starting
## values to tune in play. Health of a block = its mass x strength.

const MaterialTextures = preload("res://scripts/material_textures.gd")
const PART_SHADER = preload("res://shaders/part.gdshader")
const TINT_SHADER = preload("res://shaders/part_tint.gdshader")
const SHINE_SHADER = preload("res://shaders/part_shine.gdshader")

const DEFAULT_ID := "plastic"
## See-through materials: drawn as a tint over what is behind, plus reflections.
const CLEAR := ["glass", "acrylic", "diamond"]

## density in kg/m^3, friction as a coefficient, strength in HP per kg.
const MATERIALS := {
	"foam": {"name": "Foam", "density": 50.0, "friction": 0.5, "strength": 4.0,
		"color": Color(0.93, 0.90, 0.78), "metallic": 0.0, "roughness": 0.95},
	"balsa": {"name": "Balsa", "density": 150.0, "friction": 0.4, "strength": 8.0,
		"color": Color(0.87, 0.76, 0.58), "metallic": 0.0, "roughness": 0.9},
	"cork": {"name": "Cork", "density": 240.0, "friction": 0.7, "strength": 5.0,
		"color": Color(0.70, 0.55, 0.38), "metallic": 0.0, "roughness": 0.95},
	"wood": {"name": "Wood", "density": 600.0, "friction": 0.4, "strength": 10.0,
		"color": Color(0.62, 0.44, 0.27), "metallic": 0.0, "roughness": 0.85},
	"oak": {"name": "Oak", "density": 750.0, "friction": 0.45, "strength": 11.0,
		"color": Color(0.50, 0.34, 0.20), "metallic": 0.0, "roughness": 0.8},
	"ice": {"name": "Ice", "density": 917.0, "friction": 0.05, "strength": 1.0,
		"color": Color(0.72, 0.88, 0.96), "metallic": 0.0, "roughness": 0.1},
	"plastic": {"name": "Plastic", "density": 1050.0, "friction": 0.35, "strength": 6.0,
		"color": Color(0.80, 0.82, 0.86), "metallic": 0.0, "roughness": 0.6},
	"rubber": {"name": "Rubber", "density": 1100.0, "friction": 1.1, "strength": 8.0,
		"color": Color(0.14, 0.14, 0.15), "metallic": 0.0, "roughness": 0.95},
	"nylon": {"name": "Nylon", "density": 1150.0, "friction": 0.25, "strength": 9.0,
		"color": Color(0.90, 0.89, 0.84), "metallic": 0.0, "roughness": 0.5},
	"acrylic": {"name": "Acrylic", "density": 1180.0, "friction": 0.4, "strength": 5.0,
		"color": Color(0.75, 0.90, 0.95), "metallic": 0.0, "roughness": 0.08},
	"kevlar": {"name": "Kevlar", "density": 1440.0, "friction": 0.35, "strength": 45.0,
		"color": Color(0.85, 0.72, 0.25), "metallic": 0.0, "roughness": 0.7},
	"carbon_fiber": {"name": "Carbon fiber", "density": 1600.0, "friction": 0.3, "strength": 40.0,
		"color": Color(0.22, 0.23, 0.26), "metallic": 0.2, "roughness": 0.45},
	"magnesium": {"name": "Magnesium", "density": 1740.0, "friction": 0.45, "strength": 14.0,
		"color": Color(0.74, 0.75, 0.77), "metallic": 0.75, "roughness": 0.45},
	"fiberglass": {"name": "Fiberglass", "density": 1900.0, "friction": 0.35, "strength": 20.0,
		"color": Color(0.82, 0.86, 0.78), "metallic": 0.0, "roughness": 0.55},
	"brick": {"name": "Brick", "density": 1900.0, "friction": 0.7, "strength": 2.0,
		"color": Color(0.66, 0.30, 0.22), "metallic": 0.0, "roughness": 1.0},
	"concrete": {"name": "Concrete", "density": 2400.0, "friction": 0.8, "strength": 2.0,
		"color": Color(0.62, 0.62, 0.60), "metallic": 0.0, "roughness": 1.0},
	"glass": {"name": "Glass", "density": 2500.0, "friction": 0.4, "strength": 1.0,
		"color": Color(0.70, 0.86, 0.90), "metallic": 0.0, "roughness": 0.05},
	"aluminum": {"name": "Aluminum", "density": 2700.0, "friction": 0.6, "strength": 15.0,
		"color": Color(0.80, 0.82, 0.84), "metallic": 0.8, "roughness": 0.35},
	"granite": {"name": "Granite", "density": 2700.0, "friction": 0.65, "strength": 3.0,
		"color": Color(0.50, 0.48, 0.50), "metallic": 0.0, "roughness": 0.85},
	"diamond": {"name": "Diamond", "density": 3510.0, "friction": 0.1, "strength": 30.0,
		"color": Color(0.80, 0.95, 1.00), "metallic": 0.1, "roughness": 0.02},
	"titanium": {"name": "Titanium", "density": 4500.0, "friction": 0.5, "strength": 25.0,
		"color": Color(0.60, 0.61, 0.64), "metallic": 0.8, "roughness": 0.4},
	"cast_iron": {"name": "Cast iron", "density": 7200.0, "friction": 0.5, "strength": 5.0,
		"color": Color(0.26, 0.27, 0.29), "metallic": 0.6, "roughness": 0.75},
	"steel": {"name": "Steel", "density": 7850.0, "friction": 0.6, "strength": 10.0,
		"color": Color(0.48, 0.50, 0.54), "metallic": 0.85, "roughness": 0.4},
	"brass": {"name": "Brass", "density": 8500.0, "friction": 0.4, "strength": 7.0,
		"color": Color(0.80, 0.65, 0.30), "metallic": 0.9, "roughness": 0.3},
	"copper": {"name": "Copper", "density": 8960.0, "friction": 0.5, "strength": 6.0,
		"color": Color(0.80, 0.47, 0.30), "metallic": 0.9, "roughness": 0.3},
	"silver": {"name": "Silver", "density": 10490.0, "friction": 0.45, "strength": 3.0,
		"color": Color(0.88, 0.88, 0.90), "metallic": 0.95, "roughness": 0.2},
	"lead": {"name": "Lead", "density": 11340.0, "friction": 0.5, "strength": 1.0,
		"color": Color(0.36, 0.37, 0.42), "metallic": 0.7, "roughness": 0.6},
	"tungsten": {"name": "Tungsten", "density": 19250.0, "friction": 0.4, "strength": 8.0,
		"color": Color(0.40, 0.41, 0.43), "metallic": 0.85, "roughness": 0.45},
	"gold": {"name": "Gold", "density": 19300.0, "friction": 0.45, "strength": 1.0,
		"color": Color(0.95, 0.77, 0.25), "metallic": 1.0, "roughness": 0.2},
	# Not a real material: an ideal surface for experiments. Nothing grips it,
	# nothing moves it and nothing damages it. Once spawned, anything made of
	# it, and anything welded to it, is fixed in place.
	"frictionless": {"name": "Frictionless surface", "density": 1000.0, "friction": 0.0, "strength": 0.0,
		"color": Color(0.90, 0.96, 1.00), "metallic": 0.3, "roughness": 0.0, "immovable": true},
}

static var _surface_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func ids() -> Array:
	return MATERIALS.keys()


static func info(material_id: String) -> Dictionary:
	if MATERIALS.has(material_id):
		return MATERIALS[material_id]
	return MATERIALS[DEFAULT_ID]


static func display_name(material_id: String) -> String:
	return str(info(material_id)["name"])


## True for a material that cannot be moved or damaged once spawned.
static func is_immovable(material_id: String) -> bool:
	return bool(info(material_id).get("immovable", false))


## The health of a part of this material and mass, as text for the interface.
static func health_text(material_id: String, mass: float) -> String:
	if is_immovable(material_id):
		return "infinite"
	return "%d HP" % int(round(mass * float(info(material_id)["strength"])))


static func density(material_id: String) -> float:
	return float(info(material_id)["density"])


## The id of the material with the given display name, or the default material.
static func id_for_name(shown_name: String) -> String:
	for material_id in MATERIALS:
		if MATERIALS[material_id]["name"] == shown_name:
			return material_id
	return DEFAULT_ID


static func default_color(material_id: String) -> Color:
	return info(material_id)["color"]


## The text shown when hovering a material in the paint window.
static func tooltip(material_id: String) -> String:
	var data: Dictionary = info(material_id)
	if is_immovable(material_id):
		return "%s\nFriction: none, against anything\nCannot be moved or damaged once spawned" % data["name"]
	return "%s\nDensity: %d kg/m³\nFriction: %.2f\nStrength: %d HP per kg" % [
		data["name"], int(data["density"]), float(data["friction"]), int(data["strength"]),
	]


## A render material for one building material in one color. Cached, so every
## block that shares a look also shares a material. The colour picked is
## multiplied by the material's own pattern (tools/make_textures.py), laid on
## in metres so big blocks don't stretch it. A metal given a colour of its
## own is painted: duller, and the brushing shows only faintly. Glass,
## acrylic and diamond are see-through, tinted by their colour.
static func surface(material_id: String, color: Color) -> Material:
	var key := "%s#%s" % [material_id, color.to_html(true)]
	if not _surface_cache.has(key):
		_surface_cache[key] = _clear_surface(material_id, color) if is_clear(material_id) else _solid_surface(material_id, color)
	return _surface_cache[key]


static func is_clear(material_id: String) -> bool:
	return CLEAR.has(material_id)


## Whether a metal has been given a colour of its own (painted).
static func is_painted(material_id: String, color: Color) -> bool:
	var data: Dictionary = info(material_id)
	if float(data["metallic"]) < 0.5:
		return false
	var base: Color = data["color"]
	return absf(base.r - color.r) + absf(base.g - color.g) + absf(base.b - color.b) > 0.3


static func _pattern(material_id: String) -> Dictionary:
	return MaterialTextures.TEXTURES.get(material_id, {"tile": 1.0, "bump": 0.0, "gain": 1.0, "rough_var": 0.0, "normals": false})


static func _lay_pattern(look: ShaderMaterial, material_id: String) -> void:
	var pattern := _pattern(material_id)
	var picture := texture(material_id)
	if picture != null:
		look.set_shader_parameter("detail", picture)
	look.set_shader_parameter("tile", float(pattern["tile"]))
	var bumps: Texture2D = texture(material_id + "_n") if bool(pattern["normals"]) else null
	look.set_shader_parameter("bump", float(pattern["bump"]) if bumps != null else 0.0)
	if bumps != null:
		look.set_shader_parameter("bumps", bumps)


static func _solid_surface(material_id: String, color: Color) -> ShaderMaterial:
	var data: Dictionary = info(material_id)
	var pattern := _pattern(material_id)
	var look := ShaderMaterial.new()
	look.shader = PART_SHADER
	_lay_pattern(look, material_id)
	look.set_shader_parameter("albedo", color)
	look.set_shader_parameter("gain", float(pattern["gain"]))
	look.set_shader_parameter("rough_var", float(pattern["rough_var"]))
	if is_painted(material_id, color):
		look.set_shader_parameter("metallic", 0.2)
		look.set_shader_parameter("roughness", 0.45)
		look.set_shader_parameter("pattern", 0.25)
	else:
		look.set_shader_parameter("metallic", float(data["metallic"]))
		look.set_shader_parameter("roughness", float(data["roughness"]))
		look.set_shader_parameter("pattern", 1.0)
	return look


## Two passes: the tint over what is behind, then the reflections.
static func _clear_surface(material_id: String, color: Color) -> ShaderMaterial:
	var data: Dictionary = info(material_id)
	var tint := ShaderMaterial.new()
	tint.shader = TINT_SHADER
	tint.set_shader_parameter("albedo", color)
	var shine := ShaderMaterial.new()
	shine.shader = SHINE_SHADER
	_lay_pattern(shine, material_id)
	shine.set_shader_parameter("albedo", color)
	shine.set_shader_parameter("roughness", float(data["roughness"]))
	tint.next_pass = shine
	return tint


## One of the material pictures, by name ("oak", "oak_n"), or null if it
## isn't there. Imported by the editor when it is open; read straight from
## the file otherwise (in tests).
static func texture(picture: String) -> Texture2D:
	if _texture_cache.has(picture):
		return _texture_cache[picture]
	var path := "res://textures/materials/%s.png" % picture
	var found: Texture2D = null
	if ResourceLoader.exists(path):
		found = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			image.generate_mipmaps()
			found = ImageTexture.create_from_image(image)
	_texture_cache[picture] = found
	return found
