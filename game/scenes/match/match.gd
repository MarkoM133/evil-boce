extends Node3D
## A 1v1 match (step 2). The rules engine owns the GameState; this scene draws it, turns clicks
## into moves, runs the physics for the Roll phase and feeds the RollOutcome back. Slots are
## local players (hot seat) or the Bot (Easy or Hard).

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const REPLAYS_SCENE: String = "res://scenes/replays/replays_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
## Seconds between two bot moves, so a human can follow.
const BOT_DELAY: float = 0.5
## Core token radius; a rolling ball picks a core up when it touches it.
const CORE_RADIUS: float = 0.34
## The token is drawn this much bigger than its pick-up radius, so its picture reads.
const CORE_LOOK: float = 1.3
const CORE_COLORS: Dictionary[String, Color] = {
	"Buff": Color("4fb858"), "Major": Color("ffd23f"), "Debuff": Color("9a5bd6"),
}

var tuning: PhysicsTuning
var db: CardDb
var engine: RulesEngine
var state: GameState
var recorder: MatchRecorder
## Online: "host" (this scene drives NetHost, which owns the recorder), "client" (moves go to the
## host, the state comes back) or "" for a local match.
var net_role: String = ""
var net_host: NetHost
var net_client: NetClient
var _ball_tick: float = 0.0
## Last HP drawn per hero, and the heroes shown as KO, so _sync can animate what changed.
var _hp: Dictionary[String, int] = {}
var _ko_shown: Dictionary[String, bool] = {}
## True while a redraw must not animate (a replay jumping frames).
var _quiet: bool = false
## Slow motion already ran in this roll.
var _slowed: bool = false
## demo_until_cards: give player 1 back to the mouse when it may play cards.
var _demo_hand_back: bool = false
## Set by every demo_ helper: a screenshot run never writes the save, replays, stats or the
## main menu's last-match picture.
var _demo: bool = false
## Phases in which demo_until_cards / demo_mulligan hand player 1 back.
var _demo_phases: Array[String] = [GameState.PHASE_PREROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE]
## A guest's copy of the finished match, sent by the host when it ends.
var _net_record: MatchRecord
var arena: Arena
var world: ArenaWorld
var cam: OrbitCamera
var hud: MatchHud
var bots: Dictionary[int, Bot] = {}

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
## Setup: the stage or core the local player places next ("" = the first one left) and the
## hex under the mouse, for the preview.
var _setup_pick: String = ""
var _setup_hover := Vector2i(9999, 9999)
## Watching a recorded match: the record, the frame shown, playback.
var _replay: MatchRecord
var _frame: int = 0
var _replay_bar: ReplayBar
var _playing: bool = false
var _play_wait: float = 0.0
var _replay_speed: float = 1.0
var _replay_busy: bool = false
## Frames already in user://saves/current.json, and whether the finished match was filed.
var _saved_frames: int = 0
var _filed: bool = false


