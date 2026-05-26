shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 color_yellow : source_color = vec3(1.0, 0.82, 0.12);
uniform vec3 color_orange : source_color = vec3(1.0, 0.42, 0.05);
uniform float noise_scale : hint_range(0.5, 8.0) = 2.5;
uniform float scroll_speed : hint_range(0.0, 4.0) = 1.0;
uniform float emission_strength : hint_range(0.0, 8.0) = 3.0;

void fragment() {
	vec2 uv_a = UV * noise_scale + vec2(TIME * scroll_speed * 0.35, TIME * scroll_speed);
	vec2 uv_b = UV * noise_scale * 1.6 + vec2(-TIME * scroll_speed * 0.55, TIME * scroll_speed * 0.85);
	float noise_a = texture(noise_tex, uv_a).r;
	float noise_b = texture(noise_tex, uv_b).r;
	float blend = clamp(noise_a * 0.55 + noise_b * 0.45, 0.0, 1.0);
	vec3 flame = mix(color_orange, color_yellow, blend);
	ALBEDO = flame;
	EMISSION = flame * emission_strength;
}
