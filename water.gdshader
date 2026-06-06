shader_type spatial;

uniform vec3 water_color : source_color = vec3(0.1, 0.4, 0.6);
uniform vec3 foam_color : source_color = vec3(0.8, 0.9, 1.0);

// Portable cell hash (no sin of large values — stable on D3D/Vulkan/Metal).
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float voronoi(vec2 uv) {
	vec2 p = floor(uv);
	vec2 f = fract(uv);
	float res = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 b = vec2(float(i), float(j));
			vec2 r = b - f + hash22(p + b);
			res = min(res, dot(r, r));
		}
	}
	return sqrt(res);
}

void fragment() {
	float time = TIME * 0.2;

	// Sample in mesh UV space — MODEL_MATRIX * VERTEX is camera-relative in Godot
	// and makes the pattern slide when the camera moves.
	float v1 = voronoi(UV * 100.0 + time);
	float v2 = voronoi(UV * 150.0 - time * 0.5);

	float final_v = smoothstep(0.35, 0.55, v1 * v2);
	vec3 normal_offset = vec3(v1 - 0.5, 0.0, v2 - 0.5) * 0.2;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + normal_offset);

	ALBEDO = mix(water_color, foam_color, final_v);
	ROUGHNESS = 0.1;
	SPECULAR = 0.0;
	ALPHA = 0.9;
	METALLIC = 0.0;
}
