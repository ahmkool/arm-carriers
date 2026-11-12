shader_type spatial;

uniform vec3 water_color : source_color = vec3(0.1, 0.4, 0.6);
uniform vec3 foam_color : source_color = vec3(0.8, 0.9, 1.0);
uniform float wave_scale : hint_range(0.1, 50.0) = 1.0;
uniform float wave_scale_detail : hint_range(0.1, 50.0) = 1.50;
// Rain: expanding rings scattered over the surface. 0 turns them off (the default).
uniform float rain_ripples : hint_range(0.0, 1.0) = 0.0;
uniform float ripple_cell = 1.4;
uniform float ripple_speed = 1.3;

varying vec3 v_world_pos;

// Portable cell hash (no sin of large values — stable on D3D/Vulkan/Metal).
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float voronoi(vec2 uv) {
	vec2 p = floor(uv);
	vec2 f = fract(uv);
	float res = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 r = b - f + hash22(p + b);
			res = min(res, dot(r, r));
		}
	}
	return sqrt(res);
}

// One ring per cell, each with its own centre and timing. Returns the ring's strength at this point.
float rain_ring(vec2 uv, float t) {
	vec2 cell = floor(uv);
	vec2 jitter = hash22(cell);
	float phase = fract(t * ripple_speed + jitter.x * 7.0);
	vec2 centre = cell + 0.2 + jitter * 0.6;
	float radius = phase * 0.5;
	float ring = 1.0 - smoothstep(0.0, 0.06, abs(length(uv - centre) - radius));
	return ring * (1.0 - phase);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float time = TIME * 0.2;
	vec2 world_uv = v_world_pos.xz;

	float v1 = voronoi(world_uv * wave_scale + time);
	float v2 = voronoi(world_uv * wave_scale_detail - time * 0.5);

	float final_v = smoothstep(0.35, 0.55, v1 * v2);
	vec3 normal_offset = vec3(v1 - 0.5, 0.0, v2 - 0.5) * 0.2;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + normal_offset);

	if (rain_ripples > 0.0) {
		vec2 ripple_uv = world_uv / ripple_cell;
		float rings = rain_ring(ripple_uv, TIME) + rain_ring(ripple_uv + vec2(0.5, 0.37), TIME + 0.41);
		final_v = max(final_v, rings * rain_ripples * 0.7);
	}

	ALBEDO = mix(water_color, foam_color, final_v);
	ROUGHNESS = 0.1;
	SPECULAR = 0.0;
	ALPHA = 0.9;
	METALLIC = 0.0;
}
