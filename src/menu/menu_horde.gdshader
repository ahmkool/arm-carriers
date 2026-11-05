shader_type canvas_item;
// The skeleton horde is one baked image, so a travelling wave makes it look like it is marching.

uniform float march_amount = 0.002;
uniform float march_speed = 3.2;
uniform float march_frequency = 20.0;
uniform float sway_amount = 0.0008;

varying vec4 layer_tint;

void vertex() {
	layer_tint = COLOR;
}

void fragment() {
	vec2 uv = UV;
	uv.y += sin(UV.x * march_frequency + TIME * march_speed) * march_amount;
	uv.x += cos(UV.y * 6.0 + TIME * march_speed * 0.6) * sway_amount;
	COLOR = texture(TEXTURE, uv) * layer_tint;
}
