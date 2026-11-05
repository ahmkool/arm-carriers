shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// One drifting sheet of clouds. Stack several at different depths: parallax sells the altitude.
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 shade_color : source_color = vec3(0.72, 0.84, 0.95);
uniform vec3 sky_color : source_color = vec3(0.32, 0.62, 0.92);
uniform float sky_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float coverage : hint_range(0.0, 1.0) = 0.5;
uniform float softness : hint_range(0.01, 0.5) = 0.12;
uniform float noise_scale = 0.03;
uniform vec2 drift = vec2(0.6, 0.15);

varying vec3 v_world_pos;

// Portable hash (no sin of large values), same approach as water.gdshader.
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float bottom = mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), u.x);
	float top = mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0, 1.0)), u.x);
	return mix(bottom, top, u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return total / 0.9375;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (v_world_pos.xz + drift * TIME) * noise_scale;
	float density = fbm(uv);
	float threshold = 1.0 - coverage;
	float cloud = smoothstep(threshold - softness, threshold + softness, density);
	// Fake lighting: the sample offset toward the light is thinner on the lit side of each puff.
	float lit = smoothstep(-0.08, 0.14, density - fbm(uv + vec2(0.05, 0.07)));
	vec3 puff = mix(shade_color, cloud_color, lit);
	ALBEDO = mix(sky_color, puff, cloud);
	ALPHA = max(cloud, sky_opacity);
}
