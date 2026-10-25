extends Node3D
## A 1v1 match (step 2). The rules engine owns the GameState; this scene draws it, turns clicks
## into moves, runs the physics for the Roll phase and feeds the RollOutcome back. Slots are
## local players (hot seat) or the placeholder SimpleBot.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
## Seconds between two bot moves, so a human can follow.
const BOT_DELAY: float = 0.5
## Core token radius; a rolling ball picks a core up when it touches it.
const CORE_RADIUS: float = 0.34
const CORE_COLORS: Dictionary[String, Color] = {
	"Buff": Color("4fb858"), "Major": Color("ffd23f"), "Debuff": Color("9a5bd6"),
}

var tuning: PhysicsTuning
var db: CardDb
var engine: RulesEngine
var state: GameState
var arena: Arena
var world: ArenaWorld
var cam: OrbitCamera
var hud: MatchHud
var bots: Dictionary[int, SimpleBot] = {}

var _config: Dictionary = {}
var _runner: RollRunner
var _sling: Slingshot
var _balls: Node3D
var _tokens: Node3D
var _marks := ImmediateMesh.new()
var _line_mat: StandardMaterial3D
var _bodies: Dictionary[String, BallBody] = {}
var _views: Dictionary[String, BallView] = {}
var _core_tokens: Dictionary[String, Node3D] = {}
var _hovered: String = ""
var _range_key: String = ""
var _launching: bool = false
## Core id -> ball id, in pick-up order, while a roll runs.
var _picked: Dictionary[String, String] = {}
var _pick_order: PackedStringArray = PackedStringArray()
var _bot_wait: float = 0.0
var _press_on_empty: bool = false
var _menu: Control


func _ready() -> void:
	tuning = PhysicsTuning.load_default()
	db = CardDb.load_from(GameSettings.data_path())
	engine = RulesEngine.new(db.catalog)
	_config = MatchLaunch.take(db.catalog)
	var settings: MatchSettings = _config["settings"]
	var decks: Array = _config["decks"]
	var seed_: int = JsonUtil.as_int(_config.get("seed", 1), 1)
	state = engine.start_match(settings, decks, seed_)
	for slot: int in JsonUtil.as_array(_config.get("bots", [])):
		bots[slot] = SimpleBot.new(seed_ + slot)

	TableEnv.add_to(self)
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)
	arena.build(HexMap.new(settings.map_size, tuning.hex_size), tuning)
	world = ArenaWorld.new(tuning, arena, engine.terrain(state))
	arena.set_terrain(world.terrain)
	_balls = Node3D.new()
	_balls.name = "Balls"
	add_child(_balls)
	_tokens = Node3D.new()
	_tokens.name = "Tokens"
	add_child(_tokens)
	_runner = RollRunner.new()
	_runner.name = "RollRunner"
	_runner.finished.connect(_on_roll_finished)
	add_child(_runner)
	cam = OrbitCamera.new()
	cam.name = "Camera"
	add_child(cam)
	cam.frame_table(arena.extent(), 0.13, 1.32)

	_line_mat = MeshKit.unshaded(Color.WHITE)
	var marks_mi := MeshInstance3D.new()
	marks_mi.mesh = _marks
	marks_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marks_mi)
	_sling = Slingshot.new(tuning)
	add_child(_sling.make_instance())

	_build_balls()
	_build_hud()
	_sync()


# --- scene ------------------------------------------------------------------

func _build_balls() -> void:
	for h: HeroState in state.heroes:
		var card: CardDef = db.catalog.get_card(h.card_id)
		var def: HeroDef = _hero_def(h.card_id)
		var b := BallBody.new()
		b.name = h.id.replace(":", "_")
		b.setup(h.id, card.wt if card != null else 2, world)
		var v := BallView.new()
		var color: Color = def.ball_color if def != null else Palette.hero(card.color if card != null else "")
		var accent: Color = def.ball_accent if def != null else Palette.DEFAULT_ACCENT
		v.configure(color, accent, Palette.team(state.team_of(h.owner)),
			db.emblem(def.set_code if def != null else ""), db.sprite(def) if def != null else null)
		v.set_radius(b.radius())
		b.add_child(v)
		_balls.add_child(b)
		b.place(_strip_spot(h))
		b.moved.connect(v.roll)
		v.settle()
		_bodies[h.id] = b
		_views[h.id] = v
		world.bodies.append(b)
		_runner.watch(b)


