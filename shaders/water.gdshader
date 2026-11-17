shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

// The lake surface. Two sheets share this shader: a fine grid that follows
// the camera and carries the waves (near_grid on), and one huge flat sheet
// for the rest of the lake, which leaves a hole where the fine grid is.
// The water shows only over the lake itself, read from the surface kinds in
// the baked terrain pictures (kind 5 is lake), so low ground beyond the lake
// stays dry, except where a tsunami has pushed the water up over the land.
//
// The waves are four swells travelling with the wind; weather.gd works out
// the same heights for the buoyancy, so boats ride what is drawn.

uniform sampler2D coarse_map : filter_nearest, repeat_disable;
uniform sampler2D detail_map : filter_nearest, repeat_disable;
uniform sampler2D noise_map : repeat_enable, filter_linear_mipmap;
uniform vec2 coarse_origin;
uniform float coarse_spacing;
uniform vec2 coarse_size;
uniform vec2 coarse_code;
uniform vec2 detail_origin;
uniform float detail_spacing;
uniform vec2 detail_size;
uniform vec2 detail_code;
uniform float lake_y;
uniform vec2 map_offset;    // map = world + map_offset (see origin.gd)
uniform vec3 shallow : source_color = vec3(0.16, 0.42, 0.58);
uniform vec3 deep : source_color = vec3(0.05, 0.20, 0.36);
uniform bool near_grid = false;
uniform vec4 near_box = vec4(0.0);   // the fine grid's square: centre x, centre z (map), half size, and 1 if there is one
uniform float wave_height = 0.1;     // metres, crest to trough
uniform float wind_angle = 0.0;      // the way the waves travel, radians from +X toward +Z
uniform vec4 wave_phase = vec4(0.0);
uniform vec4 tsunami = vec4(0.0);    // centre x, centre z (map), radius of the front, height
uniform float tsunami_width = 150.0;
uniform float storm = 0.0;           // 0 to 1: greyer, rougher water

const vec4 WAVE_LENGTH = vec4(41.0, 27.0, 63.0, 19.0);
const vec4 WAVE_TURN = vec4(0.0, 0.45, -0.35, 0.8);
const vec4 WAVE_SHARE = vec4(0.45, 0.25, 0.2, 0.1);
const vec4 WAVE_SHIFT = vec4(0.0, 1.7, 4.1, 2.6);

varying vec3 world_position;
varying vec2 slope;

float kind_at(sampler2D map, ivec2 p) {
	return mod(floor(texelFetch(map, p, 0).b * 255.0 + 0.5), 8.0);
}

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

float decode(vec4 texel, vec2 code) {
	float value = floor(texel.r * 255.0 + 0.5) * 256.0 + floor(texel.g * 255.0 + 0.5);
	return value / code.x - code.y;
}

float ground_height(vec2 xz) {
	vec2 g = (xz - detail_origin) / detail_spacing;
	if (g.x >= 0.0 && g.y >= 0.0 && g.x <= detail_size.x - 1.001 && g.y <= detail_size.y - 1.001) {
		return decode(texelFetch(detail_map, ivec2(floor(g + 0.5)), 0), detail_code);
	}
	g = clamp((xz - coarse_origin) / coarse_spacing, vec2(0.0), coarse_size - 1.001);
	return decode(texelFetch(coarse_map, ivec2(floor(g + 0.5)), 0), coarse_code);
}

float tsunami_height(vec2 xz, out vec2 tilt) {
	tilt = vec2(0.0);
	if (tsunami.w <= 0.0) {
		return 0.0;
	}
	vec2 away = xz - tsunami.xy;
	float r = max(length(away), 0.001);
	float u = (r - tsunami.z) / tsunami_width;
	float v = (r - tsunami.z + 2.2 * tsunami_width) / tsunami_width;
	float e1 = exp(-u * u);
	float e2 = exp(-v * v);
	float along = tsunami.w * (-2.0 * u * e1 + 0.35 * 2.0 * v * e2) / tsunami_width;
	tilt = along * away / r;
	return tsunami.w * (e1 - 0.35 * e2);
}

float wave_height_at(vec2 xz, out vec2 tilt) {
	float h = 0.0;
	tilt = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		float angle = wind_angle + WAVE_TURN[i];
		vec2 along = vec2(cos(angle), sin(angle));
		float k = 6.2831853 / WAVE_LENGTH[i];
		float amp = wave_height * 0.5 * WAVE_SHARE[i];
		float arg = k * dot(along, xz) - wave_phase[i] + WAVE_SHIFT[i];
		h += amp * sin(arg);
		tilt += amp * k * cos(arg) * along;
	}
	return h;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope = vec2(0.0);
	if (near_grid) {
		vec2 xz = world_position.xz + map_offset;
		// The swells fade out toward the edge of the fine grid, to meet the flat sheet.
		vec2 from_middle = abs(xz - near_box.xy);
		float fade = 1.0 - smoothstep(near_box.z * 0.75, near_box.z * 0.97, max(from_middle.x, from_middle.y));
		vec2 tilt;
		float h = wave_height_at(xz, tilt) * fade;
		vec2 tsunami_tilt;
		h += tsunami_height(xz, tsunami_tilt);
		slope = tilt * fade + tsunami_tilt;
		world_position.y += h;
		VERTEX.y += h;   // the fine grid is neither turned nor scaled
	}
}

void fragment() {
	vec2 xz = world_position.xz + map_offset;
	if (!near_grid && near_box.w > 0.5 && abs(xz.x - near_box.x) < near_box.z * 0.98 && abs(xz.y - near_box.y) < near_box.z * 0.98) {
		discard;
	}
	if (!is_lake(xz)) {
		// Dry land shows water only under a tsunami that has come ashore.
		vec2 unused;
		float rise = tsunami_height(xz, unused);
		if (rise < 0.3 || ground_height(xz) > lake_y + rise) {
			discard;
		}
	}
	// Two layers of ripples drifting different ways, rougher in a storm.
	float a = texture(noise_map, xz / 23.0 + vec2(TIME * 0.011, TIME * 0.007)).r;
	float b = texture(noise_map, xz / 9.0 - vec2(TIME * 0.016, -TIME * 0.009)).r;
	float c = texture(noise_map, (xz + vec2(0.37, 0.0)) / 23.0 + vec2(TIME * 0.011, TIME * 0.007)).r;
	float d = texture(noise_map, (xz + vec2(0.0, 0.37)) / 9.0 - vec2(TIME * 0.016, -TIME * 0.009)).r;
	float rough = 2.5 + storm * 4.0;
	vec3 ripple = normalize(vec3((a - c) * rough - slope.x, 1.0, (b - d) * rough - slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(ripple, 0.0)).xyz);
	float facing = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
	vec3 water = mix(deep, shallow, facing * 0.6 + a * 0.2);
	water = mix(water, vec3(0.22, 0.26, 0.28), storm * 0.5);
	// Foam on steep crests.
	float foam = smoothstep(0.35, 0.6, length(slope)) * (0.6 + 0.4 * b);
	ALBEDO = mix(water, vec3(0.92, 0.95, 0.97), foam);
	ALPHA = mix(mix(0.95, 0.72, facing), 1.0, foam);
	ROUGHNESS = 0.06 + storm * 0.2 + foam * 0.5;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