func _ready() -> void:
	tuning = PhysicsTuning.load_default()
	db = CardDb.load_from(GameSettings.data_path())
	_config = MatchLaunch.take(db.catalog)
	_demo = JsonUtil.as_bool(_config.get("dev", false))
	var settings: MatchSettings = _config["settings"]
	var decks: Array = _config["decks"]
	var seed_: int = JsonUtil.as_int(_config.get("seed", 1), 1)
	var bot_slots: Array = JsonUtil.as_array(_config.get("bots", []))
	var bot_level: String = str(_config.get("bot_level", "easy"))
	# Every match is recorded (replay, save, stats); a resumed or watched one uses the cards as
	# they were when it was played.
	var resume_from: MatchRecord = _config.get("resume", null)
	_replay = _config.get("replay", null)
	var from_record: MatchRecord = _replay if _replay != null else resume_from
	engine = RulesEngine.new(from_record.catalog() if from_record != null else db.catalog)
	var net: Dictionary = JsonUtil.as_dict(_config.get("net", {}))
	net_role = str(net.get("role", ""))
	if net_role == "host":
		net_host = net["node"]
		engine = net_host.engine
		recorder = net_host.recorder
		settings = net_host.settings
		for s: Dictionary in net_host.seats:
			if JsonUtil.as_bool(s.get("bot", false)):
				bot_slots.append(JsonUtil.as_int(s["slot"]))
		bot_level = str(net_host.seat(JsonUtil.as_int(bot_slots[0])).get("bot_level", "easy")) if not bot_slots.is_empty() else "easy"
		net_host.state_changed.connect(_on_net_state)
		net_host.paused_changed.connect(func(on: bool, by: int) -> void: _on_net_pause(on, by, str(net_host.seat(by).get("name", ""))))
		net_host.player_changed.connect(func(slot: int, on: bool) -> void:
			hud.toast("%s %s" % [str(net_host.seat(slot).get("name", "")), "is back" if on else "dropped; waiting…"]))
	elif net_role == "client":
		net_client = net["node"]
		settings = MatchSettings.from_dict(net_client.settings)
		state = net_client.state
		net_client.state_received.connect(func(_s: GameState) -> void: _on_net_state())
		net_client.move_refused.connect(func(_m: Dictionary, why: String) -> void: hud.toast(why, Palette.FG))
		net_client.balls_received.connect(_on_net_balls)
		net_client.paused_changed.connect(_on_net_pause)
		net_client.player_changed.connect(func(_slot: int, name: String, on: bool) -> void:
			hud.toast("%s %s" % [name, "is back" if on else "dropped; waiting…"]))
		net_client.disconnected.connect(func(why: String) -> void:
			hud.net_paused = "Lost the host (%s). Esc → Main menu" % why
			hud.refresh())
		net_client.match_over.connect(func(summary: Dictionary, record: MatchRecord) -> void:
			# The host keeps the stats; the guest keeps its own replay (GDD 2).
			hud.end_summary = summary
			if record != null:
				_net_record = record
				ReplayStore.save_replay(record)
			hud.refresh())
		net_client.back_in_lobby.connect(func() -> void: get_tree().change_scene_to_file(LOBBY_SCENE))
	if net_role != "":
		pass
	elif _replay != null:
		_frame = clampi(JsonUtil.as_int(_config.get("frame", 0)), 0, _replay.frame_count() - 1)
		state = _replay.state_at(_frame)
		bot_slots = []
	elif resume_from != null:
		recorder = MatchRecorder.resume(engine, resume_from, JsonUtil.as_int(_config.get("frame", -1), -1))
	else:
		var seats: Array = []
		for i: int in decks.size():
			var d: Dictionary = JsonUtil.as_dict(decks[i])
			seats.append({"name": d.get("name", ""), "bot": bot_slots.has(i), "bot_level": bot_level, "deck_name": d.get("deck_name", "")})
		recorder = MatchRecorder.start(engine, settings, decks, seed_, seats, str(ProjectSettings.get_setting("application/config/version", "")))
	if recorder != null:
		state = recorder.state
	if state == null:
		push_error("no state to show")
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	for slot: Variant in bot_slots:
		bots[JsonUtil.as_int(slot)] = Bot.new(seed_ + JsonUtil.as_int(slot), Bot.level_from(bot_level))

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
			db.emblem(def.set_code if def != null else ""), db.sprite(def) if def != null else null,
			card.color if card != null else "")
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
	if net_role == "host":
		local.append(net_host.host_slot)
	elif net_role == "client":
		local.append(net_client.slot)
	else:
		for p: PlayerState in state.players:
			if not bots.has(p.slot) and _replay == null:
				local.append(p.slot)
	hud.replay = _replay != null
	hud.setup(engine, state, db, local)
	if _replay != null:
		_replay_bar = ReplayBar.new()
		_replay_bar.theme = UiTheme.get_theme()
		hud.add_child(_replay_bar)
		_replay_bar.step_pressed.connect(func(d: int) -> void: _show_frame(_frame + d, d > 0))
		_replay_bar.jump_pressed.connect(func(to_end: bool) -> void: _show_frame(_replay.frame_count() - 1 if to_end else 0, false))
		_replay_bar.play_toggled.connect(_toggle_play)
		_replay_bar.speed_changed.connect(func(s: float) -> void: _replay_speed = s)
		_replay_bar.continue_pressed.connect(func() -> void:
			MatchLaunch.config = MatchLaunch.from_record(_replay, _frame)
			get_tree().change_scene_to_file(MATCH_SCENE))
		_replay_bar.exit_pressed.connect(func() -> void: get_tree().change_scene_to_file(REPLAYS_SCENE))
		_replay_bar.show_frame(_frame, _replay.frame_count(), state.turn, state.phase)
		if JsonUtil.as_bool(_config.get("autoplay", false)):
			_set_playing.call_deferred(true)
	hud.pass_pressed.connect(func(slot: int) -> void: _apply(Move.make(Move.PASS, slot)))
	hud.choice_pressed.connect(func(slot: int, roll: bool) -> void: _apply(Move.make(Move.CHOICE, slot, {"roll": roll})))
	hud.keep_pressed.connect(func(slot: int, keep: bool) -> void: _apply(Move.make(Move.MULLIGAN, slot, {"keep": keep})))
	hud.no_hero_pressed.connect(func(slot: int) -> void: _apply(Move.make(Move.SELECT, slot, {"hero": ""})))
	hud.card_pressed.connect(func(slot: int, cid: String) -> void: _apply(Move.make(Move.PLAY_CARD, slot, {"card": cid})))
	hud.damage_pressed.connect(func(slot: int, target: String) -> void: _apply(Move.make(Move.DAMAGE_TO, slot, {"target": target})))
	hud.choose_pressed.connect(func(slot: int, value: Variant) -> void: _apply(Move.make(Move.CHOOSE, slot, {"value": value})))
	hud.ability_pressed.connect(func(slot: int, hero_id: String, card_id: String, index: int) -> void:
		_apply(Move.make(Move.USE_ABILITY, slot, {"hero": hero_id, "card": card_id, "index": index})))
	hud.hero_clicked.connect(_on_hero_clicked)
	hud.hero_hovered.connect(func(id: String) -> void: _set_hover(id, false))
	hud.menu_pressed.connect(_toggle_menu)
	hud.rematch_pressed.connect(_rematch)
	hud.watch_replay_pressed.connect(func() -> void:
		var rec: MatchRecord = recorder.record if recorder != null else _net_record
		if rec == null:
			hud.toast("The replay has not come in yet", Palette.FG)
			return
		# Watching ends the online session; the replay stays in Replays.
		_close_net()
		MatchLaunch.config = MatchLaunch.from_record(rec, 0, true)
		get_tree().change_scene_to_file(MATCH_SCENE))
	hud.setup_item_pressed.connect(func(id: String) -> void:
		_setup_pick = id
		_range_key = ""
		hud.setup_pick = _setup_item()
		hud.refresh())
	if net_role == "host":
		hud.rematch_text = "Back to the lobby"
	elif net_role == "client":
		hud.rematch_text = ""
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
	resume.text = "RESUME"
	resume.theme_type_variation = &"Primary"
	resume.pressed.connect(_toggle_menu)
	col.add_child(resume)
	if net_role != "":
		var pause := Button.new()
		pause.text = "Pause for everyone"
		pause.pressed.connect(func() -> void:
			_toggle_menu()
			if net_role == "host":
				var why: String = net_host.set_paused(not net_host.paused, net_host.host_slot)
				if not why.is_empty():
					hud.toast(why, Palette.FG)
			else:
				net_client.send_pause(not net_client.paused))
		col.add_child(pause)
	for slot: int in hud.local_slots:
		var give_up := Button.new()
		give_up.text = "Surrender (%s)" % hud.player_name(slot)
		give_up.pressed.connect(func() -> void:
			_toggle_menu()
			_apply(Move.make(Move.SURRENDER, slot)))
		col.add_child(give_up)
	var back := Button.new()
	back.text = "Main menu"
	back.pressed.connect(_leave)
	col.add_child(back)
	return root


