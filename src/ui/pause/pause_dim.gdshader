shader_type canvas_item;
// Pause backdrop: blurs, desaturates and darkens the frozen game. strength 0 leaves the picture untouched.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float blur_lod = 2.6;
uniform float desaturation = 0.55;
uniform float vignette = 0.3;

void fragment() {
	vec3 scene = textureLod(screen_texture, SCREEN_UV, blur_lod * strength).rgb;
	float gray = dot(scene, vec3(0.299, 0.587, 0.114));
	scene = mix(scene, vec3(gray), desaturation * strength);
	float edge = smoothstep(0.35, 0.95, distance(UV, vec2(0.5))) * vignette;
	float darkening = clamp((COLOR.a + edge) * strength, 0.0, 1.0);
	COLOR = vec4(mix(scene, COLOR.rgb, darkening), 1.0);
}