func _hero_def(card_id: String) -> HeroDef:
	for d: HeroDef in db.heroes:
		if d.id == card_id:
			return d
	return null


## Where a hero waits on its start strip: its own spot along the strip.
func _strip_spot(h: HeroState) -> Vector3:
	var team: int = state.team_of(h.owner)
	var mine: Array[HeroState] = state.heroes_of(h.owner)
	var i: int = mine.find(h)
	var xr: Vector2 = arena.strip_x_range(team)
	var t: float = float(i + 1) / float(mine.size() + 1)
	return arena.strip_point(team, lerpf(xr.x, xr.y, t), 1.0)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = MatchHud.new()
	layer.add_child(hud)
	var local := PackedInt32Array()
	for p: PlayerState in state.players:
		if not bots.has(p.slot):
			local.append(p.slot)
	hud.setup(engine, state, db, local)
	hud.pass_pressed.connect(func(slot: int) -> void: _apply(Move.make(Move.PASS, slot)))
	hud.choice_pressed.connect(func(slot: int, roll: bool) -> void: _apply(Move.make(Move.CHOICE, slot, {"roll": roll})))
	hud.keep_pressed.connect(func(slot: int, keep: bool) -> void: _apply(Move.make(Move.MULLIGAN, slot, {"keep": keep})))
	hud.no_hero_pressed.connect(func(slot: int) -> void: _apply(Move.make(Move.SELECT, slot, {"hero": ""})))
	hud.card_pressed.connect(func(slot: int, cid: String) -> void: _apply(Move.make(Move.PLAY_CARD, slot, {"card": cid})))
	hud.damage_pressed.connect(func(slot: int, target: String) -> void: _apply(Move.make(Move.DAMAGE_TO, slot, {"target": target})))
	hud.hero_clicked.connect(_on_hero_clicked)
	hud.hero_hovered.connect(func(id: String) -> void: _set_hover(id, false))
	hud.menu_pressed.connect(_toggle_menu)
	hud.rematch_pressed.connect(_rematch)
	_menu = _build_menu_overlay()
	layer.add_child(_menu)


func _build_menu_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
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
	for slot: int in hud.local_slots:
		var give_up := Button.new()
		give_up.text = "Surrender (%s)" % hud.player_name(slot)
		give_up.pressed.connect(func() -> void:
			_toggle_menu()
			_apply(Move.make(Move.SURRENDER, slot)))
		col.add_child(give_up)
	var back := Button.new()
	back.text = "Main menu"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	col.add_child(back)
	return root


func _toggle_menu() -> void:
	if state.is_over():
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	_menu.visible = not _menu.visible


func _rematch() -> void:
	var settings: MatchSettings = _config["settings"]
	var c: Dictionary = _config.duplicate()
	c["settings"] = MatchSettings.from_dict(settings.to_dict())
	c["seed"] = randi()
	MatchLaunch.config = c
	get_tree().change_scene_to_file(MATCH_SCENE)


# --- moves ------------------------------------------------------------------

func _apply(m: Move) -> void:
	if _runner.is_running() or _launching:
		return
	var err: String = engine.apply(state, m)
	if not err.is_empty():
		hud.toast(err, Palette.FG)
		return
	_sync()


## Puts every node where the state says and redraws the HUD.
func _sync() -> void:
	world.terrain = engine.terrain(state)
	arena.set_terrain(world.terrain)
	world.blocked.clear()
	for w: WallState in state.walls:
		for a: Vector2i in w.hexes:
			world.blocked[a] = true
	for h: HeroState in state.heroes:
		_sync_hero(h)
	_rebuild_tokens()
	_range_key = ""
	_draw_marks()
	hud.rolling = _runner.is_running() or _launching
	hud.refresh()
	if state.awaiting_roll and not _runner.is_running() and not _launching:
		_launch_roll()


