shader_type spatial;

// Overgrown ancient temple stone in world space, with mossy joints on walkable flagstones,
// stepped temple masonry on cliff sides, and lush emerald river moss creeping up from the waterline.
// Walkable tops stay a calm, weathered olive-slate so enemies, hazards, and glowing aim arrows pop.
// Moving bridge piers turn on local_space and timber_top while keeping waterline moss in true world Y.
uniform vec3 flag_color : source_color = vec3(0.42, 0.45, 0.38);
uniform vec3 flag_alt_color : source_color = vec3(0.35, 0.39, 0.33);
uniform vec3 wall_color : source_color = vec3(0.31, 0.35, 0.29);
uniform vec3 mortar_color : source_color = vec3(0.12, 0.2, 0.12);
uniform vec3 moss_color : source_color = vec3(0.18, 0.36, 0.16);
uniform vec3 river_moss_color : source_color = vec3(0.09, 0.27, 0.15);
uniform vec3 wood_color : source_color = vec3(0.34, 0.21, 0.12);
uniform vec3 seam_color : source_color = vec3(0.11, 0.07, 0.04);
uniform float flag_size = 1.25;
uniform float course_height = 0.58;
uniform float block_length = 1.3;
uniform float water_y = -4.6;
uniform float moss_height = 1.8;
uniform float plank_width = 0.48;
uniform float plank_length = 3.0;
uniform bool timber_top = false;
uniform bool local_space = false;

varying vec3 v_pos;
varying vec3 v_normal;
varying float v_true_world_y;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm(vec2 p) {
	return noise2d(p) * 0.55 + noise2d(p * 2.3 + 7.1) * 0.3 + noise2d(p * 5.1 + 3.4) * 0.15;
}

vec3 bond(vec2 uv, vec2 size, float split_chance) {
	float row = floor(uv.y / size.y);
	float along = uv.x / size.x + hash21(vec2(row, 5.0)) * 3.0;
	float block = floor(along);
	vec2 local = vec2(fract(along) * size.x, fract(uv.y / size.y) * size.y);
	float edge = min(min(local.x, size.x - local.x), min(local.y, size.y - local.y));
	float split = 0.3 + hash21(vec2(block, row) + 9.0) * 0.4;
	if (hash21(vec2(block, row) + 21.0) < split_chance) {
		edge = min(edge, abs(local.x - split * size.x));
		block += step(split * size.x, local.x) * 0.5;
	}
	return vec3(edge, block, row);
}

void vertex() {
	v_true_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	v_pos = local_space ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = local_space ? NORMAL : normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 timber_deck(vec2 xz, out float seam) {
	float row = floor(xz.x / plank_width);
	float shift = hash21(vec2(row, 3.0)) * plank_length;
	float board = floor((xz.y + shift) / plank_length);
	vec2 local = vec2(fract(xz.x / plank_width) * plank_width, fract((xz.y + shift) / plank_length) * plank_length);
	float edge = min(min(local.x, plank_width - local.x), min(local.y, plank_length - local.y));
	seam = 1.0 - smoothstep(0.012, 0.032, edge);
	float grain = fbm(vec2(xz.x * 16.0, xz.y * 1.8 + row * 5.0));
	float id = hash21(vec2(row, board) + 13.0);
	vec3 wood = wood_color * (0.82 + id * 0.28) * (0.88 + grain * 0.24);
	float edge_moss = smoothstep(0.58, 0.86, fbm(xz * 0.85)) * (1.0 - smoothstep(0.02, 0.14, edge));
	wood = mix(wood, moss_color * 0.9, edge_moss * 0.55);
	return mix(wood, seam_color, seam);
}

vec3 temple_flagstones(vec2 xz, out float joint) {
	vec2 warp = vec2(fbm(xz * 0.65), fbm(xz * 0.65 + 11.0)) * 0.16;
	vec3 b = bond(xz + warp, vec2(flag_size * 1.7, flag_size), 0.55);
	float id = hash21(b.yz + 17.0);
	joint = 1.0 - smoothstep(0.025, 0.065, b.x);
	float bevel = smoothstep(0.06, 0.22, b.x);
	vec3 stone = mix(flag_color, flag_alt_color, step(0.5, id)) * (0.88 + id * 0.18);
	stone *= 0.9 + bevel * 0.1;
	float moss_tuft = smoothstep(0.46, 0.78, fbm(xz * 0.6)) * (1.0 - smoothstep(0.04, 0.24, b.x));
	stone = mix(stone, moss_color, moss_tuft * 0.5);
	return mix(stone, mortar_color, joint * 0.88);
}

vec3 temple_wall(vec3 pos, out float joint) {
	vec2 uv = vec2(pos.x + pos.z, pos.y);
	vec3 b = bond(uv, vec2(block_length, course_height), 0.35);
	float id = hash21(b.yz + 31.0);
	joint = 1.0 - smoothstep(0.02, 0.055, b.x);
	float grain = 0.9 + fbm(uv * 3.5 + id * 7.0) * 0.2;
	vec3 stone = wall_color * (0.8 + id * 0.32) * grain;
	float vine_patch = fbm(vec2((pos.x - pos.z) * 0.55, pos.y * 0.45));
	float high_moss = smoothstep(0.56, 0.82, vine_patch);
	stone = mix(stone, moss_color * 0.85, high_moss * 0.48);
	float water_creep = 1.0 - smoothstep(0.0, moss_height + vine_patch * 0.8, v_true_world_y - water_y);
	stone = mix(stone, river_moss_color * (0.85 + id * 0.3), water_creep * 0.88);
	return mix(stone, mortar_color * 0.85, joint);
}

void fragment() {
	bool is_top = v_normal.y > 0.55;
	float joint = 0.0;
	vec3 top_surface = timber_top ? timber_deck(v_pos.xz, joint) : temple_flagstones(v_pos.xz, joint);
	vec3 wall_surface = temple_wall(v_pos, joint);
	ALBEDO = is_top ? top_surface : wall_surface;
	ROUGHNESS = is_top ? mix(0.76, 0.92, joint) : 0.84;
	SPECULAR = is_top ? 0.22 : 0.16;
}
