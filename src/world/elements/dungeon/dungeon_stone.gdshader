shader_type spatial;

// Stone blocks laid out in world space, so any box tiles seamlessly with no UVs.
uniform vec3 stone_color : source_color = vec3(0.34, 0.36, 0.42);
uniform vec3 grout_color : source_color = vec3(0.07, 0.07, 0.09);
uniform vec3 top_color : source_color = vec3(0.34, 0.36, 0.42);
uniform float block_size = 1.5;
uniform float grout_width : hint_range(0.0, 0.3) = 0.05;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool is_top = abs(v_world_normal.y) > 0.5;
	vec2 uv = is_top ? v_world_pos.xz : vec2(v_world_pos.x + v_world_pos.z, v_world_pos.y);
	uv /= block_size;
	uv.x += mod(floor(uv.y), 2.0) * 0.5; // running bond
	vec2 cell = floor(uv);
	vec2 local = fract(uv);
	vec2 edge = min(local, 1.0 - local);
	float mortar = 1.0 - smoothstep(0.0, grout_width, min(edge.x, edge.y));
	float shade = 0.72 + hash21(cell) * 0.5;
	float grain = 0.92 + hash21(floor(uv * 14.0)) * 0.16;
	vec3 base = is_top ? top_color : stone_color;
	ALBEDO = mix(base * shade * grain, grout_color, mortar);
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
