shader_type sky;

// Mystical Uranian gas-atmosphere sky: deep sapphire-indigo zenith, swirling cerulean & glacial
// cyan banded clouds, ethereal moonlit aquamarine horizon haze, soft drifting magical aurora veils,
// and faint starlight above — fantastical and enchanted rather than sci-fi.
uniform vec3 zenith_color : source_color = vec3(0.05, 0.14, 0.30);
uniform vec3 upper_cerulean : source_color = vec3(0.14, 0.42, 0.64);
uniform vec3 mid_turquoise : source_color = vec3(0.32, 0.72, 0.86);
uniform vec3 horizon_glow_color : source_color = vec3(0.68, 0.93, 0.98);
uniform vec3 lower_mist_color : source_color = vec3(0.11, 0.34, 0.54);
uniform vec3 abyss_color : source_color = vec3(0.03, 0.10, 0.22);
uniform vec3 moon_dir = vec3(-0.30, 0.38, -0.87);

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x);
	float b = mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x);
	return mix(a, b, u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p = p * 2.04 + vec2(11.7, 5.3);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, 0.0, 1.0);
	float down = clamp(-dir.y, 0.0, 1.0);

	// Base vertical gas-giant gradient: pale aquamarine horizon -> cerulean -> deep mystical sapphire.
	vec3 sky_grad = mix(horizon_glow_color, mid_turquoise, smoothstep(0.0, 0.22, up));
	sky_grad = mix(sky_grad, upper_cerulean, smoothstep(0.16, 0.56, up));
	sky_grad = mix(sky_grad, zenith_color, smoothstep(0.45, 0.92, up));

	// Swirling Uranian gas-atmosphere cloud ribbons across the dome.
	vec2 dome_uv = dir.xz / max(abs(dir.y) + 0.20, 0.20);
	float swirl_a = fbm(dome_uv * vec2(0.45, 1.65) + vec2(TIME * 0.008, -TIME * 0.003));
	float swirl_b = fbm(dome_uv * vec2(1.05, 2.90) + vec2(swirl_a * 0.55 - TIME * 0.011, 0.2));
	float band_mask = smoothstep(0.02, 0.48, up) * (1.0 - smoothstep(0.68, 0.98, up));
	vec3 gas_tint = mix(vec3(0.16, 0.44, 0.68), vec3(0.72, 0.96, 1.0), swirl_a);
	sky_grad = mix(sky_grad, gas_tint, band_mask * smoothstep(0.30, 0.78, swirl_b) * 0.52);

	// Soft magical aurora veil high in the blue atmosphere.
	float aurora_wave = sin(dome_uv.x * 1.4 + swirl_a * 3.2 + TIME * 0.14) * 0.5 + 0.5;
	float aurora_band = smoothstep(0.22, 0.58, up) * (1.0 - smoothstep(0.62, 0.90, up));
	float aurora = pow(aurora_wave, 3.0) * smoothstep(0.42, 0.80, swirl_b) * aurora_band;
	sky_grad += mix(vec3(0.20, 0.85, 0.92), vec3(0.48, 0.56, 0.98), swirl_a) * aurora * 0.32;

	// Faint twinkling starlight peeking through the upper sapphire veil.
	vec2 star_cell = floor(dome_uv * 28.0);
	float star_rand = hash21(star_cell);
	float star_dist = length(fract(dome_uv * 28.0) - 0.5);
	float star = step(0.988, star_rand) * (1.0 - smoothstep(0.0, 0.22, star_dist));
	float twinkle = 0.65 + 0.35 * sin(TIME * 2.2 + star_rand * 40.0);
	sky_grad += vec3(0.82, 0.96, 1.0) * star * twinkle * smoothstep(0.28, 0.75, up) * 0.75;

	// Lower hemisphere dissolves into deep blue-cyan gas clouds below the floating platforms.
	vec3 lower_grad = mix(horizon_glow_color * 0.85, lower_mist_color, smoothstep(0.0, 0.30, down));
	lower_grad = mix(lower_grad, abyss_color, smoothstep(0.26, 0.86, down));
	vec3 col = mix(sky_grad, lower_grad, step(dir.y, 0.0));

	// Ethereal horizon mist band and diffused celestial glow.
	float horizon_veil = exp(-abs(dir.y) * 8.0);
	col = mix(col, horizon_glow_color, horizon_veil * 0.52);

	vec3 mdir = normalize(moon_dir);
	float moon_align = max(dot(dir, mdir), 0.0);
	col += vec3(0.18, 0.42, 0.56) * pow(moon_align, 5.0);
	col += vec3(0.55, 0.88, 0.98) * pow(moon_align, 32.0);

	COLOR = col;
}
