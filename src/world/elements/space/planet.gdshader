shader_type spatial;

// A banded gas giant far below the station, lit by the sun, with a thin glowing atmosphere at its limb.
uniform vec3 band_a : source_color = vec3(0.86, 0.58, 0.38);
uniform vec3 band_b : source_color = vec3(0.55, 0.3, 0.24);
uniform vec3 band_c : source_color = vec3(0.95, 0.85, 0.7);
uniform vec3 atmosphere : source_color = vec3(0.45, 0.65, 1.0);
uniform float spin_speed = 0.004;

varying vec3 v_local;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = i.x + i.y * 57.0;
	return mix(mix(hash(n), hash(n + 1.0), f.x), mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y);
}

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	float lat = v_local.y;
	float lon = atan(v_local.z, v_local.x) + TIME * spin_speed;
	float turbulence = noise(vec2(lon * 6.0, lat * 18.0)) * 0.6 + noise(vec2(lon * 14.0, lat * 40.0)) * 0.25;
	float bands = sin(lat * 26.0 + turbulence * 2.4);
	vec3 col = mix(band_b, band_a, smoothstep(-0.6, 0.6, bands));
	col = mix(col, band_c, smoothstep(0.75, 1.0, sin(lat * 9.0 + turbulence * 3.0)) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = atmosphere * rim * 1.4;
}
