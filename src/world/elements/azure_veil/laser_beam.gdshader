shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

// Mystical arcane light-stream shader for map laser beams: bright celestial cyan-gold ribbons
// scrolling along the beam length with soft Fresnel edge falloff.
uniform vec3 core_color : source_color = vec3(0.85, 0.98, 1.0);
uniform vec3 aura_color : source_color = vec3(0.22, 0.78, 1.0);
uniform float intensity = 2.4;
uniform float scroll_speed = 4.2;
uniform float alpha_scale : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	float fresnel = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float pulse_wave = 0.72 + 0.28 * sin(UV.y * 26.0 - TIME * scroll_speed * 6.28318);
	float spiral = 0.78 + 0.22 * sin(UV.x * 12.566 + UV.y * 14.0 - TIME * scroll_speed * 4.0);

	vec3 col = mix(aura_color, core_color, pow(fresnel, 1.8));
	float alpha = pow(fresnel, 0.75) * pulse_wave * spiral * alpha_scale;

	ALBEDO = col * intensity;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
