shader_type canvas_item;

// Controls the overall intensity of the effect.
uniform float effect_strength : hint_range(0.0, 1.0) = 0.0;
// Use a faster pulse speed for dark (almost black) pixels…
uniform float pulse_speed_black : hint_range(0.0, 10.0) = 5.0;
// …and a slower pulse for brighter pixels.
uniform float pulse_speed_nonblack : hint_range(0.0, 10.0) = 2.0;

void fragment() {
    vec4 base_color = texture(TEXTURE, UV);

    // Compute brightness (simple average of RGB channels)
    float brightness = (base_color.r + base_color.g + base_color.b) / 3.0;

    // Choose pulse speed based on brightness.
    // Here, we consider a pixel "black" if brightness is below 0.1.
    float chosen_speed = brightness < 0.1 ? pulse_speed_black : pulse_speed_nonblack;

    // Compute the pulse factor. It will oscillate between 0 and 1.
    float pulse = abs(sin(TIME * chosen_speed)) * effect_strength;

    // Mix the original color with white (vec3(1.0)).
    vec3 final_color = mix(base_color.rgb, vec3(1.0), pulse);

    COLOR = vec4(final_color, base_color.a);
}
