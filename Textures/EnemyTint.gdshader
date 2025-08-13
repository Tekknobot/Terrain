shader_type canvas_item;

uniform vec4  tint_color : source_color = vec4(1.0, 0.43, 1.0, 1.0);
uniform float strength    : hint_range(0.0, 1.0) = 1.0;   // global recolor strength

// Highlight/shadow preservation (keeps lighting readable)
uniform float preserve_highlights : hint_range(0.0, 1.0) = 0.6;
uniform float highlight_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float highlight_softness  : hint_range(0.0, 1.0) = 0.20;

uniform float preserve_shadows    : hint_range(0.0, 1.0) = 0.25;
uniform float shadow_threshold    : hint_range(0.0, 1.0) = 0.10;
uniform float shadow_softness     : hint_range(0.0, 1.0) = 0.15;

// NEW: Accent highlight to ensure strong contrast vs team tint on bright pixels
uniform float accent_strength     : hint_range(0.0, 1.0) = 0.5;  // how much accent enters highlights
uniform float accent_hue_shift    : hint_range(0.0, 1.0) = 0.5;  // 0.5 = complementary hue
uniform float accent_sat_scale    : hint_range(0.0, 2.0) = 0.7;  // lower to keep accent closer to white
uniform float accent_val          : hint_range(0.0, 1.0) = 1.0;  // accent brightness

vec3 rgb2hsv(vec3 c) {
    float cmax = max(c.r, max(c.g, c.b));
    float cmin = min(c.r, min(c.g, c.b));
    float d = cmax - cmin;
    float h = 0.0;

    if (d > 1e-5) {
        if (cmax == c.r)      h = mod((c.g - c.b) / d, 6.0);
        else if (cmax == c.g) h = (c.b - c.r) / d + 2.0;
        else                  h = (c.r - c.g) / d + 4.0;
        h /= 6.0;
        if (h < 0.0) h += 1.0;
    }
    float s = (cmax <= 0.0) ? 0.0 : (d / cmax);
    float v = cmax;
    return vec3(h, s, v);
}

vec3 hsv2rgb(vec3 c) {
    float h = c.x * 6.0;
    float s = c.y;
    float v = c.z;

    float i = floor(h);
    float f = h - i;
    float p = v * (1.0 - s);
    float q = v * (1.0 - s * f);
    float t = v * (1.0 - s * (1.0 - f));

    if (i == 0.0) return vec3(v, t, p);
    if (i == 1.0) return vec3(q, v, p);
    if (i == 2.0) return vec3(p, v, t);
    if (i == 3.0) return vec3(p, q, v);
    if (i == 4.0) return vec3(t, p, v);
    return vec3(v, p, q);
}

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    vec3 hsv_base = rgb2hsv(base.rgb);
    vec3 hsv_tint = rgb2hsv(tint_color.rgb);

    // Base recolor: replace hue (and saturation) but keep the sprite’s original value (brightness)
    float s_mix = 1.0; // 1: use tint’s saturation fully; 0: keep original saturation
    vec3 hsv_replaced = vec3(
        hsv_tint.x,
        mix(hsv_base.y, hsv_tint.y, s_mix),
        hsv_base.z
    );
    vec3 rgb_replaced = hsv2rgb(hsv_replaced);

    // Preserve highlights/shadows by reducing tinting locally
    float v = hsv_base.z;
    float hmask = smoothstep(highlight_threshold, highlight_threshold + highlight_softness, v);
    float smask = 1.0 - smoothstep(shadow_threshold, shadow_threshold + shadow_softness, v);

    float local_strength = strength;
    local_strength *= (1.0 - preserve_highlights * hmask);
    local_strength *= (1.0 - preserve_shadows   * smask);

    // --- Accent highlights for contrast (only where very bright) ---
    // Build an accent color that’s hue-shifted from the team tint (default: complementary),
    // slightly desaturated and very bright, so edges/speculars pop against the team color.
    float accent_h = fract(hsv_tint.x + accent_hue_shift);
    float accent_s = clamp(hsv_tint.y * accent_sat_scale, 0.0, 1.0);
    vec3  accent_rgb = hsv2rgb(vec3(accent_h, accent_s, accent_val));

    // Blend accent into the RECOLORED result, proportional to highlight mask
    vec3 with_accent = mix(rgb_replaced, accent_rgb, hmask * accent_strength);

    // Finally mix the (accented recolor) with original based on local strength
    vec3 out_rgb = mix(base.rgb, with_accent, clamp(local_strength, 0.0, 1.0));
    COLOR = vec4(out_rgb, base.a);
}