func _sync_hero(h: HeroState) -> void:
	var b: BallBody = _bodies[h.id]
	var v: BallView = _views[h.id]
	if h.is_ko():
		if b.visible:
			b.visible = false
			b.collision_layer = 0
			b.freeze = true
			world.bodies.erase(b)
		return
	var target: Vector3 = arena.hex_center(h.hex) if h.is_on_map() else _strip_spot(h)
	var here := Vector3(b.global_position.x, 0, b.global_position.z)
	if here.distance_to(target) > 0.05:
		if h.is_on_map() and arena.area_at(b.global_position) == BallWorld.Area.MAP:
			_slide(b, target)
		else:
			v.close_now()
			b.place(target)
			v.settle()
	if h.is_on_map() and not v.is_open() and v.state != BallView.State.OPENING:
		v.open()
	elif not h.is_on_map() and v.is_open():
		v.close()


## Knockback and other rule moves: slide the ball over to its new hex.
func _slide(b: BallBody, target: Vector3) -> void:
	b.freeze = true
	var to := Vector3(target.x, b.global_position.y, target.z)
	var t: Tween = create_tween()
	t.tween_property(b, "global_position", to, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: b.place(target))


# --- tokens and marks ----------------------------------------------------------

func _rebuild_tokens() -> void:
	for c: Node in _tokens.get_children():
		c.queue_free()
	_core_tokens.clear()
	for c: CoreState in state.cores:
		if c.place != CoreState.ON_FIELD:
			continue
		var card: CardDef = db.catalog.get_card(c.card_id)
		var col: Color = CORE_COLORS.get(card.kind if card != null else "", Palette.MUTED) if c.face_up else Color("2a2622")
		var token: Node3D = _hex_prism(CORE_RADIUS, 0.12, col, Palette.GOLD if not c.face_up else col.lightened(0.3))
		token.position = arena.hex_center(c.hex) + Vector3(0, 0.06, 0)
		_tokens.add_child(token)
		_core_tokens[c.id] = token
	for w: WallState in state.walls:
		for a: Vector2i in w.hexes:
			var wall: Node3D = _hex_prism(tuning.hex_size * 0.92, 1.2, Color("5a5049"), Color("6d625a"))
			wall.position = arena.hex_center(a) + Vector3(0, 0.6, 0)
			_tokens.add_child(wall)
	for st: StageState in state.stages:
		if st.is_claimed():
			var flag := MeshInstance3D.new()
			var pole := CylinderMesh.new()
			pole.top_radius = 0.05
			pole.bottom_radius = 0.05
			pole.height = 2.2
			flag.mesh = pole
			flag.material_override = MeshKit.unshaded(Palette.team(state.team_of(st.claimed_by)), false)
			flag.position = arena.hex_center(st.center) + Vector3(0, 1.1, 0)
			_tokens.add_child(flag)


func _hex_prism(radius: float, height: float, color: Color, rim: Color) -> Node3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 6
	m.rings = 1
	mi.mesh = m
	mi.rotation.y = PI / 6.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mat.emission_enabled = true
	mat.emission = rim
	mat.emission_energy_multiplier = 0.15
	mi.material_override = mat
	return mi


## Stage outlines and battle arrows.
func _draw_marks() -> void:
	_marks.clear_surfaces()
	_marks.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_mat)
	var any: bool = false
	for st: StageState in state.stages:
		if not st.placed:
			continue
		var col: Color = Color(Palette.GOLD, 0.35)
		if st.revealed:
			col = Color(Palette.GOLD, 0.85)
		if st.is_claimed():
			col = Palette.team(state.team_of(st.claimed_by))
		any = _outline(st.footprint(), col) or any
	if state.phase == GameState.PHASE_BATTLE or state.phase == GameState.PHASE_POSTROLL:
		any = _battle_arrows() or any
	if not any:
		_marks.surface_add_vertex(Vector3.ZERO)
		_marks.surface_add_vertex(Vector3.ZERO)
		_marks.surface_add_vertex(Vector3.ZERO)
	_marks.surface_end()


func _outline(cells: Array[Vector2i], color: Color) -> bool:
	var drew: bool = false
	for a: Vector2i in cells:
		var c2: Vector2 = arena.map.to_world(a)
		for i: int in 6:
			if cells.has(a + Hex.DIRECTIONS[i]):
				continue
			var p0: Vector2 = c2 + Hex.corner(i - 1, tuning.hex_size) * 0.97
			var p1: Vector2 = c2 + Hex.corner(i, tuning.hex_size) * 0.97
			MeshKit.ribbon(_marks, PackedVector3Array([Vector3(p0.x, 0.04, p0.y), Vector3(p1.x, 0.04, p1.y)]), 0.09, color)
			drew = true
	return drew


