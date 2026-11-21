extends RefCounted
## Written by tools/make_textures.py: do not edit by hand.
## For each material, how many metres one copy of its picture covers,
## how strong its bumps are (0: no normal map), the gain that keeps the
## average colour equal to the colour picked, and how much the pattern
## changes the roughness.

const TEXTURES := {
	"foam": {"tile": 0.200, "bump": 0.80, "gain": 1.199, "rough_var": 0.00, "normals": true},
	"balsa": {"tile": 0.600, "bump": 0.25, "gain": 1.111, "rough_var": 0.10, "normals": true},
	"cork": {"tile": 0.250, "bump": 0.60, "gain": 1.460, "rough_var": 0.00, "normals": true},
	"wood": {"tile": 0.700, "bump": 0.35, "gain": 1.257, "rough_var": 0.15, "normals": true},
	"oak": {"tile": 0.700, "bump": 0.45, "gain": 1.342, "rough_var": 0.15, "normals": true},
	"ice": {"tile": 1.000, "bump": 0.30, "gain": 1.265, "rough_var": 0.20, "normals": true},
	"plastic": {"tile": 0.300, "bump": 0.15, "gain": 1.083, "rough_var": 0.00, "normals": true},
	"rubber": {"tile": 0.150, "bump": 0.50, "gain": 1.186, "rough_var": 0.10, "normals": true},
	"nylon": {"tile": 0.150, "bump": 0.10, "gain": 1.069, "rough_var": 0.05, "normals": true},
	"acrylic": {"tile": 1.000, "bump": 0.00, "gain": 1.000, "rough_var": 0.00, "normals": false},
	"kevlar": {"tile": 0.060, "bump": 0.70, "gain": 1.485, "rough_var": 0.15, "normals": true},
	"carbon_fiber": {"tile": 0.050, "bump": 0.50, "gain": 1.899, "rough_var": 0.25, "normals": true},
	"magnesium": {"tile": 0.400, "bump": 0.10, "gain": 1.172, "rough_var": 0.20, "normals": true},
	"fiberglass": {"tile": 0.400, "bump": 0.30, "gain": 1.278, "rough_var": 0.10, "normals": true},
	"brick": {"tile": 0.600, "bump": 1.20, "gain": 1.370, "rough_var": 0.10, "normals": true},
	"concrete": {"tile": 0.800, "bump": 0.70, "gain": 1.280, "rough_var": 0.10, "normals": true},
	"glass": {"tile": 1.000, "bump": 0.00, "gain": 1.000, "rough_var": 0.00, "normals": false},
	"aluminum": {"tile": 0.400, "bump": 0.12, "gain": 1.145, "rough_var": 0.25, "normals": true},
	"granite": {"tile": 0.500, "bump": 0.00, "gain": 1.836, "rough_var": 0.10, "normals": false},
	"diamond": {"tile": 0.300, "bump": 1.50, "gain": 1.241, "rough_var": 0.00, "normals": true},
	"titanium": {"tile": 0.350, "bump": 0.12, "gain": 1.195, "rough_var": 0.20, "normals": true},
	"cast_iron": {"tile": 0.400, "bump": 0.60, "gain": 1.258, "rough_var": 0.25, "normals": true},
	"steel": {"tile": 0.400, "bump": 0.12, "gain": 1.183, "rough_var": 0.25, "normals": true},
	"brass": {"tile": 0.500, "bump": 0.08, "gain": 1.162, "rough_var": 0.20, "normals": true},
	"copper": {"tile": 0.500, "bump": 0.08, "gain": 1.210, "rough_var": 0.20, "normals": true},
	"silver": {"tile": 0.500, "bump": 0.06, "gain": 1.094, "rough_var": 0.15, "normals": true},
	"lead": {"tile": 0.500, "bump": 0.25, "gain": 1.277, "rough_var": 0.20, "normals": true},
	"tungsten": {"tile": 0.200, "bump": 0.20, "gain": 1.144, "rough_var": 0.20, "normals": true},
	"gold": {"tile": 0.500, "bump": 0.05, "gain": 1.111, "rough_var": 0.15, "normals": true},
	"frictionless": {"tile": 1.000, "bump": 0.00, "gain": 1.022, "rough_var": 0.00, "normals": false},
}
