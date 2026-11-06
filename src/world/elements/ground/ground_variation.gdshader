// Ground tile shader: keeps the KayKit palette texture but breaks up large flat
// grass areas with world-space color patches, fine speckle and drifting cloud shadows.
// Applied at runtime to floor GridMaps by ground_variation.gd.
shader_type spatial;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

group_uniforms patches;
// Multiplied onto grass in the dark / light patches.
uniform vec3 lush_tint : source_color = vec3(0.72, 0.86, 0.66);
uniform vec3 dry_tint : source_color = vec3(1.18, 1.12, 0.74);
uniform float patch_scale = 0.075;
uniform float patch_strength : hint_range(0.0, 1.0) = 0.85;
uniform float speckle_scale = 0.9;
uniform float speckle_strength : hint_range(0.0, 0.3) = 0.07;

group_uniforms clouds;
uniform float cloud_scale = 0.025;
uniform vec2 cloud_velocity = vec2(1.2, 0.6);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.18;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.22;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

// 1 on clearly green texels, 0 on dirt, rock and wood.
float grass_mask(vec3 color) {
	float greenness = color.g - max(color.r, color.b);
	return smoothstep(0.02, 0.10, greenness);
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 ground_uv = world_pos.xz;

	float on_grass = grass_mask(base) * smoothstep(0.55, 0.9, world_normal.y);

	float patches = fbm(ground_uv * patch_scale);
	vec3 tint = mix(lush_tint, dry_tint, smoothstep(0.3, 0.7, patches));
	float speckle = (value_noise(ground_uv * speckle_scale) - 0.5) * 2.0 * speckle_strength;
	vec3 grass = base * mix(vec3(1.0), tint, patch_strength) * (1.0 + speckle);
	vec3 color = mix(base, grass, on_grass);

	float clouds = fbm(ground_uv * cloud_scale + TIME * cloud_velocity * cloud_scale);
	float shadow = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + cloud_softness, clouds);
	color *= 1.0 - shadow * cloud_darkness;

	ALBEDO = color;
	ROUGHNESS = roughness;
}
