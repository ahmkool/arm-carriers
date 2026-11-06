shader_type spatial;

// Snow on top, cold rock on the cliff faces. Walkable snow stays bright and calm, so ice and enemies stand out.
#include "res://src/world/elements/snow/snow_common.gdshaderinc"

uniform vec3 snow_color : source_color = vec3(0.82, 0.86, 0.92);
uniform vec3 shadow_tint : source_color = vec3(0.66, 0.73, 0.86);
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
	float drifts = snow_noise(v_pos.xz * 0.35) * 0.6 + snow_noise(v_pos.xz * 1.3) * 0.4;
	vec3 top = mix(shadow_tint, snow_color, smoothstep(0.25, 0.75, drifts));
	float sparkle = step(0.985, snow_hash22(floor(v_pos.xz * 9.0)).x);
	ALBEDO = is_top ? top + sparkle * 0.08 : snow_cliff(v_pos, rock_color, snow_color, top_y);
	ROUGHNESS = is_top ? 0.85 - sparkle * 0.5 : 0.95;
	SPECULAR = is_top ? 0.3 + sparkle * 0.5 : 0.15;
}
