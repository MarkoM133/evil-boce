extends Node3D
## Sandbox (step 1a): spawn heroes, throw them with the slingshot, watch them snap, open and
## show their range. No game rules here.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"

enum Tool { NONE, SPAWN, TERRAIN }

var tuning: PhysicsTuning
var db: CardDb
var heroes: Array[HeroDef] = []
var arena: Arena
var world: ArenaWorld
## Painted terrain; the arena draws it and the world reads friction from it.
var terrain := TerrainMap.new()
var cam: OrbitCamera
var pieces: Array[SandboxPiece] = []

var _runner: RollRunner
var _last_outcome: RollOutcome
var _by_body: Dictionary[BallBody, SandboxPiece] = {}
var _balls: Node3D
var _aim_mesh := ImmediateMesh.new()
var _path_mesh := ImmediateMesh.new()
var _line_mat: StandardMaterial3D
var _panel: CheatPanel
var _hud: Control
var _power_label: Label
var _toast: Label
var _toast_tween: Tween
var _menu: Control

var _selected: SandboxPiece
var _hovered: SandboxPiece
var _tool: Tool = Tool.NONE
var _terrain_tool: Terrain.Type = Terrain.Type.NONE
var _aiming: SandboxPiece
var _aim_dir := Vector3.FORWARD
var _aim_power: float = 0.0
var _aim_pull := Vector3.ZERO
var _press_pos := Vector2.ZERO
var _press_on_empty: bool = false
var _auto_open: bool = true
var _show_path: bool = true
var _range_key: String = ""
var _next_id: int = 1


func _ready() -> void:
	tuning = PhysicsTuning.load_default()
	db = CardDb.load_from(GameSettings.data_path())
	heroes = db.heroes if db.is_ok() and not db.heroes.is_empty() else HeroDef.test_heroes()
	_build_scene()
	_build_hud()
	_set_map_size(GameSettings.map_size())


# --- scene ------------------------------------------------------------------

func _build_scene() -> void:
	TableEnv.add_to(self)

	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.set_terrain(terrain)
	world = ArenaWorld.new(tuning, arena, terrain)
	_balls = Node3D.new()
	_balls.name = "Balls"
	add_child(_balls)
	_runner = RollRunner.new()
	_runner.name = "RollRunner"
	_runner.finished.connect(_on_outcome)
	add_child(_runner)
	cam = OrbitCamera.new()
	cam.name = "Camera"
	add_child(cam)

	_line_mat = MeshKit.unshaded(Color.WHITE)
	_line_mat.no_depth_test = false
	for im: ImmediateMesh in [_aim_mesh, _path_mesh]:
		var mi := MeshInstance3D.new()
		mi.mesh = im
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _set_map_size(n: int) -> void:
	_clear_balls()
	GameSettings.set_map_size(n)
	terrain.clear()
	arena.build(HexMap.new(n, tuning.hex_size), tuning)
	cam.frame_table(arena.extent())
	_range_key = ""
	_panel.set_last_throw("–", "Distance is start hex to end hex.")


