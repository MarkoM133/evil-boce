class_name TableFloor
extends Node3D
## What is under the table when Evil Bochet holds it (Marko 2026-11-13, chosen in the game from the F6 mockup):
##   abyss (the default): no floor, two layers of grey-violet mist drifting apart, a faint violet glow from deep
##     down and a few embers rising; his hands and arms fade out into it;
##   light: a dim violet pool under the table going to black, and a thin mist.
## Settings → Quality and effects → Under the table. On low quality the mist stands still and there are no embers.
## Without Bochet the table keeps its slab and this is not built.

const MIST_SHADER: String = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec3 tint : source_color = vec3(0.16, 0.13, 0.17);
uniform vec3 glow : source_color = vec3(0.30, 0.16, 0.55);
uniform float strength = 0.6;
uniform float glow_amt = 0.6;
uniform float speed = 1.0;
uniform float scale = 0.05;
uniform float reach = 40.0;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wp.xz * scale;
	float t = TIME * 0.05 * speed;
	float n = fbm(p + vec2(t, t * 0.6)) * 0.6 + fbm(p * 1.7 - vec2(t * 0.8, -t * 0.3)) * 0.4;
	float dens = smoothstep(0.38, 0.78, n);
	float r = length(wp.xz) / reach;
	float near = 1.0 - smoothstep(0.35, 1.0, r);
	vec3 c = mix(tint, glow, glow_amt * near * near);
	ALBEDO = c * (0.6 + dens * 0.8);
	ALPHA = clamp(dens * strength * (0.25 + 0.75 * near), 0.0, 1.0);
}
"""

const POOL_SHADER: String = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec3 inner : source_color = vec3(0.12, 0.08, 0.14);
uniform float reach = 40.0;
uniform float strength = 1.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float r = length(wp.xz * vec2(0.8, 1.0)) / reach;
	float k = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = inner;
	ALPHA = k * k * strength;
}
"""

## Settings values (GameSettings.under_table).
const ABYSS: String = "abyss"
const LIGHT: String = "light"

var kind: String = ABYSS
var _arena: Arena
var _still: bool = false


## The floor of `kind_` under the table of `arena`; it hides the table's slab and darkens the background.
static func make(arena: Arena, kind_: String) -> TableFloor:
	var f := TableFloor.new()
	f.name = "TableFloor"
	f._arena = arena
	f.kind = kind_ if [ABYSS, LIGHT].has(kind_) else ABYSS
	f._still = GameSettings.quality() == "low"
	return f


func _ready() -> void:
	var table: Node3D = _arena.get_node_or_null("Table")
	if table != null:
		table.visible = false
	var we: Array[Node] = get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if not we.is_empty():
		var env: Environment = (we[0] as WorldEnvironment).environment
		env.background_color = Color("070608") if kind == ABYSS else Color("060508")
		env.fog_light_color = env.background_color
	var ext: Vector2 = _arena.extent() * 0.5
	var reach: float = maxf(ext.x, ext.y) * 2.2
	var speed: float = 0.0 if _still else 1.0
	if kind == ABYSS:
		_plane(POOL_SHADER, -16.0, {"inner": Color(0.13, 0.08, 0.18), "reach": reach * 0.9, "strength": 0.9})
		_plane(MIST_SHADER, -9.0, {"strength": 0.75, "glow_amt": 0.45, "speed": speed, "scale": 0.028, "reach": reach,
			"tint": Color(0.34, 0.31, 0.36), "glow": Color(0.42, 0.30, 0.55)})
		_plane(MIST_SHADER, -5.5, {"strength": 0.45, "glow_amt": 0.25, "speed": -0.7 * speed, "scale": 0.045, "reach": reach,
			"glow": Color(0.40, 0.32, 0.48), "tint": Color(0.30, 0.28, 0.31)})
		if not _still:
			_embers(ext)
	else:
		# Violet (Marko 2026-11-13: the mockup's warm brown, tried in violet).
		_plane(POOL_SHADER, -12.0, {"inner": Color(0.17, 0.10, 0.26), "reach": reach, "strength": 1.0})
		_plane(MIST_SHADER, -7.0, {"strength": 0.22, "glow_amt": 0.3, "speed": 0.6 * speed, "scale": 0.05, "reach": reach,
			"tint": Color(0.12, 0.10, 0.15), "glow": Color(0.22, 0.14, 0.32)})


func _plane(shader: String, y: float, params: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = shader
	var m := ShaderMaterial.new()
	m.shader = sh
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = y
	add_child(mi)


func _embers(ext: Vector2) -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.visibility_aabb = AABB(Vector3(-60, -20, -60), Vector3(120, 30, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(ext.x * 1.4, 0.5, ext.y * 1.3)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.05, 0.05, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.55, 0.25, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.55, 0.25, 0.9))
	ramp.add_point(0.7, Color(0.75, 0.35, 1.0, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.3, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.emission_enabled = true
	qm.emission = Color(1.0, 0.6, 0.35)
	qm.emission_energy_multiplier = 1.5
	quad.material = qm
	p.draw_pass_1 = quad
	p.position.y = -9.0
	add_child(p)
