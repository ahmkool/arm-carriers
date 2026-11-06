shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// The erupting column: bright streaks rushing upward, fading out at the top.
uniform vec3 core_color : source_color = vec3(1.0, 0.72, 0.25);
uniform vec3 edge_color : source_color = vec3(1.0, 0.2, 0.02);
uniform float intensity = 1.8;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float wrap = UV.x * 12.0;
	float streak = noise(vec2(wrap, UV.y * 2.5 + TIME * 5.0)) * 0.6 + noise(vec2(wrap * 2.3, UV.y * 6.0 + TIME * 8.0)) * 0.4;
	float fade = smoothstep(0.0, 0.45, UV.y);
	float strength = smoothstep(0.22, 0.62, streak) * fade;
	ALBEDO = mix(edge_color, core_color, strength) * strength * intensity;
}
