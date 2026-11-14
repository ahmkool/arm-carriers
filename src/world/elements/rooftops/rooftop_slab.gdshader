shader_type spatial;

// World-space skyscraper rooftop slab & parapet concrete.
// Calm dark slate/concrete membrane tiles with expansion joints, fine aggregate, and subtle damp night sheen.
uniform vec3 slab_color : source_color = vec3(0.24, 0.26, 0.31);
uniform vec3 joint_color : source_color = vec3(0.10, 0.11, 0.14);
uniform vec3 curb_color : source_color = vec3(0.32, 0.35, 0.41);
uniform vec3 coping_color : source_color = vec3(0.15, 0.18, 0.23);
uniform float tile_size = 1.5;

varying vec3 v_pos;
varying vec3 v_normal;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x);
	float b = mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x);
	return mix(a, b, u.y);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 sample_rooftop_top(vec2 p) {
	vec2 cell = floor(p / tile_size);
	vec2 f = fract(p / tile_size);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float joint = 1.0 - smoothstep(0.0, 0.022, edge);

	// Coarser 3 m structural slab seam.
	vec2 macro_f = fract(p / (tile_size * 2.0));
	float macro_edge = min(min(macro_f.x, 1.0 - macro_f.x), min(macro_f.y, 1.0 - macro_f.y));
	float macro_joint = 1.0 - smoothstep(0.0, 0.018, macro_edge);

	float grain = value_noise(p * 5.5) * 0.10 + value_noise(p * 17.0) * 0.05;
	float damp = smoothstep(0.56, 0.78, value_noise(p * 0.24 + vec2(3.7, 9.2)));
	float panel_tone = 0.93 + hash21(cell) * 0.14;

	vec3 col = slab_color * panel_tone + vec3(grain - 0.06);
	col = mix(col, col * 0.74, damp * 0.65);
	col = mix(col, joint_color, clamp(joint * 0.75 + macro_joint * 0.55, 0.0, 1.0));
	float rough = mix(0.76, 0.34, damp);
	return vec4(col, rough);
}

void fragment() {
	vec4 top = sample_rooftop_top(v_pos.xz);
	float is_coping = step(-0.82, v_pos.y);
	float seam_coping = 1.0 - smoothstep(0.0, 0.025, min(fract(v_pos.x / 1.5), fract(v_pos.z / 1.5)));
	vec3 coping = mix(coping_color, joint_color, seam_coping * 0.5);

	vec3 up_albedo = mix(top.rgb, coping, is_coping);
	float up_rough = mix(top.a, 0.34, is_coping);
	float up_metal = mix(0.08, 0.68, is_coping);

	float grain_side = value_noise(vec2(v_pos.x + v_pos.z, v_pos.y) * 4.0) * 0.08;
	vec3 side_col = mix(curb_color + vec3(grain_side - 0.04), coping_color, step(-0.72, v_pos.y));
	float top_mask = step(0.5, v_normal.y);

	ALBEDO = mix(side_col, up_albedo, top_mask);
	ROUGHNESS = mix(0.68, up_rough, top_mask);
	METALLIC = mix(0.16, up_metal, top_mask);
}
