shader_type canvas_item;

// 0.0 = fully transparent, 1.0 = fully opaque
uniform float progress : hint_range(0.0, 1.0);

void fragment() {
    // sample the map as usual
    vec4 col = texture(TEXTURE, UV);
    // apply uniform alpha
    COLOR = vec4(col.rgb, col.a * progress);
}
