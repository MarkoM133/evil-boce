class_name BallView
extends Node3D
## Procedural ball look (GDD 5): hero-coloured top half, accent bottom half (the pedestal),
## team-coloured seam and ground ring, emblem button at the front. Opening makes the top half
## vanish in a flash and grows the hero's sprite standee on the pedestal.
## Built at unit radius; set_radius() scales it.

signal state_changed(state: State)

enum State { CLOSED, OPENING, OPEN, CLOSING }

const SETTLE_TIME: float = 0.12
const LID_TIME: float = 0.3
const FIGURE_TIME: float = 0.32
const FIGURE_DELAY: float = 0.08
const CLOSE_TIME: float = 0.32
const CLOSE_TIME_FAST: float = 0.2
## Standee height and maximum width, in ball radii.
const FIGURE_HEIGHT: float = 3.0
const FIGURE_MAX_WIDTH: float = 3.6

static var _fallback_emblem: Texture2D
static var _flash_texture: Texture2D

var state: State = State.CLOSED
var radius: float = 0.6

var _body: Node3D
var _spinner: Node3D
var _lid: Node3D
var _figure_pivot: Node3D
var _figure: Sprite3D
var _ground_ring: MeshInstance3D
var _flash: MeshInstance3D
var _burst: CPUParticles3D

var _top_mat := StandardMaterial3D.new()
var _bottom_mat := StandardMaterial3D.new()
var _seam_mat := StandardMaterial3D.new()
var _socket_mat := StandardMaterial3D.new()
var _ring_mat := StandardMaterial3D.new()
var _inner_mat := StandardMaterial3D.new()
var _button_mat := StandardMaterial3D.new()
var _emblem_mat := StandardMaterial3D.new()
var _flash_mat := StandardMaterial3D.new()
var _burst_mat := StandardMaterial3D.new()

var _hero_color: Color = Color.WHITE
var _team_color: Color = Color.WHITE
var _glow: bool = false
var _glow_t: float = 0.0
var _tween: Tween


func _init() -> void:
	_build()


func configure(hero_color: Color, accent: Color, team_color: Color,
		emblem: Texture2D, figure: Texture2D) -> void:
	_hero_color = hero_color
	_team_color = team_color
	_top_mat.albedo_color = hero_color
	_bottom_mat.albedo_color = accent
	_seam_mat.albedo_color = team_color
	_seam_mat.emission = team_color
	_socket_mat.albedo_color = team_color
	_ring_mat.albedo_color = Color(team_color, 0.9)
	_flash_mat.albedo_color = Color(hero_color, 0.0)
	_burst_mat.albedo_color = hero_color
	_emblem_mat.albedo_texture = emblem if emblem != null else _get_fallback_emblem()
	_figure.texture = figure if figure != null else _placeholder_figure(hero_color)
	_fit_figure()


func set_radius(r: float) -> void:
	radius = r
	_body.scale = Vector3.ONE * r
	_ground_ring.scale = Vector3.ONE * r
	_ground_ring.position.y = -r + 0.015
	_burst.scale = Vector3.ONE * r
	_fit_figure()


## Activation glow on the seam.
func set_glow(on: bool) -> void:
	_glow = on
	_glow_t = 0.0
	_seam_mat.emission_energy_multiplier = 0.0


func is_open() -> bool:
	return state == State.OPEN or state == State.OPENING


## Turns the spinner by the distance travelled, as if the ball rolled.
func roll(delta: Vector3) -> void:
	var d := Vector3(delta.x, 0, delta.z)
	var dist: float = d.length()
	if dist < 0.00001:
		return
	var axis: Vector3 = Vector3.UP.cross(d / dist).normalized()
	_spinner.basis = (Basis(axis, dist / radius) * _spinner.basis).orthonormalized()


## Turns the ball upright with the button towards the camera.
func settle() -> void:
	if state != State.CLOSED:
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_spinner, "quaternion", _upright(), SETTLE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func open() -> void:
	if state != State.CLOSED:
		return
	_set_state(State.OPENING)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_spinner, "quaternion", _upright(), SETTLE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_start_open_fx)
	_tween.tween_property(_lid, "rotation:x", -0.6, LID_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_lid, "scale", Vector3.ONE * 0.001, LID_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_lid, "position:y", 0.4, LID_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_set_flash_open, 0.0, 1.0, 0.45)
	_tween.parallel().tween_property(_figure_pivot, "scale", Vector3.ONE, FIGURE_TIME) \
		.set_delay(FIGURE_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_on_opened)


