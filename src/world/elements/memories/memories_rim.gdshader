shader_type spatial;

// Sculpted obsidian-teal stone perimeter curb & luminous silver-aqua bevel for "World of Memories" platforms.
// Opaque so platform drop-off edges are 100% crisp and readable against both the semi-transparent floor and the cloud sea.
uniform vec3 body_color : source_color = vec3(0.11, 0.20, 0.26);
uniform vec3 cap_color : source_color = vec3(0.22, 0.35, 0.42);
uniform vec3 trim_glow : source_color = vec3(0.58, 0.86, 0.92);
uniform float trim_energy = 0.85;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

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
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float grain = value_noise(v_world_pos.xz * 4.5) * 0.08;
	float block_joint = 1.0 - smoothstep(0.0, 0.022, min(fract(v_world_pos.x / 1.4995), fract(v_world_pos.z / 1.4995)));
	float top_face = step(0.55, v_world_normal.y);

	// Subtle luminous aqua-silver inlay band near the top lip of every platform edge.
	float lip_band = 1.0 - smoothstep(0.0, 0.032, abs(v_world_pos.y - (-0.965)));
	float pulse = 0.88 + 0.12 * sin(TIME * 1.4 + (v_world_pos.x + v_world_pos.z) * 0.35);

	vec3 stone = mix(body_color, cap_color, top_face) + vec3(grain - 0.04);
	stone = mix(stone, body_color * 0.55, block_joint * 0.55);

	ALBEDO = mix(stone, trim_glow * 0.8, lip_band * 0.65);
	ROUGHNESS = mix(0.42, 0.24, top_face);
	METALLIC = 0.22;
	EMISSION = trim_glow * lip_band * trim_energy * pulse;
}
