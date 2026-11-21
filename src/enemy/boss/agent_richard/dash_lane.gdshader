shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec3 base_color : source_color = vec3(1.0, 0.14, 0.08);
uniform vec3 hot_color : source_color = vec3(1.0, 0.62, 0.22);
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float locked : hint_range(0.0, 1.0) = 0.0;
uniform float lane_length = 10.0;

void fragment() {
	// PlaneMesh has UV.y = 1 at +Z (feet) and UV.y = 0 at -Z (dash target).
	float forward_t = 1.0 - UV.y;
	float side = abs(UV.x - 0.5) * 2.0;

	// Taper the leading 12% into a crisp forward arrowhead tip.
	float tip_start = 0.88;
	float max_half_w = 1.0;
	if (forward_t > tip_start) {
		max_half_w = clamp(1.0 - (forward_t - tip_start) / (1.0 - tip_start), 0.0, 1.0);
	}
	float inside_mask = 1.0 - smoothstep(max_half_w - 0.04, max_half_w + 0.02, side);

	// Glowing outer border rails + arrowhead outline.
	float border_dist = abs(side - (max_half_w - 0.06));
	float rail = (1.0 - smoothstep(0.02, 0.09, border_dist)) * step(side, max_half_w + 0.03);
	float back_edge = (1.0 - smoothstep(0.0, 0.035, forward_t)) * inside_mask;

	// Animated forward-sweeping chevrons (>>>) scaled cleanly by physical lane length.
	float chev_coord = forward_t * max(lane_length * 0.42, 2.0) - TIME * (3.6 + locked * 3.4) + side * 0.55;
	float chev_band = smoothstep(0.72, 0.86, fract(chev_coord)) * (1.0 - smoothstep(0.92, 0.99, fract(chev_coord)));
	float chevrons = chev_band * inside_mask * smoothstep(0.05, 0.16, forward_t) * (1.0 - smoothstep(0.84, 0.95, forward_t));

	// Charge fill wave sweeping from feet to tip as windup completes.
	float fill_mask = (1.0 - smoothstep(charge - 0.06, charge + 0.03, forward_t)) * inside_mask;
	float sweep_front = exp(-pow((forward_t - charge) * 14.0, 2.0)) * inside_mask;

	// Subtle pulse once the dash direction locks.
	float lock_pulse = 1.0 + locked * (0.28 + 0.22 * sin(TIME * 34.0));

	float base_fill = inside_mask * (0.12 + fill_mask * 0.24);
	float pattern = clamp(rail * 0.85 + back_edge * 0.5 + chevrons * 0.75 + sweep_front * 0.8, 0.0, 1.0);

	vec3 col = mix(base_color, hot_color, clamp(chevrons * 0.55 + sweep_front * 0.85 + locked * 0.32, 0.0, 1.0));
	col *= (1.15 + pattern * 0.95) * lock_pulse;

	float alpha = clamp((base_fill + pattern * 0.55) * mix(0.65, 1.0, charge), 0.0, 0.92);
	if (alpha < 0.01) {
		discard;
	}

	ALBEDO = col;
	ALPHA = alpha;
}