## `fast` is the 0.2 s close before a throw or a knock.
func close(fast: bool = false) -> void:
	if state == State.CLOSED or state == State.CLOSING:
		return
	_set_state(State.CLOSING)
	_kill_tween()
	var t: float = CLOSE_TIME_FAST if fast else CLOSE_TIME
	_lid.visible = true
	_tween = create_tween()
	_tween.tween_property(_figure_pivot, "scale", Vector3.ONE * 0.001, t * 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_set_flash_close, 0.0, 1.0, t)
	_tween.tween_property(_lid, "rotation:x", 0.0, t * 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_lid, "scale", Vector3.ONE, t * 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_lid, "position:y", 0.0, t * 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_on_closed)


## Jumps straight to closed, no animation.
func close_now() -> void:
	_kill_tween()
	_lid.visible = true
	_lid.rotation = Vector3.ZERO
	_lid.scale = Vector3.ONE
	_lid.position = Vector3.ZERO
	_figure_pivot.scale = Vector3.ONE * 0.001
	_figure_pivot.visible = false
	_flash.visible = false
	if state != State.CLOSED:
		_set_state(State.CLOSED)


func _process(delta: float) -> void:
	if _glow:
		_glow_t += delta
		_seam_mat.emission_energy_multiplier = 1.1 + 0.7 * sin(_glow_t * 4.0)


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func _start_open_fx() -> void:
	_figure_pivot.visible = true
	_figure_pivot.scale = Vector3.ONE * 0.001
	_burst.restart()
	_burst.emitting = true


func _on_opened() -> void:
	_lid.visible = false
	_flash.visible = false
	_set_state(State.OPEN)


func _on_closed() -> void:
	_figure_pivot.visible = false
	_flash.visible = false
	_set_state(State.CLOSED)


func _set_flash_open(k: float) -> void:
	_flash.visible = k < 1.0
	_flash.scale = Vector3.ONE * radius * (0.8 + 5.2 * k)
	_flash_mat.albedo_color.a = k * 4.0 if k < 0.25 else 1.0 - (k - 0.25) / 0.75


func _set_flash_close(k: float) -> void:
	_flash.visible = k < 1.0
	_flash.scale = Vector3.ONE * radius * (4.0 - 3.2 * k)
	_flash_mat.albedo_color.a = (k * 3.0 if k < 0.3 else (1.0 - k) * 1.4) * 0.8


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _upright() -> Quaternion:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return Quaternion.IDENTITY
	var to_cam: Vector3 = cam.global_position - global_position
	return Quaternion(Vector3.UP, atan2(to_cam.x, to_cam.z))


func _fit_figure() -> void:
	if _figure == null or _figure.texture == null:
		return
	var size: Vector2 = _figure.texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_figure.pixel_size = minf(radius * FIGURE_HEIGHT / size.y, radius * FIGURE_MAX_WIDTH / size.x)
	_figure.offset = Vector2(0, size.y * 0.5)


