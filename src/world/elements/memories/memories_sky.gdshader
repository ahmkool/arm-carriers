shader_type sky;

// Dreamlike twilight sky inspired by Final Fantasy X ("Inside Sin / Sea of Sorrow"):
// dusty rose-blush clouds, pale peach-ivory horizon glow, muted lavender-mauve zenith,
// and a soft silver-pearl upper sheen so metallic weapons reflect cleanly without tinting dark.
uniform vec3 zenith_color : source_color = vec3(0.44, 0.43, 0.54);
uniform vec3 upper_rose_color : source_color = vec3(0.83, 0.66, 0.72);
uniform vec3 horizon_glow_color : source_color = vec3(0.95, 0.86, 0.82);
uniform vec3 lower_mist_color : source_color = vec3(0.46, 0.48, 0.57);
uniform vec3 abyss_color : source_color = vec3(0.28, 0.31, 0.40);
uniform vec3 sun_dir = vec3(-0.22, 0.34, -0.91);

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

	// Base vertical gradient from lavender zenith through rose-blush mid-sky to pale peach horizon.
	vec3 sky_grad = mix(horizon_glow_color, upper_rose_color, smoothstep(0.0, 0.24, up));
	sky_grad = mix(sky_grad, zenith_color, smoothstep(0.20, 0.82, up));

	// Painterly wind-stretched cloud bands in the upper dome.
	vec2 dome_uv = dir.xz / max(abs(dir.y) + 0.18, 0.18);
	float streak_a = fbm(dome_uv * vec2(0.55, 1.45) + vec2(TIME * 0.006, -TIME * 0.002));
	float streak_b = fbm(dome_uv * vec2(1.15, 2.8) - vec2(TIME * 0.009, 0.0));
	float band_mask = smoothstep(0.02, 0.55, up) * (1.0 - smoothstep(0.65, 0.98, up));
	vec3 cloud_tint = mix(vec3(0.52, 0.50, 0.60), vec3(0.94, 0.80, 0.82), streak_a);
	sky_grad = mix(sky_grad, cloud_tint, band_mask * smoothstep(0.32, 0.78, streak_b) * 0.55);

	// Lower hemisphere blends smoothly into misty lavender-slate beneath the cloud sea.
	vec3 lower_grad = mix(horizon_glow_color * 0.92, lower_mist_color, smoothstep(0.0, 0.28, down));
	lower_grad = mix(lower_grad, abyss_color, smoothstep(0.25, 0.85, down));
	vec3 col = mix(sky_grad, lower_grad, step(dir.y, 0.0));

	// Soft horizon veil and diffused celestial glow toward north-northwest.
	float horizon_veil = exp(-abs(dir.y) * 9.0);
	col = mix(col, horizon_glow_color, horizon_veil * 0.48);

	vec3 sdir = normalize(sun_dir);
	float sun_align = max(dot(dir, sdir), 0.0);
	col += vec3(0.24, 0.18, 0.18) * pow(sun_align, 5.0);
	col += vec3(0.38, 0.34, 0.36) * pow(sun_align, 28.0);

	COLOR = col;
}
