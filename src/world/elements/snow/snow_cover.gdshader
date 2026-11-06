shader_type spatial;

// KayKit props with their own colours, and snow settled on whatever faces up.
#include "res://src/world/elements/snow/snow_common.gdshaderinc"

uniform sampler2D base_texture : source_color, filter_linear_mipmap;
uniform vec3 snow_color : source_color = vec3(0.92, 0.95, 1.0);
uniform vec3 cold_tint : source_color = vec3(0.68, 0.8, 0.86);
uniform float coverage = 0.2;

varying vec3 v_pos;
varying vec3 v_normal;

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = texture(base_texture, UV).rgb * cold_tint;
	float up = v_normal.y - coverage + (snow_noise(v_pos.xz * 2.5 + v_pos.y) - 0.5) * 0.35;
	ALBEDO = mix(base, snow_color, smoothstep(0.0, 0.15, up));
	ROUGHNESS = 0.85;
}
