shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec3 color_yellow : source_color = vec3(1.0, 0.82, 0.12);
uniform vec3 color_orange : source_color = vec3(1.0, 0.42, 0.05);
uniform float noise_scale : hint_range(0.5, 8.0) = 2.5;
uniform float scroll_speed : hint_range(0.0, 4.0) = 1.0;
uniform float fire_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float emission_strength : hint_range(0.0, 8.0) = 3.0;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	float coverage = base.a;
	vec2 uv_a = UV * noise_scale + vec2(TIME * scroll_speed * 0.35, TIME * scroll_speed);
	vec2 uv_b = UV * noise_scale * 1.6 + vec2(-TIME * scroll_speed * 0.55, TIME * scroll_speed * 0.85);
	float noise_a = texture(noise_tex, uv_a).r;
	float noise_b = texture(noise_tex, uv_b).r;
	float blend = clamp(noise_a * 0.55 + noise_b * 0.45, 0.0, 1.0);
	vec3 fire = mix(color_orange, color_yellow, blend);
	float fire_mask = smoothstep(0.2, 0.8, blend) * fire_intensity * coverage;
	float hot = smoothstep(0.55, 0.95, blend);
	vec3 fire_colors = mix(fire, color_yellow, hot * 0.5);
	float enraged = step(0.001, fire_intensity);
	ALBEDO = mix(base.rgb, fire_colors, fire_mask);
	EMISSION = fire_colors * fire_mask * emission_strength;
	ALPHA = coverage;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	ROUGHNESS = mix(0.5, 0.35, enraged);
	METALLIC = 0.2 * enraged;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
