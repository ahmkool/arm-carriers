shader_type spatial;

// Plain dark wood for posts that drop into the castle siege's bottomless gorge (the balconies' and the scaffolding's).
// Fades to black below fade_top_y, fully black fade_depth metres down, and applies the fog itself, fading it out
// too, exactly as castle_stone_chasm.gdshader does for the wall: the posts go dark at the same depth as the stone.
uniform vec3 wood_color : source_color = vec3(0.27, 0.17, 0.1);
uniform float fade_top_y = -1.0;
uniform float fade_depth = 3.5;
// Keep in sync with castle_stone.gdshaderinc's chasm_fog_color. The density is a global the Sandstorm keeps equal to
// the environment's, gusts included.
uniform vec3 chasm_fog_color : source_color = vec3(0.9, 0.74, 0.56);
global uniform float chasm_fog_density;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float depth = clamp((fade_top_y - v_world_y) / fade_depth, 0.0, 1.0);
	float light_left = 1.0 - smoothstep(0.0, 1.0, depth);
	ALBEDO = wood_color * light_left;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2 * light_left;
	float fog_amount = 1.0 - exp(-length(VERTEX) * chasm_fog_density);
	FOG = vec4(chasm_fog_color, fog_amount * light_left);
}
