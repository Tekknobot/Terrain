shader_type canvas_item;

uniform vec4 target_color = vec4(0, 0, 1, 1); // Navy Blue
uniform float pulse_speed = 3.0;
uniform float threshold = 0.15;
uniform vec4 base_modulate = vec4(1, 1, 1, 1); // Will be set via code

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    // Check if this pixel is nearly black.
    if (tex_color.r < threshold && tex_color.g < threshold && tex_color.b < threshold) {
        float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
        tex_color.rgb = mix(vec3(0.0), target_color.rgb, pulse);
    }
    COLOR = tex_color * base_modulate;
}
