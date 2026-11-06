shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

// A hard-light bridge: a bright frame and scrolling chevrons over a faint fill, pointing the way across.
uniform vec3 light_color : source_color = vec3(0.3, 0.85, 1.0);
uniform float intensity = 1.6;
instance uniform float flicker = 0.0;

void fragment() {
	vec2 uv = UV;
	float frame = 1.0 - smoothstep(0.0, 0.05, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
	float chevron = smoothstep(0.42, 0.5, abs(fract(uv.y * 3.0 + abs(uv.x - 0.5) * 1.2 + TIME * 0.6) - 0.5));
	float scan = 0.5 + 0.5 * sin(uv.y * 40.0 - TIME * 6.0);
	float alpha = 0.18 + frame * 0.9 + chevron * 0.35 + scan * 0.05;
	alpha *= 1.0 - flicker * step(0.5, fract(TIME * 23.0));
	ALBEDO = light_color * alpha * intensity;
}
