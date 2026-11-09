shader_type spatial;
// Drawn on top of everything so the bar stays readable when the enemy is behind scenery.
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

// Must match the QuadMesh size in enemy_health_bar_3d.tscn; the border is measured in metres against it.
uniform vec2 bar_size = vec2(1.0, 0.11);
uniform float border = 0.022;
uniform vec4 frame_color : source_color = vec4(0.04, 0.03, 0.03, 0.9);
uniform vec4 empty_color : source_color = vec4(0.2, 0.06, 0.06, 0.85);
uniform vec4 fill_color : source_color = vec4(0.92, 0.17, 0.12, 1.0);
uniform vec4 trail_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);

// Per enemy, so every bar can share one material.
instance uniform float fill = 1.0;
instance uniform float trail = 1.0;
instance uniform float flash = 0.0;
instance uniform float opacity = 1.0;

void vertex() {
	// Face the camera while keeping the node's own scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * bar_size;
	float inner_width = max(bar_size.x - 2.0 * border, 0.001);
	float x = (p.x - border) / inner_width;

	vec4 col = empty_color;
	col = mix(col, trail_color, step(x, trail));
	col = mix(col, fill_color, step(x, fill));
	// A soft highlight along the top half gives the fill some depth.
	col.rgb *= 1.0 + 0.3 * step(UV.y, 0.45) * step(x, fill);

	float in_frame = max(
		max(step(p.x, border), step(bar_size.x - border, p.x)),
		max(step(p.y, border), step(bar_size.y - border, p.y)));
	col = mix(col, frame_color, in_frame);

	col.rgb = mix(col.rgb, vec3(1.0), flash * 0.65);
	ALBEDO = col.rgb;
	ALPHA = col.a * opacity;
}
