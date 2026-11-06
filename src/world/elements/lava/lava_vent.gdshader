shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;

// The vent on the ground. The rim marks exactly how far an eruption reaches, even while it is quiet.
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform vec3 scorch_color : source_color = vec3(0.08, 0.05, 0.045);
uniform vec3 idle_rim_color : source_color = vec3(0.9, 0.22, 0.03);
uniform vec3 hot_color : source_color = vec3(1.0, 0.5, 0.06);

void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	float angle = atan(UV.y - 0.5, UV.x - 0.5);
	float rim = smoothstep(0.86, 0.92, radius) * (1.0 - smoothstep(0.96, 1.0, radius));
	float spokes = pow(abs(sin(angle * 3.5 + radius * 5.0)), 10.0) * (1.0 - smoothstep(0.0, 0.8, radius));
	float filled = (1.0 - smoothstep(fill - 0.05, fill, radius)) * step(0.001, fill);
	vec3 glow = idle_rim_color * (rim * (0.85 + heat) + spokes * 0.35);
	glow += hot_color * filled * (0.45 + heat * 0.5);
	ALBEDO = glow * 2.0 + scorch_color;
	ALPHA = (1.0 - smoothstep(0.97, 1.0, radius)) * 0.92;
}
