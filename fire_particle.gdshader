shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D noise_tex : repeat_enable;
uniform sampler2D color_ramp;
uniform float scroll_speed = 1.5;
uniform float erosion_threshold : hint_range(0.0, 1.0) = 0.4;

void fragment() {
    // Scroll the noise texture over time to simulate movement
    vec2 moving_uv = UV + vec2(0.0, TIME * scroll_speed);
    float noise_value = texture(noise_tex, moving_uv).r;
    
    // Mask out the edges using the particle's built-in UVs so it stays contained
    float mask = sin(UV.x * 3.14159) * sin(UV.y * 3.14159);
    float combined = noise_value * mask;
    
    // The Stylization Trick: Step function gives sharp, cell-shaded borders
    // instead of soft gradients.
    float alpha = step(erosion_threshold, combined);
    
    // Map the remaining shapes to a vivid color gradient
    vec4 flame_color = texture(color_ramp, vec2(combined, 0.0));
    
    ALBEDO = flame_color.rgb;
    ALPHA = alpha * COLOR.a; // Multiplied by particle lifetime alpha
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
