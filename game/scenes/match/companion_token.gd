class_name CompanionToken
extends Node3D
## A companion on the table (GDD 10, Marko 2026-11-21, variant A of the mockup): a flat disc with the card's art
## on top and a rim in its player's colour. A hero hidden inside shows as its picture above the disc with
## IN SHELTER; while a hero of its player may hide inside, a gold ring pulses round it. It draws only: the
## match scene puts it on a BallBody, so balls push it as they push each other.

const _TOP_SHADER: String = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 rim : source_color = vec4(0.18, 0.42, 1.0, 1.0);
uniform float aspect = 1.5;
uniform vec2 focus = vec2(0.5, 0.5);
uniform float zoom = 1.0;
uniform bool has_tex = true;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	if (r > 1.0) discard;
	// The middle of the art (or where the card's crop looks), as tall as the disc.
	vec2 uv = focus + vec2(d.x / aspect, d.y) * 1.15 / max(zoom, 0.2);
	vec3 c = has_tex ? texture(tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb : vec3(0.16);
	if (r > 0.84) c = rim.rgb;
	if (r > 0.84 && r < 0.88) c = vec3(0.05);
	ALBEDO = c;
	ROUGHNESS = 0.6;
}
"""

const _ICON_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 rim : source_color = vec4(0.18, 0.42, 1.0, 1.0);
uniform bool has_tex = true;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	if (r > 1.0) discard;
	// The hero card's picture: its upper part, where the face is.
	vec3 c = has_tex ? texture(tex, vec2(0.3 + d.x * 0.55, 0.42 + d.y * 0.75)).rgb : vec3(0.2);
	if (r > 0.82) c = rim.rgb;
	ALBEDO = c;
}
"""

const _RING_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 color : source_color = vec4(1.0, 0.83, 0.42, 1.0);
uniform float glow = 1.0;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float band = smoothstep(0.78, 0.86, r) * (1.0 - smoothstep(0.92, 1.0, r));
	ALBEDO = color.rgb * band * glow;
	ALPHA = band * glow;
}
"""

## Height of the disc's top over the table.
const TOP: float = 0.145

var radius: float = 0.5
var _icon: MeshInstance3D
var _label: Label3D
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _icon_mat: ShaderMaterial
var _t: float = 0.0
var _ring_on: bool = false


## `art` the card's art (null: a plain dark top), `crop` the card's art crop ({x, y, zoom}), `rim` its player's
## colour, `radius` the size of the ball it rides on.
func build(art: Texture2D, crop: Dictionary, rim: Color, radius_: float) -> void:
	radius = radius_
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 1.03
	cyl.height = TOP - 0.005
	base.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.albedo_color = rim.darkened(0.25)
	bm.roughness = 0.5
	base.material_override = bm
	base.position.y = (TOP - 0.005) * 0.5
	add_child(base)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	top.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = _TOP_SHADER
	sm.shader = sh
	sm.set_shader_parameter("rim", rim)
	sm.set_shader_parameter("has_tex", art != null)
	if art != null:
		sm.set_shader_parameter("tex", art)
		sm.set_shader_parameter("aspect", float(art.get_width()) / float(maxi(art.get_height(), 1)))
		sm.set_shader_parameter("focus", Vector2(JsonUtil.as_float(crop.get("x", 0.5), 0.5), JsonUtil.as_float(crop.get("y", 0.5), 0.5)))
		sm.set_shader_parameter("zoom", JsonUtil.as_float(crop.get("zoom", 1.0), 1.0))
	top.material_override = sm
	top.position.y = TOP
	add_child(top)
	# The ring a hero may hide in it by: flat on the table round the disc.
	_ring = MeshInstance3D.new()
	var rm := PlaneMesh.new()
	rm.size = Vector2(radius * 3.0, radius * 3.0)
	_ring.mesh = rm
	_ring_mat = ShaderMaterial.new()
	var rs := Shader.new()
	rs.code = _RING_SHADER
	_ring_mat.shader = rs
	_ring_mat.set_shader_parameter("color", Palette.GOLD)
	_ring.material_override = _ring_mat
	_ring.position.y = 0.02
	_ring.visible = false
	add_child(_ring)
	_icon = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 1.55, radius * 1.55)
	_icon.mesh = qm
	_icon_mat = ShaderMaterial.new()
	var ish := Shader.new()
	ish.code = _ICON_SHADER
	_icon_mat.shader = ish
	_icon_mat.set_shader_parameter("rim", rim)
	_icon.material_override = _icon_mat
	_icon.position.y = radius * 2.5
	_icon.visible = false
	add_child(_icon)
	_label = Label3D.new()
	_label.text = "IN SHELTER"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 30
	_label.outline_size = 14
	_label.pixel_size = 0.006
	_label.modulate = Color("ffd36a")
	_label.no_depth_test = true
	_label.position.y = _icon.position.y + radius
	_label.visible = false
	add_child(_label)


## The hero hidden inside: its card picture above the disc, or nothing (null and "" when it is empty).
func set_inside(picture: Texture2D, hero_id: String) -> void:
	var on: bool = not hero_id.is_empty()
	_icon.visible = on
	_label.visible = on
	_icon_mat.set_shader_parameter("has_tex", picture != null)
	if picture != null:
		_icon_mat.set_shader_parameter("tex", picture)
	set_meta("inside", hero_id)


## Where the icon of the hero inside is, for a click on it.
func icon_position() -> Vector3:
	return _icon.global_position


func shows_icon() -> bool:
	return _icon.visible


## The gold ring: a hero of its player may hide inside now.
func set_ring(on: bool) -> void:
	_ring_on = on
	_ring.visible = on


func _process(delta: float) -> void:
	if not _ring_on:
		return
	_t += delta
	_ring_mat.set_shader_parameter("glow", 0.55 + 0.45 * sin(_t * 4.0))
