shader_type spatial;
render_mode cull_disabled;

// Heraldic cloth for banners and pennants, on a subdivided QuadMesh. Colours are per instance,
// so one material serves every banner in a level (set them with instance_shader_parameters).
// pennant = false: a banner pinned along its top edge, swallowtail at the bottom, swaying in the wind.
// pennant = true: a triangular pennant pinned along its left edge, rippling outwards.
instance uniform vec3 field_color : source_color = vec3(0.62, 0.1, 0.1);
instance uniform vec3 charge_color : source_color = vec3(0.95, 0.76, 0.25);
// 0 cross, 1 chevron, 2 bend (diagonal stripe), 3 plain with a roundel.
instance uniform int charge = 0;
uniform bool pennant = false;
uniform float sway = 0.07;
uniform float wind_speed = 1.7;

varying float v_free;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = world.x * 0.53 + world.z * 0.31;
	// How far this vertex is from the pinned edge, 0 to 1.
	v_free = pennant ? UV.x : UV.y;
	float along = pennant ? UV.x * 5.0 : UV.y * 3.0;
	float wave = sin(TIME * wind_speed * (pennant ? 2.6 : 1.0) + phase + along) * 0.7
		+ sin(TIME * wind_speed * 1.9 + phase * 1.7 + along * 1.6) * 0.3;
	// A banner hangs against a wall, so it only billows outwards from it; a pennant flaps both ways.
	float push = pennant ? wave * 2.0 : wave * 0.5 + 0.5;
	VERTEX.z += push * sway * v_free;
	if (pennant) {
		VERTEX.y += sin(TIME * wind_speed * 1.3 + phase + UV.x * 3.0) * 0.06 * UV.x;
	}
}

float band(float d, float width) {
	return 1.0 - smoothstep(width - 0.012, width + 0.012, abs(d));
}

float charge_mask(vec2 uv) {
	if (charge == 0) {
		return max(band(uv.x - 0.5, 0.09), band(uv.y - 0.4, 0.065));
	}
	if (charge == 1) {
		return band(uv.y - 0.62 + abs(uv.x - 0.5) * 0.9, 0.06);
	}
	if (charge == 2) {
		return band((uv.x - uv.y * 0.42) - 0.3, 0.1);
	}
	return 1.0 - smoothstep(0.2, 0.215, length((uv - vec2(0.5, 0.38)) * vec2(1.0, 0.43)));
}

void fragment() {
	vec2 uv = UV;
	if (pennant && abs(uv.y - 0.5) > 0.5 * (1.0 - uv.x)) {
		discard;
	}
	if (!pennant && uv.y > 0.84 && abs(uv.x - 0.5) < (uv.y - 0.84) * 2.6) {
		discard;
	}
	vec3 color = field_color;
	if (!pennant) {
		float trim = 1.0 - step(0.055, min(uv.x, 1.0 - uv.x));
		trim = max(trim, 1.0 - step(0.035, uv.y));
		color = mix(color, charge_color, max(trim, charge_mask(uv)));
	}
	if (pennant) {
		color = mix(color, charge_color, step(0.82, fract(uv.x * 2.5)) * step(uv.x, 0.75));
	}
	// Folds catch the light a little differently; darker at the free edge reads as depth from above.
	ALBEDO = color * (0.92 - v_free * 0.12);
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	BACKLIGHT = color * 0.35;
}