func _clear_balls() -> void:
	_cancel_aim()
	_select(null)
	_hovered = null
	for p: SandboxPiece in pieces:
		p.body.queue_free()
	pieces.clear()
	world.bodies.clear()
	_by_body.clear()
	_runner.unwatch_all()
	_last_outcome = null
	_path_mesh.clear_surfaces()


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = UiTheme.get_theme()
	layer.add_child(_hud)

	_panel = CheatPanel.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -312
	_panel.offset_right = -12
	_panel.offset_top = 12
	_panel.offset_bottom = -12
	_hud.add_child(_panel)
	var info: String = "cards.json v%d · %d heroes" % [db.version, db.heroes.size()]
	if not db.is_ok():
		info = db.error + " · using test balls"
	_panel.set_heroes(heroes, info)
	_panel.map_size_selected.connect(_set_map_size)
	_panel.reset_pressed.connect(_on_reset)
	_panel.spawn_toggled.connect(_on_spawn_toggled)
	_panel.terrain_tool_selected.connect(_on_terrain_tool)
	_panel.wt_changed.connect(_on_wt_changed)
	_panel.range_changed.connect(_on_range_changed)
	_panel.hp_changed.connect(_on_hp_changed)
	_panel.open_pressed.connect(_toggle_open_selected)
	_panel.remove_pressed.connect(_remove_selected)
	_panel.show_path_toggled.connect(_on_show_path)
	_panel.auto_open_toggled.connect(func(on: bool) -> void: _auto_open = on)

	var menu_btn := Button.new()
	menu_btn.text = "MENU"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.position = Vector2(12, 12)
	menu_btn.pressed.connect(_toggle_menu)
	_hud.add_child(menu_btn)

	var hint := Label.new()
	hint.theme_type_variation = &"Muted"
	hint.text = "Drag a ball: throw  ·  Right drag / drag table: turn  ·  Middle drag, WASD: move  ·  Wheel: zoom  ·  Q E: turn  ·  O open  ·  F focus  ·  Del remove  ·  Home reset view"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(14, -30)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud.add_child(hint)

	_power_label = Label.new()
	_power_label.add_theme_font_override("font", UiTheme.display_bold())
	_power_label.add_theme_font_size_override("font_size", 26)
	_power_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_power_label.add_theme_constant_override("outline_size", 6)
	_power_label.visible = false
	_hud.add_child(_power_label)

	_toast = Label.new()
	_toast.add_theme_font_override("font", UiTheme.display_bold())
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_color", Palette.GOLD)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(-300, 24)
	_toast.size = Vector2(600, 40)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_toast)

	_menu = _build_menu_overlay()
	_hud.add_child(_menu)


func _build_menu_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(260, 0)
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = &"Big"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_toggle_menu)
	col.add_child(resume)
	var back := Button.new()
	back.text = "Main menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	col.add_child(back)
	return root


func _toggle_menu() -> void:
	_menu.visible = not _menu.visible


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


# --- pieces -----------------------------------------------------------------

func spawn(hero: HeroDef, team: int, pos: Vector3) -> SandboxPiece:
	var p := SandboxPiece.new()
	p.hero = hero
	p.team = team
	# Same range as in a Standard match.
	p.rng = MatchSettings.standard().adjust_rng(hero.rng)
	p.hp = hero.hp
	p.body = BallBody.new()
	p.body.name = "%s_%d" % [hero.id, _next_id]
	p.body.setup("%s#%d" % [hero.id, _next_id], hero.wt, world)
	_next_id += 1
	p.view = BallView.new()
	p.view.configure(hero.ball_color, hero.ball_accent, Palette.team(team), db.emblem(hero.set_code), db.sprite(hero))
	p.view.set_radius(p.body.radius())
	p.body.add_child(p.view)
	_balls.add_child(p.body)
	p.body.place(pos)
	p.body.moved.connect(p.view.roll)
	p.body.motion_started.connect(_on_motion_started)
	p.body.roll_finished.connect(_on_roll_finished)
	p.view.state_changed.connect(func(_s: BallView.State) -> void: _on_view_state(p))
	pieces.append(p)
	world.bodies.append(p.body)
	_by_body[p.body] = p
	_runner.watch(p.body)
	p.view.settle()
	return p


func _remove(p: SandboxPiece) -> void:
	if p == null:
		return
	if _aiming == p:
		_cancel_aim()
	if _selected == p:
		_select(null)
	if _hovered == p:
		_hovered = null
	pieces.erase(p)
	world.bodies.erase(p.body)
	_by_body.erase(p.body)
	_runner.unwatch(p.body)
	p.body.queue_free()
	_range_key = ""


