shader_type spatial;
// The first pass of a see-through part (glass, acrylic, diamond): it
// multiplies whatever is behind by the part's colour, so tinted glass
// darkens and colours the view through it. part_shine.gdshader draws the
// reflections on top.
render_mode blend_mul, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float clarity = 1.0;       // 1 the colour as picked; less is murkier

void fragment() {
	ALBEDO = albedo.rgb * clarity;
}
