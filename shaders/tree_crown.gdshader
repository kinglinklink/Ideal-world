shader_type spatial;
render_mode cull_back;

// Pine crowns (forest.gd). Each tree's green comes from its instance colour.
// In autumn some trees (the larches) turn gold; above the snow line the
// tops of the boughs are white.

uniform float autumn = 0.0;        // 0 to 1
uniform float snow_line_y = 2000.0; // game metres
uniform float cold = 0.0;          // 0 midsummer to 1 midwinter

varying vec3 tint;
varying float height;

void vertex() {
	tint = COLOR.rgb;
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 c = tint;
	float larch = step(0.72, fract(tint.r * 91.7 + tint.g * 37.3));
	c = mix(c, vec3(0.78, 0.58, 0.14), autumn * larch);
	c = mix(c, c * vec3(1.05, 0.9, 0.7), smoothstep(0.6, 0.9, cold) * larch);
	vec3 up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float snowy = smoothstep(snow_line_y - 150.0, snow_line_y, height) * smoothstep(0.1, 0.6, up.y);
	c = mix(c, vec3(0.9, 0.93, 0.96), snowy);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
