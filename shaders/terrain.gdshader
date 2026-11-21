shader_type spatial;
render_mode world_vertex_coords, cull_back;

// The ground of the whole map, drawn from the baked height pictures.
// terrain.gd keeps several square grids of vertices centred on the camera,
// each twice as coarse as the one inside it. Every vertex reads its height
// here, and each grid leaves a hole where the finer grid inside it is drawn.
//
// Each picture holds a 16-bit height in red (high byte) and green (low byte),
// and in blue the surface kind (low 3 bits) and how wooded the spot is (high
// 5 bits). The detailed picture covers the islands near the start; the coarse
// one covers everything.

uniform sampler2D coarse_map : filter_nearest, repeat_disable;
uniform sampler2D detail_map : filter_nearest, repeat_disable;
uniform sampler2D noise_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec2 coarse_origin;
uniform float coarse_spacing;
uniform vec2 coarse_size;
uniform vec2 coarse_code;   // scale, offset: height = value / scale - offset
uniform vec2 detail_origin;
uniform float detail_spacing;
uniform vec2 detail_size;
uniform vec2 detail_code;
uniform float lake_y;
uniform float base_elevation;
uniform vec4 inner_box;     // the finer grid's square: centre x, centre z, half size, and 1 if there is one
uniform float vertex_step;  // this grid's vertex spacing, in metres
uniform vec2 map_offset;    // map = world + map_offset (see origin.gd)

uniform vec3 grass_dark : source_color = vec3(0.22, 0.44, 0.17);
uniform vec3 grass_mid : source_color = vec3(0.33, 0.58, 0.25);
uniform vec3 grass_light : source_color = vec3(0.46, 0.68, 0.30);
uniform vec3 grass_dry : source_color = vec3(0.64, 0.62, 0.34);
uniform vec3 forest_floor : source_color = vec3(0.13, 0.27, 0.13);
uniform vec3 rock : source_color = vec3(0.47, 0.44, 0.40);
uniform vec3 sand : source_color = vec3(0.70, 0.64, 0.50);
uniform vec3 lake_bed : source_color = vec3(0.42, 0.40, 0.33);
uniform vec3 asphalt : source_color = vec3(0.20, 0.20, 0.22);
uniform vec3 gravel : source_color = vec3(0.60, 0.55, 0.45);
uniform vec3 site : source_color = vec3(0.56, 0.54, 0.49);
uniform vec3 snow : source_color = vec3(0.93, 0.95, 0.98);

// The seasons and the weather (weather.gd), the volcano (disasters.gd) and
// the cave mouths (caves.gd).
uniform float snow_line = 2300.0;     // metres above sea level
uniform float autumn = 0.0;           // 0 to 1
uniform float spring_green = 0.0;     // 0 to 1
uniform float cold = 0.0;             // 0 midsummer to 1 midwinter
uniform float wet = 0.0;              // rain darkens the ground
uniform vec4 volcano = vec4(0.0);     // crater centre x, z (map), crater radius, heat 0 to 1
uniform vec4 holes[8];                // cave mouths: a line from xy to zw (map)
uniform float hole_radius[8];
uniform int hole_count = 0;

varying vec3 world_position;
varying vec3 world_normal;

float decode(vec4 texel, vec2 code) {
	float value = floor(texel.r * 255.0 + 0.5) * 256.0 + floor(texel.g * 255.0 + 0.5);
	return value / code.x - code.y;
}