func _select(p: SandboxPiece) -> void:
	if _selected != null:
		_selected.view.set_glow(false)
	_selected = p
	if p != null:
		p.view.set_glow(true)
	_panel.show_selection(p)
	_range_key = ""


func _on_view_state(p: SandboxPiece) -> void:
	if p == _selected:
		_panel.set_open_state(p.view.is_open())


func _find_hero(id: String) -> HeroDef:
	for h: HeroDef in heroes:
		if h.id == id:
			return h
	return heroes[absi(id.hash()) % heroes.size()]


# --- physics events -----------------------------------------------------------

func _on_motion_started(ball: BallBody, thrown: bool) -> void:
	var p: SandboxPiece = _by_body.get(ball)
	if p == null:
		return
	if p.view.is_open() or p.view.state == BallView.State.CLOSING:
		p.view.close(true)
	_range_key = ""


## Off the table or onto any start strip (own included) after being on the map is a ring-out.
## The match applies the same rule in the rules engine; the sim only reports the facts.
static func _is_out(r: RollResult) -> bool:
	return r.ring_out or r.strip_entered >= 0


func _on_roll_finished(ball: BallBody, result: RollResult) -> void:
	var p: SandboxPiece = _by_body.get(ball)
	if p == null:
		return
	if _is_out(result):
		p.return_in = tuning.ring_out_return_delay
		_show_toast("RING-OUT  ·  %s" % p.label())
	elif _auto_open and result.end_area == BallWorld.Area.MAP:
		p.view.open()
	else:
		p.view.settle()
	_range_key = ""


## Throws `p` through the RollRunner; false while another roll is still going.
func _throw(p: SandboxPiece, dir: Vector3, power: float) -> bool:
	if _runner.is_running():
		_show_toast("Wait for the roll to finish")
		return false
	return _runner.start(p.body, dir, power)


func _on_outcome(o: RollOutcome) -> void:
	_last_outcome = o
	_report_throw(o)
	_draw_paths()


func _piece_by_id(ball_id: String) -> SandboxPiece:
	for q: SandboxPiece in pieces:
		if q.body.ball_id == ball_id:
			return q
	return null


func _report_throw(o: RollOutcome) -> void:
	var r: RollResult = o.thrower_result()
	var p: SandboxPiece = _piece_by_id(o.thrower)
	if r == null or p == null:
		return
	var spacing: float = tuning.hex_spacing()
	var big: String
	if _is_out(r):
		big = "RING-OUT"
	else:
		big = "%d HEX" % Hex.distance(r.start_hex, r.end_hex)
	var hits: String = "no hits"
	if not r.collisions.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for id: String in r.collisions:
			var q: SandboxPiece = _piece_by_id(id)
			if q != null:
				names.append(q.label())
		hits = "hit " + ", ".join(names)
	var info: String = "%s · WT%d · power %d%%\n%.1f hexes in a straight line, %.1f s, %s" % [
		p.label(), p.body.wt, roundi(r.power * 100.0), r.displacement() / spacing, r.duration, hits]
	if r.ring_out:
		info += "\nout over the edge"
	elif r.strip_entered >= 0:
		info += "\nout onto team %d's start strip" % (r.strip_entered + 1)
	if o.results.size() > 1:
		info += "\n%d balls moved, table still after %.1f s" % [o.results.size(), o.duration]
	_panel.set_last_throw(big, info)


func _return_to_strip(p: SandboxPiece) -> void:
	var r: float = p.body.radius()
	var x0: float = p.body.global_position.x
	var step: float = 2.0 * tuning.radius(tuning.big_from_wt) + 0.2
	for i: int in 40:
		var off: float = step * ceilf(i / 2.0) * (1.0 if i % 2 == 0 else -1.0)
		var pos: Vector3 = arena.strip_point(p.team, x0 + off, r)
		var free: bool = true
		for q: SandboxPiece in pieces:
			if q != p and _dist2(q.body.global_position, pos) < pow(q.body.radius() + r + 0.1, 2.0):
				free = false
				break
		if free:
			p.view.close_now()
			p.body.place(pos)
			p.view.settle()
			return
	p.body.place(arena.strip_point(p.team, x0, r))


