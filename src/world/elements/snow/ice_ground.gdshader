shader_type spatial;

// Frozen ground: glossy pale ice with deeper patches and white cracks, clearly unlike the snow around it.
#include "res://src/world/elements/snow/snow_common.gdshaderinc"

uniform vec3 ice_color : source_color = vec3(0.42, 0.68, 0.86);
uniform vec3 deep_color : source_color = vec3(0.18, 0.42, 0.66);
uniform vec3 crack_color : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 snow_color : source_color = vec3(0.9, 0.93, 0.98);
uniform vec3 rock_color : source_color = vec3(0.34, 0.38, 0.46);
uniform float top_y = -1.0;

varying vec3 v_pos;
varying vec3 v_normal;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool is_top = v_normal.y > 0.65;
	float depth = smoothstep(0.35, 0.75, snow_noise(v_pos.xz * 0.28));
	vec2 plates = snow_cracks(v_pos.xz * 0.45);
	float crack = 1.0 - smoothstep(0.0, 0.035, plates.x);
	float streak = smoothstep(0.7, 0.95, snow_noise(vec2(v_pos.x * 0.6 + v_pos.z * 0.6, (v_pos.z - v_pos.x) * 4.0)));
	vec3 top = mix(ice_color, deep_color, depth * 0.7) * (0.93 + plates.y * 0.12);
	top = mix(top, crack_color, max(crack * 0.85, streak * 0.35));
	ALBEDO = is_top ? top : snow_cliff(v_pos, rock_color, snow_color, top_y);
	ROUGHNESS = is_top ? 0.08 + crack * 0.5 : 0.95;
	SPECULAR = is_top ? 0.75 : 0.15;
	METALLIC = 0.0;
}
