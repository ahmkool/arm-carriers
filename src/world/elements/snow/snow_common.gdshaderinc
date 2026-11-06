// Shared by the snow and ice tile shaders: hashing, plate noise, and the rock faces under the snow.

vec2 snow_hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float snow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(snow_hash22(i).x, snow_hash22(i + vec2(1.0, 0.0)).x, f.x),
			mix(snow_hash22(i + vec2(0.0, 1.0)).x, snow_hash22(i + vec2(1.0, 1.0)).x, f.x), f.y);
}

// x: distance to the nearest crack between plates. y: a tone for the plate.
vec2 snow_cracks(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 local = fract(uv);
	float nearest = 8.0;
	float second = 8.0;
	float tone = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 offset = vec2(float(i), float(j));
			vec2 jitter = snow_hash22(cell + offset);
			float dist = length(offset + jitter - local);
			if (dist < nearest) {
				second = nearest;
				nearest = dist;
				tone = jitter.x;
			} else if (dist < second) {
				second = dist;
			}
		}
	}
	return vec2(second - nearest, tone);
}

// Cold rock on cliff faces, with snow caught on its upper edge.
vec3 snow_cliff(vec3 world_pos, vec3 rock_color, vec3 snow_color, float top_y) {
	vec2 plates = snow_cracks(vec2(world_pos.x + world_pos.z, world_pos.y * 1.5) * 0.8);
	vec3 rock = rock_color * (0.8 + plates.y * 0.3);
	rock = mix(rock, rock * 0.45, 1.0 - smoothstep(0.0, 0.05, plates.x));
	float drift = smoothstep(top_y - 0.55 - snow_noise(world_pos.xz * 1.7) * 0.35, top_y - 0.1, world_pos.y);
	return mix(rock, snow_color, drift);
}