static func _dist2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()


# --- frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	for p: SandboxPiece in pieces:
		if p.return_in >= 0.0:
			p.return_in -= delta
			if p.return_in < 0.0:
				_return_to_strip(p)
	if _aiming != null:
		_update_aim()
	_refresh_marks()


func _refresh_marks() -> void:
	var cells: Array[Vector2i] = []
	var marked: Array[Vector2i] = []
	var key: String = ""
	for p: SandboxPiece in [_selected, _hovered]:
		if p == null or p.body.motion != BallBody.Motion.RESTING:
			continue
		var c: Vector2i = p.body.cell
		key += "%s:%s:%d:%d;" % [p.body.ball_id, c, p.rng, p.body.wt]
		cells.append_array(arena.map.range_cells(c, p.body.is_big(), p.rng))
		marked.append_array(arena.map.footprint(c, p.body.is_big()))
	if _tool != Tool.NONE:
		var g: Variant = _ground_under_mouse()
		if g != null:
			var gp: Vector3 = g
			var h: Vector2i = arena.hex_at(gp)
			var big: bool = _tool == Tool.TERRAIN
			if _tool == Tool.SPAWN:
				var hero: HeroDef = _panel.selected_hero()
				big = hero != null and tuning.is_big(hero.wt)
			key += "tool:%s:%s" % [h, big]
			marked.append_array(arena.map.footprint(h, big))
	if key == _range_key:
		return
	_range_key = key
	arena.show_range(cells, marked)


func _draw_paths() -> void:
	_path_mesh.clear_surfaces()
	if not _show_path:
		return
	if _last_outcome == null:
		return
	var any: bool = false
	for r: RollResult in _last_outcome.results:
		if r.path.size() >= 2:
			any = true
	if not any:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_mat)
	for r: RollResult in _last_outcome.results:
		var p: SandboxPiece = _piece_by_id(r.ball_id)
		if p == null:
			continue
		var pts := PackedVector3Array()
		for v: Vector3 in r.path:
			if v.y > -0.05:
				pts.append(Vector3(v.x, 0.03, v.z))
		var width: float = 0.12 if r.ball_id == _last_outcome.thrower else 0.07
		MeshKit.ribbon(_path_mesh, pts, width, Color(Palette.team(p.team).lightened(0.35), 0.75))
	_path_mesh.surface_end()


# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _menu.visible:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_toggle_menu()
		return
	if event is InputEventKey:
		_on_key(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left(mb.pressed)
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and (_aiming != null or _tool != Tool.NONE):
			_cancel_aim()
			_set_tool(Tool.NONE)
			return
	if event is InputEventMouseMotion and _aiming == null and not cam.is_dragging():
		_update_hover()
	cam.handle_input(event)


func _on_key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_ESCAPE:
			if _aiming != null:
				_cancel_aim()
			elif _tool != Tool.NONE:
				_set_tool(Tool.NONE)
			else:
				_toggle_menu()
		KEY_O:
			_toggle_open_selected()
		KEY_DELETE, KEY_BACKSPACE:
			_remove_selected()
		KEY_F:
			if _selected != null:
				cam.focus(_selected.body.global_position, 9.0)
		KEY_HOME:
			cam.reset_view()


func _on_left(pressed: bool) -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	if pressed:
		_press_pos = mouse
		_press_on_empty = false
		if _tool == Tool.SPAWN:
			_spawn_at_mouse()
			return
		if _tool == Tool.TERRAIN:
			_paint_at_mouse()
			return
		var p: SandboxPiece = _piece_under_mouse()
		if p != null:
			_select(p)
			if p.body.motion == BallBody.Motion.RESTING and p.return_in < 0.0:
				_start_aim(p)
			return
		_press_on_empty = true
		cam.begin_drag(OrbitCamera.Drag.ORBIT)
		return
	if _aiming != null:
		_release_aim()
		return
	cam.begin_drag(OrbitCamera.Drag.NONE)
	if _press_on_empty and mouse.distance_to(_press_pos) < 5.0:
		_select(null)
	_press_on_empty = false


func _piece_under_mouse() -> SandboxPiece:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = cam.camera.project_ray_origin(mouse)
	var to: Vector3 = from + cam.camera.project_ray_normal(mouse) * 500.0
	var q := PhysicsRayQueryParameters3D.create(from, to, BallBody.LAYER_BALLS)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var obj: Object = hit.get("collider")
	if obj is BallBody:
		return _by_body.get(obj as BallBody)
	return null


## Point on the table (y = 0) under the mouse, or null.
func _ground_under_mouse() -> Variant:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = cam.camera.project_ray_origin(mouse)
	var dir: Vector3 = cam.camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, dir)


