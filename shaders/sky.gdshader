shader_type sky;
// The sky, for daylight.gd: a gradient from horizon to zenith, the sun and
// its glow, and at night the moon and stars.

uniform vec3 top_color = vec3(0.22, 0.47, 0.88);
uniform vec3 horizon_color = vec3(0.68, 0.82, 0.95);
uniform vec3 ground_color = vec3(0.30, 0.42, 0.30);
uniform vec3 glow_color = vec3(1.0, 0.6, 0.3);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);    // toward the sun
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);  // toward the moon
uniform float night = 0.0;                           // 0 by day, 1 at full night
uniform float sun_size = 0.9997;                     // cosine of the sun's radius
uniform float cloud_cover = 0.1;                     // 0 clear to 1 overcast (weather.gd)
uniform vec2 cloud_shift = vec2(0.0);                // the clouds drift with the wind
uniform float overcast = 0.0;                        // how dark and grey the sky is
uniform float flash = 0.0;                           // lightning
uniform vec3 ash = vec3(0.0);                        // direction toward an eruption's ash cloud, and its strength in its length

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

float clouds(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += noise2(p) * amp;
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return sum;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 color = mix(horizon_color, top_color, smoothstep(0.0, 0.55, up));
	if (up < 0.0) {
		color = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -up));
	}
	// The sun's glow, warm near the horizon, and its disc.
	float toward_sun = max(dot(d, sun_direction), 0.0);
	float low_sun = 1.0 - smoothstep(0.0, 0.5, sun_direction.y);
	color += glow_color * (pow(toward_sun, 6.0) * (0.25 + 0.6 * low_sun)) * (1.0 - night);
	if (sun_direction.y > -0.05) {
		color += vec3(1.0, 0.95, 0.85) * smoothstep(sun_size, sun_size + 0.0001, toward_sun) * 6.0;
	}
	// The moon, a pale disc, and the stars.
	if (night > 0.0 && up > -0.02) {
		float toward_moon = dot(d, moon_direction);
		color += vec3(0.85, 0.88, 0.95) * smoothstep(0.99955, 0.99965, toward_moon) * 1.6 * night;
		color += vec3(0.25, 0.28, 0.4) * pow(max(toward_moon, 0.0), 40.0) * 0.15 * night;
		vec3 cell = floor(d * 260.0);
		float h = hash(cell);
		if (h > 0.996) {
			vec3 centre = (cell + 0.5 + (vec3(hash(cell + 3.1), hash(cell + 7.7), hash(cell + 1.3)) - 0.5) * 0.6);
			float spot = length(d * 260.0 - centre);
			color += vec3(0.9, 0.92, 1.0) * smoothstep(0.35, 0.0, spot) * (h - 0.996) * 250.0 * night
					* smoothstep(-0.02, 0.15, up);
		}
	}
	// Weather: a grey sky under cloud, and the clouds themselves.
	vec3 grey = vec3(0.52, 0.55, 0.6) * (1.0 - night * 0.9) * (1.0 - overcast * 0.45);
	color = mix(color, grey, overcast * 0.85);
	if (up > 0.0 && cloud_cover > 0.01) {
		vec2 p = d.xz / max(up, 0.06) * 1.6 + cloud_shift;
		float c = clouds(p);
		float amount = smoothstep(1.0 - cloud_cover - 0.05, 1.0 - cloud_cover + 0.3, c) * smoothstep(0.0, 0.12, up);
		float lit = (1.0 - night * 0.92) * (1.0 - overcast * 0.55);
		vec3 cloud_color = mix(vec3(0.95, 0.96, 0.98), vec3(0.45, 0.47, 0.5), overcast) * lit;
		cloud_color += glow_color * pow(max(dot(d, sun_direction), 0.0), 8.0) * 0.4 * (1.0 - night);
		color = mix(color, cloud_color, amount);
	}
	// Ash from an eruption, dark brown toward the volcano.
	float ash_strength = length(ash);
	if (ash_strength > 0.001) {
		float toward = max(dot(d, ash / ash_strength), 0.0);
		color = mix(color, vec3(0.18, 0.15, 0.13), clamp(ash_strength * (0.3 + 0.7 * pow(toward, 3.0)), 0.0, 0.9));
	}
	color += vec3(0.8, 0.85, 1.0) * flash;
	COLOR = color;
}
