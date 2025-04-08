shader_type canvas_item;

// Progress of the shatter effect (0 = logo intact, 1 = fully shattered).
uniform float shatter_progress : hint_range(0.0, 1.0) = 0.0;

// Noise texture used as a random mask.
// Use a high‑contrast grayscale texture (set to “Nearest” filter and “Repeat” enabled).
uniform sampler2D noise_texture;

// Scale factor for noise sampling.
uniform float noise_scale : hint_range(1.0, 20.0) = 10.0;

// Determines how many blocks the image is divided into along one axis.
// For example, if you use 32 on a 256px‑wide logo, each block represents 8 pixels.
uniform float blocks_count : hint_range(1.0, 128.0) = 32.0;

// Maximum displacement in pixels for each block when fully shattered.
uniform float max_displacement : hint_range(0.0, 200.0) = 50.0;

void vertex() {
    // Quantize the UV coordinates so that many pixels sample the same noise value.
    vec2 quant_uv = floor(UV * blocks_count) / blocks_count;

    // Sample the noise texture at the quantized UV coordinates (scaled by noise_scale).
    float noise_val = texture(noise_texture, quant_uv * noise_scale).r;

    // If the noise sample is below the current shatter progress threshold, displace this block.
    if (noise_val < shatter_progress) {
        // Compute a pseudo-random value based on the quantized UV.
        float rand_val = fract(sin(dot(quant_uv, vec2(12.9898, 78.233))) * 43758.5453);
        // Calculate an angle (full circle in radians).
        float angle = rand_val * 6.28318530718;
        vec2 direction = vec2(cos(angle), sin(angle));

        // Determine a displacement factor that increases as the effect progresses.
        float disp_factor = clamp((shatter_progress - noise_val) / shatter_progress, 0.0, 1.0);

        // Displace the vertex in the chosen direction.
        // (VERTEX here is in local space; ensure your mesh has enough subdivision for noticeable per-block movement.)
        VERTEX.xy += direction * max_displacement * disp_factor;
    }
}

void fragment() {
    // Simply sample and output the texture color.
    vec4 col = texture(TEXTURE, UV);
    // Optionally fade out (you could make shattered blocks gradually become transparent):
    col.a *= 1.0 - shatter_progress;
    COLOR = col;
}
