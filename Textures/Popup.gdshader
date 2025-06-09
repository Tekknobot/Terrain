shader_type canvas_item;
render_mode blend_mix;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // base text color
uniform vec4 pulse_color : source_color = vec4(1.0, 0.2, 0.2, 1.0); // pulse highlight color
uniform float pulse_speed = 3.0;
uniform float scan_thickness = 0.2;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float alpha = tex.a;
	if (alpha < 0.01) {
		discard;
	}

	// Pulse: subtle glow over time
	float pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);

	// Scanline animation from top to bottom
	float scan = smoothstep(0.0, scan_thickness, fract(TIME * 1.5) - UV.y);

	// Mix colors with time + scan
	vec4 color = mix(base_color, pulse_color, pulse * 0.3 + scan * 0.7);

	COLOR = color * alpha;
}
