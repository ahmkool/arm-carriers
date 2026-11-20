shader_type spatial;
render_mode blend_mix, cull_back;

// Semi-transparent rippled water-glass floor for "World of Memories" (FFX Sea of Sorrow):
// dark abyssal slate-teal glassy surface with wind-rippled wavelets, slow expanding droplet rings,
// calm inlaid astral seams, real shadow reception, and ~30% transmission so the rose-lavender
// fantasy clouds drifting below glow softly through the floor under the carriers' feet.
uniform vec3 deep_teal : source_color = vec3(0.055, 0.145, 0.215);
uniform vec3 crest_teal : source_color = vec3(0.145, 0.285, 0.365);
uniform vec3 reflection_tint : source_color = vec3(0.78, 0.69, 0.76);
uniform vec3 rune_line_color : source_color = vec3(0.38, 0.66, 0.74);
uniform float base_alpha : hint_range(0.3, 0.95) = 0.62;
uniform float tile_size = 2.999;

varying vec3 v_world_pos;

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

float memory_ripple(vec2 uv, float t) {
	vec2 cell = floor(uv);
	vec2 jitter = hash22(cell);
	float phase = fract(t * 0.28 + jitter.x * 5.7 + jitter.y * 2.3);
	vec2 centre = cell + 0.22 + jitter * 0.56;
	float dist = length(uv - centre);
	float radius = phase * 0.46;
	float ring = 1.0 - smoothstep(0.0, 0.032, abs(dist - radius));
	float echo = 1.0 - smoothstep(0.0, 0.025, abs(dist - max(radius - 0.09, 0.0)));
	return (ring + echo * 0.45) * (1.0 - phase) * smoothstep(0.0, 0.08, phase);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	float t = TIME * 0.18;

	// Anisotropic horizontal water wavelets (like the dark rippled Sea of Sorrow floor in FFX).
	float v1 = voronoi(p * vec2(0.55, 1.25) + vec2(t * 0.8, t * 0.35));
	float v2 = voronoi(p * vec2(0.95, 2.10) - vec2(t * 0.55, t * 0.25));
	float wave = smoothstep(0.24, 0.62, v1 * v2);

	float swell = 0.5 + 0.5 * sin(p.y * 2.6 + sin(p.x * 0.8 + TIME * 0.5) * 1.4 - TIME * 0.9);
	float crests = clamp(wave * 0.75 + swell * 0.18, 0.0, 1.0);

	// Gentle expanding droplet/memory rings across the glassy water sheet.
	vec2 r_uv = p / 4.2;
	float rings = memory_ripple(r_uv, TIME) + memory_ripple(r_uv + vec2(0.47, 0.61), TIME + 1.7);

	// Very calm sacred-geometry hairlines on the 3 m grid so the surface reads as an ancient sanctuary floor
	// without competing with bright combat telegraphs.
	vec2 cell_f = fract(p / tile_size);
	float border = min(min(cell_f.x, 1.0 - cell_f.x), min(cell_f.y, 1.0 - cell_f.y));
	float seam = 1.0 - smoothstep(0.0, 0.014, border);

	vec2 macro_center = (floor(p / (tile_size * 3.0)) + 0.5) * (tile_size * 3.0);
	float radial = length(p - macro_center);
	float astral_ring = (1.0 - smoothstep(0.0, 0.045, abs(radial - 3.6))) * 0.35;

	vec3 normal_pert = vec3((v1 - 0.5) * 0.14, 0.0, (v2 - 0.5) * 0.20 + (swell - 0.5) * 0.06);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(0.0, 1.0, 0.0) + normal_pert), 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	vec3 col = mix(deep_teal, crest_teal, crests);
	col = mix(col, reflection_tint * 0.52, fresnel * 0.55);
	col = mix(col, rune_line_color, clamp(seam * 0.28 + astral_ring + rings * 0.32, 0.0, 0.55));

	float alpha = base_alpha + crests * 0.07 + fresnel * 0.14 + seam * 0.10 + rings * 0.08;

	ALBEDO = col;
	ROUGHNESS = mix(0.32, 0.20, crests);
	METALLIC = 0.06;
	SPECULAR = 0.26;
	EMISSION = rune_line_color * (rings * 0.14 + astral_ring * 0.10);
	ALPHA = clamp(alpha, 0.45, 0.88);
}
