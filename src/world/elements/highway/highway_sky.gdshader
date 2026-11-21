shader_type sky;

// Dramatic twilight-sunset highway sky: warm amber/crimson glow on the northern horizon
// where the highway heads, deep twilight indigo overhead, and dark city dusk below.
uniform vec3 zenith_color : source_color = vec3(0.055, 0.075, 0.175);
uniform vec3 mid_sky_color : source_color = vec3(0.18, 0.14, 0.30);
uniform vec3 horizon_color : source_color = vec3(0.92, 0.44, 0.24);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.72, 0.38);
uniform vec3 abyss_color : source_color = vec3(0.035, 0.04, 0.085);
uniform vec3 sun_dir = vec3(-0.18, 0.12, -0.97);

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, 0.0, 1.0);
	float down = clamp(-dir.y, 0.0, 1.0);

	vec3 upper = mix(horizon_color, mid_sky_color, smoothstep(0.0, 0.28, up));
	upper = mix(upper, zenith_color, smoothstep(0.22, 0.78, up));

	vec3 base = mix(upper, abyss_color, smoothstep(0.0, 0.35, down));

	// Warm sunset band wrapping around the horizon.
	float horizon_band = exp(-abs(dir.y) * 9.0);
	base += horizon_color * horizon_band * 0.28;

	// Low sun halo ahead of the highway convoy.
	vec3 sdir = normalize(sun_dir);
	float sun_align = max(dot(dir, sdir), 0.0);
	vec3 sun_halo = sun_glow_color * pow(sun_align, 10.0) * 0.65;
	vec3 sun_disc = vec3(1.15, 0.92, 0.68) * smoothstep(0.9965, 0.9988, sun_align);

	COLOR = base + sun_halo + sun_disc;
}
