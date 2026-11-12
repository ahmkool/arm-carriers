shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// A rain streak: a quad stretched along the drop's fall in 3D and turned around that axis to face the camera.
// Projecting both ends of a real 3D segment gives the perspective the camera sees: seen from above, drops
// falling away streak out from the point under the camera, the way they move on screen. The built-in
// "billboard Y to velocity" mode drops the velocity's depth, so its streaks followed the wind and lay flat
// while the drops visibly fell.
// Needs the particles' transform_align = Y_TO_VELOCITY, so the particle's Y axis is its velocity.

uniform vec4 tint : source_color = vec4(0.8, 0.87, 1.0, 0.3);
varying float v_along;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(axis, to_camera);
	// Looking straight down a drop's path, it shows as a dot: any side will do.
	side = length(side) < 0.001 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	vec3 world_pos = centre + axis * VERTEX.y + side * VERTEX.x;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
	v_along = UV.y;
}

void fragment() {
	// Faint at the tail, brightest just behind the head.
	float fade = smoothstep(1.0, 0.45, v_along) * smoothstep(0.0, 0.2, v_along);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * fade;
}