float grid_height(sampler2D map, vec2 g, vec2 code) {
	vec2 corner = floor(g);
	vec2 f = g - corner;
	ivec2 p = ivec2(corner);
	float h00 = decode(texelFetch(map, p, 0), code);
	float h10 = decode(texelFetch(map, p + ivec2(1, 0), 0), code);
	float h01 = decode(texelFetch(map, p + ivec2(0, 1), 0), code);
	float h11 = decode(texelFetch(map, p + ivec2(1, 1), 0), code);
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

bool in_detail(vec2 g) {
	return g.x >= 0.0 && g.y >= 0.0 && g.x <= detail_size.x - 1.001 && g.y <= detail_size.y - 1.001;
}

float terrain_height(vec2 xz) {
	vec2 g = (xz - detail_origin) / detail_spacing;
	if (in_detail(g)) {
		return grid_height(detail_map, g, detail_code);
	}
	g = clamp((xz - coarse_origin) / coarse_spacing, vec2(0.0), coarse_size - 1.001);
	return grid_height(coarse_map, g, coarse_code);
}

// Adds one sample's blue byte (surface kind and woods) to the running
// shares, weighted: made.x asphalt, .y gravel, .z levelled site, .w beyond
// the wall; and how wooded.
void add_surface(float byte_value, float weight, inout vec4 made, inout float wooded) {
	float kind = mod(byte_value, 8.0);
	wooded += weight * floor(byte_value / 8.0) / 31.0;
	if (kind > 0.5 && kind < 1.5) {
		made.x += weight;
	} else if (kind > 1.5 && kind < 2.5) {
		made.y += weight;
	} else if (kind > 2.5 && kind < 3.5) {
		made.z += weight;
	} else if (kind > 3.5 && kind < 4.5) {
		made.w += weight;
	}
}

float blue_byte(sampler2D map, ivec2 p) {
	return floor(texelFetch(map, p, 0).b * 255.0 + 0.5);
}

// The surface kinds and woods round a spot, blended from the four nearest
// samples, so the edges of runways and clearings run smoothly instead of in
// steps the size of the samples.
void surface_shares(vec2 xz, out vec4 made, out float wooded) {
	made = vec4(0.0);
	wooded = 0.0;
	vec2 g = (xz - detail_origin) / detail_spacing;
	bool detail = in_detail(g);
	if (!detail) {
		g = clamp((xz - coarse_origin) / coarse_spacing, vec2(0.0), coarse_size - 1.001);
	}
	vec2 corner = floor(g);
	vec2 f = g - corner;
	ivec2 p = ivec2(corner);
	float b00 = detail ? blue_byte(detail_map, p) : blue_byte(coarse_map, p);
	float b10 = detail ? blue_byte(detail_map, p + ivec2(1, 0)) : blue_byte(coarse_map, p + ivec2(1, 0));
	float b01 = detail ? blue_byte(detail_map, p + ivec2(0, 1)) : blue_byte(coarse_map, p + ivec2(0, 1));
	float b11 = detail ? blue_byte(detail_map, p + ivec2(1, 1)) : blue_byte(coarse_map, p + ivec2(1, 1));
	add_surface(b00, (1.0 - f.x) * (1.0 - f.y), made, wooded);
	add_surface(b10, f.x * (1.0 - f.y), made, wooded);
	add_surface(b01, (1.0 - f.x) * f.y, made, wooded);
	add_surface(b11, f.x * f.y, made, wooded);
	// Sharpen the blend back into a clean edge along the smooth line.
	made = smoothstep(vec4(0.35), vec4(0.65), made);
}

void vertex() {
	vec2 xz = VERTEX.xz + map_offset;
	float e = vertex_step;
	VERTEX.y = terrain_height(xz);
	float slope_x = terrain_height(xz + vec2(e, 0.0)) - terrain_height(xz - vec2(e, 0.0));
	float slope_z = terrain_height(xz + vec2(0.0, e)) - terrain_height(xz - vec2(0.0, e));
	world_normal = normalize(vec3(-slope_x, 2.0 * e, -slope_z));
	NORMAL = world_normal;
	world_position = VERTEX;
}

void fragment() {
	vec2 xz = world_position.xz + map_offset;
	if (inner_box.w > 0.5 && abs(xz.x - inner_box.x) < inner_box.z && abs(xz.y - inner_box.y) < inner_box.z) {
		discard;
	}
	for (int i = 0; i < hole_count; i++) {
		vec2 a = holes[i].xy;
		vec2 along = holes[i].zw - a;
		float t = clamp(dot(xz - a, along) / max(dot(along, along), 0.0001), 0.0, 1.0);
		if (length(xz - a - along * t) < hole_radius[i]) {
			discard;
		}
	}
	vec4 made;
	float wooded;
	surface_shares(xz, made, wooded);
	vec3 n = normalize(world_normal);
	float steep = 1.0 - n.y;
	float above_lake = world_position.y - lake_y;

	// Grass, mixed from one noise picture at three sizes.
	float fine = texture(noise_map, xz / 2.7).r;
	float medium = texture(noise_map, xz / 31.0 + vec2(0.37, 0.11)).r;
	float broad = texture(noise_map, xz / 410.0 + vec2(0.71, 0.53)).r;
	float shade = medium * 0.65 + fine * 0.35;
	vec3 color = mix(grass_dark, grass_mid, smoothstep(0.25, 0.5, shade));
	color = mix(color, grass_light, smoothstep(0.5, 0.8, shade));
	color = mix(color, grass_dry, smoothstep(0.5, 0.85, broad) * 0.55);
	// Fresh green in spring, gold in autumn, dull and dry in winter.
	color = mix(color, grass_light * 1.08, spring_green * 0.35);
	// Wildflowers dotted through the open grass in spring.
	float bloom = spring_green * (1.0 - smoothstep(0.05, 0.4, wooded));
	float dots = texture(noise_map, xz / 0.9 + vec2(0.13, 0.77)).r;
	float pick = texture(noise_map, xz / 23.0 + vec2(0.5, 0.2)).r;
	vec3 flower = pick < 0.42 ? vec3(0.98, 0.85, 0.15) : (pick < 0.55 ? vec3(0.45, 0.55, 0.95)
			: (pick < 0.68 ? vec3(0.72, 0.42, 0.88) : vec3(0.97, 0.97, 0.94)));
	color = mix(color, flower, smoothstep(0.7, 0.78, dots) * bloom * 0.8);
	color = mix(color, vec3(0.66, 0.54, 0.26) * (0.85 + 0.3 * fine), autumn * 0.7);
	color = mix(color, vec3(0.52, 0.49, 0.36) * (0.85 + 0.3 * fine), smoothstep(0.55, 0.85, cold) * 0.6);

	// Under the trees, steep rock, beaches, the lake bed and high snow.
	color = mix(color, forest_floor * (0.85 + 0.3 * fine), smoothstep(0.05, 0.6, wooded));
	color = mix(color, rock * (0.8 + 0.4 * fine), smoothstep(0.35, 0.6, steep));
	color = mix(color, sand * (0.9 + 0.2 * fine), 1.0 - smoothstep(0.6, 1.6, above_lake));
	if (above_lake < 0.0) {
		color = mix(sand, lake_bed, smoothstep(0.0, 6.0, -above_lake)) * (0.85 + 0.3 * fine);
	}
	float real_height = world_position.y + base_elevation;
	float snowy = smoothstep(snow_line - 150.0, snow_line, real_height + medium * 120.0) * (1.0 - smoothstep(0.55, 0.8, steep));
	if (above_lake < 0.3) {
		snowy = 0.0;
	}

	// The volcano: dark rock round the summit, and the crater glowing.
	vec3 glow = vec3(0.0);
	if (volcano.z > 0.0) {
		float from_crater = length(xz - volcano.xy);
		float rocky = 1.0 - smoothstep(volcano.z * 1.3, volcano.z * 7.0, from_crater);
		color = mix(color, vec3(0.17, 0.15, 0.14) * (0.8 + 0.4 * fine), rocky);
		snowy *= 1.0 - rocky * (0.4 + 0.6 * volcano.w);
		float inside = 1.0 - smoothstep(volcano.z * 0.55, volcano.z * 0.8, from_crater);
		vec3 lava = mix(vec3(1.0, 0.25, 0.03), vec3(1.0, 0.75, 0.2), fine * medium);
		color = mix(color, lava * 0.4, inside * volcano.w);
		glow = lava * inside * volcano.w * 3.0;
	}
	color = mix(color, snow, snowy);
	color *= 1.0 - 0.22 * wet * (1.0 - snowy);

	// Made ground.
	color *= 1.0 - 0.1 * made.w;   // beyond the wall
	color = mix(color, asphalt * (0.9 + 0.2 * fine), made.x);
	color = mix(color, gravel * (0.85 + 0.3 * fine), made.y);
	color = mix(color, site * (0.85 + 0.3 * fine), made.z);

	ALBEDO = color;
	EMISSION = glow;
	ROUGHNESS = 1.0 - 0.4 * wet;
	SPECULAR = 0.1;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
