shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A flat sheet of blowing sand. Patchy noise in world space scrolls along the wind, so the sheet can follow the camera
// while the sand itself keeps drifting across the ground. Stack a few at different heights for a rolling haze.
// Where the sheet cuts through walls, cliffs or characters it fades out over `soft_distance` metres, so it never
// draws a hard line across them.
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 haze_color : source_color = vec3(0.9, 0.75, 0.55);
// Opacity of the thickest patches when calm, and at a gust's peak.
uniform float calm_opacity = 0.11;
uniform float gust_opacity = 0.2;
// 0 calm, 1 at a gust's peak (set by Sandstorm).
uniform float gust = 0.0;
// Metres per second, in world x and z.
uniform vec2 wind = vec2(5.0, 1.25);
// Size of the patches: smaller is bigger patches.
uniform float patch_scale = 0.06;
// How much longer patches are along the wind than across it.
uniform float stretch = 3.0;
// How much of the sheet is left clear, calm and at a gust's peak.
uniform float calm_clearing = 0.45;
uniform float gust_clearing = 0.35;
uniform float soft_distance = 2.0;
// Fades the sheet out towards its edge (distance from its centre, in metres), so its border never shows.
uniform float edge_radius = 55.0;

varying vec3 v_world_pos;
varying vec3 v_center;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.1 + 5.3) * 0.3 + noise(p * 4.3 + 9.7) * 0.2;
}

// Noise coordinates with the wind along x, stretched so patches streak downwind.
vec2 _wind_space(vec2 p) {
	vec2 along = normalize(wind);
	vec2 across = vec2(-along.y, along.x);
	return vec2(dot(p, along) / stretch, dot(p, across)) * patch_scale;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	// Two layers at different speeds, so the patches churn instead of sliding past as one rigid picture.
	float slow = fbm(_wind_space(v_world_pos.xz - wind * TIME));
	float fast = fbm(_wind_space(v_world_pos.xz - wind * 1.7 * TIME) * 2.4 + 17.0);
	float sand = slow * 0.65 + fast * 0.35;
	float clearing = mix(calm_clearing, gust_clearing, gust);
	float cover = smoothstep(clearing, clearing + 0.3, sand);

	float scene_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float soft = clamp((VERTEX.z - scene_view.z) / soft_distance, 0.0, 1.0);

	float edge = 1.0 - smoothstep(edge_radius * 0.6, edge_radius, distance(v_world_pos.xz, v_center.xz));

	ALBEDO = haze_color;
	ALPHA = cover * mix(calm_opacity, gust_opacity, gust) * soft * edge;
}
