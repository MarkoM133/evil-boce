shader_type spatial;
// Top of the hex map. Hex lines are faint and get stronger with `emphasis` (aiming, placing).
// Colours are mixed in sRGB (so small mixes stay small) and converted at the end.
// Per-hex data comes from `cells` (one texel per hex, odd-r offset layout):
//   r = terrain id (0 none, 1 ice, 2 mud), g = in range, b = marked (footprint / hover).

uniform sampler2D cells : filter_nearest, repeat_disable;
uniform int map_n = 17;
uniform float hex_size = 1.0;
uniform vec2 origin = vec2(0.0);
uniform float grid_alpha = 0.05;
uniform float grid_alpha_emph = 0.3;
uniform float emphasis : hint_range(0.0, 1.0) = 0.0;
uniform vec3 base_color = vec3(0.17, 0.148, 0.13);
uniform vec3 mid_color = vec3(0.2, 0.172, 0.148);
uniform vec3 line_color = vec3(0.95, 0.9, 0.8);
uniform vec3 range_color = vec3(1.0, 0.82, 0.25);
uniform vec3 mark_color = vec3(1.0, 1.0, 1.0);
uniform vec3 ice_color = vec3(0.62, 0.85, 1.0);
uniform vec3 mud_color = vec3(0.3, 0.2, 0.12);

varying vec3 wpos;

const float SQRT3 = 1.7320508;
const vec2 NORMALS[6] = vec2[6](
	vec2(1.0, 0.0), vec2(0.5, 0.8660254), vec2(-0.5, 0.8660254),
	vec2(-1.0, 0.0), vec2(-0.5, -0.8660254), vec2(0.5, -0.8660254));
const ivec2 DIRS[6] = ivec2[6](
	ivec2(1, 0), ivec2(0, 1), ivec2(-1, 1), ivec2(-1, 0), ivec2(0, -1), ivec2(1, -1));

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

ivec2 cube_round(vec2 qr) {
	float q = qr.x;
	float r = qr.y;
	float s = -q - r;
	float rq = round(q);
	float rr = round(r);
	float rs = round(s);
	float dq = abs(rq - q);
	float dr = abs(rr - r);
	float ds = abs(rs - s);
	if (dq > dr && dq > ds) {
		rq = -rr - rs;
	} else if (dr > ds) {
		rr = -rq - rs;
	}
	return ivec2(int(rq), int(rr));
}

vec4 cell_at(ivec2 a) {
	int row = a.y;
	if (row < 0 || row >= map_n) {
		return vec4(0.0);
	}
	int col = a.x + (row - (row & 1)) / 2;
	if (col < 0 || col >= map_n) {
		return vec4(0.0);
	}
	return texelFetch(cells, ivec2(col, row), 0);
}

void fragment() {
	vec2 p = (wpos.xz + origin) / hex_size;
	ivec2 a = cube_round(vec2(SQRT3 / 3.0 * p.x - p.y / 3.0, 2.0 / 3.0 * p.y));
	vec2 c = vec2(SQRT3 * (float(a.x) + float(a.y) * 0.5), 1.5 * float(a.y));
	vec2 d = p - c;
	float best = -1e9;
	int k = 0;
	for (int i = 0; i < 6; i++) {
		float e = dot(d, NORMALS[i]);
		if (e > best) {
			best = e;
			k = i;
		}
	}
	float edge = SQRT3 * 0.5 - best;
	float aa = fwidth(edge);
	vec4 me = cell_at(a);
	vec4 nb = cell_at(a + DIRS[k]);

	vec3 col = base_color;
	int row = a.y;
	int third = map_n / 3;
	if (row >= third && row < map_n - third) {
		col = mid_color;
	}
	float rough = 0.85;
	float spec = 0.3;
	int ter = int(round(me.r * 255.0));
	int ter_nb = int(round(nb.r * 255.0));
	if (ter == 1) {
		col = mix(col, ice_color, 0.45);
		rough = 0.12;
		spec = 0.8;
	} else if (ter == 2) {
		col = mix(col, mud_color, 0.8);
		rough = 1.0;
		spec = 0.1;
	}

	float thin = 1.0 - smoothstep(0.0, aa * 1.5 + 0.01, edge);
	float thick = 1.0 - smoothstep(0.0, aa * 1.5 + 0.045, edge);

	vec3 emit = vec3(0.0);
	if (ter != ter_nb) {
		col = mix(col, vec3(0.9), 0.35 * thin);
	}
	col = mix(col, mark_color, 0.1 * me.b);
	col = mix(col, range_color, 0.08 * me.g);
	float ga = mix(grid_alpha, grid_alpha_emph, emphasis);
	col = mix(col, line_color, ga * thin);
	if (abs(me.g - nb.g) > 0.5) {
		col = mix(col, range_color, 0.9 * thick);
		emit = range_color * 0.5 * thick;
	}

	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = pow(emit, vec3(2.2));
}
