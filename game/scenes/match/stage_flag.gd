class_name StageFlag
extends Node3D
## The flag on a claimed stage (item 21, G4, Marko 2026-11-10): a pole on the stage's back edge, tall
## enough to clear the heroes on it, and a waving cloth in the claimer's colour with the logo of each
## different hero that took the stage, each in a light badge like the button of its ball. At the claim
## the pole grows and the flag goes up it (rise).

const POLE_HEIGHT: float = 3.4
const POLE_RADIUS: float = 0.06
const POLE_COLOR := Color("e8e2d6")
const CLOTH_HEIGHT: float = 0.78
## The cloth is this wide without a logo, and this much wider for each.
const CLOTH_BARE: float = 1.1
const CLOTH_EDGE: float = 0.4
const CLOTH_PER_LOGO: float = 0.76
## How far behind the stage's centre the pole stands (the back edge of its middle hex's ring).
const BACK: float = 1.95

const CLOTH_SHADER: String = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
void vertex() {
	// Held at the pole (UV.x 0), freer towards its end.
	float k = UV.x;
	VERTEX.z += sin(UV.x * 7.0 - TIME * 4.5) * 0.1 * k;
	VERTEX.y += sin(UV.x * 5.0 - TIME * 3.2) * 0.035 * k;
}
void fragment() {
	float fold = 0.9 + 0.1 * sin(UV.x * 7.0 - TIME * 4.5 + 1.2);
	ALBEDO = texture(tex, UV).rgb * fold;
}
"""

static var _shader: Shader

var _pole: Node3D
var _cloth: Node3D
var _cloth_y: float = 0.0
## What it was made from (the match makes it again when that changes).
var key: String = ""


## A flag in `team` colour with these logos (each once, in order; none leaves the cloth plain).
static func make(team: Color, logos: Array[Texture2D]) -> StageFlag:
	var f := StageFlag.new()
	f._build(team, logos)
	return f


func _build(team: Color, logos: Array[Texture2D]) -> void:
	_pole = Node3D.new()
	add_child(_pole)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = POLE_RADIUS
	cyl.bottom_radius = POLE_RADIUS
	cyl.height = POLE_HEIGHT
	cyl.radial_segments = 8
	pole.mesh = cyl
	pole.material_override = MeshKit.unshaded(POLE_COLOR, false)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position.y = POLE_HEIGHT * 0.5
	_pole.add_child(pole)
	var w: float = cloth_width(logos.size())
	_cloth = Node3D.new()
	_cloth_y = POLE_HEIGHT - 0.06 - CLOTH_HEIGHT * 0.5
	_cloth.position = Vector3(POLE_RADIUS, _cloth_y, 0)
	add_child(_cloth)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(w, CLOTH_HEIGHT)
	plane.subdivide_width = 16
	plane.subdivide_depth = 2
	mi.mesh = plane
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CLOTH_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tex", cloth_texture(team, logos, w))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.x = w * 0.5
	_cloth.add_child(mi)


static func cloth_width(logos: int) -> float:
	return CLOTH_BARE if logos <= 0 else CLOTH_EDGE + CLOTH_PER_LOGO * logos


## The cloth's picture: the team's colour, and the logos in a row as light badges.
static func cloth_texture(team: Color, logos: Array[Texture2D], width: float) -> Texture2D:
	var h: int = 256
	var w: int = maxi(8, roundi(h * width / CLOTH_HEIGHT))
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(team, 1.0))
	var d: int = int(h * 0.74)
	for i: int in logos.size():
		var badge: Image = BallView.emblem_badge(logos[i]).get_image()
		badge.convert(Image.FORMAT_RGBA8)
		badge.resize(d, d, Image.INTERPOLATE_LANCZOS)
		var cx: float = w * (i + 0.5) / logos.size()
		img.blend_rect(badge, Rect2i(0, 0, d, d), Vector2i(int(cx - d * 0.5), (h - d) / 2))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The claim: the pole grows out of the stage and the flag goes up it and unfurls.
func rise() -> void:
	_pole.scale.y = 0.02
	_cloth.position.y = 0.5
	_cloth.scale = Vector3(0.05, 0.6, 1)
	_cloth.visible = false
	var t: Tween = create_tween()
	t.tween_property(_pole, "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: _cloth.visible = true)
	t.tween_property(_cloth, "position:y", _cloth_y, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_cloth, "scale", Vector3.ONE, 0.3).set_delay(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
