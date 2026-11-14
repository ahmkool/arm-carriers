shader_type spatial;
render_mode unshaded, fog_disabled;

// Deep night city street grid far below the skyscrapers: blocks, warm sodium/cool LED avenues,
// and tiny moving headlight & taillight streaks 20+ stories down.
uniform vec3 block_color : source_color = vec3(0.014, 0.020, 0.042);
uniform vec3 road_color : source_color = vec3(0.035, 0.048, 0.088);
uniform vec3 street_lamp_warm : source_color = vec3(0.95, 0.62, 0.26);
uniform vec3 street_lamp_cool : source_color = vec3(0.32, 0.68, 0.98);
uniform float block_size = 26.0;

varying vec3 v_pos;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_pos.xz;
	vec2 grid = fract(p / block_size);
	vec2 block_id = floor(p / block_size);

	float road_x = 1.0 - smoothstep(0.0, 0.085, min(grid.x, 1.0 - grid.x));
	float road_z = 1.0 - smoothstep(0.0, 0.085, min(grid.y, 1.0 - grid.y));
	float road = max(road_x, road_z);
	float intersection = road_x * road_z;

	// Streetlamps spaced along avenues.
	float lamp_x = exp(-pow(fract(p.x / 6.5) - 0.5, 2.0) * 28.0) * road_z;
	float lamp_z = exp(-pow(fract(p.y / 6.5) - 0.5, 2.0) * 28.0) * road_x;
	float lamp = max(lamp_x, lamp_z) * 0.55 + intersection * 0.65;
	vec3 lamp_tint = mix(street_lamp_warm, street_lamp_cool, step(0.68, hash21(block_id)));

	// Tiny moving traffic streaks along avenues.
	float lane_dir = mix(-1.0, 1.0, step(0.5, fract(p.x / block_size * 12.0)));
	float car_z = fract((p.y + TIME * 6.5 * lane_dir) / 19.0 + hash21(vec2(floor(p.x * 0.5), 3.0)));
	float car_along_z = smoothstep(0.94, 0.995, car_z) * road_x * (1.0 - road_z);

	float lane_dir_x = mix(-1.0, 1.0, step(0.5, fract(p.y / block_size * 12.0)));
	float car_x = fract((p.x + TIME * 5.8 * lane_dir_x) / 21.0 + hash21(vec2(floor(p.y * 0.5), 9.0)));
	float car_along_x = smoothstep(0.94, 0.995, car_x) * road_z * (1.0 - road_x);

	vec3 car_col_z = mix(vec3(1.1, 0.22, 0.18), vec3(1.2, 1.05, 0.8), step(0.0, lane_dir));
	vec3 car_col_x = mix(vec3(1.1, 0.22, 0.18), vec3(1.2, 1.05, 0.8), step(0.0, lane_dir_x));

	// Faint rooftop court lights inside city blocks.
	vec2 sub = fract(grid * 4.0);
	float court_dot = step(0.86, hash21(floor(p / 6.5))) * step(0.35, sub.x) * step(sub.x, 0.65) * step(0.35, sub.y) * step(sub.y, 0.65) * (1.0 - road);

	// Distance falloff from play area so far horizon blends seamlessly into abyss sky.
	float dist_fade = 1.0 - smoothstep(85.0, 230.0, length(p - vec2(0.0, -24.0)));

	vec3 col = mix(block_color, road_color, road);
	col += lamp_tint * lamp * 0.52 * dist_fade;
	col += (car_col_z * car_along_z + car_col_x * car_along_x) * 0.75 * dist_fade;
	col += street_lamp_warm * court_dot * 0.18 * dist_fade;

	ALBEDO = mix(block_color * 0.85, col, dist_fade);
}