## Arrows from each hero to the opponents it reaches (range is not mutual, GDD 11).
func _battle_arrows() -> bool:
	var drew: bool = false
	var current := PackedStringArray()
	if state.phase == GameState.PHASE_BATTLE and state.battle_index >= 0 and state.battle_index < state.battles.size():
		current = JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", []))
	for a: HeroState in state.heroes:
		for b: HeroState in state.heroes:
			if a == b or state.same_team(a, b) or not engine.in_range(state, a, b):
				continue
			var hot: bool = current.has(a.id) and current.has(b.id)
			var col: Color = Palette.GOLD if hot else Color(1, 1, 1, 0.35)
			var from: Vector3 = arena.hex_center(a.hex)
			var to: Vector3 = arena.hex_center(b.hex)
			var d: Vector3 = (to - from).normalized()
			var ra: float = _bodies[a.id].radius() + 0.15
			var rb: float = _bodies[b.id].radius() + 0.35
			var start: Vector3 = from + d * ra + Vector3(0, 0.06, 0)
			var head: Vector3 = to - d * rb + Vector3(0, 0.06, 0)
			MeshKit.ribbon(_marks, PackedVector3Array([start, head]), 0.12 if hot else 0.07, col)
			var side: Vector3 = Vector3.UP.cross(d) * 0.3
			_marks.surface_set_color(col)
			_marks.surface_add_vertex(head + side)
			_marks.surface_add_vertex(head - side)
			_marks.surface_add_vertex(head + d * 0.45)
			drew = true
	return drew


## Range of the activated heroes always, of the hovered one too, and the legal hexes while a
## core waits to be put back.
func _refresh_range() -> void:
	var cells: Array[Vector2i] = []
	var marked: Array[Vector2i] = []
	var key: String = ""
	var ids := PackedStringArray()
	for slot: int in state.active:
		ids.append(str(state.active[slot]))
	if not _hovered.is_empty():
		ids.append(_hovered)
	for id: String in ids:
		var h: HeroState = state.hero(id)
		if h == null or not h.is_on_map() or _bodies[h.id].motion != BallBody.Motion.RESTING:
			continue
		var rng: int = engine.stat(state, h, "rng")
		key += "%s:%s:%d;" % [h.id, h.hex, rng]
		cells.append_array(arena.map.range_cells(h.hex, h.big, rng))
		marked.append_array(state.footprint(h))
	var d: Dictionary = _local_decision()
	if str(d.get("type", "")) == RulesEngine.DECISION_RETURN_CORE:
		var c: CoreState = state.core(str(d.get("core", "")))
		key += "core:%s" % c.id
		cells.clear()
		for a: Vector2i in arena.map.cells():
			if engine.core_return_error(state, c, a).is_empty():
				cells.append(a)
	if key == _range_key:
		return
	_range_key = key
	arena.show_range(cells, marked)


## The pending decision if a local player has to make it, else {}.
func _local_decision() -> Dictionary:
	if state.pending.is_empty():
		return {}
	var d: Dictionary = state.pending[0]
	return d if hud.local_slots.has(JsonUtil.as_int(d.get("player", -1), -1)) else {}


# --- roll -------------------------------------------------------------------

## Every aim is in: close the balls and throw them all at once.
func _launch_roll() -> void:
	_launching = true
	hud.rolling = true
	hud.refresh()
	for slot: int in state.aims:
		var h: HeroState = state.active_hero(slot)
		if h != null:
			_views[h.id].close(true)
	get_tree().create_timer(BallView.CLOSE_TIME_FAST + 0.05).timeout.connect(_throw_all)


func _throw_all() -> void:
	var throws: Array[Dictionary] = []
	var slots: Array = state.aims.keys()
	slots.sort()
	# The initiative player's throw goes first in the outcome.
	if slots.has(state.initiative):
		slots.erase(state.initiative)
		slots.push_front(state.initiative)
	for slot: Variant in slots:
		var s: int = JsonUtil.as_int(slot)
		var h: HeroState = state.active_hero(s)
		if h == null or h.is_ko():
			continue
		var aim: Dictionary = state.aims[s]
		var dir: Array = JsonUtil.as_array(aim.get("dir", []))
		throws.append({
			"ball": _bodies[h.id],
			"dir": Vector3(JsonUtil.as_float(dir[0]), 0, JsonUtil.as_float(dir[1])),
			"power": JsonUtil.as_float(aim.get("power", 1.0)),
		})
	_picked.clear()
	_pick_order = PackedStringArray()
	_launching = false
	if throws.is_empty() or not _runner.start_many(throws):
		_on_roll_finished(RollOutcome.new())


