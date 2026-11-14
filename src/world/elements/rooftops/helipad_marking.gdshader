shader_type spatial;
render_mode blend_mix, depth_draw_never, shadows_disabled;

// Weathered rooftop helipad circle and "H" paint marking on Building 2's concrete deck.
uniform vec3 paint_color : source_color = vec3(0.76, 0.80, 0.86);
uniform vec3 accent_color : source_color = vec3(0.90, 0.66, 0.14);

varying vec2 v_uv;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_uv = UV * 2.0 - 1.0;
}

void fragment() {
	float r = length(v_uv);
	float outer_ring = (1.0 - smoothstep(0.032, 0.046, abs(r - 0.86)));
	float dashed_ring = (1.0 - smoothstep(0.016, 0.026, abs(r - 0.72))) * step(0.35, fract(atan(v_uv.y, v_uv.x) / 6.2831853 * 16.0));

	// Central "H" glyph.
	float left_leg = step(abs(v_uv.x + 0.24), 0.065) * step(abs(v_uv.y), 0.38);
	float right_leg = step(abs(v_uv.x - 0.24), 0.065) * step(abs(v_uv.y), 0.38);
	float cross_bar = step(abs(v_uv.x), 0.24) * step(abs(v_uv.y), 0.06);
	float h_shape = clamp(left_leg + right_leg + cross_bar, 0.0, 1.0);

	float scuff = 0.62 + 0.38 * hash21(floor(v_uv * 42.0));
	float mask = clamp(outer_ring + dashed_ring + h_shape, 0.0, 1.0);

	ALBEDO = mix(paint_color, accent_color, dashed_ring);
	ROUGHNESS = 0.72;
	METALLIC = 0.05;
	ALPHA = mask * scuff * 0.58;
}
