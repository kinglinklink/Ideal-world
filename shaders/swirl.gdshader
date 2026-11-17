shader_type spatial;
render_mode cull_disabled, depth_draw_never, unshaded;

// A tornado's funnel or its skirt of dust: a lathed shape whose noise
// pattern spins round it and streams upward. Transparent, darker in the
// middle of the band, fading at the top and bottom.

uniform sampler2D noise_map : repeat_enable, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.35, 0.34, 0.33);
uniform float opacity = 0.6;
uniform float spin = 0.25;     // turns of the pattern per second
uniform float rise = 0.2;
uniform float strength = 1.0;  // 0 to 1: how fully formed it is

void fragment() {
	vec2 uv = vec2(UV.x * 3.0 + TIME * spin, UV.y * 2.0 - TIME * rise);
	float n = texture(noise_map, uv).r;
	float m = texture(noise_map, uv * 2.3 + vec2(0.4, 0.1)).r;
	float band = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	float alpha = opacity * band * strength * smoothstep(0.25, 0.75, n * 0.7 + m * 0.5);
	ALBEDO = tint * (0.7 + 0.5 * m);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
