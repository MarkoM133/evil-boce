shader_type canvas_item;
// Cuts a card picture's corners round, so the black corners of a JPG card image do not show.
// radius is a share of the picture's width.

uniform float radius = 0.045;
uniform float aspect = 0.714;

void fragment() {
	vec2 p = UV * vec2(1.0, 1.0 / aspect);
	vec2 size = vec2(1.0, 1.0 / aspect);
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
	float d = length(max(q, 0.0)) - radius;
	// COLOR already carries the texture sample times modulate.
	vec4 c = COLOR;
	c.a *= 1.0 - smoothstep(-0.004, 0.004, d);
	COLOR = c;
}
