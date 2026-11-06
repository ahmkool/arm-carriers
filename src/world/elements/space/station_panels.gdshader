shader_type spatial;

// Metal deck plating laid out in world space, so decks of any shape tile with no UVs.
// Tops are calm grey panels; side faces are dark hull ribs with a lit window band, so edges read as a drop.
uniform vec3 panel_color : source_color = vec3(0.4, 0.43, 0.48);
uniform vec3 seam_color : source_color = vec3(0.16, 0.18, 0.22);
uniform vec3 hull_color : source_color = vec3(0.2, 0.22, 0.27);
uniform vec3 window_color : source_color = vec3(0.35, 0.85, 1.0);
uniform float panel_size = 1.5;
uniform float window_strength = 2.2;

varying vec3 v_pos;
varying vec3 v_normal;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 top_plating(vec2 p) {
	vec2 cell = floor(p / panel_size);
	vec2 f = fract(p / panel_size);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float seam = 1.0 - smoothstep(0.0, 0.025, edge);
	float tone = 0.88 + hash(cell) * 0.2;
	vec3 base = panel_color * tone;
	// Some panels are gratings: fine parallel slots.
	float is_grate = step(0.82, hash(cell + 17.0));
	float slots = smoothstep(0.35, 0.5, abs(fract(f.x * 9.0) - 0.5)) * is_grate * step(0.1, edge);
	base = mix(base, seam_color * 1.3, slots * 0.7);
	// A bolt near each panel corner.
	float bolt = 1.0 - smoothstep(0.015, 0.03, length(abs(f - 0.5) - 0.42));
	base = mix(base, seam_color * 1.6, bolt * 0.6);
	return mix(base, seam_color, seam);
}

void fragment() {
	bool is_top = v_normal.y > 0.5;
	if (is_top) {
		ALBEDO = top_plating(v_pos.xz);
		METALLIC = 0.35;
		ROUGHNESS = 0.55;
	} else {
		float along = v_pos.x + v_pos.z;
		float rib = smoothstep(0.42, 0.5, abs(fract(along / 0.75) - 0.5));
		float band = 1.0 - smoothstep(0.08, 0.12, abs(v_pos.y + 1.55));
		float lit = step(0.35, hash(vec2(floor(along / 0.75), 5.0)));
		ALBEDO = mix(hull_color, hull_color * 0.55, rib);
		EMISSION = window_color * band * lit * window_strength * (1.0 - rib);
		METALLIC = 0.4;
		ROUGHNESS = 0.6;
	}
}
