shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// The lake surface: one flat sheet at the lake's level. It shows only over
// the lake itself, read from the surface kinds in the baked terrain pictures
// (kind 5 is lake), so low ground beyond the lake stays dry.

uniform sampler2D coarse_map : filter_nearest, repeat_disable;
uniform sampler2D detail_map : filter_nearest, repeat_disable;
uniform sampler2D noise_map : repeat_enable, filter_linear_mipmap;
uniform vec2 coarse_origin;
uniform float coarse_spacing;
uniform vec2 coarse_size;
uniform vec2 detail_origin;
uniform float detail_spacing;
uniform vec2 detail_size;
uniform vec2 map_offset;    // map = world + map_offset (see origin.gd)
uniform vec3 shallow : source_color = vec3(0.16, 0.42, 0.58);
uniform vec3 deep : source_color = vec3(0.05, 0.20, 0.36);

varying vec3 world_position;

float kind_at(sampler2D map, ivec2 p) {
	return mod(floor(texelFetch(map, p, 0).b * 255.0 + 0.5), 8.0);
}

// True if any of the four samples around a point is lake, so the water
// reaches a little under the shore rather than stopping short of it.
bool is_lake(vec2 xz) {
	vec2 g = (xz - detail_origin) / detail_spacing;
	if (g.x >= 0.0 && g.y >= 0.0 && g.x <= detail_size.x - 1.001 && g.y <= detail_size.y - 1.001) {
		ivec2 p = ivec2(floor(g));
		return kind_at(detail_map, p) == 5.0 || kind_at(detail_map, p + ivec2(1, 0)) == 5.0
				|| kind_at(detail_map, p + ivec2(0, 1)) == 5.0 || kind_at(detail_map, p + ivec2(1, 1)) == 5.0;
	}
	g = (xz - coarse_origin) / coarse_spacing;
	if (g.x < 0.0 || g.y < 0.0 || g.x > coarse_size.x - 1.001 || g.y > coarse_size.y - 1.001) {
		return false;
	}
	ivec2 p = ivec2(floor(g));
	return kind_at(coarse_map, p) == 5.0 || kind_at(coarse_map, p + ivec2(1, 0)) == 5.0
			|| kind_at(coarse_map, p + ivec2(0, 1)) == 5.0 || kind_at(coarse_map, p + ivec2(1, 1)) == 5.0;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_position.xz + map_offset;
	if (!is_lake(xz)) {
		discard;
	}
	// Two layers of ripples drifting different ways.
	float a = texture(noise_map, xz / 23.0 + vec2(TIME * 0.011, TIME * 0.007)).r;
	float b = texture(noise_map, xz / 9.0 - vec2(TIME * 0.016, -TIME * 0.009)).r;
	float c = texture(noise_map, (xz + vec2(0.37, 0.0)) / 23.0 + vec2(TIME * 0.011, TIME * 0.007)).r;
	float d = texture(noise_map, (xz + vec2(0.0, 0.37)) / 9.0 - vec2(TIME * 0.016, -TIME * 0.009)).r;
	vec3 ripple = normalize(vec3((a - c) * 2.5, 1.0, (b - d) * 2.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(ripple, 0.0)).xyz);
	float facing = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
	ALBEDO = mix(deep, shallow, facing * 0.6 + a * 0.2);
	ALPHA = mix(0.95, 0.72, facing);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
