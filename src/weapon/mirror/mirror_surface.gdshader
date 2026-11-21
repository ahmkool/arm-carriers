shader_type spatial;
render_mode cull_back;

// Mystical celestial mirror glass: cool silver-aquamarine sheen with subtle astral ripples,
// bright Fresnel reflection, fine arcane border inlay, and a brilliant flare on absorb/laser bounce.
uniform vec3 mirror_base : source_color = vec3(0.46, 0.78, 0.90);
uniform vec3 mirror_highlight : source_color = vec3(0.88, 0.98, 1.0);
uniform vec3 arcane_tint : source_color = vec3(0.32, 0.88, 1.0);
uniform vec3 fire_tint : source_color = vec3(1.0, 0.20, 0.14);
uniform float flash : hint_range(0.0, 1.5) = 0.0;
uniform float laser_glow : hint_range(0.0, 1.5) = 0.0;
uniform float fire_charge : hint_range(0.0, 1.5) = 0.0;

void fragment() {
	vec2 uv = UV;
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float inner_border = 1.0 - smoothstep(0.025, 0.065, abs(edge - 0.055));

	// Subtle drifting diagonal specular sheen across the polished arcane glass.
	float sweep = sin((uv.x * 3.8 + uv.y * 2.2) - TIME * 1.4) * 0.5 + 0.5;
	float glint = smoothstep(0.76, 0.98, sweep) * 0.35;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float energy = clamp(flash + laser_glow * 0.85, 0.0, 1.5);
	float fire_energy = clamp(fire_charge, 0.0, 1.5);

	vec3 col = mix(mirror_base, mirror_highlight, clamp(fresnel * 0.72 + glint, 0.0, 1.0));
	col = mix(col, arcane_tint, inner_border * 0.45);
	col = mix(col, vec3(0.95, 1.0, 1.0), clamp(energy * 0.6, 0.0, 0.85));
	col = mix(col, fire_tint, clamp(fire_energy * 0.45, 0.0, 0.65));

	vec3 base_emission = mix(arcane_tint, mirror_highlight, 0.55) * (0.28 + inner_border * 0.45 + fresnel * 0.35 + energy * 1.6);
	vec3 red_emission = fire_tint * (fire_energy * (0.75 + inner_border * 0.85 + fresnel * 0.5));

	ALBEDO = col;
	METALLIC = 0.88;
	ROUGHNESS = mix(0.09, 0.04, clamp(energy + fire_energy, 0.0, 1.0));
	SPECULAR = 0.92;
	EMISSION = base_emission + red_emission;
}
