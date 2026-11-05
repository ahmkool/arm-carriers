shader_type canvas_item;
// Sweeps a golden glint across the logo every few seconds.

uniform float period = 6.0;
uniform float band_width = 0.07;
uniform vec3 sheen_color = vec3(1.0, 0.82, 0.38);

void fragment() {
	float sweep = fract(TIME / period) * 3.0 - 0.5;
	float distance_to_band = abs(UV.x + UV.y * 0.35 - sweep);
	float band = 1.0 - smoothstep(0.0, band_width, distance_to_band);
	COLOR.rgb = mix(COLOR.rgb, sheen_color, band * 0.85);
}
