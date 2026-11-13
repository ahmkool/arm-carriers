shader_type spatial;

// Sandstone in world space, for tiles without suitable UVs. Tops are pale wind-rippled sand; cliff faces are
// red-orange strata. Below the ledge tops everything fades smoothly to black, fully black `black_depth` metres down,
// so a chasm reads as a bottomless hole from the steep camera.
uniform vec3 sand_color : source_color = vec3(0.86, 0.68, 0.46);
uniform vec3 sand_dark : source_color = vec3(0.74, 0.55, 0.36);
uniform vec3 strata_a : source_color = vec3(0.78, 0.44, 0.26);
uniform vec3 strata_b : source_color = vec3(0.66, 0.33, 0.2);
uniform vec3 strata_c : source_color = vec3(0.86, 0.6, 0.4);
// Tops above the ledges (hills) turn this rockier tone, so the pale sand only marks ground the carriers can walk on.
uniform vec3 high_top_color : source_color = vec3(0.78, 0.5, 0.32);
uniform float high_top_span = 4.0;
uniform float top_y = -1.0;
// How far below top_y everything is fully black. The tall cliff tiles end 4.3 m below the tops, so the fade must
// finish by then or their bottom edge shows as a hard line against the black canyon floor.
uniform float black_depth = 4.0;
// The level's fog, applied here by hand so it can fade out with depth too: environment fog grows with camera distance,
// so fogged cliff bottoms never quite match the unfogged black canyon floor and leave a visible edge.
// fog_color: keep in sync with the Environment of world_local_castle_siege.tscn. The density is a global that the
// Sandstorm keeps equal to the environment's, gusts included.
uniform vec3 fog_color : source_color = vec3(0.9, 0.74, 0.56);
global uniform float chasm_fog_density;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec3 strata(float y, float along) {
	float warp = noise(vec2(along * 0.12, y * 0.05)) * 1.6;
	float band = fract((y + warp) * 0.42);
	vec3 color = mix(strata_a, strata_b, smoothstep(0.3, 0.38, band));
	color = mix(color, strata_c, smoothstep(0.7, 0.76, band));
	return color * (0.88 + noise(vec2(along * 1.3, y * 4.0)) * 0.2);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool is_top = v_world_normal.y > 0.65;
	vec3 color;
	if (is_top) {
		float ripple = sin(v_world_pos.x * 1.7 + v_world_pos.z * 0.6 + noise(v_world_pos.xz * 0.35) * 5.0);
		float patches = noise(v_world_pos.xz * 0.18);
		color = mix(sand_dark, sand_color, smoothstep(0.25, 0.75, patches)) * (0.95 + ripple * 0.04);
		float rise = clamp((v_world_pos.y - top_y - 1.0) / high_top_span, 0.0, 1.0);
		color = mix(color, high_top_color * (0.9 + patches * 0.2), rise * 0.9);
	} else {
		color = strata(v_world_pos.y, v_world_pos.x + v_world_pos.z);
	}
	float light_left = 1.0 - smoothstep(0.0, 1.0, clamp((top_y - v_world_pos.y) / black_depth, 0.0, 1.0));
	ALBEDO = color * light_left;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2 * light_left;
	float fog_amount = 1.0 - exp(-length(VERTEX) * chasm_fog_density);
	FOG = vec4(fog_color, fog_amount * light_left);
}