func _toggle_menu() -> void:
	if state.is_over() and _replay == null:
		_leave()
		return
	_menu.visible = not _menu.visible


## Back to the main menu; an online match closes its link first.
func _leave() -> void:
	await _snapshot()
	_close_net()
	get_tree().change_scene_to_file(MENU_SCENE)


## A picture of the table (no HUD) for the main menu's Play tile; not while watching a replay.
func _snapshot() -> void:
	if _replay != null or _demo or state == null or not is_inside_tree():
		return
	var menu_was: bool = _menu.visible
	hud.visible = false
	_menu.visible = false
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	hud.visible = true
	_menu.visible = menu_was
	var names := PackedStringArray()
	for p: PlayerState in state.players:
		names.append(hud.player_name(p.slot))
	var caption: String = "Last match: %s  ·  turn %d" % [" vs ".join(names), state.turn]
	if state.is_over():
		caption += "  ·  " + ("draw" if state.winner < 0 else "%s won" % hud.player_name(state.winner))
	ReplayStore.save_last_shot(img, caption)


func _close_net() -> void:
	if net_host != null:
		net_host.link.close()
		net_host.queue_free()
		net_host = null
	if net_client != null:
		net_client.link.close()
		net_client.queue_free()
		net_client = null


func _rematch() -> void:
	if net_role == "host":
		# Online: everyone goes back to the lobby, keeps the seat and the deck, presses Ready.
		net_host.back_to_lobby()
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return
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
	if net_role == "client":
		net_client.send_move(m)
		return
	if net_role == "host":
		# NetHost.apply emits state_changed, which saves and redraws (_on_net_state).
		var why: String = net_host.apply(m)
		if not why.is_empty():
			hud.toast(why, Palette.FG)
		return
	if recorder == null:
		return
	var err: String = recorder.apply(m)
	if not err.is_empty():
		hud.toast(err, Palette.FG)
		return
	_after_change()
	_sync()


