shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// Crystallized memory bridge span: semi-transparent aquamarine & pale rose-gold water-glass with
// luminous edge curbs and scrolling arcane chevrons guiding the carriers across the cloud chasm.
uniform vec3 glass_color : source_color = vec3(0.11, 0.28, 0.36);
uniform vec3 rune_color : source_color = vec3(0.62, 0.94, 0.98);
uniform vec3 warm_accent : source_color = vec3(0.98, 0.82, 0.86);
uniform float glow_intensity = 1.45;
instance uniform float flicker = 0.0;

void fragment() {
	vec2 uv = UV;
	float side_dist = min(uv.x, 1.0 - uv.x);
	float end_dist = min(uv.y, 1.0 - uv.y);

	float side_rail = 1.0 - smoothstep(0.0, 0.065, side_dist);
	float inner_line = 1.0 - smoothstep(0.0, 0.018, abs(side_dist - 0.11));
	float end_seam = 1.0 - smoothstep(0.0, 0.03, end_dist);

	// Scrolling FFX-inspired rune chevrons & central memory ring.
	float scroll = fract(uv.y * 2.0 + abs(uv.x - 0.5) * 0.9 + TIME * 0.42);
	float chevron = 1.0 - smoothstep(0.0, 0.065, abs(scroll - 0.5));
	float center_ring = 1.0 - smoothstep(0.0, 0.025, abs(length(uv - vec2(0.5)) - 0.28));

	float pattern = clamp(side_rail * 0.95 + inner_line * 0.65 + chevron * 0.42 + center_ring * 0.5 + end_seam * 0.35, 0.0, 1.0);
	vec3 rune_tint = mix(rune_color, warm_accent, smoothstep(0.2, 0.8, abs(uv.x - 0.5) * 2.0));

	float shimmer = 1.0 - flicker * (0.45 + 0.55 * step(0.5, fract(TIME * 21.0 + uv.y * 3.0)));
	vec3 col = mix(glass_color, rune_tint * glow_intensity, pattern);
	float alpha = (0.56 + pattern * 0.36) * shimmer;

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
