shader_type canvas_item;

uniform float flash_amount = 0.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = mix(tex_color, vec4(1.0), flash_amount);
}
