class_name ColorFx
extends RefCounted
## One-shot effects in the hero's card colour (GDD 5): Red fire and sparks, Cyan wind and speed
## lines, Blue a shockwave, Green leaves and a heal light, Purple fog, Yellow golden flashes.
## Each one is a node added to `parent` that frees itself when it is done. Sizes are in ball
## radii, so they scale with the ball.

const LIFE: float = 1.2


## Plays the colour's burst on `parent` (a BallView), for a ball of radius `r`.
static func burst(parent: Node3D, style: String, color: Color, r: float) -> void:
	var root := Node3D.new()
	root.name = "ColorFx"
	parent.add_child(root)
	match style:
		"Red":
			_particles(root, r, color, {"amount": 40, "lifetime": 0.7, "gravity": Vector3(0, 3.0, 0),
				"speed": Vector2(0.6, 1.8), "spread": 35.0, "size": 0.09, "end": Color("ffcf4a")})
			_particles(root, r, Color("ffe08a"), {"amount": 18, "lifetime": 0.45, "gravity": Vector3(0, -6, 0),
				"speed": Vector2(3.0, 5.0), "spread": 80.0, "size": 0.035, "end": Color("ff6a2a")})
		"Cyan":
			_speed_lines(root, r, color)
		"Blue":
			_shockwave(root, r, color)
			_particles(root, r, color.lightened(0.4), {"amount": 16, "lifetime": 0.5, "gravity": Vector3.ZERO,
				"speed": Vector2(2.5, 3.5), "spread": 90.0, "flat": true, "size": 0.05, "end": color})
		"Green":
			_particles(root, r, color, {"amount": 22, "lifetime": 1.1, "gravity": Vector3(0, -0.8, 0),
				"speed": Vector2(0.8, 1.6), "spread": 70.0, "size": 0.08, "leaf": true, "end": Color("c6f07a")})
			_glow(root, r, Color("b9ffb0"))
		"Purple":
			_particles(root, r, color.darkened(0.2), {"amount": 14, "lifetime": 1.2, "gravity": Vector3(0, 0.3, 0),
				"speed": Vector2(0.4, 0.9), "spread": 90.0, "flat": true, "size": 0.32, "soft": true, "end": color})
		"Yellow":
			_particles(root, r, Color("fff2b0"), {"amount": 26, "lifetime": 0.55, "gravity": Vector3(0, -2.0, 0),
				"speed": Vector2(2.0, 3.6), "spread": 75.0, "size": 0.06, "end": color})
			_glow(root, r, Color("ffe066"))
		_:
			_particles(root, r, color, {"amount": 30, "lifetime": 0.8, "gravity": Vector3(0, -8, 0),
				"speed": Vector2(2.0, 4.5), "spread": 70.0, "size": 0.035, "end": color})
	root.get_tree().create_timer(LIFE + 0.4).timeout.connect(root.queue_free)


static func _particles(parent: Node3D, r: float, color: Color, o: Dictionary) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = JsonUtil.as_int(o.get("amount", 30))
	p.lifetime = JsonUtil.as_float(o.get("lifetime", 0.8))
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = JsonUtil.as_float(o.get("spread", 60.0))
	if JsonUtil.as_bool(o.get("flat", false)):
		# Outwards along the ground.
		p.direction = Vector3(1, 0, 0)
		p.spread = 180.0
		p.flatness = 1.0
	var speed: Vector2 = o.get("speed", Vector2(1, 2))
	p.initial_velocity_min = speed.x * r
	p.initial_velocity_max = speed.y * r
	var g: Vector3 = o.get("gravity", Vector3.ZERO)
	p.gravity = g * r
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 * r
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	if JsonUtil.as_bool(o.get("leaf", false)):
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
	var size: float = JsonUtil.as_float(o.get("size", 0.05)) * r
	var mesh: Mesh
	if JsonUtil.as_bool(o.get("leaf", false)):
		var q := QuadMesh.new()
		q.size = Vector2(size * 2.0, size)
		mesh = q
	else:
		var s := SphereMesh.new()
		s.radius = size
		s.height = size * 2.0
		s.radial_segments = 8
		s.rings = 4
		mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if JsonUtil.as_bool(o.get("leaf", false)):
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not JsonUtil.as_bool(o.get("soft", false)):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.surface_set_material(0, mat)
	p.mesh = mesh
	var ramp := Gradient.new()
	var end: Color = o.get("end", color)
	var soft: bool = JsonUtil.as_bool(o.get("soft", false))
	ramp.set_color(0, Color(color, 0.55 if soft else 1.0))
	ramp.set_color(1, Color(end, 0.0))
	p.color_ramp = ramp
	if soft:
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.4))
		grow.add_point(Vector2(1, 1.6))
		p.scale_amount_curve = grow
	p.position.y = 0.2 * r
	parent.add_child(p)
	p.emitting = true


## Cyan: thin streaks that circle the ball once and fade.
static func _speed_lines(parent: Node3D, r: float, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color.lightened(0.3)
	for i: int in 7:
		var arm := Node3D.new()
		arm.rotation.y = TAU * i / 7.0
		arm.position.y = (0.2 + 0.25 * (i % 3)) * r
		parent.add_child(arm)
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, 0.03, 0.9) * r
		line.mesh = box
		line.material_override = mat
		line.position.x = 1.5 * r
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arm.add_child(line)
		var t: Tween = arm.create_tween()
		t.tween_property(arm, "rotation:y", arm.rotation.y + TAU * 0.9, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(line, "position:x", 2.4 * r, 0.55)
		t.parallel().tween_property(line, "transparency", 1.0, 0.55).set_delay(0.15)


## Blue: a ring on the ground that races outwards and fades.
static func _shockwave(parent: Node3D, r: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = MeshKit.annulus(0.85, 1.0, true, 64)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color.lightened(0.35)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = -0.9 * r
	ring.scale = Vector3.ONE * r
	parent.add_child(ring)
	var t: Tween = ring.create_tween()
	t.tween_property(ring, "scale", Vector3.ONE * r * 4.5, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(ring, "transparency", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Green / Yellow: a soft light that swells and fades.
static func _glow(parent: Node3D, r: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 3.0 * r
	light.light_energy = 0.0
	light.position.y = 0.8 * r
	parent.add_child(light)
	var t: Tween = light.create_tween()
	t.tween_property(light, "light_energy", 2.5, 0.15)
	t.tween_property(light, "light_energy", 0.0, 0.7)
