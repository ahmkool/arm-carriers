shader_type spatial;

// Castle stone in world space, for tiles without suitable UVs.
// Faces pointing up are a worn flagstone courtyard; walls are coursed ashlar blocks with damp and moss near the moat.
// The walkable stone stays a calm, light tone so enemies and the sword read clearly on it.
// timber_top lays a plank deck on top instead (walkways and bridge piers).
// Anything that moves must turn on local_space, or its stones stay still while it slides beneath them.
uniform vec3 flag_color : source_color = vec3(0.66, 0.6, 0.5);
uniform vec3 flag_alt_color : source_color = vec3(0.56, 0.54, 0.5);
uniform vec3 wall_color : source_color = vec3(0.55, 0.51, 0.45);
uniform vec3 mortar_color : source_color = vec3(0.24, 0.22, 0.2);
uniform vec3 moss_color : source_color = vec3(0.27, 0.36, 0.16);
uniform vec3 damp_color : source_color = vec3(0.17, 0.2, 0.17);
uniform float flag_size = 1.15;
uniform float course_height = 0.62;
uniform float block_length = 1.25;
uniform float water_y = -5.0;
uniform float damp_height = 1.6;
uniform bool timber_top = false;
uniform bool local_space = false;
uniform vec3 wood_color : source_color = vec3(0.5, 0.33, 0.19);
uniform vec3 seam_color : source_color = vec3(0.15, 0.09, 0.05);
uniform float plank_width = 0.5;
uniform float plank_length = 3.4;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.3 + 7.1) * 0.3 + noise(p * 5.1 + 3.4) * 0.15;
}

// Running bond: rows of blocks, each row shifted by a random amount, and some blocks split in two
// at a random point so the lengths vary. Returns the distance to the nearest joint (in metres) in x
// and the block's id in yz.
vec3 bond(vec2 uv, vec2 size, float split_chance) {
	float row = floor(uv.y / size.y);
	float along = uv.x / size.x + hash(vec2(row, 5.0)) * 3.0;
	float block = floor(along);
	vec2 local = vec2(fract(along) * size.x, fract(uv.y / size.y) * size.y);
	float edge = min(min(local.x, size.x - local.x), min(local.y, size.y - local.y));
	float split = 0.3 + hash(vec2(block, row) + 9.0) * 0.4;
	if (hash(vec2(block, row) + 21.0) < split_chance) {
		edge = min(edge, abs(local.x - split * size.x));
		block += step(split * size.x, local.x) * 0.5;
	}
	return vec3(edge, block, row);
}

void vertex() {
	v_world_pos = local_space ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = local_space ? NORMAL : normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 flagstones(vec2 xz, out float joint) {
	vec2 warp = vec2(fbm(xz * 0.7), fbm(xz * 0.7 + 11.0)) * 0.18;
	vec3 b = bond(xz + warp, vec2(flag_size * 1.9, flag_size), 0.6);
	float id = hash(b.yz + 17.0);
	joint = 1.0 - smoothstep(0.025, 0.06, b.x);
	float bevel = smoothstep(0.06, 0.2, b.x);
	vec3 stone = mix(flag_color, flag_alt_color, step(0.55, id)) * (0.86 + id * 0.2);
	stone *= 0.9 + bevel * 0.1;
	float wear = fbm(xz * 1.8 + id * 9.0);
	stone *= 0.93 + wear * 0.12;
	float dirt = smoothstep(0.55, 0.85, fbm(xz * 0.22));
	return mix(stone, stone * vec3(0.82, 0.8, 0.74), dirt * 0.6);
}

// Planks running along x, laid in rows across z, with staggered butt joints.
vec3 planks(vec2 xz, out float joint) {
	float row = floor(xz.y / plank_width);
	float along = xz.x / plank_length + hash(vec2(row, 3.0)) * 7.0;
	vec2 cell = vec2(floor(along), row);
	float across = fract(xz.y / plank_width);
	float seam = 1.0 - smoothstep(0.0, 0.06, min(across, 1.0 - across));
	float butt = 1.0 - smoothstep(0.0, 0.012, min(fract(along), 1.0 - fract(along)));
	joint = max(seam, butt);
	float grain = noise(vec2(xz.x * 0.9 + hash(cell) * 40.0, xz.y * 16.0));
	return wood_color * (0.76 + hash(cell) * 0.36) * (0.86 + grain * 0.26);
}

vec3 ashlar(vec3 pos, out float joint) {
	vec2 uv = vec2(pos.x + pos.z, pos.y);
	vec3 b = bond(uv, vec2(block_length, course_height), 0.25);
	float id = hash(b.yz + 3.0);
	joint = 1.0 - smoothstep(0.03, 0.07, b.x);
	float bevel = smoothstep(0.05, 0.16, b.x);
	vec3 stone = wall_color * (0.8 + id * 0.28) * (0.88 + bevel * 0.12);
	stone *= 0.9 + fbm(uv * 2.5 + id * 5.0) * 0.16;
	float damp = 1.0 - smoothstep(water_y, water_y + damp_height, pos.y + (fbm(uv * 1.4) - 0.5) * 0.8);
	return mix(stone, damp_color, damp * 0.75);
}

void fragment() {
	bool is_top = v_world_normal.y > 0.7;
	float joint = 0.0;
	vec3 base = is_top ? flagstones(v_world_pos.xz, joint) : ashlar(v_world_pos, joint);
	vec2 moss_uv = is_top ? v_world_pos.xz : vec2(v_world_pos.x + v_world_pos.z, v_world_pos.y);
	float mossy = smoothstep(0.5, 0.75, fbm(moss_uv * 0.45 + 4.0));
	vec3 joint_color = mix(mortar_color, moss_color, mossy * 0.8);
	vec3 stone = mix(base, joint_color, joint * (is_top ? 0.6 : 0.8));
	bool deck = is_top && timber_top;
	float plank_joint = 0.0;
	vec3 wood = deck ? planks(v_world_pos.xz, plank_joint) : vec3(0.0);
	ALBEDO = deck ? mix(wood, seam_color, plank_joint) : stone;
	ROUGHNESS = deck ? 0.85 : 0.92;
	SPECULAR = deck ? 0.25 : 0.2;
}
