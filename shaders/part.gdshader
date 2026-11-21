shader_type spatial;
// A building part's surface: the colour picked, times the material's
// pattern (wood grain, weave, brushed metal...), with its bumps, roughness
// and shine. See part.gdshaderinc for how the pattern is laid on.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/part.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform float metallic = 0.0;
uniform float roughness = 0.5;
uniform float gain = 1.0;          // puts the pattern's average back to 1
uniform float pattern = 1.0;       // 0 plain colour (paint), 1 full pattern
uniform float rough_var = 0.0;     // darker parts of the pattern are rougher by this much

varying vec3 at;
varying vec3 facing;
varying vec3 stretch;

void vertex() {
	stretch = part_stretch(MODEL_MATRIX);
	at = VERTEX * stretch;
	facing = normalize(NORMAL / stretch);
}

void fragment() {
	vec3 n = normalize(facing);
	vec3 w = part_weights(n);
	bvec3 turns = part_turns(stretch);
	float shade = part_detail(at, w, turns) * gain;
	ALBEDO = albedo.rgb * mix(1.0, shade, pattern);
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + (1.0 - shade) * rough_var * pattern, 0.02, 1.0);
	if (bump > 0.0) {
		NORMAL = part_normal(at, n, w, turns, MODEL_MATRIX, VIEW_MATRIX);
	}
}
