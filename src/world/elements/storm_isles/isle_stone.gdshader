shader_type spatial;

// The dungeon's stone blocks (dungeon_stone.gdshader), rained on and standing in the sea:
// darker and glossier on top, with a band of weed above the waterline. Laid out in world space, so no UVs.
uniform vec3 stone_color : source_color = vec3(0.34, 0.36, 0.4);
uniform vec3 grout_color : source_color = vec3(0.06, 0.07, 0.08);
uniform vec3 top_color : source_color = vec3(0.36, 0.38, 0.42);
uniform vec3 weed_color : source_color = vec3(0.12, 0.2, 0.15);
uniform float block_size = 1.5;
uniform float grout_width : hint_range(0.0, 0.3) = 0.05;
uniform float water_y = -4.6;
uniform float weed_height = 1.3;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.5;

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
	float shade = 0.74 + hash21(cell) * 0.46;
	float grain = 0.92 + hash21(floor(uv * 14.0)) * 0.16;
	vec3 base = is_top ? top_color : stone_color;
	vec3 stone = base * shade * grain;
	// Weed creeps up the sides from the sea, patchy along the wall.
	float patch = hash21(floor(v_world_pos.xz * 0.9 + v_world_pos.y * 0.3)) * 0.5;
	float weed = is_top ? 0.0 : 1.0 - smoothstep(0.0, weed_height + patch, v_world_pos.y - water_y);
	stone = mix(stone, weed_color * (0.8 + hash21(cell * 3.1) * 0.4), weed * 0.85);
	ALBEDO = mix(stone, grout_color, mortar);
	// Rain pools in the grout and keeps the tops glossy.
	ROUGHNESS = is_top ? mix(wet_roughness, 0.3, mortar) : 0.75;
	SPECULAR = is_top ? 0.3 : 0.2;
}
