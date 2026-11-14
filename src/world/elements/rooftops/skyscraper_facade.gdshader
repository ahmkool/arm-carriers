shader_type spatial;

// Modern high-rise curtain-wall facade: concrete spandrel bands, vertical dark mullions,
// sky-reflecting dark glass, lit night office windows with interior blind bands, and deep abyss fade.
uniform vec3 wall_color : source_color = vec3(0.22, 0.26, 0.35);
uniform vec3 mullion_color : source_color = vec3(0.09, 0.11, 0.16);
uniform vec3 glass_dark : source_color = vec3(0.07, 0.11, 0.19);
uniform vec3 warm_window : source_color = vec3(1.0, 0.76, 0.42);
uniform vec3 cool_window : source_color = vec3(0.56, 0.84, 1.0);
uniform vec3 abyss_fade_color : source_color = vec3(0.015, 0.024, 0.052);
uniform float roof_y = -1.0;
uniform float story_height = 3.1;
uniform float bay_width = 2.0;
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.36;
uniform float emission_strength = 2.1;
uniform float fade_start_depth = 18.0;
uniform float fade_end_depth = 52.0;
uniform float seed_offset = 0.0;

varying vec3 v_pos;
varying vec3 v_normal;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float depth = max(roof_y - v_pos.y, 0.0);
	float fade = 1.0 - smoothstep(fade_start_depth, fade_end_depth, depth);

	// Coordinate along whichever horizontal axis this wall faces.
	float horiz = mix(v_pos.x, v_pos.z, step(0.5, abs(v_normal.x)));
	float face_id = floor((v_normal.x * 2.0 + v_normal.z * 3.0) * 2.0) + seed_offset;

	// Top 2.1 m under the roof coping is a mechanical penthouse louver / cornice band.
	float cornice_mask = 1.0 - smoothstep(1.85, 2.05, depth);
	float louver = smoothstep(0.35, 0.65, abs(fract(depth * 5.5) - 0.5));

	float floor_idx = floor((depth - 2.1) / story_height);
	float fy = fract((depth - 2.1) / story_height);
	float bay_idx = floor(horiz / bay_width);
	float fx = fract(horiz / bay_width);

	// Structural spandrel slab top/bottom of each story & vertical mullions.
	float in_pane_y = step(0.16, fy) * step(fy, 0.86);
	float in_pane_x = step(0.11, fx) * step(fx, 0.89);
	// Every 4th bay is a wider structural column pier.
	float pier = step(0.75, fract(bay_idx * 0.25)) * (1.0 - step(0.22, fx) * step(fx, 0.78));
	float glass_mask = in_pane_y * in_pane_x * (1.0 - pier) * (1.0 - cornice_mask) * step(0.0, depth - 2.1);

	vec2 win_id = vec2(bay_idx, floor_idx * 13.0 + face_id * 7.0);
	float h_lit = hash21(win_id);
	float h_tint = hash21(win_id + vec2(19.3, 5.7));
	float h_blind = hash21(win_id + vec2(41.1, 11.9));

	float is_lit = step(1.0 - lit_ratio, h_lit) * glass_mask;
	// Venetian blinds or desk/ceiling gradient inside lit rooms.
	float pane_v = clamp((fy - 0.16) / 0.70, 0.0, 1.0);
	float blind_drop = mix(0.0, 0.65, step(0.55, h_blind) * fract(h_blind * 7.3));
	float blind_slats = mix(1.0, 0.35 + 0.25 * step(0.5, fract(pane_v * 9.0)), step(pane_v, blind_drop));
	float room_grad = (0.65 + 0.45 * (1.0 - pane_v)) * blind_slats;

	vec3 win_col = mix(warm_window, cool_window, step(0.66, h_tint));
	float brightness = (0.55 + 0.65 * fract(h_lit * 13.7)) * room_grad;

	vec3 frame_col = mix(wall_color, mullion_color, step(0.5, in_pane_y) * (1.0 - in_pane_x));
	vec3 cornice_col = mix(wall_color * 1.15, mullion_color, louver * 0.55);
	vec3 solid_col = mix(frame_col, cornice_col, cornice_mask);

	vec3 base_albedo = mix(solid_col, glass_dark, glass_mask);
	base_albedo = mix(base_albedo, win_col * 0.85, is_lit);

	// Top cap of background towers if visible.
	float is_top_cap = step(0.5, v_normal.y);
	vec3 final_albedo = mix(base_albedo, wall_color * 0.75, is_top_cap);

	// Subtle city-sky bounce on vertical spandrels & mullions so the curtain-wall grid stays legible at night.
	vec3 ambient_grid = final_albedo * 0.22 * (1.0 - is_lit) * (1.0 - is_top_cap);

	ALBEDO = mix(abyss_fade_color, final_albedo, fade);
	EMISSION = (win_col * brightness * emission_strength * is_lit * (1.0 - is_top_cap) + ambient_grid) * fade;
	ROUGHNESS = mix(0.74, mix(0.22, 0.45, is_lit), glass_mask * (1.0 - is_top_cap));
	METALLIC = mix(0.22, 0.38, glass_mask * (1.0 - is_top_cap));
}