func _physics_process(_delta: float) -> void:
	if not _runner.is_running():
		return
	for c: CoreState in state.cores:
		if c.place != CoreState.ON_FIELD or _picked.has(c.id):
			continue
		var at: Vector3 = arena.hex_center(c.hex)
		for id: String in _bodies:
			var b: BallBody = _bodies[id]
			if b.motion != BallBody.Motion.MOVING or arena.area_at(b.global_position) != BallWorld.Area.MAP:
				continue
			var d: float = Vector2(b.global_position.x - at.x, b.global_position.z - at.z).length()
			if d < b.radius() + CORE_RADIUS:
				_picked[c.id] = id
				_pick_order.append(c.id)
				if _core_tokens.has(c.id):
					_core_tokens[c.id].visible = false
				break


func _on_roll_finished(o: RollOutcome) -> void:
	for cid: String in _pick_order:
		var r: RollResult = o.result_for(_picked[cid])
		if r != null:
			r.cores_picked.append(cid)
	var err: String = engine.apply_roll(state, o)
	if not err.is_empty():
		hud.toast(err, Palette.FG)
	for r: RollResult in o.results:
		var h: HeroState = state.hero(r.ball_id)
		if h != null and (r.ring_out or r.strip_entered >= 0):
			hud.toast("RING-OUT  ·  %s" % hud.hero_name(h))
	_sync()


# --- frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _sling.is_aiming():
		_sling.update(cam.camera, get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size.y)
	_refresh_range()
	_run_bots(delta)


func _run_bots(delta: float) -> void:
	if bots.is_empty() or state.is_over() or _runner.is_running() or _launching or _menu.visible:
		return
	_bot_wait -= delta
	if _bot_wait > 0.0:
		return
	var positions: Dictionary[String, Vector2] = {}
	for id: String in _bodies:
		var p: Vector3 = _bodies[id].global_position
		positions[id] = Vector2(p.x, p.z)
	for slot: int in bots:
		var m: Move = bots[slot].next_move(engine, state, slot, positions, tuning)
		if m == null:
			continue
		_bot_wait = BOT_DELAY
		_apply(m)
		return


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
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _sling.is_aiming():
			_sling.cancel()
			arena.set_grid_emphasis(false)
			return
	if event is InputEventMouseMotion and not _sling.is_aiming() and not cam.is_dragging():
		_set_hover(_hero_under_mouse(), true)
	cam.handle_input(event)


func _on_key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_ESCAPE:
			if _sling.is_aiming():
				_sling.cancel()
				arena.set_grid_emphasis(false)
			else:
				_toggle_menu()
		KEY_SPACE:
			if hud.local_slots.has(state.to_act) and not state.round_over:
				_apply(Move.make(Move.PASS, state.to_act))
		KEY_HOME:
			cam.reset_view()


func _on_left(pressed: bool) -> void:
	if pressed:
		_press_on_empty = false
		var d: Dictionary = _local_decision()
		if str(d.get("type", "")) == RulesEngine.DECISION_RETURN_CORE:
			var g: Variant = _ground_under_mouse()
			if g != null:
				var gp: Vector3 = g
				_apply(Move.make(Move.RETURN_CORE, JsonUtil.as_int(d.get("player", 0)),
					{"core": str(d.get("core", "")), "hex": Hex.to_json(arena.hex_at(gp))}))
			return
		var id: String = _hero_under_mouse()
		if not id.is_empty() and _try_aim(id):
			return
		if not id.is_empty():
			_on_hero_clicked(id)
			return
		_press_on_empty = true
		cam.begin_drag(OrbitCamera.Drag.ORBIT)
		return
	if _sling.is_aiming():
		_release_aim()
		return
	cam.begin_drag(OrbitCamera.Drag.NONE)
	_press_on_empty = false


