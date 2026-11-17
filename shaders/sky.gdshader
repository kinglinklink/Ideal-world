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

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
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
	COLOR = color;
}
