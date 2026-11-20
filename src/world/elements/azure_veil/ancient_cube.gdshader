shader_type spatial;

// Ancient mystical floating stone cube for Azure Veil: weathered deep-lapis monolith stone
// etched with nested concentric squares, weathered cracks, and softly pulsing aquamarine-gold
// arcane sigils on every face. Magical & archaic, not sci-fi.
uniform vec3 stone_dark : source_color = vec3(0.06, 0.12, 0.24);
uniform vec3 stone_light : source_color = vec3(0.16, 0.30, 0.48);
uniform vec3 rune_cyan : source_color = vec3(0.40, 0.92, 1.0);
uniform vec3 rune_gold : source_color = vec3(0.86, 0.92, 0.72);
uniform float rune_energy = 1.25;

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
	// BoxMesh standard UVs tile each face; wrap into [0..1]^2 per face.
	vec2 fuv = fract(UV * vec2(3.0, 2.0));
	vec2 c = abs(fuv - 0.5);
	float box_d = max(c.x, c.y);
	float rad_d = length(fuv - 0.5);

	// Weathering grain & carved masonry relief.
	float grain = value_noise(fuv * 9.0 + floor(v_world_pos.xz) * 0.37) * 0.65
		+ value_noise(fuv * 22.0) * 0.35;

	// Ancient nested square grooves & central arcane ring sigil.
	float outer_frame = 1.0 - smoothstep(0.0, 0.022, abs(box_d - 0.40));
	float inner_frame = 1.0 - smoothstep(0.0, 0.018, abs(box_d - 0.26));
	float center_ring = 1.0 - smoothstep(0.0, 0.018, abs(rad_d - 0.14));
	float cross_axis = (1.0 - smoothstep(0.0, 0.014, min(c.x, c.y))) * step(0.14, rad_d) * step(box_d, 0.40);
	float bevel_edge = smoothstep(0.44, 0.50, box_d);

	float rune = clamp(outer_frame * 0.85 + inner_frame * 0.65 + center_ring * 1.0 + cross_axis * 0.45, 0.0, 1.0);
	float pulse = 0.72 + 0.28 * sin(TIME * 1.3 + v_world_pos.x * 0.22 + v_world_pos.z * 0.19);
	vec3 glow_col = mix(rune_cyan, rune_gold, center_ring * 0.45);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.8);
	vec3 stone = mix(stone_dark, stone_light, clamp(grain * 0.8 + bevel_edge * 0.35, 0.0, 1.0));
	stone = mix(stone, vec3(0.45, 0.82, 0.96), fresnel * 0.38);

	ALBEDO = mix(stone, glow_col * 0.85, rune * 0.65);
	ROUGHNESS = mix(0.58, 0.26, rune * 0.6 + bevel_edge * 0.3);
	METALLIC = 0.18;
	EMISSION = glow_col * rune * rune_energy * pulse + vec3(0.10, 0.28, 0.42) * fresnel * 0.35;
}
