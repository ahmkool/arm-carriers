shader_type spatial;

// Tropical canopy & moss tint for KayKit trees, bushes, and boulders in the jungle ruin theme.
// Deepens shadows into rich rainforest emerald and settles warm sunlit moss on upward faces.
uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform vec3 jungle_tint : source_color = vec3(0.68, 0.9, 0.64);
uniform vec3 canopy_moss : source_color = vec3(0.32, 0.56, 0.21);
uniform float coverage = 0.24;

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
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = texture(base_texture, UV).rgb * jungle_tint;
	float n = value_noise(v_pos.xz * 2.1 + v_pos.y * 0.9);
	float up = v_normal.y - coverage + (n - 0.5) * 0.36;
	ALBEDO = mix(base, canopy_moss * (0.85 + n * 0.3), smoothstep(0.0, 0.22, up) * 0.58);
	ROUGHNESS = 0.86;
}
