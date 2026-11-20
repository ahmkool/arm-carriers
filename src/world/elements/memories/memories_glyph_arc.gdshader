shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;

// Sweeping curved spectral rune/glyph ribbon inspired by Final Fantasy X's Yu Yevon / Inside Sin arcs.
// Bends a subdivided PlaneMesh (size.x = span, size.y = width) into a 3D circular arch in vertex(),
// and renders twin bands of scrolling circular spiral-glyphs in dark indigo & luminous silver-ivory.
uniform float arc_radius = 16.0;
uniform float arc_angle_radians = 2.35;
uniform float ribbon_tilt = 0.42;
uniform float scroll_speed = 0.18;
uniform float glyph_density = 18.0;
uniform vec3 ink_color : source_color = vec3(0.11, 0.15, 0.26);
uniform vec3 glow_color : source_color = vec3(0.86, 0.95, 1.0);
uniform float glow_strength = 1.35;
uniform float opacity : hint_range(0.0, 1.0) = 0.82;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Procedural FFX-style circular spiral/crescent rune inside a [0..1]^2 cell.
float rune_glyph(vec2 cell_uv, float seed) {
	vec2 p = (cell_uv - 0.5) * 2.2;
	float r = length(p);
	float ang = atan(p.y, p.x);

	float rot = seed * 6.2831853;
	float a1 = mod(ang + rot + 3.14159265, 6.2831853) - 3.14159265;
	float a2 = mod(ang - rot * 1.7 + 3.14159265, 6.2831853) - 3.14159265;

	// Outer broken ring + inner eccentric crescent + calligraphic radial stroke.
	float outer_arc = (1.0 - smoothstep(0.0, 0.10, abs(r - 0.72))) * step(-1.8, a1) * step(a1, 1.4);
	vec2 inner_off = vec2(cos(rot), sin(rot)) * 0.18;
	float inner_r = length(p - inner_off);
	float inner_arc = (1.0 - smoothstep(0.0, 0.095, abs(inner_r - 0.38))) * step(-1.3, a2) * step(a2, 1.9);

	vec2 dir = vec2(cos(rot * 0.5), sin(rot * 0.5));
	float proj = clamp(dot(p, dir), -0.78, 0.78);
	float stem = (1.0 - smoothstep(0.0, 0.075, length(p - dir * proj))) * step(0.35, fract(seed * 7.3));
	float dot_mark = 1.0 - smoothstep(0.0, 0.13, length(p + inner_off * 1.9));

	return clamp(outer_arc + inner_arc + stem * 0.85 + dot_mark * 0.9, 0.0, 1.0);
}

void vertex() {
	float u = UV.x;
	float theta = (u - 0.5) * arc_angle_radians;
	float base_y = cos(arc_angle_radians * 0.5) * arc_radius;

	vec3 radial = vec3(sin(theta), cos(theta), 0.0);
	vec3 side = normalize(vec3(0.0, sin(ribbon_tilt), cos(ribbon_tilt)));
	// VERTEX.z holds the PlaneMesh's cross-ribbon coordinate (-width/2 .. +width/2).
	float cross_coord = VERTEX.z;

	vec3 center = vec3(sin(theta) * arc_radius, cos(theta) * arc_radius - base_y, 0.0);
	VERTEX = center + (side * cos(ribbon_tilt) + radial * sin(ribbon_tilt) * 0.35) * cross_coord;
	NORMAL = normalize(cross(vec3(cos(theta), -sin(theta), 0.0), side));
}

void fragment() {
	float end_fade = smoothstep(0.0, 0.14, UV.x) * smoothstep(1.0, 0.86, UV.x);

	// Twin parallel rune tracks like the double curving glyph arc in Final Fantasy X.
	float track_v = UV.y * 2.0;
	float track_id = floor(track_v);
	vec2 local = vec2(UV.x * glyph_density - TIME * scroll_speed * (1.0 + track_id * 0.35), fract(track_v));
	float cell_idx = floor(local.x);
	vec2 cell_uv = vec2(fract(local.x), local.y);

	// Leave breathing gaps between clusters of runes along the arc.
	float cluster = smoothstep(0.18, 0.32, hash21(vec2(floor(cell_idx * 0.35), track_id + 3.0)));
	float seed = hash21(vec2(cell_idx, track_id * 13.7 + 1.9));
	float glyph = rune_glyph(cell_uv, seed) * cluster;

	// Subtle luminous guide filament and halo around each dark/glowing rune stroke.
	float track_margin = smoothstep(0.04, 0.16, cell_uv.y) * smoothstep(0.96, 0.84, cell_uv.y);
	float guide = (1.0 - smoothstep(0.0, 0.035, abs(cell_uv.y - 0.5))) * 0.16;

	float halo = rune_glyph((cell_uv - 0.5) * 0.90 + 0.5, seed) * cluster;
	float glow_ring = clamp(halo - glyph * 0.55, 0.0, 1.0);

	vec3 col = mix(glow_color * glow_strength, ink_color, glyph * 0.72);
	float alpha = (glyph * 0.88 + glow_ring * 0.42 + guide * cluster) * track_margin * end_fade * opacity;

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
