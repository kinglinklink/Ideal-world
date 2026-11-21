// Shared by the part shaders: the material's picture laid on each face from
// the side it faces (triplanar), in metres along the part's own axes. The
// mesh is a unit shape stretched to the part's size, so the stretch is put
// back here and a long beam shows the same grain as a small block.

uniform sampler2D detail : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bumps : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.5;          // metres one copy of the picture covers
uniform float bump = 0.0;          // 0: no normal map

// Each shader keeps, as varyings: where on the part, in metres along its
// own axes (at = VERTEX * stretch), and the surface's normal along those
// axes (facing = NORMAL / stretch).
vec3 part_stretch(mat4 model) {
	return max(vec3(length(model[0].xyz), length(model[1].xyz), length(model[2].xyz)), vec3(1e-4));
}

vec3 part_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

// Which faces turn their picture a quarter, so that its v (the grain, the
// brushing) runs along the part's longest side wherever that side lies in
// the face: a long beam has its grain along it on every face.
bvec3 part_turns(vec3 stretch) {
	bool z_long = stretch.z > stretch.y && stretch.z >= stretch.x;
	bool x_long = stretch.x > stretch.y && stretch.x > stretch.z;
	return bvec3(z_long, x_long, x_long);
}

vec2 part_uv_x(vec3 at, bvec3 turns) { return turns.x ? at.yz : at.zy; }
vec2 part_uv_y(vec3 at, bvec3 turns) { return turns.y ? at.zx : at.xz; }
vec2 part_uv_z(vec3 at, bvec3 turns) { return turns.z ? at.yx : at.xy; }

float part_detail(vec3 at, vec3 w, bvec3 turns) {
	return texture(detail, part_uv_x(at, turns) / tile).r * w.x
			+ texture(detail, part_uv_y(at, turns) / tile).r * w.y
			+ texture(detail, part_uv_z(at, turns) / tile).r * w.z;
}

// The bumped normal, in view space.
vec3 part_normal(vec3 at, vec3 n, vec3 w, bvec3 turns, mat4 model, mat4 view) {
	vec2 bx = texture(bumps, part_uv_x(at, turns) / tile).rg * 2.0 - 1.0;
	vec2 by = texture(bumps, part_uv_y(at, turns) / tile).rg * 2.0 - 1.0;
	vec2 bz = texture(bumps, part_uv_z(at, turns) / tile).rg * 2.0 - 1.0;
	// Each projection's tilt along its picture's (u, v), back on the part's axes.
	vec3 tx = turns.x ? vec3(0.0, bx.x, bx.y) : vec3(0.0, bx.y, bx.x);
	vec3 ty = turns.y ? vec3(by.y, 0.0, by.x) : vec3(by.x, 0.0, by.y);
	vec3 tz = turns.z ? vec3(bz.y, bz.x, 0.0) : vec3(bz.x, bz.y, 0.0);
	vec3 bent = normalize(n + (tx * w.x + ty * w.y + tz * w.z) * bump);
	mat3 turn = mat3(normalize(model[0].xyz), normalize(model[1].xyz), normalize(model[2].xyz));
	return normalize((view * vec4(turn * bent, 0.0)).xyz);
}
