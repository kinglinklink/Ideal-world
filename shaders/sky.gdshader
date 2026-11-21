shader_type sky;
// The sky, for daylight.gd: a gradient from horizon to zenith, the sun and
// its glow, and at night the moon and stars. The moon is drawn, not
// painted: dark seas (maria) and pale highlands from noise on its sphere,
// a few craters with bright rims and two with long rays, and its phase,
// lit from the side by moon_phase, with faint earthshine on the dark part.

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
uniform float moon_phase = 0.5;                      // 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter
uniform float moon_size = 0.042;                     // radians, the moon's radius in the sky (drawn large)

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

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), u.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), u.x), u.y);
	float b = mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), u.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), u.x), u.y);
	return mix(a, b, u.z);
}

// The moon's face at a point n on its sphere (z toward you): how pale it is.
float moon_albedo(vec3 n) {
	vec3 p = n * 2.3 + vec3(4.1, 1.3, 7.7);
	float seas = noise3(p) * 0.55 + noise3(p * 2.1) * 0.27 + noise3(p * 4.3) * 0.12 + noise3(p * 9.1) * 0.06;
	float pale = mix(0.8, 0.48, smoothstep(0.48, 0.62, seas));  // highlands to maria
	pale *= 0.88 + 0.16 * noise3(n * 18.0) + 0.08 * noise3(n * 47.0);   // grain
	// Craters: a dark floor, a bright rim; the first two throw long rays.
	vec3 centres[7] = vec3[](vec3(-0.15, -0.62, 0.77), vec3(0.42, 0.38, 0.82), vec3(-0.55, 0.2, 0.81),
			vec3(0.62, -0.3, 0.72), vec3(0.05, 0.25, 0.97), vec3(-0.3, 0.68, 0.67), vec3(0.75, 0.15, 0.64));
	float sizes[7] = float[](0.07, 0.06, 0.09, 0.05, 0.04, 0.06, 0.045);
	for (int i = 0; i < 7; i++) {
		vec3 c = normalize(centres[i]);
		float r = length(n - c) / sizes[i];
		pale *= mix(0.85, 1.0, smoothstep(0.55, 0.9, r));
		pale += 0.12 * smoothstep(0.7, 0.95, r) * (1.0 - smoothstep(0.95, 1.3, r));
		if (i < 2) {
			vec3 side = normalize(cross(c, vec3(0.0, 1.0, 0.0)));
			vec3 up = cross(side, c);
			vec3 across = n - c * dot(n, c);
			float angle = atan(dot(across, up), dot(across, side));
			float streaks = pow(abs(sin(angle * 7.0 + float(i) * 1.3)), 30.0) + 0.6 * pow(abs(sin(angle * 13.0 + 0.7)), 50.0);
			streaks *= 0.6 + 0.4 * noise3(n * 30.0);
			pale += 0.09 * streaks * smoothstep(1.0, 1.5, r) * (1.0 - smoothstep(1.5, 8.0, r));
		}
	}
	return clamp(pale, 0.0, 1.2);
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
	// The moon, in its phase, and the stars.
	if (night > 0.0 && up > -0.02) {
		vec3 m = normalize(moon_direction);
		float toward_moon = dot(d, m);
		vec3 side = normalize(cross(m, abs(m.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 above = cross(side, m);
		vec2 q = vec2(dot(d, side), dot(d, above)) / moon_size;
		float r2 = dot(q, q);
		float lit_share = 0.5 - 0.5 * cos(moon_phase * 6.2831853);
		float cover = 0.0;
		if (toward_moon > 0.0 && r2 < 1.0) {
			vec3 n = vec3(q, sqrt(1.0 - r2));
			float angle = moon_phase * 6.2831853;
			vec3 from_sun = vec3(sin(angle), 0.0, -cos(angle));
			float sunlit = dot(n, from_sun);
			float lit = smoothstep(-0.03, 0.06, sunlit) * (0.6 + 0.4 * max(sunlit, 0.0));
			float pale = moon_albedo(n) * (0.82 + 0.18 * n.z);
			vec3 face = vec3(0.95, 0.94, 0.9) * pale * (lit * 1.08 + 0.028);
			cover = smoothstep(1.0, 0.96, r2);
			color = mix(color, face, cover * night);
		}
		color += vec3(0.25, 0.28, 0.4) * pow(max(toward_moon, 0.0), 40.0) * 0.15 * night * (0.2 + 0.8 * lit_share);
		vec3 cell = floor(d * 260.0);
		float h = hash(cell);
		if (h > 0.996) {
			vec3 centre = (cell + 0.5 + (vec3(hash(cell + 3.1), hash(cell + 7.7), hash(cell + 1.3)) - 0.5) * 0.6);
			float spot = length(d * 260.0 - centre);
			color += vec3(0.9, 0.92, 1.0) * smoothstep(0.35, 0.0, spot) * (h - 0.996) * 250.0 * night
					* smoothstep(-0.02, 0.15, up) * (1.0 - cover);
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
