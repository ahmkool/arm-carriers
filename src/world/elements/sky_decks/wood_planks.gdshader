shader_type spatial;

// Planks laid out in world space, so decks of any shape tile with no UVs.
// Anything that moves must turn on local_space, or its boards stay still while it slides beneath them.
uniform vec3 wood_color : source_color = vec3(0.56, 0.37, 0.2);
uniform vec3 seam_color : source_color = vec3(0.13, 0.08, 0.05);
uniform float plank_width = 0.75;
uniform float plank_length = 4.5;
uniform bool local_space = false;
// Planks run along world x by default; on runs the other way across z. A bridge along x lays them along z, so its
// boards cross it.
uniform bool planks_along_z = false;

varying vec3 v_pos;
varying vec3 v_normal;

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

void vertex() {
	v_pos = local_space ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool is_top = abs(v_normal.y) > 0.5;
	vec2 flat_pos = planks_along_z ? v_pos.zx : v_pos.xz;
	vec2 uv = is_top ? flat_pos : vec2(v_pos.x + v_pos.z, v_pos.y * 2.0);
	float row = floor(uv.y / plank_width);
	float along = uv.x / plank_length + hash(vec2(row, 3.0)) * 7.0;
	float plank = floor(along);
	vec2 cell = vec2(plank, row);
	float across = fract(uv.y / plank_width);
	float seam = 1.0 - smoothstep(0.0, 0.05, min(across, 1.0 - across));
	float butt = 1.0 - smoothstep(0.0, 0.012, min(fract(along), 1.0 - fract(along)));
	float grain = noise(vec2(uv.x * 0.9 + hash(cell) * 40.0, uv.y * 16.0));
	float tone = 0.74 + hash(cell) * 0.42;
	vec3 base = wood_color * tone * (0.84 + grain * 0.3);
	ALBEDO = mix(base, seam_color, max(seam, butt));
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
