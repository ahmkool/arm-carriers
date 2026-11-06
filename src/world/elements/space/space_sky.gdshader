shader_type sky;

// Deep space: three layers of stars and a faint nebula. Below the horizon too, since the camera looks down past the decks.
uniform vec3 void_color : source_color = vec3(0.004, 0.006, 0.016);
uniform vec3 nebula_a : source_color = vec3(0.16, 0.05, 0.28);
uniform vec3 nebula_b : source_color = vec3(0.02, 0.12, 0.26);
uniform float star_brightness = 2.2;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float stars(vec3 dir, float scale, float threshold) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash3(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 offset = vec3(hash3(cell + 3.1), hash3(cell + 7.7), hash3(cell + 1.3)) - 0.5;
	float d = length(f - offset * 0.6);
	return smoothstep(0.09, 0.0, d) * (h - threshold) / (1.0 - threshold);
}

void sky() {
	vec3 dir = EYEDIR;
	float n = fbm(dir * 2.4 + vec3(4.0, 1.0, 7.0));
	float m = fbm(dir * 4.0 - vec3(2.0, 9.0, 1.0));
	vec3 nebula = nebula_a * smoothstep(0.45, 0.8, n) + nebula_b * smoothstep(0.5, 0.85, m);
	float s = stars(dir, 140.0, 0.93) + stars(dir, 260.0, 0.95) * 0.7 + stars(dir, 60.0, 0.985) * 1.6;
	float twinkle = 0.75 + 0.25 * sin(TIME * 2.0 + hash3(floor(dir * 140.0)) * 40.0);
	vec3 star_tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.75), hash3(floor(dir * 60.0)));
	COLOR = void_color + nebula + star_tint * s * star_brightness * twinkle;
}
