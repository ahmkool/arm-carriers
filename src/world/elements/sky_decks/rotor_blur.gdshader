shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The blur of the spinning blades: faint disc, brighter toward the rim.
uniform vec3 blur_color : source_color = vec3(0.92, 0.88, 0.78);
uniform float strength = 0.34;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float disc = 1.0 - smoothstep(0.94, 1.0, r);
	float bands = 0.92 + 0.08 * sin(r * 26.0);
	ALBEDO = blur_color;
	ALPHA = disc * bands * strength * mix(0.45, 1.0, r);
}