## The host sent a new state (host: after any seat's move; client: always).
func _on_net_state() -> void:
	if net_role == "client":
		state = net_client.state
		hud.state = state
	else:
		_after_change()
	_sync()


func _on_net_pause(on: bool, _by: int, name: String) -> void:
	hud.net_paused = ("Paused by %s" % name) if on else ""
	hud.refresh()


## Ball positions from the host while its physics runs.
func _on_net_balls(positions: Dictionary) -> void:
	if not hud.rolling:
		hud.rolling = true
		hud.refresh()
	for id: Variant in positions:
		if not _bodies.has(str(id)):
			continue
		var p: Array = JsonUtil.as_array(positions[id])
		if p.size() != 3:
			continue
		var b: BallBody = _bodies[str(id)]
		b.freeze = true
		var to := Vector3(JsonUtil.as_float(p[0]), JsonUtil.as_float(p[1]), JsonUtil.as_float(p[2]))
		_views[str(id)].roll(to - b.global_position)
		b.global_position = to


## Saves the match in progress; when it is over, files the replay and the stats summary.
## A resumed match starts from the beginning of its last phase, so the save is only written
## when a new phase opens, not after every move.
func _after_change() -> void:
	if net_role == "client" or _demo:
		return
	if state.is_over():
		if _filed:
			return
		_filed = true
		_snapshot()
		if net_role == "":
			ReplayStore.clear_current()
		ReplayStore.save_replay(recorder.record)
		ReplayStore.write_stats(recorder.record, db.root_dir)
		hud.end_summary = recorder.record.summary()
	elif net_role == "" and recorder.record.frame_count() != _saved_frames:
		# Only local matches can be continued; an online one needs everyone at the table.
		_saved_frames = recorder.record.frame_count()
		ReplayStore.save_current(recorder.record)


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
	hud.setup_pick = _setup_item()
	hud.refresh()
	if _replay != null or net_role == "client":
		# Watching, or a guest: nothing moves by itself; balls follow what the host sends.
		hud.rolling = net_role == "client" and state.awaiting_roll
		hud.refresh()
		for b: BallBody in _bodies.values():
			b.freeze = true
		return
	if state.awaiting_roll and not _runner.is_running() and not _launching:
		_launch_roll()


func _sync_hero(h: HeroState) -> void:
	var b: BallBody = _bodies[h.id]
	var v: BallView = _views[h.id]
	var first: bool = not _hp.has(h.id)
	var was: int = _hp.get(h.id, h.hp)
	_hp[h.id] = h.hp
	var animate: bool = not first and not _quiet
	if h.is_ko():
		if not _ko_shown.has(h.id):
			_ko_shown[h.id] = true
			b.collision_layer = 0
			b.freeze = true
			world.bodies.erase(b)
			if animate:
				if h.hp < was:
					v.hit(was - h.hp)
				v.ko()
				v.ko_finished.connect(func() -> void: b.visible = not _ko_shown.has(h.id), CONNECT_ONE_SHOT)
			else:
				b.visible = false
		return
	if _ko_shown.has(h.id):
		# Back from a KO: a replay stepped back over it.
		_ko_shown.erase(h.id)
		b.visible = true
		b.collision_layer = BallBody.LAYER_BALLS
		world.bodies.append(b)
		v.revive()
	if animate and h.hp < was:
		v.hit(was - h.hp)
		_hit_stop()
	elif animate and h.hp > was:
		v.float_text("+%d" % (h.hp - was), Palette.HEAL)
	var target: Vector3 = arena.hex_center(h.hex) if h.is_on_map() else _strip_spot(h)
	var here := Vector3(b.global_position.x, 0, b.global_position.z)
	if here.distance_to(target) > 0.05:
		if h.is_on_map() and arena.area_at(b.global_position) == BallWorld.Area.MAP:
			_slide(b, target, v)
		else:
			v.close_now()
			b.place(target)
			v.settle()
	var open: bool = _shows_figure(h)
	if open and not v.is_open() and v.state != BallView.State.OPENING:
		v.open()
	elif not open and v.is_open():
		v.close()


