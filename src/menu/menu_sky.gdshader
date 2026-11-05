shader_type canvas_item;
// Gives the baked sky image slow-moving clouds: warps the picture slightly and adds drifting wisps.

uniform float warp_amount = 0.006;
uniform float wisp_strength = 0.4;
uniform float wisp_speed = 0.014;

varying vec4 layer_tint;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float bottom = mix(hash(cell), hash(cell + vec2(1.0, 0.0)), u.x);
	float top = mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), u.x);
	return mix(bottom, top, u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	layer_tint = COLOR;
}

void fragment() {
	vec2 warp = vec2(sin(UV.y * 5.0 + TIME * 0.13), cos(UV.x * 4.0 + TIME * 0.1));
	vec4 sky = texture(TEXTURE, UV + warp * warp_amount);
	float noise = fbm(UV * vec2(3.0, 6.0) + vec2(TIME * wisp_speed, TIME * wisp_speed * 0.2));
	float upper_sky = 1.0 - smoothstep(0.1, 0.7, UV.y);
	float wisps = smoothstep(0.48, 0.78, noise) * upper_sky * wisp_strength;
	sky.rgb = mix(sky.rgb, vec3(1.0), wisps);
	COLOR = sky * layer_tint;
}