func _update_hover() -> void:
	var p: SandboxPiece = _piece_under_mouse()
	if p != _hovered:
		_hovered = p


# --- slingshot --------------------------------------------------------------

func _start_aim(p: SandboxPiece) -> void:
	_aiming = p
	_aim_power = 0.0
	arena.set_grid_emphasis(true)
	_power_label.visible = true
	_update_aim()


func _update_aim() -> void:
	var p: SandboxPiece = _aiming
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var ball: Vector3 = p.body.global_position
	var ball_screen: Vector2 = cam.camera.unproject_position(ball)
	var full: float = tuning.max_drag_screen_fraction * get_viewport().get_visible_rect().size.y
	_aim_power = clampf(mouse.distance_to(ball_screen) / full, 0.0, 1.0)
	var g: Variant = _ground_under_mouse()
	if g != null:
		var gp: Vector3 = g
		var pull := Vector3(gp.x - ball.x, 0, gp.z - ball.z)
		if pull.length() > 0.05:
			_aim_dir = -pull.normalized()
			_aim_pull = pull
	_draw_aim()
	_power_label.text = "%d%%" % roundi(_aim_power * 100.0)
	_power_label.position = _hud.get_local_mouse_position() + Vector2(18, -34)
	_power_label.add_theme_color_override("font_color", Palette.GOLD if _aim_power >= 0.995 else Palette.FG)


func _draw_aim() -> void:
	_aim_mesh.clear_surfaces()
	if _aiming == null or _aim_power < tuning.min_power:
		return
	var ball: Vector3 = _aiming.body.global_position
	var r: float = _aiming.body.radius()
	var base := Vector3(ball.x, 0.05, ball.z)
	var side: Vector3 = Vector3.UP.cross(_aim_dir)
	var len: float = r + 0.3 + _aim_power * 4.0 * tuning.hex_spacing()
	var color: Color = Color.WHITE.lerp(Palette.GOLD, _aim_power)
	_aim_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_mat)
	var band := PackedVector3Array([base, base + _aim_pull.limit_length(len * 1.2)])
	MeshKit.ribbon(_aim_mesh, band, 0.05, Color(1, 1, 1, 0.35))
	var start: Vector3 = base + _aim_dir * (r + 0.15)
	var head: Vector3 = base + _aim_dir * len
	MeshKit.ribbon(_aim_mesh, PackedVector3Array([start, head]), 0.16, Color(color, 0.95))
	var hw: float = 0.38
	_aim_mesh.surface_set_color(Color(color, 0.95))
	_aim_mesh.surface_add_vertex(head + side * hw)
	_aim_mesh.surface_add_vertex(head - side * hw)
	_aim_mesh.surface_add_vertex(head + _aim_dir * 0.6)
	_aim_mesh.surface_end()


