shader_type spatial;

// Weathered timber for the forest bridge platforms, drawn in the mesh's local space so it travels with the platform
// as it rises and sinks. Top faces are a plank deck with staggered butt joints, grain, knots and nail heads;
// the sides are vertical posts with deep grooves, getting darker and mossier toward the base.
// The deck stays a warm, mid tone so enemies and the sword read clearly on it.
uniform vec3 wood_color : source_color = vec3(0.56, 0.38, 0.22);
uniform vec3 wood_alt_color : source_color = vec3(0.45, 0.3, 0.17);
uniform vec3 seam_color : source_color = vec3(0.1, 0.06, 0.035);
uniform vec3 post_color : source_color = vec3(0.34, 0.23, 0.14);
uniform vec3 moss_color : source_color = vec3(0.22, 0.34, 0.12);
uniform vec3 nail_color : source_color = vec3(0.16, 0.15, 0.15);
uniform float plank_width = 0.5;
uniform float plank_length = 1.5;
uniform float post_width = 0.375;
uniform float moss_height = 2.2;

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

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.3 + 7.1) * 0.3 + noise(p * 5.1 + 3.4) * 0.15;
}

// Wood grain: stretched noise warped into slow wavy rings. u runs along the board, v across it.
float grain(vec2 uv, float seed) {
	float warp = fbm(vec2(uv.x * 0.5 + seed, uv.y * 1.5)) * 2.0;
	float rings = sin((uv.y * 9.0 + warp * 3.0) * 3.14159 + seed) * 0.5 + 0.5;
	float fibres = noise(vec2(uv.x * 0.8 + seed * 3.0, uv.y * 40.0));
	return rings * 0.6 + fibres * 0.4;
}

void vertex() {
	v_pos = VERTEX;
	v_normal = NORMAL;
}

void deck(vec2 xz, out vec3 color, out float groove) {
	float row = floor(xz.y / plank_width);
	float along = xz.x / plank_length + hash(vec2(row, 3.0)) * 7.0;
	vec2 cell = vec2(floor(along), row);
	vec2 local = vec2(fract(along) * plank_length, fract(xz.y / plank_width) * plank_width);
	float id = hash(cell);

	float edge_across = min(local.y, plank_width - local.y);
	float edge_along = min(local.x, plank_length - local.x);
	float seam = 1.0 - smoothstep(0.0, 0.045, edge_across);
	float butt = 1.0 - smoothstep(0.0, 0.03, edge_along);
	float bevel = smoothstep(0.0, 0.1, edge_across);
	groove = max(seam, butt);

	vec3 tone = mix(wood_color, wood_alt_color, step(0.55, id));
	float g = grain(vec2(xz.x + id * 50.0, local.y / plank_width), id * 20.0);
	vec3 base = tone * (0.8 + id * 0.3) * (0.82 + g * 0.36);
	base *= 0.88 + bevel * 0.12;

	vec2 knot_pos = vec2(0.2 + hash(cell + 5.0) * 0.6, 0.5) * vec2(plank_length, plank_width);
	float knot = (1.0 - smoothstep(0.03, 0.11, length((local - knot_pos) * vec2(0.6, 1.0)))) * step(0.72, hash(cell + 9.0));
	base = mix(base, base * 0.45, knot);

	// A nail near each end of every plank.
	float nail_a = 1.0 - smoothstep(0.018, 0.03, length(local - vec2(0.13, plank_width * 0.5)));
	float nail_b = 1.0 - smoothstep(0.018, 0.03, length(local - vec2(plank_length - 0.13, plank_width * 0.5)));
	base = mix(base, nail_color, max(nail_a, nail_b));

	float wear = fbm(xz * 1.3 + 4.0);
	base *= 0.9 + wear * 0.18;
	color = base;
}

void side(vec3 pos, out vec3 color, out float groove) {
	float u = pos.x + pos.z;
	float col = floor(u / post_width);
	float x_local = fract(u / post_width);
	float id = hash(vec2(col, 11.0));
	groove = 1.0 - smoothstep(0.0, 0.07, min(x_local, 1.0 - x_local));
	float g = grain(vec2(pos.y * 1.2 + id * 30.0, x_local), id * 13.0);
	vec3 base = post_color * (0.75 + id * 0.35) * (0.8 + g * 0.4);
	// Rope-like iron bands at intervals down the post.
	float band = 1.0 - smoothstep(0.03, 0.06, abs(fract(pos.y / 1.7 + 0.1) - 0.5) - 0.44);
	base = mix(base, nail_color * 1.4, band * 0.8);
	float depth_dark = smoothstep(0.0, -5.0, pos.y);
	base *= 1.0 - depth_dark * 0.45;
	float moss = smoothstep(0.45, 0.7, fbm(vec2(u * 1.1, pos.y * 0.9) + 2.0));
	float low = 1.0 - smoothstep(-5.18, -5.18 + moss_height, pos.y + (fbm(vec2(u, pos.y)) - 0.5) * 1.0);
	base = mix(base, moss_color, moss * low * 0.85);
	color = base;
}

void fragment() {
	bool is_top = v_normal.y > 0.7;
	vec3 wood;
	float groove;
	if (is_top) {
		deck(v_pos.xz, wood, groove);
	} else {
		side(v_pos, wood, groove);
	}
	ALBEDO = mix(wood, seam_color, groove * 0.85);
	ROUGHNESS = is_top ? 0.82 : 0.9;
	SPECULAR = 0.25;
}
