shader_type spatial;
// The enemy shield's bubble: faint in the middle, bright at the rim, so the enemy inside
// stays readable while the outline reads as a shell. `flash` lights it all up on a hit.
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 shield_color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float base_alpha = 0.12;
uniform float rim_alpha = 0.75;
uniform float rim_power = 2.5;
uniform float flash = 0.0;
uniform float fade = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float alpha = base_alpha + rim * rim_alpha + flash * 0.45;
	ALBEDO = mix(shield_color.rgb, vec3(1.0), flash * 0.6);
	ALPHA = clamp(alpha, 0.0, 1.0) * fade;
}
