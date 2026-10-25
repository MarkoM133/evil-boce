class_name MenuTable
extends SubViewportContainer
## The main menu's table (mockup M8 + 3): the match table in 3D behind the logo, fading into
## the black, with a few heroes' balls on it. Hovering a ball opens it into the hero's figure
## until the mouse leaves; a click keeps it open, another click closes it. The camera drifts
## slowly from side to side.

const MAP_SIZE: int = 7
## Seconds for one sway of the camera, and how far it turns (degrees).
const DRIFT_TIME: float = 16.0
const DRIFT_YAW: float = 7.0
const PITCH: float = 30.0
## How near the mouse must be to a ball (or its open figure) on screen, in pixels.
const PICK_PX: float = 40.0
## Where the balls stand, as shares of the table's size (x across, z towards the camera):
## out to the sides of the logo, behind the menu row.
const SPOTS: Array[Vector2] = [Vector2(-0.38, -0.04), Vector2(-0.26, -0.3), Vector2(0.38, -0.1), Vector2(0.28, -0.33)]

var _viewport: SubViewport
var _cam: Camera3D
var _target: Vector3
var _distance: float = 10.0
var _balls: Array[BallView] = []
var _pinned: Dictionary[BallView, bool] = {}
var _hover: BallView
var _t: float = 0.0


func setup(db: CardDb) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var root := Node3D.new()
	_viewport.add_child(root)
	TableEnv.add_to(root)
	# Black around the table, and thicker fog so its far side sinks into it.
	for c: Node in root.get_children():
		if c is WorldEnvironment:
			var env: Environment = (c as WorldEnvironment).environment
			env.background_color = Palette.BG
			env.fog_light_color = Palette.BG
			env.fog_density = 0.035

	var tuning: PhysicsTuning = PhysicsTuning.load_default()
	var arena := Arena.new()
	root.add_child(arena)
	arena.set_terrain(TerrainMap.new())
	arena.build(HexMap.new(MAP_SIZE, tuning.hex_size), tuning)
	var ext: Vector2 = arena.extent()
	_target = Vector3(0, 0, ext.y * 0.12)
	_distance = maxf(ext.x, ext.y) * 1.25
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_place_camera()

	# Heroes with a figure, two of each team.
	var heroes: Array[HeroDef] = []
	if db != null and db.is_ok():
		for h: HeroDef in db.heroes:
			if db.sprite(h) != null:
				heroes.append(h)
	heroes.shuffle()
	for i: int in mini(SPOTS.size(), heroes.size()):
		var h: HeroDef = heroes[i]
		var team: int = 0 if SPOTS[i].x < 0.0 else 1
		var view := BallView.new()
		view.configure(h.ball_color, h.ball_accent, Palette.team(team), db.emblem(h.set_code), db.sprite(h), h.color_name)
		var r: float = tuning.radius(h.wt)
		view.set_radius(r)
		root.add_child(view)
		var spot: Vector3 = arena.hex_center(arena.hex_at(Vector3(SPOTS[i].x * ext.x, 0, SPOTS[i].y * ext.y)))
		view.position = spot + Vector3(0, r, 0)
		# Turned a little towards the middle, so the emblems show.
		view.rotation.y = deg_to_rad(25.0 if team == 0 else -25.0)
		view.settle()
		_balls.append(view)

	# The edges sink into the black.
	var vignette := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.45)
	grad.fill_to = Vector2(1.0, 0.45)
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(Palette.BG, 0.0))
	grad.gradient.set_color(1, Palette.BG)
	grad.gradient.add_point(0.55, Color(Palette.BG, 0.0))
	vignette.texture = grad
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


## Opens the first ball and keeps it open (screenshots).
func pin_first() -> void:
	if not _balls.is_empty():
		_pinned[_balls[0]] = true
		_balls[0].open()


func _process(delta: float) -> void:
	_t += delta
	_place_camera()


func _place_camera() -> void:
	if _cam == null:
		return
	var yaw: float = deg_to_rad(DRIFT_YAW) * sin(TAU * _t / DRIFT_TIME)
	var pitch: float = deg_to_rad(PITCH)
	_cam.position = _target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _distance
	_cam.look_at(_target)


func _input(event: InputEvent) -> void:
	if _balls.is_empty() or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		_set_hover(_ball_at(get_local_mouse_position()))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _hover != null:
			if _pinned.has(_hover):
				_pinned.erase(_hover)
				_hover.close()
			else:
				_pinned[_hover] = true
				if not _hover.is_open():
					_hover.open()
			get_viewport().set_input_as_handled()


func _set_hover(b: BallView) -> void:
	if b == _hover:
		return
	if _hover != null and not _pinned.has(_hover):
		_hover.close()
	_hover = b
	if b != null and not b.is_open():
		b.open()


## The ball under `p` (local pixels): near its centre, or along its figure when it is open.
## None while the mouse is on a button of the menu.
func _ball_at(p: Vector2) -> BallView:
	if get_viewport().gui_get_hovered_control() is BaseButton:
		return null
	var scale_px: float = float(_viewport.size.x) / maxf(size.x, 1.0)
	var vp: Vector2 = p * scale_px
	var best: BallView = null
	var best_d: float = PICK_PX * scale_px
	for b: BallView in _balls:
		var c: Vector2 = _cam.unproject_position(b.global_position)
		var d: float = vp.distance_to(c)
		if b.is_open():
			var top: Vector2 = _cam.unproject_position(b.global_position + Vector3.UP * b.radius * BallView.FIGURE_HEIGHT)
			d = vp.distance_to(Geometry2D.get_closest_point_to_segment(vp, c, top))
		if d < best_d:
			best_d = d
			best = b
	return best
