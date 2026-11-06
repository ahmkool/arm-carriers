shader_type spatial;
render_mode unshaded, shadows_disabled;

// Molten rock in world space: a dark crust broken into plates, with bright lava in the cracks.
// Colours go above 1 on purpose, so the environment's glow picks them up.
uniform vec3 crust_color : source_color = vec3(0.09, 0.025, 0.018);
uniform vec3 ember_color : source_color = vec3(0.72, 0.09, 0.015);
uniform vec3 molten_color : source_color = vec3(1.0, 0.42, 0.04);
uniform vec3 white_hot_color : source_color = vec3(1.0, 0.68, 0.2);
uniform float brightness = 1.35;
uniform float plate_scale = 0.2;
uniform float flow_speed = 0.035;

varying vec3 v_world_pos;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash22(i).x;
	float b = hash22(i + vec2(1.0, 0.0)).x;
	float c = hash22(i + vec2(0.0, 1.0)).x;
	float d = hash22(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.1 + 7.3) * 0.3 + value_noise(p * 4.3 + 2.9) * 0.15;
}

// Distance to the nearest border between two plates: small along the cracks.
float plate_edge(vec2 uv, float time) {
	vec2 cell = floor(uv);
	vec2 local = fract(uv);
	float nearest = 8.0;
	float second = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 offset = vec2(float(i), float(j));
			vec2 jitter = hash22(cell + offset);
			jitter = 0.5 + 0.42 * sin(time * 6.0 + jitter * 6.2831);
			float dist = length(offset + jitter - local);
			if (dist < nearest) {
				second = nearest;
				nearest = dist;
			} else if (dist < second) {
				second = dist;
			}
		}
	}
	return second - nearest;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float time = TIME * flow_speed;
	vec2 pos = v_world_pos.xz;
	vec2 warp = vec2(fbm(pos * 0.07 + time), fbm(pos * 0.07 - time + 11.0)) - 0.5;
	vec2 uv = (pos + warp * 16.0) * plate_scale + vec2(time * 0.9, -time * 1.4);

	// Pools are where the crust has melted away, so the cracks widen there.
	float pool = smoothstep(0.5, 0.76, fbm(pos * 0.045 + vec2(-time * 0.7, time * 0.5)));
	float large_crack = 1.0 - smoothstep(0.0, mix(0.06, 0.32, pool), plate_edge(uv, time));
	float small_crack = 1.0 - smoothstep(0.0, 0.1, plate_edge(uv * 2.6 + 5.0, time * 1.3));
	float heat = clamp(large_crack + small_crack * 0.22 + pool * 0.25, 0.0, 1.0);

	vec3 color = mix(crust_color, ember_color, smoothstep(0.0, 0.3, heat));
	color = mix(color, molten_color, smoothstep(0.28, 0.7, heat));
	color = mix(color, white_hot_color, smoothstep(0.88, 1.0, heat));
	ALBEDO = color * brightness * (0.9 + 0.1 * sin(TIME * 0.7 + pos.x * 0.05 + pos.y * 0.03));
}