func _build() -> void:
	for m: StandardMaterial3D in [_top_mat, _bottom_mat]:
		m.roughness = 0.3
		m.clearcoat_enabled = true
		m.clearcoat = 0.5
		m.clearcoat_roughness = 0.25
	_bottom_mat.roughness = 0.4
	_seam_mat.roughness = 0.35
	_seam_mat.metallic = 0.25
	_seam_mat.emission_enabled = true
	_seam_mat.emission_energy_multiplier = 0.0
	_socket_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_inner_mat.albedo_color = Color("1b1a1d")
	_inner_mat.roughness = 0.6
	_button_mat.albedo_color = Color("d9d2c5")
	_button_mat.metallic = 0.6
	_button_mat.roughness = 0.3
	_emblem_mat.roughness = 0.4
	_emblem_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_spinner = Node3D.new()
	_spinner.name = "Spinner"
	_body.add_child(_spinner)

	# Bottom half: the pedestal.
	_mesh(_spinner, MeshKit.hemisphere(false), _bottom_mat)
	_mesh(_spinner, MeshKit.annulus(0.0, 0.985, true), _inner_mat, Vector3(0, 0.002, 0))
	_mesh(_spinner, MeshKit.annulus(0.32, 0.4, true), _socket_mat, Vector3(0, 0.004, 0))
	var seam := TorusMesh.new()
	seam.inner_radius = 0.975
	seam.outer_radius = 1.05
	seam.rings = 64
	seam.ring_segments = 10
	_mesh(_spinner, seam, _seam_mat)
	var button := CylinderMesh.new()
	button.top_radius = 0.26
	button.bottom_radius = 0.26
	button.height = 0.1
	button.radial_segments = 40
	var b: MeshInstance3D = _mesh(_spinner, button, _button_mat, Vector3(0, 0, 1.0))
	b.rotation.x = PI * 0.5
	var emblem := QuadMesh.new()
	emblem.size = Vector2(0.42, 0.42)
	_mesh(_spinner, emblem, _emblem_mat, Vector3(0, 0, 1.052))

	# Top half: vanishes when the ball opens.
	_lid = Node3D.new()
	_lid.name = "Lid"
	_spinner.add_child(_lid)
	_mesh(_lid, MeshKit.hemisphere(true), _top_mat)
	_mesh(_lid, MeshKit.annulus(0.0, 0.985, false), _inner_mat, Vector3(0, -0.002, 0))

	# Team ring on the table, so teams read from the overview camera.
	_ground_ring = MeshInstance3D.new()
	_ground_ring.mesh = MeshKit.annulus(1.12, 1.3, true, 64)
	_ground_ring.material_override = _ring_mat
	_ground_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground_ring)

	_figure_pivot = Node3D.new()
	_figure_pivot.name = "Figure"
	_figure_pivot.visible = false
	_figure_pivot.scale = Vector3.ONE * 0.001
	add_child(_figure_pivot)
	_figure = Sprite3D.new()
	_figure.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_figure.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_figure.shaded = false
	_figure.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_figure_pivot.add_child(_figure)

	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.albedo_texture = _get_flash_texture()
	_flash_mat.no_depth_test = false
	_flash = MeshInstance3D.new()
	_flash.mesh = QuadMesh.new()
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.position.y = 0.2
	_flash.visible = false
	add_child(_flash)

	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 48
	_burst.lifetime = 0.8
	_burst.explosiveness = 0.95
	_burst.direction = Vector3.UP
	_burst.spread = 70.0
	_burst.initial_velocity_min = 2.0
	_burst.initial_velocity_max = 4.5
	_burst.gravity = Vector3(0, -8, 0)
	_burst.local_coords = true
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	dot.radial_segments = 6
	dot.rings = 3
	_burst_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_burst_mat.vertex_color_use_as_albedo = true
	_burst_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = _burst_mat
	_burst.mesh = dot
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	_burst.color_ramp = fade
	add_child(_burst)

	set_radius(radius)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _get_flash_texture() -> Texture2D:
	if _flash_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.7))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_flash_texture = t
	return _flash_texture


## Stand-in for a missing set emblem: a white star on a dark disc with a light rim.
static func _get_fallback_emblem() -> Texture2D:
	if _fallback_emblem != null:
		return _fallback_emblem
	var n: int = 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var star := PackedVector2Array()
	for i: int in 10:
		var ang: float = -PI * 0.5 + i * PI / 5.0
		var rr: float = 0.24 if i % 2 == 1 else 0.56
		star.append(Vector2(cos(ang), sin(ang)) * rr)
	for y: int in n:
		for x: int in n:
			var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			var d: float = p.length()
			var c := Color(0, 0, 0, 0)
			if d <= 1.0:
				c = Color("d9d2c5")
			if d <= 0.84:
				c = Color("16181c")
			if d <= 0.84 and Geometry2D.is_point_in_polygon(p, star):
				c = Color("f1e9dc")
			img.set_pixel(x, y, c)
	_fallback_emblem = ImageTexture.create_from_image(img)
	return _fallback_emblem


## Used when a hero has no sprite: a plain silhouette in the hero colour.
static func _placeholder_figure(color: Color) -> Texture2D:
	var w: int = 96
	var h: int = 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var head: bool = Vector2(x - w * 0.5, y - 36.0).length() < 28.0
			var body: bool = y > 62 and absf(x - w * 0.5) < 14.0 + (y - 62) * 0.28
			if head or body:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