func _release_aim() -> void:
	var p: SandboxPiece = _aiming
	var power: float = _aim_power
	var dir: Vector3 = _aim_dir
	_cancel_aim()
	if p == null or power < tuning.min_power:
		return
	if _runner.is_running():
		_show_toast("Wait for the roll to finish")
		return
	if p.view.state == BallView.State.CLOSED:
		_throw(p, dir, power)
		return
	p.view.close(true)
	get_tree().create_timer(BallView.CLOSE_TIME_FAST).timeout.connect(func() -> void:
		if is_instance_valid(p.body) and p.body.motion == BallBody.Motion.RESTING:
			_throw(p, dir, power))


func _cancel_aim() -> void:
	_aiming = null
	_aim_mesh.clear_surfaces()
	if _power_label != null:
		_power_label.visible = false
	if arena != null:
		arena.set_grid_emphasis(_tool != Tool.NONE)


# --- tools ------------------------------------------------------------------

func _set_tool(t: Tool) -> void:
	_tool = t
	if t != Tool.SPAWN:
		_panel.set_spawn_active(false)
	if t != Tool.TERRAIN:
		_panel.clear_terrain_tool()
	arena.set_grid_emphasis(t != Tool.NONE or _aiming != null)
	_range_key = ""


func _on_spawn_toggled(on: bool) -> void:
	_set_tool(Tool.SPAWN if on else Tool.NONE)


func _on_terrain_tool(t: int) -> void:
	if t < 0:
		_set_tool(Tool.NONE)
		return
	_terrain_tool = t as Terrain.Type
	_set_tool(Tool.TERRAIN)


func _spawn_at_mouse() -> void:
	var hero: HeroDef = _panel.selected_hero()
	var g: Variant = _ground_under_mouse()
	if hero == null or g == null:
		return
	var gp: Vector3 = g
	var team: int = _panel.selected_team()
	var r: float = tuning.radius(hero.wt)
	var pos: Vector3
	match arena.area_at(gp):
		BallWorld.Area.MAP:
			var h: Vector2i = arena.hex_at(gp)
			if not world.is_free(h, tuning.is_big(hero.wt)):
				_show_toast("Hex taken")
				return
			pos = arena.hex_center(h)
		BallWorld.Area.STRIP:
			pos = arena.strip_point(arena.strip_at(gp), gp.x, r)
			for q: SandboxPiece in pieces:
				if _dist2(q.body.global_position, pos) < pow(q.body.radius() + r, 2.0):
					_show_toast("Spot taken")
					return
		_:
			return
	_select(spawn(hero, team, pos))


func _paint_at_mouse() -> void:
	var g: Variant = _ground_under_mouse()
	if g == null:
		return
	var gp: Vector3 = g
	terrain.set_patch(arena.hex_at(gp), _terrain_tool, arena.map)
	arena.refresh_terrain()


# --- panel callbacks ----------------------------------------------------------

func _on_reset() -> void:
	_clear_balls()
	terrain.clear()
	arena.refresh_terrain()
	_set_tool(Tool.NONE)
	_panel.set_last_throw("–", "Distance is start hex to end hex.")


func _on_wt_changed(v: int) -> void:
	if _selected == null:
		return
	_selected.body.set_wt(v)
	_selected.view.set_radius(_selected.body.radius())
	if arena.area_at(_selected.body.global_position) == BallWorld.Area.MAP:
		_selected.body.resnap()
	_range_key = ""


func _on_range_changed(v: int) -> void:
	if _selected != null:
		_selected.rng = v
		_range_key = ""


func _on_hp_changed(v: int) -> void:
	if _selected != null:
		_selected.hp = v


func _toggle_open_selected() -> void:
	if _selected == null or _selected.body.motion != BallBody.Motion.RESTING:
		return
	if _selected.view.is_open():
		_selected.view.close()
	else:
		_selected.view.open()


func _remove_selected() -> void:
	_remove(_selected)


