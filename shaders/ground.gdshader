shader_type spatial;

// Grass for the open ground. One noise picture is read at three sizes:
// fine mottling a couple of metres across, patches tens of metres across,
// and broad dry areas hundreds of metres across. Mixing the three keeps the
// ground from looking flat up close or tiled from the air.

uniform sampler2D noise_map : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 grass_dark : source_color = vec3(0.22, 0.44, 0.17);
uniform vec3 grass_mid : source_color = vec3(0.33, 0.58, 0.25);
uniform vec3 grass_light : source_color = vec3(0.46, 0.68, 0.30);
uniform vec3 grass_dry : source_color = vec3(0.60, 0.62, 0.32);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 ground = world_position.xz;
	float fine = texture(noise_map, ground / 2.7).r;
	float medium = texture(noise_map, ground / 31.0 + vec2(0.37, 0.11)).r;
	float broad = texture(noise_map, ground / 410.0 + vec2(0.71, 0.53)).r;

	float shade = medium * 0.65 + fine * 0.35;
	vec3 color = mix(grass_dark, grass_mid, smoothstep(0.25, 0.5, shade));
	color = mix(color, grass_light, smoothstep(0.5, 0.8, shade));
	color = mix(color, grass_dry, smoothstep(0.55, 0.9, broad) * 0.5);

	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
