shader_type spatial;
// The second pass of a see-through part: its reflections of the sky and the
// sun, faint face on and strong at a glancing angle (Fresnel), with any
// facets or ripples from the material's bumps.
render_mode blend_premul_alpha, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/part.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.05;
uniform float body = 0.04;         // how much light the glass itself scatters

varying vec3 at;
varying vec3 facing;
varying vec3 stretch;

void vertex() {
	stretch = part_stretch(MODEL_MATRIX);
	at = VERTEX * stretch;
	facing = normalize(NORMAL / stretch);
}

void fragment() {
	// Glass lets the light through: it casts no shadow.
	if (IN_SHADOW_PASS) {
		discard;
	}
	vec3 n = normalize(facing);
	if (bump > 0.0) {
		NORMAL = part_normal(at, n, part_weights(n), part_turns(stretch), MODEL_MATRIX, VIEW_MATRIX);
	}
	float glance = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(glance, 5.0);
	ALBEDO = albedo.rgb * body;
	ALPHA = clamp(body + fresnel, 0.0, 1.0);
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	SPECULAR = 0.5;
}
