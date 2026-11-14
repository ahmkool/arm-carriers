shader_type sky;

// Midnight urban sky: starry zenith, cool moonlight reflection sheen for metal surfaces,
// subtle city light-pollution glow near the horizon, and deep indigo abyss below.
uniform vec3 zenith_color : source_color = vec3(0.025, 0.042, 0.095);
uniform vec3 horizon_color : source_color = vec3(0.085, 0.145, 0.28);
uniform vec3 city_glow_color : source_color = vec3(0.18, 0.12, 0.22);
uniform vec3 abyss_color : source_color = vec3(0.012, 0.018, 0.042);
uniform vec3 moon_dir = vec3(0.0, 0.62, -0.78);
uniform float star_brightness = 1.6;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
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
	return smoothstep(0.085, 0.0, d) * (h - threshold) / (1.0 - threshold);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, 0.0, 1.0);
	float down = clamp(-dir.y, 0.0, 1.0);

	vec3 upper = mix(horizon_color, zenith_color, pow(up, 0.55));
	float horizon_band = exp(-abs(dir.y) * 7.5);
	vec3 base = mix(upper, abyss_color, smoothstep(0.0, 0.42, down));
	base += city_glow_color * horizon_band * 0.55;

	// Soft moonlit sheen in the upper sky so metallic bridges and blades catch cool highlights.
	vec3 mdir = normalize(moon_dir);
	float moon_align = max(dot(dir, mdir), 0.0);
	vec3 moon_halo = vec3(0.32, 0.44, 0.68) * pow(moon_align, 6.0) * 0.55;
	vec3 moon_disc = vec3(0.85, 0.92, 1.15) * smoothstep(0.996, 0.9985, moon_align);

	float star_mask = smoothstep(0.05, 0.35, dir.y);
	float s = stars(dir, 130.0, 0.945) + stars(dir, 70.0, 0.985) * 1.5;
	float twinkle = 0.8 + 0.2 * sin(TIME * 1.8 + hash3(floor(dir * 130.0)) * 30.0);

	COLOR = base + moon_halo + moon_disc + vec3(0.78, 0.88, 1.0) * s * star_brightness * twinkle * star_mask;
}
