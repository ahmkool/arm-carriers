shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Sweeping painterly fantasy cloud sheet for "World of Memories" (FFX Inside Sin palette).
// Multiple layers at different depths create deep parallax beneath the semi-transparent floor.
uniform vec3 lit_color : source_color = vec3(0.95, 0.83, 0.84);
uniform vec3 mid_color : source_color = vec3(0.78, 0.65, 0.73);
uniform vec3 shade_color : source_color = vec3(0.39, 0.42, 0.52);
uniform vec3 sky_color : source_color = vec3(0.56, 0.53, 0.63);
uniform vec3 horizon_color : source_color = vec3(0.86, 0.77, 0.80);
uniform float sky_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float coverage : hint_range(0.0, 1.0) = 0.52;
uniform float softness : hint_range(0.02, 0.5) = 0.16;
uniform float max_alpha : hint_range(0.1, 1.0) = 0.92;
uniform vec2 uv_scale = vec2(0.018, 0.038);
uniform vec2 drift = vec2(0.85, 0.18);
uniform float fade_radius = 420.0;

varying vec3 v_world_pos;

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
	for (int i = 0; i < 5; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.3, 9.1);
		amplitude *= 0.5;
	}
	return total / 0.96875;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz + drift * TIME;
	vec2 uv = p * uv_scale;
	// Domain warp gives soft, billowing FFX-style painted cloud banks rather than boxy noise.
	float warp = fbm(uv * 0.65 + vec2(4.2, -2.7));
	vec2 warped_uv = uv + vec2(warp * 0.45, (warp - 0.5) * 0.28);

	float density = fbm(warped_uv);
	float threshold = 1.0 - coverage;
	float cloud = smoothstep(threshold - softness, threshold + softness, density);

	// Directional puff lighting: rose-ivory crests on the north-west side, cool slate-mauve undersides.
	float neighbor = fbm(warped_uv + vec2(-0.07, -0.09));
	float highlight = smoothstep(-0.06, 0.14, density - neighbor);
	float ridge = smoothstep(threshold + softness * 0.2, threshold + softness * 1.6, density);

	vec3 puff = mix(shade_color, mid_color, smoothstep(0.15, 0.65, highlight * 0.6 + ridge * 0.5));
	puff = mix(puff, lit_color, smoothstep(0.48, 0.92, highlight * 0.75 + ridge * 0.35));

	vec3 col = mix(sky_color, puff, cloud);
	float dist = length(v_world_pos.xz - INV_VIEW_MATRIX[3].xz);
	float horizon_blend = smoothstep(fade_radius * 0.38, fade_radius, dist);
	col = mix(col, horizon_color, horizon_blend * 0.72);

	float alpha = max(cloud * max_alpha, sky_opacity);
	alpha *= 1.0 - smoothstep(fade_radius * 0.82, fade_radius, dist) * (1.0 - sky_opacity);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
