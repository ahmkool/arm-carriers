shader_type spatial;

// Basalt in world space, for tiles without suitable UVs. Tops stay plain so walkable ground reads
// clearly against the lava; only cliff faces glow, more strongly the closer they are to the surface.
uniform vec3 top_color : source_color = vec3(0.34, 0.33, 0.34);
uniform vec3 cliff_color : source_color = vec3(0.12, 0.095, 0.095);
uniform vec3 crack_color : source_color = vec3(0.045, 0.035, 0.035);
uniform vec3 heat_color : source_color = vec3(1.0, 0.27, 0.035);
uniform float heat_strength = 1.3;
uniform float lava_y = -4.6;
uniform float top_y = -1.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// x: distance to the nearest crack. y: a tone for the plate this point is on.
vec2 cracks(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 local = fract(uv);
	float nearest = 8.0;
	float second = 8.0;
	float tone = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 offset = vec2(float(i), float(j));
			vec2 jitter = hash22(cell + offset);
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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool is_top = v_world_normal.y > 0.65;
	vec2 uv = is_top ? v_world_pos.xz * 0.75 : vec2(v_world_pos.x + v_world_pos.z, v_world_pos.y * 1.4) * 0.8;
	vec2 plates = cracks(uv);
	float crack = 1.0 - smoothstep(0.0, 0.05, plates.x);
	vec3 base = (is_top ? top_color : cliff_color) * (0.82 + plates.y * 0.3);
	ALBEDO = mix(base, crack_color, crack * 0.6);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;

	float height = clamp((v_world_pos.y - lava_y) / (top_y - lava_y), 0.0, 1.0);
	float heat = pow(1.0 - height, 2.2);
	float glow = is_top ? 0.0 : heat * 0.75 + crack * (0.1 + heat);
	EMISSION = heat_color * heat_strength * glow;
}
