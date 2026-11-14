shader_type spatial;

// Industrial metallic skybridge deck: brushed steel diamond-plate treads, slotted steel grating
// strips, bolted transverse cross-seams, and weathered yellow/black diagonal hazard curb stripes.
uniform vec3 steel_color : source_color = vec3(0.23, 0.27, 0.34);
uniform vec3 dark_steel : source_color = vec3(0.10, 0.12, 0.16);
uniform vec3 grate_slot_color : source_color = vec3(0.03, 0.04, 0.07);
uniform vec3 hazard_yellow : source_color = vec3(0.88, 0.66, 0.10);
uniform vec3 hazard_black : source_color = vec3(0.08, 0.09, 0.11);
uniform bool local_space = true;

varying vec3 v_pos;
varying vec3 v_normal;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (local_space) {
		v_pos = VERTEX;
	}
}

float diamond_tread(vec2 p) {
	vec2 g = p * 9.0;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	float flip = mod(cell.x + cell.y, 2.0);
	vec2 r = vec2(f.x + f.y, f.x - f.y) * 0.7071;
	float major = mix(abs(r.x), abs(r.y), flip);
	float minor = mix(abs(r.y), abs(r.x), flip);
	return (1.0 - smoothstep(0.05, 0.11, minor)) * (1.0 - smoothstep(0.24, 0.34, major));
}

void fragment() {
	float is_top = step(0.5, v_normal.y);
	vec2 p = v_pos.xz;

	// Transverse riveted I-beam seam every 1.5 m along Z, and panel seam at X edges.
	vec2 f = fract((p + vec2(1.5, 1.5)) / 1.5);
	float seam_z = 1.0 - smoothstep(0.0, 0.04, min(f.y, 1.0 - f.y));
	float seam_x = 1.0 - smoothstep(0.0, 0.03, min(f.x, 1.0 - f.x));
	float seam = max(seam_z, seam_x * 0.7);

	// Rivet bolts along transverse seams.
	float bolt_x = abs(fract(p.x * 4.0) - 0.5);
	float bolt_z = min(fract((p.y + 1.5) / 1.5), 1.0 - fract((p.y + 1.5) / 1.5)) * 1.5;
	float rivet = 1.0 - smoothstep(0.022, 0.04, length(vec2(bolt_x * 0.25, abs(bolt_z - 0.08))));

	// Center-side slotted steel catwalk grate strip (local x in 0.55 .. 1.38) for industrial contrast.
	float in_grate_band = step(0.55, p.x) * step(p.x, 1.38) * (1.0 - seam_z);
	float grate_slot_x = smoothstep(0.26, 0.34, abs(fract(p.x * 11.0) - 0.5));
	float grate_bar_z = 1.0 - smoothstep(0.0, 0.06, abs(fract(p.y * 3.0) - 0.5));
	float grate_hole = in_grate_band * (1.0 - grate_slot_x) * (1.0 - grate_bar_z);

	// Outer curb diagonal yellow/black hazard stripe (local x in -1.33 .. -1.08).
	float in_hazard = step(-1.33, p.x) * step(p.x, -1.08);
	float diag = step(0.5, fract((p.x + p.y) * 2.2));
	float wear = 0.82 + 0.18 * hash21(floor(p * 18.0));
	vec3 hazard_col = mix(hazard_black, hazard_yellow, diag) * wear;

	// Brushed steel variation & diamond tread lugs.
	float brush = 0.94 + 0.12 * hash21(floor(vec2(p.x * 40.0, p.y * 3.0)));
	float lug = diamond_tread(p) * (1.0 - in_grate_band) * (1.0 - in_hazard) * (1.0 - seam);
	vec3 plate = steel_color * brush + vec3(0.09) * lug;
	plate = mix(plate, grate_slot_color, grate_hole * 0.88);
	plate = mix(plate, dark_steel, seam * 0.82);
	plate = mix(plate, steel_color * 1.3, rivet * (1.0 - in_hazard) * 0.7);
	plate = mix(plate, hazard_col, in_hazard);

	vec3 side_metal = dark_steel * 1.35;
	ALBEDO = mix(side_metal, plate, is_top);
	METALLIC = mix(0.78, mix(0.76, 0.22, in_hazard), is_top);
	ROUGHNESS = mix(0.38, mix(mix(0.46, 0.26, lug), 0.58, max(in_hazard, grate_hole)), is_top);
}
