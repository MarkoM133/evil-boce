class_name AbilityFx
extends RefCounted
## A hero's ability going off on the table (Marko 2026-11-02: Purple Haze had no effect): a
## wave in the hero's colour runs over the ground out to its range, and the colour adds its
## own touch: Purple a toxic fog over the whole reach (Purple Haze's virus), the others a
## burst of sparks along the wave. Each one frees itself when it is done.

const LIFE: float = 1.8


## Plays it on `parent` (a node in the world) around `center`, out to `reach` metres.
static func play(parent: Node3D, center: Vector3, reach: float, color: Color, style: String) -> void:
	var root := Node3D.new()
	root.name = "AbilityFx"
	parent.add_child(root)
	root.global_position = center + Vector3(0, 0.06, 0)
	_wave(root, reach, color)
	if style == "Purple":
		_fog(root, reach, color)
		_spores(root, reach, color.lightened(0.35))
	else:
		_spores(root, reach, color.lightened(0.3))
	root.get_tree().create_timer(LIFE + 0.3).timeout.connect(root.queue_free)


## A flat ring that grows from the hero out to `reach` and fades, with a faint disc behind it.
static func _wave(root: Node3D, reach: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.lightened(0.2), 0.95)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.2, 0.05, 0.2)
	root.add_child(ring)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.01
	cyl.radial_segments = 48
	disc.mesh = cyl
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(color, 0.28)
	disc.material_override = dmat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.scale = Vector3(0.2, 1.0, 0.2)
	root.add_child(disc)
	var t: Tween = root.create_tween().set_parallel()
	t.tween_property(ring, "scale", Vector3(reach, 0.05, reach), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.5).set_delay(0.45)
	t.tween_property(disc, "scale", Vector3(reach, 1.0, reach), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(dmat, "albedo_color:a", 0.0, 0.9).set_delay(0.6)


## Purple: soft puffs of fog that well up over the whole reach and drift, then thin out.
static func _fog(root: Node3D, reach: float, color: Color) -> void:
	var fog := CPUParticles3D.new()
	fog.one_shot = true
	fog.explosiveness = 0.75
	fog.amount = 46
	fog.lifetime = 1.6
	fog.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fog.emission_sphere_radius = reach * 0.85
	fog.direction = Vector3.UP
	fog.spread = 30.0
	fog.initial_velocity_min = 0.2
	fog.initial_velocity_max = 0.6
	fog.gravity = Vector3(0, 0.25, 0)
	fog.scale_amount_min = 1.0
	fog.scale_amount_max = 2.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(0.5, 1.0))
	grow.add_point(Vector2(1.0, 1.25))
	fog.scale_amount_curve = grow
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_texture()
	quad.material = mat
	fog.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.darkened(0.15), 0.0))
	ramp.add_point(0.2, Color(color, 0.55))
	ramp.add_point(0.7, Color(color.lightened(0.1), 0.35))
	ramp.set_color(ramp.get_point_count() - 1, Color(color.lightened(0.2), 0.0))
	fog.color_ramp = ramp
	fog.position.y = 0.3
	root.add_child(fog)
	fog.emitting = true


## Small bright motes thrown up along the wave (Purple: the virus capsules breaking).
static func _spores(root: Node3D, reach: float, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 36
	p.lifetime = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = reach * 0.75
	p.emission_ring_inner_radius = reach * 0.3
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -3.0, 0)
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	dot.radial_segments = 6
	dot.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	dot.material = mat
	p.mesh = dot
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 1.0))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.position.y = 0.1
	root.add_child(p)
	p.emitting = true


static var _puff: Texture2D


## A round soft-edged puff, made once.
static func _puff_texture() -> Texture2D:
	if _puff != null:
		return _puff
	var size: int = 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c: float = (size - 1) * 0.5
	for y: int in size:
		for x: int in size:
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_puff = ImageTexture.create_from_image(img)
	return _puff