func _on_show_path(on: bool) -> void:
	_show_path = on
	_draw_paths()


# --- screenshot helpers (tools/screenshot.gd --call=...) ------------------------

func demo_setup() -> void:
	var c: Vector2i = arena.map.center_cell()
	var luffy: SandboxPiece = spawn(_find_hero("OP1-001"), 0, arena.hex_center(c + Vector2i(-2, 3)))
	spawn(_find_hero("OP1-005"), 1, arena.hex_center(c + Vector2i(2, -3)))
	spawn(_find_hero("JO1-002"), 1, arena.hex_center(c + Vector2i(4, -1)))
	spawn(_find_hero("OP1-002"), 0, arena.strip_point(0, -3.0, 1.0))
	spawn(_find_hero("JO1-005"), 1, arena.strip_point(1, 4.0, 1.0))
	terrain.set_patch(c + Vector2i(-4, 0), Terrain.Type.ICE, arena.map)
	terrain.set_patch(c + Vector2i(4, 1), Terrain.Type.MUD, arena.map)
	arena.refresh_terrain()
	for p: SandboxPiece in pieces:
		if arena.area_at(p.body.global_position) == BallWorld.Area.MAP:
			p.view.open()
	_select(luffy)


func demo_closeup() -> void:
	if _selected != null:
		cam.focus(_selected.body.global_position + Vector3(0, 0, -0.5), 7.0)
		cam.pitch = deg_to_rad(28.0)
		cam.yaw = deg_to_rad(-20.0)


func demo_aim() -> void:
	var p: SandboxPiece = _selected if _selected != null else pieces[0]
	_aiming = p
	_aim_power = 0.7
	_aim_dir = Vector3(0.3, 0, -1).normalized()
	_aim_pull = -_aim_dir * 3.0
	arena.set_grid_emphasis(true)
	_draw_aim()
	set_process(false)


## Throws the selected ball at the nearest other ball on the map, at 80 % power.
func demo_throw() -> void:
	var p: SandboxPiece = _selected if _selected != null else pieces[0]
	var best: SandboxPiece = null
	for q: SandboxPiece in pieces:
		if q != p and arena.area_at(q.body.global_position) == BallWorld.Area.MAP:
			if best == null or _dist2(q.body.global_position, p.body.global_position) < _dist2(best.body.global_position, p.body.global_position):
				best = q
	if best == null:
		return
	var d: Vector3 = best.body.global_position - p.body.global_position
	p.view.close_now()
	_throw(p, d, 0.8)


## Throws the selected ball straight off the left edge.
func demo_ringout() -> void:
	var p: SandboxPiece = _selected if _selected != null else pieces[0]
	p.view.close_now()
	_throw(p, Vector3.LEFT, 1.0)


## Throws the selected ball at full power towards the far start strip.
func demo_strip() -> void:
	var p: SandboxPiece = _selected if _selected != null else pieces[0]
	p.view.close_now()
	_throw(p, Vector3.FORWARD if p.team == 0 else Vector3.BACK, 1.0)


## Prints every ball's state (for tools and debugging).
func debug_dump() -> void:
	for p: SandboxPiece in pieces:
		var pos: Vector3 = p.body.global_position
		print("%-22s motion=%s pos=(%.2f, %.2f, %.2f) area=%s cell=%s view=%s return_in=%.2f v=%s grounded=%s sleeping=%s" % [
			p.body.ball_id, BallBody.Motion.keys()[p.body.motion], pos.x, pos.y, pos.z,
			BallWorld.Area.keys()[arena.area_at(pos)], p.body.cell, BallView.State.keys()[p.view.state], p.return_in, p.body.linear_velocity, p.body.is_grounded(), p.body.sleeping])


## Makes the selected ball WT4 (covers 7 hexes).
func demo_big() -> void:
	if _selected != null:
		_on_wt_changed(4)