## A ball opens into its figure when it stands on a stage or is in a battle (GDD 5); else it
## stays a ball.
func _shows_figure(h: HeroState) -> bool:
	if not h.is_on_map():
		return false
	for st: StageState in state.stages:
		if st.placed and st.covers(h.hex):
			return true
	if state.phase == GameState.PHASE_BATTLE:
		for b: Dictionary in state.battles:
			if JsonUtil.as_strings(b.get("heroes", [])).has(h.id):
				return true
	return false


## Knockback and other rule moves: the ball hops over to its new hex in an arc (higher and
## longer the farther it goes) and squashes on landing.
func _slide(b: BallBody, target: Vector3, v: BallView) -> void:
	b.freeze = true
	var from: Vector3 = b.global_position
	var to := Vector3(target.x, from.y, target.z)
	var dist: float = Vector2(to.x - from.x, to.z - from.z).length()
	var steps: float = dist / maxf(tuning.hex_size * 1.7, 0.01)
	var height: float = clampf(0.35 + 0.25 * steps, 0.35, 1.6)
	var time: float = clampf(0.26 + 0.06 * steps, 0.26, 0.6)
	var t: Tween = create_tween()
	t.tween_method(func(k: float) -> void:
		var p: Vector3 = from.lerp(to, k)
		p.y += sin(k * PI) * height
		if v != null:
			v.roll(p - b.global_position)
		b.global_position = p, 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void:
		b.place(target)
		if v != null:
			v.land())


## Hit-stop: the world freezes for a blink when damage lands (Settings → Effects).
func _hit_stop() -> void:
	if not GameSettings.effect("hit_stop") or _runner.is_running():
		return
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.09, true, false, true).timeout
	Engine.time_scale = 1.0


## Slow motion while the first ball of a roll goes over the edge.
func _slow_mo() -> void:
	if _slowed or not GameSettings.effect("slow_mo"):
		return
	_slowed = true
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.75, true, false, true).timeout
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- tokens and marks ----------------------------------------------------------

func _rebuild_tokens() -> void:
	for c: Node in _tokens.get_children():
		c.queue_free()
	_core_tokens.clear()
	for c: CoreState in state.cores:
		if c.place != CoreState.ON_FIELD:
			continue
		var token: Node3D = _core_token(c)
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


## A core on the table: a dark hex chip with its picture on top, the face once it is face up,
## else its family's back (Power, Damage, Knockback). Without pictures, a chip in its kind's colour.
func _core_token(c: CoreState) -> Node3D:
	var card: CardDef = db.catalog.get_card(c.card_id)
	var pic: Texture2D = null
	if card != null:
		if c.face_up:
			pic = db.large(card.id) if db.large(card.id) != null else db.thumb(card.id)
		else:
			pic = db.core_back(card)
	if pic == null:
		var col: Color = CORE_COLORS.get(card.kind if card != null else "", Palette.MUTED) if c.face_up else Color("2a2622")
		return _hex_prism(CORE_RADIUS, 0.12, col, Palette.GOLD if not c.face_up else col.lightened(0.3))
	var r: float = CORE_RADIUS * CORE_LOOK
	var token: Node3D = _hex_prism(r, 0.12, Color("1b1f20"), Color("eeeaf0"))
	# Pointy along z like the picture (the plain prism is turned flat for the map's walls).
	token.rotation.y = 0.0
	# The top: a hexagon cut from the picture's hex (pointy along z, like the map's).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var box: Rect2 = CardDb.CORE_HEX
	var mid: Vector2 = box.get_center()
	var pts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for i: int in 6:
		var a: float = PI / 2.0 + TAU * i / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * r
		pts.append(p)
		uvs.append(mid + Vector2(p.x / (sqrt(3.0) * r) * box.size.x, p.z / (2.0 * r) * box.size.y))
	for i: int in 6:
		st.set_uv(mid)
		st.add_vertex(Vector3.ZERO)
		st.set_uv(uvs[(i + 1) % 6])
		st.add_vertex(pts[(i + 1) % 6])
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	var top := MeshInstance3D.new()
	top.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = pic
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	top.material_override = mat
	top.position.y = 0.061
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.add_child(token)
	holder.add_child(top)
	return holder


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
	var item: String = _setup_item()
	if not item.is_empty():
		key = "setup:%s:%s" % [item, _setup_hover]
		cells = _setup_cells(item)
		marked.clear()
		if cells.has(_setup_hover):
			marked = Hex.spiral(_setup_hover, 1) if state.stage(item) != null else [_setup_hover]
	var d: Dictionary = _local_decision()
	if str(d.get("type", "")) == RulesEngine.DECISION_RETURN_CORE:
		var c: CoreState = state.core(str(d.get("core", "")))
		key += "core:%s" % c.id
		cells.clear()
		for a: Vector2i in arena.map.cells():
			if engine.core_return_error(state, c, a).is_empty():
				cells.append(a)
	elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "hex":
		key += "choose:%d" % state.pending.size()
		cells.clear()
		for o: Variant in JsonUtil.as_array(d.get("options", [])):
			cells.append(JsonUtil.as_hex(o))
	if key == _range_key:
		return
	_range_key = key
	arena.show_range(cells, marked)


