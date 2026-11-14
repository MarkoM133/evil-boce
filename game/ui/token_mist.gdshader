shader_type canvas_item;
// Token cards (GDD 10, Marko 2026-11-14, mockup token-ghost.html "A + rijec"): a violet mist drifts slowly over the
// card. `speed` 0 holds it still (low quality, or animations off); `dissolve` 0..1 eats the card away into the mist
// (a token made, run backwards; a token gone at the end of the turn or played).

uniform float speed = 1.0;
uniform float strength = 0.4;
uniform float dissolve = 0.0;
uniform float aspect = 0.714;
uniform float radius = 0.045;
uniform vec4 tint : source_color = vec4(0.62, 0.45, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * vec2(1.0, 1.0 / aspect);
	vec2 size = vec2(1.0, 1.0 / aspect);
	vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
	float edge = 1.0 - smoothstep(-0.004, 0.004, length(max(q, 0.0)) - radius);
	float t = TIME * speed;
	// One slow drift of the whole mist, about every 9 s, as in the mockup.
	vec2 drift = vec2(sin(t * 0.7), cos(t * 0.55)) * 0.12;
	float m = fbm(p * 3.0 + drift + vec2(t * 0.05, -t * 0.03));
	float m2 = fbm(p * 5.5 - drift * 1.4 + vec2(-t * 0.04, t * 0.06));
	float mist = smoothstep(0.35, 0.85, m * 0.65 + m2 * 0.45);
	// The dissolve: noise above the line is gone, a lit violet rim runs along it.
	float d = fbm(p * 7.0 + 3.1);
	float gone = smoothstep(dissolve - 0.04, dissolve + 0.04, d + 0.02);
	float rim = (1.0 - abs(d - dissolve) / 0.06) * step(0.001, dissolve);
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, tint.rgb, clamp(mist * strength + max(rim, 0.0) * 0.9, 0.0, 1.0));
	c.rgb += tint.rgb * mist * strength * 0.25;
	c.a *= edge * (dissolve > 0.0 ? gone + max(rim, 0.0) * (1.0 - gone) : 1.0);
	COLOR = c;
}
