shader_type spatial;
render_mode unshaded;

// Draws the build pad: thin lines every grid cell (1 dm), bold lines every metre.

uniform vec3 base_color : source_color = vec3(0.13, 0.15, 0.19);
uniform vec3 line_color : source_color = vec3(0.62, 0.70, 0.82);
uniform float cell_size = 0.1;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Fine lines, one per cell. They fade out once too dense to draw cleanly.
	vec2 fine_coord = world_position.xz / cell_size;
	vec2 fine_width = max(fwidth(fine_coord), vec2(0.00001));
	vec2 fine_dist = abs(fract(fine_coord - 0.5) - 0.5) / fine_width;
	float fine = 1.0 - min(min(fine_dist.x, fine_dist.y), 1.0);
	fine *= clamp(1.0 - max(fine_width.x, fine_width.y), 0.0, 1.0);

	// Bold lines, one per metre.
	vec2 coarse_coord = world_position.xz / (cell_size * 10.0);
	vec2 coarse_width = max(fwidth(coarse_coord), vec2(0.00001));
	vec2 coarse_dist = abs(fract(coarse_coord - 0.5) - 0.5) / coarse_width;
	float coarse = 1.0 - min(min(coarse_dist.x, coarse_dist.y), 1.0);
	coarse *= clamp(1.0 - max(coarse_width.x, coarse_width.y), 0.0, 1.0);

	float amount = max(fine * 0.35, coarse * 0.9);
	ALBEDO = mix(base_color, line_color, amount);
}