## The stage or core a local player places now, or "" outside a local setup turn.
func _setup_item() -> String:
	if state.phase != GameState.PHASE_SETUP_STAGES and state.phase != GameState.PHASE_SETUP_CORES:
		return ""
	if not hud.local_slots.has(state.setup_turn):
		return ""
	var left: PackedStringArray = MatchHud.setup_items(state, state.setup_turn)
	if left.has(_setup_pick):
		return _setup_pick
	return left[0] if not left.is_empty() else ""


## Legal hexes for a stage (its centre) or a core during setup.
func _setup_cells(item: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var st: StageState = state.stage(item)
	var c: CoreState = state.core(item)
	for a: Vector2i in arena.map.cells():
		if st != null and engine.stage_placement_error(state, st, a).is_empty():
			out.append(a)
		elif c != null and engine.core_placement_error(state, c, a).is_empty():
			out.append(a)
	return out


func _place_at_mouse(item: String) -> void:
	var g: Variant = _ground_under_mouse()
	if g == null:
		return
	var gp: Vector3 = g
	var hex: Array = Hex.to_json(arena.hex_at(gp))
	if state.stage(item) != null:
		_apply(Move.make(Move.PLACE_STAGE, state.setup_turn, {"stage": item, "hex": hex}))
	else:
		_apply(Move.make(Move.PLACE_CORE, state.setup_turn, {"core": item, "hex": hex}))


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
	_slowed = false
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


func _physics_process(delta: float) -> void:
	if not _runner.is_running():
		return
	if net_role == "host":
		_ball_tick += delta
		if _ball_tick >= 0.05:
			_ball_tick = 0.0
			var positions: Dictionary = {}
			for id: String in _bodies:
				var p: Vector3 = _bodies[id].global_position
				positions[id] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
			net_host.send_balls(positions)
	if not _slowed:
		for b: BallBody in _bodies.values():
			if b.visible and b.motion == BallBody.Motion.OUT:
				_slow_mo()
				break
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
	var err: String = net_host.apply_roll(o) if net_role == "host" else recorder.apply_roll(o)
	if not err.is_empty():
		hud.toast(err, Palette.FG)
	else:
		_after_change()
	# Ring-outs get a banner from the log (MatchHud._scan_log).
	_sync()


# --- frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _sling.is_aiming():
		_sling.update(cam.camera, get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size.y)
	_refresh_range()
	for id: String in _views:
		# Balls ride over hills (the physics stays flat; see ArenaWorld.push_at).
		_views[id].position.y = arena.height_at(_bodies[id].global_position)
	if _replay != null:
		_run_playback(delta)
		return
	_run_bots(delta)
	var mull: bool = state.phase == GameState.PHASE_MULLIGAN and not state.player(0).mulligan_done
	if _demo_hand_back and _demo_phases.has(state.phase) and not state.player(0).hand.is_empty() 			and (mull or state.to_act == 0 and not state.round_over and state.pending.is_empty()):
		_demo_hand_back = false
		bots.erase(0)
		hud.local_slots = PackedInt32Array([0])
		hud.refresh()


# --- watching a replay --------------------------------------------------------------

## Shows frame `i`; stepping one forward first plays the rolls recorded in the frame left.
func _show_frame(i: int, animate: bool) -> void:
	if _replay_busy:
		return
	var to: int = clampi(i, 0, _replay.frame_count() - 1)
	var from: int = _frame
	_frame = to
	if animate and to == from + 1:
		var rolls: Array = JsonUtil.as_array(_replay.frames[from].get("rolls", []))
		if not rolls.is_empty():
			_replay_busy = true
			for r: Variant in rolls:
				await _play_roll(RollOutcome.from_dict(JsonUtil.as_dict(r)))
			_replay_busy = false
	state = _replay.state_at(_frame)
	hud.state = state
	_range_key = ""
	_quiet = not animate or to != from + 1
	_sync()
	_quiet = false
	_replay_bar.show_frame(_frame, _replay.frame_count(), state.turn, state.phase)
	if _frame >= _replay.frame_count() - 1:
		_set_playing(false)


## Moves every ball of the outcome along its recorded path, all at once.
func _play_roll(o: RollOutcome) -> void:
	var step: float = float(tuning.path_sample_every) / float(Engine.physics_ticks_per_second) / _replay_speed
	var longest: float = 0.0
	for r: RollResult in o.results:
		if not _bodies.has(r.ball_id) or r.path.size() < 2:
			continue
		var b: BallBody = _bodies[r.ball_id]
		_views[r.ball_id].close_now()
		b.freeze = true
		var t: Tween = create_tween()
		for p: Vector3 in r.path:
			t.tween_property(b, "global_position", p, step)
		longest = maxf(longest, step * r.path.size())
	await get_tree().create_timer(longest + 0.15).timeout


func _toggle_play() -> void:
	if _frame >= _replay.frame_count() - 1:
		_show_frame(0, false)
	_set_playing(not _playing)


func _set_playing(on: bool) -> void:
	_playing = on
	_play_wait = 0.0
	_replay_bar.set_playing(on)


func _run_playback(delta: float) -> void:
	if not _playing or _replay_busy:
		return
	_play_wait += delta * _replay_speed
	if _play_wait >= 1.2:
		_play_wait = 0.0
		_show_frame(_frame + 1, true)


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
		if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
			_toggle_menu()
		return
	if _replay != null:
		_replay_input(event)
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
	if event is InputEventMouseMotion and not _setup_item().is_empty():
		var g: Variant = _ground_under_mouse()
		if g != null:
			var gp: Vector3 = g
			_setup_hover = arena.hex_at(gp)
	if event is InputEventMouseMotion and not _sling.is_aiming() and not cam.is_dragging():
		_set_hover(_hero_under_mouse(), true)
	cam.handle_input(event)


## While watching only the camera and the replay keys work: Space play / pause, Left / Right
## step, Home view, Esc menu.
func _replay_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match GameSettings.logical_key((event as InputEventKey).keycode):
			KEY_ESCAPE:
				_toggle_menu()
			KEY_SPACE:
				_toggle_play()
			KEY_RIGHT:
				_show_frame(_frame + 1, true)
			KEY_LEFT:
				_show_frame(_frame - 1, false)
			KEY_HOME:
				cam.reset_view()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			cam.begin_drag(OrbitCamera.Drag.ORBIT if mb.pressed else OrbitCamera.Drag.NONE)
	if event is InputEventMouseMotion and not cam.is_dragging():
		_set_hover(_hero_under_mouse(), true)
	cam.handle_input(event)


func _on_key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	match GameSettings.logical_key(k.keycode):
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
		var item: String = _setup_item()
		if not item.is_empty() and _hero_under_mouse().is_empty():
			_place_at_mouse(item)
			return
		var d: Dictionary = _local_decision()
		if str(d.get("type", "")) == RulesEngine.DECISION_RETURN_CORE:
			var g: Variant = _ground_under_mouse()
			if g != null:
				var gp: Vector3 = g
				_apply(Move.make(Move.RETURN_CORE, JsonUtil.as_int(d.get("player", 0)),
					{"core": str(d.get("core", "")), "hex": Hex.to_json(arena.hex_at(gp))}))
			return
		if str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "hex":
			var g: Variant = _ground_under_mouse()
			if g != null:
				var gp: Vector3 = g
				_apply(Move.make(Move.CHOOSE, JsonUtil.as_int(d.get("player", 0)), {"value": Hex.to_json(arena.hex_at(gp))}))
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
	_demo = true
	for p: PlayerState in state.players:
		if not bots.has(p.slot):
			bots[p.slot] = Bot.new(p.slot + 7, Bot.Level.HARD)
	hud.local_slots = PackedInt32Array()


## Makes the next local move as if clicked (an Easy bot decides). At the aim it only draws the
## slingshot on the activated hero and stops, so a screenshot shows the aim.
func demo_step() -> void:
	_demo = true
	for slot: int in hud.local_slots:
		var helper := Bot.new(slot + 3)
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


## Screenshot helpers for the hit / knockback / KO animations. They change the drawn state
## directly (not through the engine), so use them only in a throwaway match.
func demo_fx_place() -> void:
	_demo = true
	var mid: Vector2i = arena.hex_at(Vector3.ZERO)
	var spots: Array[Vector2i] = [mid, mid + Vector2i(2, 0), mid + Vector2i(-1, 2), mid + Vector2i(1, -2)]
	for i: int in mini(spots.size(), state.heroes.size()):
		state.heroes[i].zone = HeroState.ZONE_MAP
		state.heroes[i].hex = spots[i]
	_sync()
	cam.focus(arena.hex_center(mid), 11.0)


## Hits hero 0, knocks hero 1 three hexes away and knocks out hero 2.
func demo_fx_hit() -> void:
	_demo = true
	state.heroes[0].hp -= 3
	state.heroes[1].hex += Vector2i(3, 0)
	state.heroes[2].hp = 0
	state.heroes[2].zone = HeroState.ZONE_KO
	_sync()


## Both of the above, 1.2 s apart (screenshot: --call=demo_fx --wait=82 --frames=0).
func demo_fx() -> void:
	_demo = true
	demo_fx_place()
	await get_tree().create_timer(1.2).timeout
	demo_fx_hit()


## Screenshot helper (after the cores are placed): turns every other core on the table face up,
## gives player 1's first hero two of them, and looks at a face-up one.
func demo_cores() -> void:
	_demo = true
	var field: Array[CoreState] = []
	for c: CoreState in state.cores:
		if c.place == CoreState.ON_FIELD:
			field.append(c)
	for i: int in field.size():
		field[i].face_up = i % 2 == 0
	var h: HeroState = state.heroes[0]
	for c: CoreState in field.slice(field.size() - 2):
		c.place = CoreState.ON_HERO
		c.holder = h.id
		c.face_up = true
		h.cores.append(c.id)
	hud.hover_hero = h.id
	_sync()
	if not field.is_empty():
		cam.focus(arena.hex_center(field[0].hex), 7.0)


## Screenshot helper: bots play until player 1 may play cards, then player 1 is handed back
## (its hand shows). Use with --wait=2400 or so.
func demo_until_cards() -> void:
	_demo = true
	demo_autoplay()
	_demo_hand_back = true


## Screenshot helper: bots place stages and cores, then player 1 gets the mulligan screen.
func demo_mulligan() -> void:
	_demo = true
	_demo_phases = [GameState.PHASE_MULLIGAN]
	demo_until_cards()


## Screenshot helper: the damage choice a lost battle asks for (drawn only, not applied).
func demo_damage() -> void:
	_demo = true
	var mine: Array = []
	for h: HeroState in state.heroes_of(0):
		mine.append(h.id)
	state.pending = [{"type": RulesEngine.DECISION_DAMAGE, "player": 0, "amount": 3,
		"winner": state.heroes_of(1)[0].id, "targets": mine}]
	hud.local_slots = PackedInt32Array([0])
	hud.refresh()


## Screenshot helper: the end screen as if player 1 won on stages (drawn only).
func demo_victory() -> void:
	_demo = true
	state.phase = GameState.PHASE_OVER
	state.winner = 0
	state.result = "stages"
	state.turn = 9
	hud.local_slots = PackedInt32Array([0])
	hud.end_summary = {"battles": 6, "players": [
		{"slot": 0, "name": state.player(0).name, "stages_claimed": 3, "kos_suffered": 1, "ring_outs_suffered": 0},
		{"slot": 1, "name": state.player(1).name, "stages_claimed": 1, "kos_suffered": 2, "ring_outs_suffered": 2}]}
	hud.refresh()


## Screenshot helper: one of each banner, queued.
func demo_banners() -> void:
	_demo = true
	hud.banner("BATTLE!", Palette.ACCENT, "GIORNO\n3000", "SHANKS\n2500")
	hud.banner("RING-OUT", Palette.GOLD, "", "SHANKS")


## Screenshot helper: player 1's first hand card shown big.
func demo_big_card() -> void:
	var p: PlayerState = state.player(0)
	if not p.hand.is_empty():
		hud._show_big(p.hand[0])
