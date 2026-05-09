shader_type spatial;

uniform vec3 water_color : source_color = vec3(0.1, 0.4, 0.6);
uniform vec3 foam_color : source_color = vec3(0.8, 0.9, 1.0);

// Simple pseudo-voronoi function
float voronoi(vec2 uv) {
    vec2 p = floor(uv);
    vec2 f = fract(uv);
    float res = 8.0;
    for(int j=-1; j<=1; j++)
    for(int i=-1; i<=1; i++) {
        vec2 b = vec2(float(i), float(j));
        vec2 r = b - f + fract(sin(vec2(dot(p+b,vec2(127.1,311.7)),dot(p+b,vec2(269.5,183.3))))*43758.5453);
        res = min(res, dot(r,r));
    }
    return sqrt(res);
}

void fragment() {
    float time = TIME * 0.2;
    // Layer two voronoi patterns for "moving" water effect
    float v1 = voronoi(UV * 50.0 + time);
    float v2 = voronoi(UV * 75.0 - time * 0.5);
    
    float final_v = smoothstep(0.4, 0.45, v1 * v2);
	vec3 normal_offset = vec3(v1 - 0.5, 0.0, v2 - 0.5) * 0.2;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + normal_offset);
    
    ALBEDO = mix(water_color, foam_color, final_v);
    ROUGHNESS = 0.1;
    SPECULAR = 0.0;
    ALPHA = 0.9; // Slight transparency
	METALLIC = 0.0;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
