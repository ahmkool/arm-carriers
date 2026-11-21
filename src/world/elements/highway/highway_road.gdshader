shader_type spatial;
render_mode specular_schlick_ggx;

// High-speed scrolling 4-lane elevated highway asphalt.
// The convoy stays near the world origin while the road texture scrolls along +Z
// at `scroll_speed` metres per second, selling highway speed with zero floating-point drift.
uniform float scroll_speed = 38.0;
uniform float road_half_width = 19.0;
uniform float lane_width = 9.0;
uniform float dash_period = 11.0;
uniform float dash_length = 4.2;
uniform vec3 asphalt_dark : source_color = vec3(0.095, 0.10, 0.125);
uniform vec3 asphalt_light : source_color = vec3(0.145, 0.15, 0.185);
uniform vec3 line_white : source_color = vec3(0.92, 0.93, 0.96);
uniform vec3 line_yellow : source_color = vec3(0.98, 0.72, 0.16);
uniform vec3 rumble_red : source_color = vec3(0.84, 0.18, 0.16);
uniform float fade_center_z = -18.0;
uniform float fade_start = 88.0;
uniform float fade_end = 132.0;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = v_world_pos.x;
	float z = v_world_pos.z;
	// Convoy drives toward -Z, so the road surface scrolls toward +Z.
	float scroll_z = z - TIME * scroll_speed;

	// Multi-scale asphalt grain + longitudinal road wear streaks.
	float grain_coarse = value_noise(vec2(x * 1.4, scroll_z * 0.45));
	float grain_fine = value_noise(vec2(x * 7.5, scroll_z * 3.5));
	float asphalt_mix = grain_coarse * 0.65 + grain_fine * 0.35;
	vec3 col = mix(asphalt_dark, asphalt_light, asphalt_mix);

	// Darker tire wear tracks inside each of the 4 lanes (centers at -13.5, -4.5, +4.5, +13.5).
	float lane_coord = mod(x + lane_width * 2.0, lane_width) - lane_width * 0.5;
	float tire_l = exp(-pow((lane_coord + 1.55) * 1.35, 2.0));
	float tire_r = exp(-pow((lane_coord - 1.55) * 1.35, 2.0));
	float tire_wear = clamp(tire_l + tire_r, 0.0, 1.0) * step(abs(x), road_half_width - 1.4);
	col *= 1.0 - tire_wear * 0.16;

	// Expansion joints across the elevated overpass every 24m.
	float joint_dist = abs(fract(scroll_z / 24.0) - 0.5) * 24.0;
	float joint = 1.0 - smoothstep(0.04, 0.14, joint_dist);
	col = mix(col, vec3(0.045, 0.048, 0.06), joint * 0.75);

	// Dashed white lane dividers at X = -9.0 and X = +9.0.
	float dash_cycle = mod(scroll_z, dash_period);
	float dash_mask = step(dash_cycle, dash_length);
	float div_outer = 1.0 - smoothstep(0.11, 0.19, abs(abs(x) - lane_width));
	float lane_dash = div_outer * dash_mask;

	// Double yellow / bright center divider at X = 0.0 (dashed center-express feel).
	float center_l = 1.0 - smoothstep(0.08, 0.15, abs(x + 0.24));
	float center_r = 1.0 - smoothstep(0.08, 0.15, abs(x - 0.24));
	float center_dash = max(center_l, center_r) * step(mod(scroll_z + 1.5, dash_period), dash_length * 1.15);

	// Solid white shoulder lines at X = +/- 17.2.
	float shoulder_line = 1.0 - smoothstep(0.13, 0.21, abs(abs(x) - (road_half_width - 1.8)));

	// Red-and-white shoulder rumble strip near the jersey barriers.
	float rumble_band = smoothstep(road_half_width - 1.55, road_half_width - 1.35, abs(x))
		* (1.0 - smoothstep(road_half_width - 0.45, road_half_width - 0.25, abs(x)));
	float rumble_stripe = step(0.5, fract(scroll_z * 0.45));
	vec3 rumble_col = mix(line_white * 0.85, rumble_red, rumble_stripe);

	// Paint markings onto asphalt.
	float paint_wear = 0.86 + 0.14 * grain_fine;
	col = mix(col, line_white, lane_dash * 0.88 * paint_wear);
	col = mix(col, line_yellow, center_dash * 0.92 * paint_wear);
	col = mix(col, line_white, shoulder_line * 0.88 * paint_wear);
	col = mix(col, rumble_col, rumble_band * 0.85);

	// Subtle dusk highway glow reflection down the middle.
	float paint_mask = clamp(lane_dash + center_dash + shoulder_line + rumble_band, 0.0, 1.0);
	float roughness = mix(0.62 - tire_wear * 0.14, 0.42, paint_mask);

	// Smoothly blend far ends of the overpass into dusk fog.
	float dist_z = abs(z - fade_center_z);
	float edge_fade = 1.0 - smoothstep(fade_start, fade_end, dist_z);

	ALBEDO = col;
	ROUGHNESS = clamp(roughness, 0.25, 0.85);
	METALLIC = 0.06;
	// Faint emissive boost on painted lines so they stay crisp under dusk lighting.
	EMISSION = (line_white * (lane_dash + shoulder_line) * 0.12 + line_yellow * center_dash * 0.22) * edge_fade;
	ALPHA = edge_fade;
}