## Starts aiming when `id` is a local player's activated hero that still has to aim.
func _try_aim(id: String) -> bool:
	if state.phase != GameState.PHASE_ROLL or state.awaiting_roll or _runner.is_running() or _launching:
		return false
	var h: HeroState = state.hero(id)
	if h == null or not hud.local_slots.has(h.owner) or state.active.get(h.owner, "") != id:
		return false
	if not state.choices.get(h.owner, false) or state.aims.has(h.owner):
		return false
	_sling.start(_bodies[id])
	arena.set_grid_emphasis(true)
	return true


func _release_aim() -> void:
	var ball: BallBody = _sling.ball
	var throw: bool = _sling.is_throw()
	var dir: Vector3 = _sling.dir
	var power: float = _sling.power
	_sling.cancel()
	arena.set_grid_emphasis(false)
	if ball == null or not throw:
		return
	var h: HeroState = state.hero(ball.ball_id)
	_apply(Move.make(Move.AIM, h.owner, {"dir": [dir.x, dir.z], "power": power}))


func _on_hero_clicked(id: String) -> void:
	var h: HeroState = state.hero(id)
	if h == null:
		return
	if state.phase == GameState.PHASE_SELECT and hud.local_slots.has(h.owner) and not state.active.has(h.owner):
		_apply(Move.make(Move.SELECT, h.owner, {"hero": id}))
		return
	if h.is_on_map():
		cam.focus(arena.hex_center(h.hex), 14.0)


## Hover from the table also expands the hero's panel; hover from a panel only lights the
## ball and its range (rebuilding the panel under the mouse would flicker).
func _set_hover(id: String, refresh_hud: bool) -> void:
	if id == _hovered:
		return
	_hovered = id
	for hid: String in _views:
		_views[hid].set_glow(hid == id)
	if refresh_hud:
		hud.hover_hero = id
		hud.refresh()


func _hero_under_mouse() -> String:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = cam.camera.project_ray_origin(mouse)
	var to: Vector3 = from + cam.camera.project_ray_normal(mouse) * 500.0
	var q := PhysicsRayQueryParameters3D.create(from, to, BallBody.LAYER_BALLS)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ""
	var obj: Object = hit.get("collider")
	if obj is BallBody:
		return (obj as BallBody).ball_id
	return ""


func _ground_under_mouse() -> Variant:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.camera.project_ray_origin(mouse), cam.camera.project_ray_normal(mouse))


# --- screenshot helpers (tools/screenshot.gd --call=...) ------------------------

## Lets the bots play both sides for a few seconds of turns.
func demo_autoplay() -> void:
	for p: PlayerState in state.players:
		if not bots.has(p.slot):
			bots[p.slot] = SimpleBot.new(p.slot + 7)
	hud.local_slots = PackedInt32Array()


## Makes the next local move as if clicked (a SimpleBot decides). At the aim it only draws the
## slingshot on the activated hero and stops, so a screenshot shows the aim.
func demo_step() -> void:
	for slot: int in hud.local_slots:
		var helper := SimpleBot.new(slot + 3)
		var positions: Dictionary[String, Vector2] = {}
		for id: String in _bodies:
			positions[id] = Vector2(_bodies[id].global_position.x, _bodies[id].global_position.z)
		var m: Move = helper.next_move(engine, state, slot, positions, tuning)
		if m == null:
			continue
		if m.type == Move.AIM:
			var h: HeroState = state.active_hero(slot)
			var dir: Array = JsonUtil.as_array(m.data.get("dir", []))
			_sling.start(_bodies[h.id])
			_sling.power = JsonUtil.as_float(m.data.get("power", 0.7))
			_sling.dir = Vector3(JsonUtil.as_float(dir[0]), 0, JsonUtil.as_float(dir[1]))
			_sling.pull = -_sling.dir * 3.0
			_sling.draw()
			arena.set_grid_emphasis(true)
			set_process(false)
			return
		_apply(m)
		return


## Prints the state as JSON (for tools and debugging).
func debug_dump() -> void:
	print("turn=%d phase=%s pending=%d over=%s result=%s winner=%d" % [state.turn, state.phase,
		state.pending.size(), state.is_over(), state.result, state.winner])
	for h: HeroState in state.heroes:
		print("  %-14s zone=%-5s hex=%s hp=%d cores=%d" % [h.id, h.zone, h.hex, h.hp, h.cores.size()])
	for i: int in range(maxi(0, state.log.size() - 12), state.log.size()):
		print("  log: ", JSON.stringify(state.log[i]))
