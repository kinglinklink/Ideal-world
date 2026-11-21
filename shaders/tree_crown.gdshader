shader_type spatial;
render_mode cull_back;

// Every tree (forest.gd). A tree's mesh carries its own colours: bark where
// UV.x is 1, foliage where it is 0, and its kind in UV.y (kind / 16). Each
// tree's instance colour shades it a little lighter or darker.
//
// Evergreen conifers stay green, a little darker in deep winter, with snow
// on their boughs above the snow line. Western larch turns gold in autumn
// and drops its needles in winter. The broadleaf trees and shrubs turn their
// own autumn colours (cottonwood and birch yellow, aspen gold, maple red,
// hawthorn deep red, serviceberry orange-red) and stand bare in winter.

uniform float autumn = 0.0;        // 0 to 1
uniform float snow_line_y = 2000.0; // game metres
uniform float cold = 0.0;          // 0 midsummer to 1 midwinter

// Per kind, in forest.gd's order: 0 evergreen, 1 larch, 2 broadleaf.
const int KIND[15] = int[](0, 0, 0, 1, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2);
const vec3 AUTUMN[15] = vec3[](
	vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.82, 0.6, 0.12), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0),
	vec3(0.85, 0.7, 0.2), vec3(0.95, 0.72, 0.1), vec3(0.9, 0.78, 0.25),
	vec3(0.85, 0.25, 0.08), vec3(0.6, 0.1, 0.06), vec3(0.88, 0.38, 0.12));

varying vec3 tint;
varying float height;
varying vec3 spot;
varying vec2 part;

void vertex() {
	tint = COLOR.rgb;
	part = UV;
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	spot = VERTEX * 2.3 + MODEL_MATRIX[3].xyz * 0.37;
}

void fragment() {
	vec3 c = tint;
	if (part.x < 0.5) {
		int kind_index = clamp(int(part.y * 16.0), 0, 14);
		int kind = KIND[kind_index];
		vec3 up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		float speck = fract(sin(dot(floor(spot * 3.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		if (kind == 0) {
			c *= mix(1.0, 0.85, smoothstep(0.5, 1.0, cold));
		} else {
			// Turning in autumn, a little unevenly from tree to tree...
			float turn = smoothstep(0.15, 0.65, autumn + (speck - 0.5) * 0.2);
			c = mix(c, AUTUMN[kind_index] * (0.8 + 0.4 * speck), turn);
			// ...and bare in winter, but for a few clinging leaves and the twigs.
			float bare = smoothstep(0.4, 0.75, cold);
			if (speck < bare * 0.88) {
				discard;
			}
			c = mix(c, vec3(0.4, 0.35, 0.3), bare);
		}
		float snowy = smoothstep(snow_line_y - 150.0, snow_line_y, height) * smoothstep(0.1, 0.6, up.y);
		c = mix(c, vec3(0.9, 0.93, 0.96), snowy * (kind == 0 ? 1.0 : 0.6));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
