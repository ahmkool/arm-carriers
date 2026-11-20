shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// Materializing ethereal blue-crystal arcane bridge span for Azure Veil.
uniform vec3 glass_color : source_color = vec3(0.08, 0.24, 0.44);
uniform vec3 rune_color : source_color = vec3(0.42, 0.92, 1.0);
uniform vec3 silver_accent : source_color = vec3(0.84, 0.96, 1.0);
uniform float glow_intensity = 1.55;
instance uniform float flicker = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 c = abs(uv - 0.5);
	float side_dist = min(uv.x, 1.0 - uv.x);
	float end_dist = min(uv.y, 1.0 - uv.y);

	float side_rail = 1.0 - smoothstep(0.0, 0.065, side_dist);
	float inner_square = 1.0 - smoothstep(0.0, 0.024, abs(max(c.x, c.y) - 0.30));
	float end_seam = 1.0 - smoothstep(0.0, 0.03, end_dist);

	float scroll = fract(uv.y * 2.0 + abs(uv.x - 0.5) * 0.8 + TIME * 0.45);
	float chevron = 1.0 - smoothstep(0.0, 0.06, abs(scroll - 0.5));

	float pattern = clamp(side_rail * 0.95 + inner_square * 0.65 + chevron * 0.45 + end_seam * 0.35, 0.0, 1.0);
	vec3 tint = mix(rune_color, silver_accent, smoothstep(0.25, 0.85, max(c.x, c.y) * 2.0));

	float shimmer = 1.0 - flicker * (0.45 + 0.55 * step(0.5, fract(TIME * 21.0 + uv.y * 3.0)));
	vec3 col = mix(glass_color, tint * glow_intensity, pattern);
	float alpha = (0.58 + pattern * 0.35) * shimmer;

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
