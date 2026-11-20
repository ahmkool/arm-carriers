shader_type spatial;
render_mode blend_mix, cull_back;

// Ancient mystical Uranian sanctuary floor: carved deep-sapphire moonstone tiles with subtle
// inlaid nested-square runes (echoing the floating ancient cubes), gentle atmospheric cloud glow
// shining softly through the glassy surface, and crisp shadow reception.
uniform vec3 deep_sapphire : source_color = vec3(0.05, 0.13, 0.26);
uniform vec3 mid_cerulean : source_color = vec3(0.11, 0.26, 0.42);
uniform vec3 sky_reflection : source_color = vec3(0.55, 0.86, 0.96);
uniform vec3 rune_color : source_color = vec3(0.45, 0.88, 0.98);
uniform float base_alpha : hint_range(0.4, 0.98) = 0.78;
uniform float tile_size = 2.999;

varying vec3 v_world_pos;

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
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	vec2 cell_id = floor(p / tile_size);
	vec2 cell_uv = fract(p / tile_size);
	vec2 centered = abs(cell_uv - 0.5);

	// Ancient stone slab bevels and nested cube-sigil inlays.
	float outer_border = min(min(cell_uv.x, 1.0 - cell_uv.x), min(cell_uv.y, 1.0 - cell_uv.y));
	float grout = 1.0 - smoothstep(0.0, 0.022, outer_border);
	float inner_square = 1.0 - smoothstep(0.0, 0.016, abs(max(centered.x, centered.y) - 0.34));
	float diamond = 1.0 - smoothstep(0.0, 0.014, abs((centered.x + centered.y) - 0.28));

	float tile_seed = hash21(cell_id);
	float stone_grain = value_noise(p * 1.8) * 0.5 + value_noise(p * 4.7) * 0.25;
	float mist_drift = value_noise(p * 0.25 + vec2(TIME * 0.08, -TIME * 0.03));

	// Gentle breathing arcane pulse flowing across the ancient tiles.
	float pulse = 0.65 + 0.35 * sin(TIME * 1.1 + tile_seed * 6.28318 + (p.x - p.y) * 0.16);
	float rune_mask = clamp(inner_square * 0.42 + diamond * step(0.45, tile_seed) * 0.38, 0.0, 0.75);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 base_stone = mix(deep_sapphire, mid_cerulean, clamp(stone_grain * 0.75 + mist_drift * 0.35, 0.0, 1.0));
	base_stone *= 0.90 + tile_seed * 0.18;
	base_stone = mix(base_stone, deep_sapphire * 0.45, grout * 0.75);
	base_stone = mix(base_stone, sky_reflection * 0.55, fresnel * 0.42);
	base_stone = mix(base_stone, rune_color, rune_mask * 0.45);

	ALBEDO = base_stone;
	ROUGHNESS = mix(0.36, 0.18, clamp(stone_grain * 0.5 + rune_mask * 0.5, 0.0, 1.0));
	METALLIC = 0.14;
	SPECULAR = 0.35;
	EMISSION = rune_color * (rune_mask * 0.30 * pulse + grout * 0.05);
	ALPHA = clamp(base_alpha + grout * 0.15 + fresnel * 0.10, 0.62, 0.95);
}
