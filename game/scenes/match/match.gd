extends Node3D
## A 1v1 match (step 2). The rules engine owns the GameState; this scene draws it, turns clicks
## into moves, runs the physics for the Roll phase and feeds the RollOutcome back. Slots are
## local players (hot seat) or the Bot (Easy or Hard).

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const REPLAYS_SCENE: String = "res://scenes/replays/replays_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
const SETUP_SCENE: String = "res://scenes/match/match_setup.tscn"
const SETTINGS_SCENE: String = "res://scenes/menu/settings_menu.tscn"
## Seconds between two bot moves, so a human can follow.
const BOT_DELAY: float = 0.5
## Auto-pass waits this long, the same whether a card could have been played or not (GDD 8).
const AUTO_PASS_DELAY: float = 1.5
## A new phase holds the table this long (Marko 2026-10-26: it went by too fast to notice):
## bots and auto-pass wait, the clock stands. The player may still move at once.
const PHASE_HOLD: float = 2.4
## Core token radius; a rolling ball picks a core up when it touches it.
const CORE_RADIUS: float = 0.34
## The token is drawn this much bigger than its pick-up radius, so its picture reads.
const CORE_LOOK: float = 1.3
## How strongly a revealed stage's art shows on its hexes.
const STAGE_ART_ALPHA: float = 0.6
## Battle camera: its tilt (the opening view's) and how long it stays after the last battle.
const BATTLE_CAM_PITCH: float = 34.0
const BATTLE_CAM_HOLD: float = 1.8
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
## When the balls' positions last went out to the guests (real time: the ring-out slow motion
## scales the physics ticks, and the guests' balls crawled at a few updates a second).
var _ball_sent_ms: int = 0
## Last HP drawn per hero, and the heroes shown as KO, so _sync can animate what changed.
var _hp: Dictionary[String, int] = {}
## Balls hopping to a new hex by a rule move: they stay closed until they land.
var _sliding: Dictionary[String, bool] = {}
var _phase_hold: float = 0.0
var _held_phase: String = ""
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
## Weather on stages with a terrain (_refresh_terrain_fx), by "stage|kind|dir".
var _terrain_fx: Dictionary[String, Node3D] = {}
## Cards played on heroes in a battle, shown beside them until it is over (_ghost_card).
var _ghosts: Array[Dictionary] = []
## Beams and rings on the heroes a card can go on (HUD 2).
var _target_fx: Node3D
## Red rings under the heroes of the battle being fought (HUD 4), and for which battle.
var _battle_fx: Node3D
var _battle_fx_key: String = ""
## The battle camera (HUD 5): which battle it last flew to, so it flies once per battle.
var _cam_battle_key: String = ""
var _marks := ImmediateMesh.new()
## Stages someone is trying to claim (Stay): their outline pulses (_process).
var _claim_marks := ImmediateMesh.new()
var _claim_mat: StandardMaterial3D
var _pulse_t: float = 0.0
var _line_mat: StandardMaterial3D
var _bodies: Dictionary[String, BallBody] = {}
var _views: Dictionary[String, BallView] = {}
var _core_tokens: Dictionary[String, Node3D] = {}
var _hovered: String = ""
var _range_key: String = ""
## Hexes of the stage or core hovered in the HUD strip (marked like a footprint).
var _board_marks: Array[Vector2i] = []
var _launching: bool = false
## The sim is running a physics knockback, not a roll (_launch_knockbacks).
var _knocking: bool = false
## Core id -> ball id, in pick-up order, while a roll runs.
var _picked: Dictionary[String, String] = {}
var _ping_tick: float = 0.0
## Online guest: where each ball is going, from the host's positions (~20 a second); the balls glide
## there every frame (online playtest 2026-11-07: set straight they stuttered).
var _net_to: Dictionary[String, Vector3] = {}
var _pick_order: PackedStringArray = PackedStringArray()
var _bot_wait: float = 0.0
## Auto-pass: how long the local player to act has had nothing to play.
var _idle_pass: float = 0.0
## Auto-pass: the state it last looked at and how long to wait there (-1: something to play).
var _pass_key: String = ""
var _pass_wait: float = -1.0
## The move timer: slot -> {"key": what the player is asked, "left": seconds} (see _run_clock).
var _clocks: Dictionary = {}
var _clock_rng := RandomNumberGenerator.new()
var _press_on_empty: bool = false
var _menu: Control
## The match log beside the pause menu (its Log button).
var _menu_log: PanelContainer
var _menu_info: Label
var _menu_first: Button
## Settings over the match, from the pause menu (null when closed).
var _settings: Control
## The pause menu's right side: the match log, or the combo list in its place (COMBO LIST).
var _menu_log_box: Control
var _combo_box: Control
var _combo_list: VBoxContainer
var _combo_toggle: HBoxContainer
## The combo list shows every combo, not only the ones this screen's deck can make.
var _combo_all: bool = false
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
		if _replay == null:
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
			var who: String = str(net_host.seat(slot).get("name", ""))
			if on:
				hud.hide_drop()
				hud.toast("%s is back" % who)
			elif not state.is_over():
				hud.show_drop(who, true))
	elif net_role == "client":
		net_client = net["node"]
		settings = MatchSettings.from_dict(net_client.settings)
		state = net_client.state
		net_client.state_received.connect(func(_s: GameState) -> void: _on_net_state())
		net_client.move_refused.connect(func(_m: Dictionary, why: String) -> void: hud.toast(why, Palette.FG))
		net_client.balls_received.connect(_on_net_balls)
		net_client.clocks_received.connect(_on_net_clocks)
		net_client.paused_changed.connect(_on_net_pause)
		net_client.player_changed.connect(func(_slot: int, name: String, on: bool) -> void:
			hud.toast("%s %s" % [name, "is back" if on else "dropped; waiting…"]))
		net_client.disconnected.connect(func(why: String) -> void:
			hud.net_paused = "Lost the host (%s). Esc → Main menu" % why
			hud.refresh()
			if not state.is_over() and not net_client.replay_stream:
				var host_name: String = "The host"
				for p: Variant in net_client.players:
					if JsonUtil.as_int(JsonUtil.as_dict(p).get("slot", -1)) == 0:
						host_name = str(JsonUtil.as_dict(p).get("name", host_name))
				hud.show_drop(host_name, false))
		net_client.match_over.connect(func(summary: Dictionary, record: MatchRecord) -> void:
			# The host keeps the stats; the guest keeps its own replay (GDD 2).
			_end_moment()
			hud.end_summary = summary
			if record != null:
				_net_record = record
				ReplayStore.save_replay(record)
			hud.refresh())
		net_client.back_in_lobby.connect(func() -> void: get_tree().change_scene_to_file(LOBBY_SCENE))
	if _replay != null:
		_frame = clampi(JsonUtil.as_int(_config.get("frame", 0)), 0, _replay.frame_count() - 1)
		state = _replay.state_at(_frame)
		bot_slots = []
	elif net_role != "":
		pass
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
	_battle_fx = Node3D.new()
	_battle_fx.name = "BattleFx"
	add_child(_battle_fx)
	_target_fx = Node3D.new()
	_target_fx.name = "TargetFx"
	add_child(_target_fx)
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
	_claim_mat = MeshKit.unshaded(Color.WHITE)
	var claim_mi := MeshInstance3D.new()
	claim_mi.mesh = _claim_marks
	claim_mi.material_override = _claim_mat
	claim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(claim_mi)
	_sling = Slingshot.new(tuning)
	add_child(_sling.make_instance())

	_build_balls()
	_build_hud()
	if net_role == "host" and net_host.paused:
		# A carried-on match waits for the others, paused (NetHost.resume_match).
		_on_net_pause(true, net_host.paused_by, str(net_host.seat(net_host.paused_by).get("name", "")))
	_sync()
	if state.turn == 0 and _replay == null and resume_from == null and not _demo and not _setup_begun():
		# A new match: the last one's battle pictures (menu idle preview) make way.
		ReplayStore.clear_highlights()
		_show_initiative()
	if _streaming():
		net_host.stream_start(_replay)
		net_host.stream_state(state)



## Setup has started already (a stage is down): a match carried on online, the who-starts dice are over.
func _setup_begun() -> bool:
	for st: StageState in state.stages:
		if st.placed:
			return true
	return false


## The host watching a replay with its table: every frame goes out (NetHost.stream_*).
func _streaming() -> bool:
	return net_role == "host" and _replay != null


func _exit_replay() -> void:
	if _streaming():
		net_host.stream_end()
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return
	get_tree().change_scene_to_file(REPLAYS_SCENE)


## A new match: both players roll two dice on screen; the higher total starts (the engine has
## drawn it already, the dice only show it). Bots wait until the dice are gone.
func _show_initiative() -> void:
	var dice := InitiativeDice.new()
	var names := PackedStringArray()
	var colors: Array[Color] = []
	for p: PlayerState in state.players:
		names.append(hud.player_name(p.slot))
		colors.append(Palette.team(state.team_of(p.slot)))
	hud.get_parent().add_child(dice)
	# People here throw by hand (playtest 2026-10-30); bots wait until the dice are gone.
	var people := PackedInt32Array()
	for slot: int in hud.local_slots:
		if not bots.has(slot):
			people.append(slot)
	dice.setup(state.rng_seed, state.initiative, names, colors, people)
	_bot_wait = 3600.0
	# The setup tray waits for the dice (playtest 2026-11-06).
	hud.intro_dice = true
	hud.refresh()
	dice.finished.connect(func() -> void:
		_bot_wait = BOT_DELAY
		hud.intro_dice = false
		hud.refresh())


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
			db.hero_emblem(def), db.sprite(def) if def != null else null,
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
		if _replay == null:
			local.append(net_host.host_slot)
	elif net_role == "client":
		# A spectator (slot -1) plays nobody.
		if net_client.slot >= 0:
			local.append(net_client.slot)
		hud.spectating = net_client.spectating or net_client.replay_stream
		if net_client.replay_stream:
			# A replay the host streams: the balls follow the recorded paths, no prompts, no end screen.
			hud.replay = true
			net_client.roll_received.connect(func(o: RollOutcome) -> void: _play_roll(o))
	else:
		for p: PlayerState in state.players:
			if not bots.has(p.slot) and _replay == null:
				local.append(p.slot)
	hud.replay = _replay != null or (net_role == "client" and net_client.replay_stream)
	hud.setup(engine, state, db, local)
	# One player here, on the red team: the camera looks from their side (two at one screen keep blue).
	if local.size() == 1 and state.team_of(local[0]) == 1:
		cam.set_flipped(true)
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
		_replay_bar.exit_pressed.connect(_exit_replay)
		if _streaming():
			_replay_bar.hide_continue()
		_replay_bar.show_frame(_frame, _replay.frame_count(), state.turn, state.phase)
		if JsonUtil.as_bool(_config.get("autoplay", false)):
			_set_playing.call_deferred(true)
	hud.pass_pressed.connect(func(slot: int) -> void: _apply(Move.make(Move.PASS, slot)))
	hud.keep_pressed.connect(func(slot: int, keep: bool) -> void: _apply(Move.make(Move.MULLIGAN, slot, {"keep": keep})))
	hud.no_hero_pressed.connect(func(slot: int) -> void: _apply(Move.make(Move.SELECT, slot, {"hero": ""})))
	hud.card_pressed.connect(func(slot: int, cid: String, hero_id: String) -> void:
		var data: Dictionary = {"card": cid}
		if not hero_id.is_empty():
			data["hero"] = hero_id
			_flash_target(hero_id)
		_apply(Move.make(Move.PLAY_CARD, slot, data)))
	hud.targeting_changed.connect(_refresh_target_fx)
	hud.pick_confirmed.connect(func(slot: int, hero_id: String, roll: bool) -> void:
		hud.picks.erase(slot)
		hud.pick_rolls.erase(slot)
		_apply(Move.make(Move.SELECT, slot, {"hero": hero_id, "roll": roll})))
	hud.battle_cam_pressed.connect(_toggle_battle_cam)
	hud.battle_resolved.connect(_on_battle_resolved)
	hud.damage_pressed.connect(func(slot: int, target: String, cards: Array) -> void: _apply(Move.make(Move.DAMAGE_TO, slot, {"target": target, "cards": cards})))
	hud.energy_pressed.connect(func(slot: int, split: Dictionary) -> void: _apply(Move.make(Move.STAGE_ENERGY, slot, {"split": split})))
	hud.choose_pressed.connect(func(slot: int, value: Variant) -> void: _apply(Move.make(Move.CHOOSE, slot, {"value": value})))
	hud.ability_pressed.connect(func(slot: int, hero_id: String, card_id: String, index: int) -> void:
		_apply(Move.make(Move.USE_ABILITY, slot, {"hero": hero_id, "card": card_id, "index": index})))
	hud.hero_clicked.connect(_on_hero_clicked)
	# A hero panel under the mouse opens with its stats and lights its ball, as hovering the ball
	# does (Marko 2026-11-06).
	hud.hero_hovered.connect(func(id: String) -> void: _set_hover(id, true))
	hud.card_played.connect(_ghost_card)
	hud.ability_fired.connect(_ability_fx)
	hud.board_hovered.connect(func(hexes: Array[Vector2i]) -> void:
		_board_marks = hexes
		_refresh_range())
	hud.ball_choice_made.connect(func(_id: String) -> void: _refresh_target_fx())
	hud.menu_pressed.connect(_toggle_menu)
	hud.leave_pressed.connect(_leave)
	hud.rematch_pressed.connect(_rematch)
	hud.new_match_pressed.connect(func() -> void:
		await _snapshot()
		get_tree().change_scene_to_file(SETUP_SCENE))
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
		_range_key = "-"
		hud.setup_pick = _setup_item()
		hud.refresh())
	hud.new_match = net_role.is_empty()
	if net_role == "host":
		hud.rematch_text = "Back to the lobby"
	elif net_role == "client":
		hud.rematch_text = ""
	_menu = _build_menu_overlay()
	layer.add_child(_menu)


## The pause menu (Esc / MENU), like the main menu: a dark slanted band on the left with PAUSED,
## the turn and the entries in big italics; the match log on the right.
func _build_menu_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.visible = false
	# Over the HUD's raised pieces (a picked card, the hero panels showed through it).
	root.z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var band := Panel.new()
	var sb: StyleBoxFlat = UiTheme.box(Color(Palette.PANEL_SOLID, 0.97), 0)
	sb.skew = Vector2(0.12, 0)
	sb.expand_margin_left = 120
	sb.border_color = Palette.ACCENT
	sb.border_width_right = 4
	band.add_theme_stylebox_override("panel", sb)
	band.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	band.offset_right = 520
	root.add_child(band)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 70
	col.offset_right = 470
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	root.add_child(col)
	col.add_child(UiTheme.label("PAUSED", 76))
	_menu_info = UiTheme.label("", 18, Palette.MUTED, false)
	col.add_child(_menu_info)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	col.add_child(gap)
	_menu_first = _menu_entry(col, "RESUME", _toggle_menu)
	if net_role != "":
		_menu_entry(col, "PAUSE FOR EVERYONE", func() -> void:
			_toggle_menu()
			if net_role == "host":
				var why: String = net_host.set_paused(not net_host.paused, net_host.host_slot)
				if not why.is_empty():
					hud.toast(why, Palette.FG)
			else:
				net_client.send_pause(not net_client.paused))
	for slot: int in hud.local_slots:
		var who: String = (" · " + hud.player_name(slot).to_upper()) if hud.local_slots.size() > 1 else ""
		_menu_entry(col, "SURRENDER" + who, func() -> void:
			_toggle_menu()
			_apply(Move.make(Move.SURRENDER, slot)))
	_menu_entry(col, "SETTINGS", _open_settings)
	_menu_entry(col, "MAIN MENU", _leave)

	# The match log, right: newest at the bottom.
	var log_box := VBoxContainer.new()
	log_box.anchor_left = 0.42
	log_box.anchor_right = 0.94
	log_box.anchor_top = 0.12
	log_box.anchor_bottom = 0.88
	log_box.add_theme_constant_override("separation", 10)
	root.add_child(log_box)
	_menu_log_box = log_box
	# Tabs MATCH LOG and COMBO LIST when there are combos (Marko 2026-11-07), else just the heading.
	if engine.catalog.of_type("Combo").is_empty():
		log_box.add_child(UiTheme.label("MATCH LOG", 26, Palette.GOLD))
	else:
		log_box.add_child(_menu_tabs(false))
	_menu_log = PanelContainer.new()
	_menu_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_log.add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.PANEL_SOLID, 0.9), 0, Color(0, 0, 0, 0), 22, 16))
	log_box.add_child(_menu_log)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_log.add_child(scroll)
	# Rich text: turn headings, names in team colours, damage in red (Marko 2026-11-01).
	var log_text := RichTextLabel.new()
	log_text.name = "Text"
	log_text.bbcode_enabled = true
	log_text.fit_content = true
	log_text.scroll_active = false
	log_text.selection_enabled = true
	log_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_text.add_theme_color_override("default_color", Color("d8d3cb"))
	log_text.add_theme_font_size_override("normal_font_size", 15)
	log_text.add_theme_font_size_override("bold_font_size", 15)
	log_text.add_theme_font_size_override("italics_font_size", 15)
	log_text.add_theme_constant_override("line_separation", 5)
	scroll.add_child(log_text)
	_combo_box = _build_combo_box()
	root.add_child(_combo_box)
	return root


## The combo list (combo plan step 6), like a fighting game's move list: the combos this screen's deck
## can make, or every combo (ALL). The opponent's deck never shows here.
func _build_combo_box() -> Control:
	var box := VBoxContainer.new()
	box.anchor_left = 0.42
	box.anchor_right = 0.94
	box.anchor_top = 0.12
	box.anchor_bottom = 0.88
	box.add_theme_constant_override("separation", 10)
	box.visible = false
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var tabs: HBoxContainer = _menu_tabs(true)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tabs)
	_combo_toggle = HBoxContainer.new()
	_combo_toggle.add_theme_constant_override("separation", 6)
	head.add_child(_combo_toggle)
	for all: bool in [false, true]:
		var b := Button.new()
		b.text = "ALL" if all else "YOUR DECK"
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func() -> void:
			_combo_all = all
			_fill_combos())
		_combo_toggle.add_child(b)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.PANEL_SOLID, 0.9), 0, Color(0, 0, 0, 0), 22, 16))
	box.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_combo_list = VBoxContainer.new()
	_combo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combo_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_combo_list)
	return box


## The two tabs over the pause menu's right side; the open one gold, the other one a quiet button.
func _menu_tabs(combos_open: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	for combos: bool in [false, true]:
		var b := Button.new()
		b.text = "COMBO LIST" if combos else "MATCH LOG"
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiTheme.display_heavy())
		b.add_theme_font_size_override("font_size", 26)
		var open: bool = combos == combos_open
		b.add_theme_color_override("font_color", Palette.GOLD if open else Palette.MUTED)
		b.add_theme_color_override("font_hover_color", Palette.GOLD if open else Palette.FG)
		b.add_theme_color_override("font_pressed_color", Palette.GOLD)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not open:
			b.pressed.connect(func() -> void: _show_combos(combos))
		row.add_child(b)
	return row


## The right side shows the combo list (true) or the match log.
func _show_combos(on: bool) -> void:
	if _combo_box == null:
		return
	_combo_box.visible = on
	_menu_log_box.visible = not on
	if on:
		_fill_combos()


func _fill_combos() -> void:
	MatchHud._clear(_combo_list)
	var mine: PackedStringArray = _own_deck_cards()
	var has_deck: bool = not mine.is_empty()
	_combo_toggle.visible = has_deck
	var show_all: bool = _combo_all or not has_deck
	for i: int in _combo_toggle.get_child_count():
		var b: Button = _combo_toggle.get_child(i) as Button
		b.theme_type_variation = &"Gold" if (i == 1) == show_all else &""
	var shown: int = 0
	for c: CardDef in engine.catalog.of_type("Combo"):
		var makes: bool = has_deck and c.ingredients.size() == 2 and mine.has(c.ingredients[0]) and mine.has(c.ingredients[1])
		if has_deck and not makes and not show_all:
			continue
		_combo_list.add_child(_combo_row(c, makes or not has_deck, has_deck, mine))
		shown += 1
	if shown == 0:
		var none: Label = UiTheme.label("Your deck makes no combo. ALL shows every combo.", 20, Palette.MUTED, false)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_combo_list.add_child(none)


## One combo: its card (its text is on it), name and extra energy, its two cards (pictures, names, codes; one your deck
## lacks is dim).
func _combo_row(c: CardDef, lit: bool, has_deck: bool, mine: PackedStringArray) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var tex: Texture2D = db.thumb(c.id) if db.thumb(c.id) != null else db.large(c.id)
	if tex != null:
		var a: float = float(tex.get_width()) / tex.get_height()
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.custom_minimum_size = Vector2(280, 280 / a)
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		pic.material = MatchHud.round_corners(a)
		row.add_child(pic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	col.add_child(UiTheme.label("%s   +%d ENERGY" % [c.name.to_upper(), c.extra_cost], 26, Palette.FG))
	var parts := HBoxContainer.new()
	parts.add_theme_constant_override("separation", 12)
	col.add_child(parts)
	for k: int in c.ingredients.size():
		var id: String = c.ingredients[k]
		if k > 0:
			var plus: Label = UiTheme.label("+", 34, Palette.GOLD)
			plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			parts.add_child(plus)
		parts.add_child(_combo_part(id, has_deck and not mine.has(id)))
	# Each combo on its own plate (Marko 2026-11-07: with several they ran together); one your deck
	# makes has a gold edge on the left, the same size as the others (the edge is drawn inside).
	var plate := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Palette.SURFACE_2, 0, Palette.LINE, 16, 14)
	if lit and has_deck:
		sb.border_color = Palette.GOLD
		sb.set_border_width_all(0)
		sb.border_width_left = 5
	plate.add_theme_stylebox_override("panel", sb)
	plate.add_child(row)
	if has_deck and not lit:
		col.add_child(UiTheme.label("NOT IN YOUR DECK", 15, Palette.MUTED))
		plate.modulate.a = 0.6
	return plate


## One card of a combo: its picture, name and code under it; dim when your deck lacks it.
func _combo_part(id: String, missing: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size.x = 120
	var tex: Texture2D = db.thumb(id) if db.thumb(id) != null else db.large(id)
	if tex != null:
		var a: float = float(tex.get_width()) / tex.get_height()
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.custom_minimum_size = Vector2(120, 120 / a)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.material = MatchHud.round_corners(a)
		box.add_child(pic)
	var card: CardDef = engine.catalog.get_card(id)
	var name: Label = UiTheme.label(card.name if card != null else "?", 17, Palette.GOLD, false)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size.x = 120
	box.add_child(name)
	var code: Label = UiTheme.label(id, 14, Palette.MUTED, false)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(code)
	if missing:
		box.modulate.a = 0.45
	return box


## The cards of the deck this screen plays: from the match record (local, host), or the deck this
## guest sent (online). Empty when nobody here plays (a replay, a spectator).
func _own_deck_cards() -> PackedStringArray:
	var slot: int = hud.hand_slot()
	if slot < 0 and not hud.local_slots.is_empty():
		slot = hud.local_slots[0]
	if slot < 0 or _replay != null:
		return PackedStringArray()
	var deck: Dictionary = {}
	if net_role == "client":
		deck = net_client.my_deck if net_client != null else {}
	elif recorder != null and slot < recorder.record.decks.size():
		deck = JsonUtil.as_dict(recorder.record.decks[slot])
	return PackedStringArray(JsonUtil.as_dict(deck.get("cards", {})).keys())


## One entry of the pause menu: big italic, left; the first one red.
func _menu_entry(col: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"MenuItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(260, 0)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	col.add_child(b)
	return b


func _toggle_menu() -> void:
	if state.is_over() and _replay == null:
		_leave()
		return
	_menu.visible = not _menu.visible
	hud.set_menu_open(_menu.visible)
	cam.keys_on = not _menu.visible
	if _menu.visible:
		# Nothing goes on under it: no ball stays lit, no throw stays in the hand.
		_set_hover("", true)
		if _sling.is_aiming():
			_sling.cancel()
			arena.set_grid_emphasis(false)
			_refresh_target_fx()
		var phase: String = MatchHud._ribbon_phase(state.phase).to_upper()
		_menu_info.text = ("TURN %d  ·  %s PHASE" % [state.turn, phase]) if state.turn > 0 else "SETUP"
		_fill_menu_log()
		_show_combos(false)
		_menu_first.grab_focus.call_deferred()


## Settings over the match (Marko 2026-11-07): the same screen as from the main menu; Back or Esc
## comes back to the pause menu, the match is never left. Changes apply at once.
func _open_settings() -> void:
	if _settings != null:
		return
	_settings = (load(SETTINGS_SCENE) as PackedScene).instantiate() as Control
	_settings.set("on_back", _close_settings)
	_settings.z_index = 110
	_menu.get_parent().add_child(_settings)


func _close_settings() -> void:
	if _settings == null:
		return
	_settings.queue_free()
	_settings = null
	hud.refresh()
	_menu_first.grab_focus.call_deferred()


## The whole log in the pause menu, newest at the bottom, scrolled there.
func _fill_menu_log() -> void:
	if _menu_log == null:
		return
	var text: RichTextLabel = _menu_log.find_child("Text", true, false) as RichTextLabel
	text.text = hud.log_bbcode()
	var scroll: ScrollContainer = text.get_parent() as ScrollContainer
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


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
	# A series (Best of 3): back to the setup for the next game's stages and cores; a finished
	# series leaves the setup to start a new one.
	if _local_series():
		if MatchSeries.current.is_over():
			MatchSeries.current = null
		get_tree().change_scene_to_file(SETUP_SCENE)
		return
	var settings: MatchSettings = _config["settings"]
	var c: Dictionary = _config.duplicate()
	c["settings"] = MatchSettings.from_dict(settings.to_dict())
	c["seed"] = randi()
	MatchLaunch.config = c
	get_tree().change_scene_to_file(MATCH_SCENE)


## The end screen's series line (Best of 3) and what its first button does next.
func _refresh_series() -> void:
	var s: MatchSeries = null
	if net_role == "host":
		s = net_host.series
	elif net_role == "client":
		s = MatchSeries.from_dict(net_client.series) if not net_client.series.is_empty() else null
	elif _local_series():
		s = MatchSeries.current
	if s == null or s.games == 0:
		hud.series_text = ""
		return
	var line: String = "SERIES %s" % s.score()
	if s.is_over():
		line += ("  ·  %s TAKES THE SERIES" % hud.player_name(s.winner()).to_upper()) if s.winner() >= 0 else "  ·  A DRAWN SERIES"
	else:
		line += "  ·  GAME %d NEXT" % (s.games + 1)
	hud.series_text = line
	if net_role == "":
		hud.rematch_text = "New series" if s.is_over() else "Next game"


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
		# The roll is over: the state puts the balls where they ended.
		_net_to.clear()
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
		_net_to[str(id)] = Vector3(JsonUtil.as_float(p[0]), JsonUtil.as_float(p[1]), JsonUtil.as_float(p[2]))
	_net_touch_cores()


## Online guest: a core a ball runs over goes from the table at once, as on the host (playtest
## 2026-11-07: it went only when the roll was over). The state after the roll settles it.
func _net_touch_cores() -> void:
	for c: CoreState in state.cores:
		if c.place != CoreState.ON_FIELD or not _core_tokens.has(c.id) or not _core_tokens[c.id].visible:
			continue
		var at: Vector3 = arena.hex_center(c.hex)
		for id: String in _net_to:
			var to: Vector3 = _net_to[id]
			if arena.area_at(to) != BallWorld.Area.MAP:
				continue
			if Vector2(to.x - at.x, to.z - at.z).length() < _bodies[id].radius() + CORE_RADIUS:
				_core_tokens[c.id].visible = false
				break


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
		_end_moment()
		_snapshot()
		if net_role == "":
			ReplayStore.clear_current()
		elif net_role == "host":
			ReplayStore.clear_current_online()
		ReplayStore.save_replay(recorder.record)
		ReplayStore.write_stats(recorder.record, db.root_dir)
		hud.end_summary = recorder.record.summary()
		if _local_series() and not MatchSeries.current.is_over():
			MatchSeries.current.record(state.winner)
	elif (net_role == "" or (net_role == "host" and _replay == null)) and recorder.record.frame_count() != _saved_frames:
		# The host keeps its online match too (online playtest 2026-11-07: a match the host left was
		# gone): Online › CONTINUE THE MATCH opens the table again and the others join back.
		_saved_frames = recorder.record.frame_count()
		if net_role == "host":
			ReplayStore.save_current_online(recorder.record)
		else:
			ReplayStore.save_current(recorder.record)


## The connection above the other player's name: the link's own round trip, nothing extra is sent.
func _update_ping() -> void:
	var ms: int = -1
	var other: int = 1
	if net_role == "host":
		other = 1 - net_host.host_slot
		var s: Dictionary = net_host.seat(other)
		if not s.is_empty() and not JsonUtil.as_bool(s.get("bot", false)) and JsonUtil.as_bool(s.get("connected", false)):
			ms = net_host.link.rtt_ms(JsonUtil.as_int(s.get("peer", -1)))
	elif net_client != null and net_client.slot >= 0:
		other = 1 - net_client.slot
		ms = net_client.link.rtt_ms(1)
	hud.set_ping(ms if not state.is_over() else -1, other == 1)


## The deciding moment before the end screen (Marko 2026-11-08: "I did not know why I won"): the
## table stays END_HOLD_TIME, the camera on where it was decided (the last hero down, the stage
## that made three), a band says what happened and who won; a click or Enter skips it.
func _end_moment() -> void:
	if hud.end_hold or _replay != null:
		return
	hud.end_hold = true
	var at: Vector3 = Vector3.ZERO
	var found: bool = false
	var e: Dictionary = {}
	for i: int in range(state.log.size() - 1, -1, -1):
		var t: String = str(state.log[i].get("type", ""))
		if t == "ko" or t == "stage_claimed":
			e = state.log[i]
			break
	if str(e.get("type", "")) == "ko":
		var h: HeroState = state.hero(str(e.get("hero", "")))
		if h != null and _bodies.has(h.id):
			at = _bodies[h.id].global_position
			found = true
	elif str(e.get("type", "")) == "stage_claimed":
		var st: StageState = state.stage(str(e.get("stage", "")))
		if st != null and st.placed:
			at = arena.hex_center(st.center)
			found = true
	if found:
		cam.focus(at, 12.0)
	var winner: String = hud.player_name(state.winner).to_upper() if state.winner >= 0 else ""
	var title: String = "DRAW" if state.winner < 0 else ("%s WINS" % winner)
	var why: String = {"ko": "EVERY HERO OF THE OTHER SIDE IS DOWN", "stages": "THREE STAGES CLAIMED", "stages_energy": "MORE ENERGY IN THE STAGES",
		"surrender": "SURRENDER"}.get(state.result, "")
	hud.banner(title, Palette.GOLD if state.winner >= 0 else Palette.SURFACE_2, "", why, MatchHud.END_HOLD_TIME, "")
	get_tree().create_timer(0.1).timeout.connect(func() -> void: _end_hold_watch())


## The end screen comes when the band is gone (held its time, or skipped).
func _end_hold_watch() -> void:
	if not is_inside_tree():
		return
	if hud.is_announcing():
		get_tree().create_timer(0.1).timeout.connect(func() -> void: _end_hold_watch())
		return
	hud.end_hold = false
	hud.refresh()


## Puts every node where the state says and redraws the HUD.
func _sync() -> void:
	world.terrain = engine.terrain(state)
	arena.set_terrain(world.terrain)
	_refresh_terrain_fx()
	_clear_ghosts()
	world.blocked.clear()
	for w: WallState in state.walls:
		for a: Vector2i in w.hexes:
			world.blocked[a] = true
	for h: HeroState in state.heroes:
		_sync_hero(h)
	_rebuild_tokens()
	# Not "": an empty highlight must still clear the last one (the setup zones stayed lit).
	_range_key = "-"
	_draw_marks()
	_update_battle_cam()
	_refresh_target_fx()
	hud.rolling = _runner.is_running() or _launching
	hud.setup_pick = _setup_item()
	if state.is_over():
		_refresh_series()
	hud.refresh()
	if _replay != null or net_role == "client":
		# Watching, or a guest: nothing moves by itself; balls follow what the host sends.
		hud.rolling = net_role == "client" and (state.awaiting_roll or not state.pending_knockbacks.is_empty())
		hud.refresh()
		for b: BallBody in _bodies.values():
			b.freeze = true
		return
	if state.awaiting_roll and not _runner.is_running() and not _launching:
		_launch_roll()
	elif not state.pending_knockbacks.is_empty() and not _runner.is_running() and not _launching:
		_launch_knockbacks()


func _sync_hero(h: HeroState) -> void:
	var b: BallBody = _bodies[h.id]
	var v: BallView = _views[h.id]
	var first: bool = not _hp.has(h.id)
	var was: int = _hp.get(h.id, h.hp)
	_hp[h.id] = h.hp
	# The standee follows the top evolution, back to the hero's own when it goes (playtest
	# 2026-10-30); an evolution without a sprite keeps the hero's.
	var top: CardDef = engine.stat_card(h)
	var figure: Texture2D = db.sprite_of(top.id) if top != null else null
	v.set_figure(figure if figure != null else db.sprite_of(h.card_id))
	var animate: bool = not first and not _quiet
	v.set_evolved(h.evolutions.size() if not h.is_ko() else 0, animate)
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
				cam.shake()
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
	if _sliding.has(h.id):
		return
	var open: bool = _shows_figure(h)
	# An open hero barely moves when bumped (BallBody.planted, playtest 2026-10-30).
	b.planted = open
	if open and not v.is_open() and v.state != BallView.State.OPENING:
		v.open()
	elif not open and v.is_open():
		v.close()
	# A closed ball at rest stands upright, button to the camera (GDD 5).
	if not open and v.state == BallView.State.CLOSED and b.motion == BallBody.Motion.RESTING:
		v.settle()


## A ball opens into its figure when it stands on a stage or is in a battle (GDD 5); else it
## stays a ball.
func _shows_figure(h: HeroState) -> bool:
	if not h.is_on_map():
		return false
	# Locked in a tied battle: it is in a fight, so it stands as a figure (Marko 2026-10-26).
	if h.tie_turns > 0:
		return true
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
	# An open ball (a figure on a stage) closes first, so the figure does not tumble off its
	# centre, and opens again on landing if it should.
	_sliding[b.ball_id] = true
	var wait: float = 0.0
	if v != null and (v.is_open() or v.state == BallView.State.OPENING):
		v.close(true)
		wait = BallView.CLOSE_TIME_FAST
	var from: Vector3 = b.global_position
	var to := Vector3(target.x, from.y, target.z)
	var dist: float = Vector2(to.x - from.x, to.z - from.z).length()
	var steps: float = dist / maxf(tuning.hex_size * 1.7, 0.01)
	# Slow enough to follow what a battle did (it used to be over in a blink).
	var height: float = clampf(0.45 + 0.3 * steps, 0.45, 1.8)
	var time: float = clampf(0.45 + 0.12 * steps, 0.45, 1.0) * GameSettings.anim_scale()
	var t: Tween = create_tween()
	if wait > 0.0:
		t.tween_interval(wait)
	t.tween_method(func(k: float) -> void:
		var p: Vector3 = from.lerp(to, k)
		p.y += sin(k * PI) * height
		if v != null:
			v.roll(p - b.global_position)
		b.global_position = p, 0.0, 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void:
		b.place(target)
		if v != null:
			v.land()
			v.settle()
		_sliding.erase(b.ball_id)
		var h: HeroState = state.hero(b.ball_id) if state != null else null
		if v != null and h != null and _shows_figure(h) and not v.is_open():
			v.open())


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
	for st: StageState in state.stages:
		if st.placed and st.revealed:
			var art: Node3D = _stage_art(st)
			if art != null:
				_tokens.add_child(art)
	for c: CoreState in state.cores:
		if c.place != CoreState.ON_FIELD:
			continue
		var token: Node3D = _core_token(c)
		token.position = arena.hex_center(c.hex) + Vector3(0, 0.06, 0)
		_tokens.add_child(token)
		_core_tokens[c.id] = token
	for w: WallState in state.walls:
		for a: Vector2i in w.hexes:
			# A wall is solid for the physics too: a physics knockback bounces off it and the sim
			# counts the hit (RollResult.walls_hit). A static body on the ground layer the balls see,
			# with the drawn prism inside.
			var body := StaticBody3D.new()
			body.collision_layer = BallBody.LAYER_GROUND
			body.collision_mask = 0
			body.add_to_group("walls")
			body.set_meta("wall", w.id)
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = tuning.hex_size * 0.92
			cyl.height = 1.2
			shape.shape = cyl
			body.add_child(shape)
			body.add_child(_hex_prism(tuning.hex_size * 0.92, 1.2, Color("5a5049"), Color("6d625a")))
			body.position = arena.hex_center(a) + Vector3(0, 0.6, 0)
			_tokens.add_child(body)
	# A tied, locked pair: shackles on the ground and dimmed balls (_lock_links, _refresh_targets),
	# no words over the table (Marko 2026-11-02).
	for st: StageState in state.stages:
		if st.is_claimed():
			var flag := MeshInstance3D.new()
			var pole := CylinderMesh.new()
			pole.top_radius = 0.06
			pole.bottom_radius = 0.06
			pole.height = 2.6
			flag.mesh = pole
			var team_col: Color = Palette.team(state.team_of(st.claimed_by))
			flag.material_override = MeshKit.unshaded(Color("e8e2d6"), false)
			flag.position = arena.hex_center(st.center) + Vector3(0, 1.3, 0)
			_tokens.add_child(flag)
			# The banner on the pole, in the claimer's colour.
			var cloth := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1.1, 0.7, 0.05)
			cloth.mesh = box
			cloth.material_override = MeshKit.unshaded(team_col, false)
			cloth.position = flag.position + Vector3(0.58, 0.85, 0)
			_tokens.add_child(cloth)
		# A stage someone stayed on, or has energy in, says so in the HUD box and by its edge
		# (_draw_marks), not in words over the table (Marko 2026-11-02).


## A revealed stage's card art laid on its hexes, faded, cut to their shape: the stage reads as
## a place on the table, not just an outline. Null without a picture.
func _stage_art(st: StageState) -> Node3D:
	var tex: Texture2D = db.large(st.card_id) if db.large(st.card_id) != null else db.thumb(st.card_id)
	if tex == null:
		return null
	var cells: Array[Vector2i] = st.footprint()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for a: Vector2i in cells:
		var c2: Vector2 = arena.map.to_world(a)
		for i: int in 6:
			var p: Vector2 = c2 + Hex.corner(i, tuning.hex_size)
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span: Vector2 = hi - lo
	var region: Rect2 = HeroSlice.card_art_region(tex, span.x / span.y)
	var stt := SurfaceTool.new()
	stt.begin(Mesh.PRIMITIVE_TRIANGLES)
	stt.set_normal(Vector3.UP)
	for a: Vector2i in cells:
		var c2: Vector2 = arena.map.to_world(a)
		for i: int in 6:
			var p0: Vector2 = c2 + Hex.corner(i, tuning.hex_size)
			var p1: Vector2 = c2 + Hex.corner(i + 1, tuning.hex_size)
			for p: Vector2 in [c2, p1, p0]:
				stt.set_uv(region.position + region.size * ((p - lo) / span))
				# Draped over a Ramp hill, so the hill shows through the picture.
				stt.add_vertex(Vector3(p.x, arena.height_at(Vector3(p.x, 0, p.y)), p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = stt.commit()
	mi.position.y = 0.02
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, STAGE_ART_ALPHA)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mat
	# The terrain shows on the picture (Marko 2026-10-26: it was felt, not seen): ice is pale
	# and shiny, mud dark and dull; snow, mud and wind play over it (_refresh_terrain_fx).
	var kind: Terrain.Type = world.terrain.at(st.center) if world != null and world.terrain != null else Terrain.Type.NONE
	match kind:
		Terrain.Type.ICE:
			mat.albedo_color = Color(0.82, 0.95, 1.15, STAGE_ART_ALPHA)
			mat.roughness = 0.12
			mat.metallic = 0.35
		Terrain.Type.MUD:
			mat.albedo_color = Color(0.72, 0.55, 0.38, STAGE_ART_ALPHA + 0.15)
			mat.roughness = 1.0
	# A Ramp shows as contour lines and downhill arrows on the hill (Arena._add_hill_marks), no
	# label (Marko 2026-11-02).
	return mi


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
	elif not c.face_up:
		pic = db.core_back(null, c.card_id)
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
	_refresh_battle_fx()
	_marks.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_mat)
	var any: bool = false
	# While a battle is on, red means only the battle: the stages step back to grey dashes.
	var fighting: bool = not _current_battle().is_empty()
	for st: StageState in state.stages:
		if not st.placed:
			continue
		var col: Color = Color(Palette.GOLD, 0.35)
		if st.revealed:
			col = Color(Palette.GOLD, 0.85)
		# The energy claim variant: the edge takes the colour of the side with energy in it
		# (the most, when both have some), and goes grey while heroes of both sides stand on it.
		if st.revealed and not st.is_claimed() and state.settings.energy_claims():
			var best: int = -1
			for sl: int in st.progress:
				if st.progress[sl] > 0 and (best < 0 or st.progress[sl] > st.progress[best]):
					best = sl
			if engine.contested(state, st):
				col = Color(0.45, 0.41, 0.37, 0.9)
			elif best >= 0:
				col = Color(Palette.team(state.team_of(best)), 0.9)
		if st.is_claimed():
			col = Palette.team(state.team_of(st.claimed_by))
		if fighting:
			col = Color(0.45, 0.41, 0.37, 0.7)
		any = _outline(st.footprint(), col, fighting) or any
		# A claimed stage is filled with its owner's colour: it reads as taken from afar.
		if st.is_claimed() and not fighting:
			_fill(st.footprint(), Color(Palette.team(state.team_of(st.claimed_by)), 0.32))
			any = true
	if state.phase == GameState.PHASE_BATTLE or state.phase == GameState.PHASE_POSTROLL:
		any = _battle_arrows() or any
	any = _lock_links() or any
	if not any:
		_marks.surface_add_vertex(Vector3.ZERO)
		_marks.surface_add_vertex(Vector3.ZERO)
		_marks.surface_add_vertex(Vector3.ZERO)
	_marks.surface_end()
	_draw_claim_marks()


## The outer edge of `cells`; `dashed` draws every edge as half a dash.
func _outline(cells: Array[Vector2i], color: Color, dashed: bool = false, im: ImmediateMesh = null, width: float = 0.09) -> bool:
	if im == null:
		im = _marks
	var drew: bool = false
	for a: Vector2i in cells:
		var c2: Vector2 = arena.map.to_world(a)
		for i: int in 6:
			if cells.has(a + Hex.DIRECTIONS[i]):
				continue
			var p0: Vector2 = c2 + Hex.corner(i - 1, tuning.hex_size) * 0.97
			var p1: Vector2 = c2 + Hex.corner(i, tuning.hex_size) * 0.97
			if dashed:
				p1 = p0.lerp(p1, 0.5)
			MeshKit.ribbon(im, PackedVector3Array([Vector3(p0.x, 0.04, p0.y), Vector3(p1.x, 0.04, p1.y)]), 0.07 if dashed else width, color)
			drew = true
	return drew


## The heroes in the battle being fought now, or none.
func _current_battle() -> PackedStringArray:
	if state.phase == GameState.PHASE_BATTLE and state.battle_index >= 0 and state.battle_index < state.battles.size():
		return JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", []))
	return PackedStringArray()


## Arrows from each hero to the opponents it reaches (range is not mutual, GDD 11).
func _battle_arrows() -> bool:
	var drew: bool = false
	var current: PackedStringArray = _current_battle()
	# Battles still to come this phase (thin, faint red).
	var waiting := PackedStringArray()
	if not current.is_empty():
		for i: int in range(state.battle_index + 1, state.battles.size()):
			waiting.append_array(JsonUtil.as_strings(state.battles[i].get("heroes", [])))
	for a: HeroState in state.heroes:
		for b: HeroState in state.heroes:
			if a == b or state.same_team(a, b) or not engine.in_range(state, a, b):
				continue
			var hot: bool = current.has(a.id) and current.has(b.id)
			var later: bool = waiting.has(a.id) and waiting.has(b.id)
			# During a battle only battles get arrows: the one now thick red, the next ones faint.
			if not current.is_empty() and not hot and not later:
				continue
			var col: Color = Palette.ACCENT if hot else (Color(Palette.ACCENT, 0.45) if later else Color(1, 1, 1, 0.35))
			var from: Vector3 = arena.hex_center(a.hex)
			var to: Vector3 = arena.hex_center(b.hex)
			var d: Vector3 = (to - from).normalized()
			var ra: float = _bodies[a.id].radius() + 0.15
			var rb: float = _bodies[b.id].radius() + 0.35
			var start: Vector3 = from + d * ra + Vector3(0, 0.06, 0)
			var head: Vector3 = to - d * rb + Vector3(0, 0.06, 0)
			MeshKit.ribbon(_marks, PackedVector3Array([start, head]), 0.22 if hot else 0.07, col)
			var side: Vector3 = Vector3.UP.cross(d) * (0.45 if hot else 0.3)
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
	# A hovered hero shows only its own range, so it is clear whose it is (playtest 2026-10-30:
	# two activated ranges ran into one patch). Otherwise the activated heroes' ranges show,
	# unless only on hover (Settings → Interface).
	if not _hovered.is_empty():
		ids.append(_hovered)
	elif GameSettings.range_mode() == "active":
		for slot: int in state.active:
			if not hud.shown_active(slot).is_empty():
				ids.append(hud.shown_active(slot))
	for id: String in ids:
		var h: HeroState = state.hero(id)
		if h == null or not h.is_on_map() or _bodies[h.id].motion != BallBody.Motion.RESTING:
			continue
		var rng: int = engine.stat(state, h, "rng")
		key += "%s:%s:%d;" % [h.id, h.hex, rng]
		cells.append_array(arena.map.range_cells(h.hex, h.big, rng))
		marked.append_array(state.footprint(h))
	# No range circles while a battle is fought: red means the battle.
	if not _current_battle().is_empty():
		cells.clear()
		marked.clear()
		key = "battle"
	var item: String = _setup_item()
	if not item.is_empty():
		key = "setup:%s:%s" % [item, _setup_hover]
		cells = _setup_cells(item)
		marked.clear()
		if cells.has(_setup_hover):
			# A ternary's value is an untyped Array, which a typed one refuses at runtime.
			if state.stage(item) != null:
				marked = Hex.spiral(_setup_hover, 1)
			else:
				marked.append(_setup_hover)
	var d: Dictionary = _local_decision()
	if str(d.get("type", "")) == RulesEngine.DECISION_RETURN_CORE:
		var c: CoreState = state.core(str(d.get("core", "")))
		key += "core:%s" % c.id
		cells.clear()
		for a: Vector2i in arena.map.cells():
			if engine.core_return_error(state, c, a).is_empty():
				cells.append(a)
	elif not hud.choice_cores.is_empty():
		key += "cores:%s" % ",".join(hud.choice_cores)
		cells.clear()
		for cid: String in hud.choice_cores:
			cells.append(state.core(cid).hex)
	elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "hex":
		key += "choose:%d" % state.pending.size()
		cells.clear()
		for o: Variant in JsonUtil.as_array(d.get("options", [])):
			cells.append(JsonUtil.as_hex(o))
	# A stage or core hovered in the HUD strip is marked where it lies.
	if not _board_marks.is_empty():
		marked.append_array(_board_marks)
		key += "board:%s" % str(_board_marks)
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
		if h != null and not JsonUtil.as_bool(state.aims[slot].get("skip", false)):
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
		if JsonUtil.as_bool(aim.get("skip", false)):
			continue
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


## Physics knockback (GDD 10, 2026-10-26): the knocked balls close, then each is hit along its
## hex direction hard enough to go the knockback's hexes on open ground (distance is linear in
## power, see PhysicsTuning); walls and balls bounce it. The sim's outcome goes back to the
## engine through apply_knockback, the way a roll's does.
func _launch_knockbacks() -> void:
	_launching = true
	_knocking = true
	hud.rolling = true
	hud.refresh()
	for k: Dictionary in state.pending_knockbacks:
		var h: HeroState = state.hero(str(k.get("hero", "")))
		if h != null and _views.has(h.id):
			_views[h.id].close(true)
	get_tree().create_timer(BallView.CLOSE_TIME_FAST + 0.05).timeout.connect(_hit_all)


func _hit_all() -> void:
	var hits: Array[Dictionary] = []
	for k: Dictionary in state.pending_knockbacks:
		var h: HeroState = state.hero(str(k.get("hero", "")))
		if h == null or not _bodies.has(h.id):
			continue
		var b: BallBody = _bodies[h.id]
		var d: Vector2 = Hex.to_world(Hex.DIRECTIONS[posmod(JsonUtil.as_int(k.get("dir", 0)), 6)], 1.0).normalized()
		var hexes: float = float(JsonUtil.as_int(k.get("steps", 0)))
		hits.append({"ball": b, "dir": Vector3(d.x, 0, d.y), "power": clampf(hexes / tuning.full_power_hexes(b.wt), 0.0, 1.0)})
	_launching = false
	if hits.is_empty() or not _runner.start_many(hits):
		_on_roll_finished(RollOutcome.new())


func _physics_process(delta: float) -> void:
	if not _runner.is_running():
		return
	if net_role == "host":
		var now: int = Time.get_ticks_msec()
		if now - _ball_sent_ms >= 50:
			_ball_sent_ms = now
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
	var err: String
	if _knocking:
		_knocking = false
		err = net_host.apply_knockback(o) if net_role == "host" else recorder.apply_knockback(o)
	else:
		err = net_host.apply_roll(o) if net_role == "host" else recorder.apply_roll(o)
	if not err.is_empty():
		hud.toast(err, Palette.FG)
	else:
		_after_change()
	# Ring-outs get a banner from the log (MatchHud._scan_log).
	_sync()


# --- frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	_ping_tick -= delta
	if _ping_tick <= 0.0 and net_role != "" and _replay == null:
		_ping_tick = 1.0
		_update_ping()
	if not _net_to.is_empty():
		var k: float = 1.0 - exp(-delta * 18.0)
		for id: String in _net_to:
			if not _bodies.has(id):
				continue
			var b: BallBody = _bodies[id]
			var step: Vector3 = b.global_position.lerp(_net_to[id], k)
			_views[id].roll(step - b.global_position)
			b.global_position = step
	if _sling.is_aiming():
		_sling.update(cam.camera, get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size.y)
	_refresh_range()
	_pulse_t += delta
	if _claim_mat != null:
		_claim_mat.albedo_color = Color(1, 1, 1, 0.35 + 0.65 * (0.5 + 0.5 * sin(_pulse_t * 5.0)))
	for id: String in _views:
		# Balls ride over hills (the physics stays flat; see ArenaWorld.push_at).
		_views[id].position.y = arena.height_at(_bodies[id].global_position)
	if _replay != null:
		_run_playback(delta)
		return
	_run_phase_hold(delta)
	# Roll / Stay under the hovered or the picked ball (it follows the camera).
	_update_ball_choice()
	_run_bots(delta)
	_run_auto_pass(delta)
	_run_clock(delta)
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
				if _streaming():
					net_host.stream_roll(RollOutcome.from_dict(JsonUtil.as_dict(r)))
				await _play_roll(RollOutcome.from_dict(JsonUtil.as_dict(r)))
			_replay_busy = false
	state = _replay.state_at(_frame)
	hud.state = state
	if _streaming():
		net_host.stream_state(state)
	# Not "": an empty highlight must still clear the last one (the setup zones stayed lit).
	_range_key = "-"
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


## Auto-pass (GDD 8): a local player to act with nothing playable is passed for after a fixed
## wait, so the opponent cannot read "no card" off the speed; the Hold key stops it. When nobody
## at all could play (the host and a local match know every hand), the round goes at once. An
## empty roll offer is declined the same way, always after the full wait: every player is asked
## when the balls stop, and the wait is what hides who had something (GDD 8, 2026-10-26).
func _run_auto_pass(delta: float) -> void:
	if not GameSettings.auto_pass() or _replay != null or _menu.visible \
			or state.is_over() or _runner.is_running() or _launching or _phase_hold > 0.0 or hud.is_announcing() \
			or state.phase == GameState.PHASE_BATTLE:
		# Battle is never passed for the player (Marko 2026-10-26): it is the big moment.
		_idle_pass = 0.0
		return
	var slot: int = state.to_act
	var offer: bool = not state.pending.is_empty() and str(state.pending[0].get("type", "")) == RulesEngine.DECISION_ROLL_OFFER
	if offer:
		slot = -1
		for local: int in hud.local_slots:
			if not bots.has(local) and MatchHud.empty_offer(hud.own_roll_offer(local)):
				slot = local
				break
	if slot < 0 or not hud.local_slots.has(slot) or bots.has(slot) or Input.is_key_pressed(GameSettings.key("hold")):
		_idle_pass = 0.0
		return
	# What can be played changes only when the state does: worked out once per state.
	var key: String = "%d|%s|%d|%d|%d|%d|%d" % [state.turn, state.phase, state.battle_index, slot,
		state.passed.size(), state.log.size(), state.pending.size()]
	if key != _pass_key:
		_pass_key = key
		_pass_wait = -1.0
		if offer:
			_pass_wait = AUTO_PASS_DELAY
		elif hud.nothing_to_play(slot):
			_pass_wait = AUTO_PASS_DELAY
			# Only when both hands are on this screen: online, a quick pass would tell the guest
			# the host had nothing to play.
			if net_role == "":
				var anyone: bool = false
				for p: PlayerState in state.players:
					var other: int = p.slot
					if other != slot and not p.surrendered and hud.can_play(other):
						anyone = true
				if not anyone:
					_pass_wait = 0.25
	if _pass_wait < 0.0:
		_idle_pass = 0.0
		return
	_idle_pass += delta
	if _idle_pass >= _pass_wait:
		_idle_pass = 0.0
		_pass_key = ""
		_apply(Move.make(Move.PASS, slot))


# --- the move timer -----------------------------------------------------------------------

## The move timer (GDD 8, 2026-10-26): a clock per player the game waits for, restarted
## whenever what is asked of them changes; when it runs out the safe move is made for them
## (MatchClock). The scene keeps the time in a local match and as the host; a guest only
## counts down what the host sent (CLOCK). Bots are never timed. A local pause menu and an
## online pause freeze the clocks; so does a rolling ball.
func _run_clock(delta: float) -> void:
	var limit: int = state.settings.timer_seconds
	if limit <= 0 or _replay != null or state.is_over():
		if not _clocks.is_empty():
			_clocks.clear()
		hud.set_clock(-1, "")
		return
	var frozen: bool = _runner.is_running() or _launching or _phase_hold > 0.0 or hud.is_announcing() \
			or (net_role == "host" and net_host.paused) or (net_role == "client" and not hud.net_paused.is_empty()) \
			or (net_role.is_empty() and _menu.visible)
	if net_role != "client":
		var waited: PackedInt32Array = MatchClock.waiting_on(engine, state)
		var changed: bool = false
		for slot: int in _clocks.keys():
			if not waited.has(slot) or bots.has(slot):
				_clocks.erase(slot)
				changed = true
		for slot: int in waited:
			if bots.has(slot):
				continue
			var key: String = MatchClock.wait_key(engine, state, slot)
			if not _clocks.has(slot) or str(_clocks[slot]["key"]) != key:
				_clocks[slot] = {"key": key, "left": float(limit)}
				changed = true
		if changed and net_role == "host":
			net_host.send_clocks(_clock_seconds())
	if not frozen:
		for slot: int in _clocks:
			var c: Dictionary = _clocks[slot]
			c["left"] = JsonUtil.as_float(c["left"]) - delta
			if JsonUtil.as_float(c["left"]) > 0.0 or net_role == "client":
				continue
			# Not again until the wait changes (a refused move must not spin).
			c["left"] = float(limit)
			var hint: Dictionary = {"hero": str(hud.picks.get(slot, "")), "roll": JsonUtil.as_bool(hud.pick_rolls.get(slot, true), true)}
			var m: Move = MatchClock.timeout_move(engine, state, slot, _clock_rng, hint)
			if m != null:
				if hud.local_slots.has(slot):
					_sling.cancel()
					hud.picks.erase(slot)
					hud.pick_rolls.erase(slot)
				hud.toast("%s: time is up" % hud.player_name(slot), Palette.GOLD)
				_apply(m)
				return
	_show_clock()


## Seconds left per slot, whole, for the guests and the HUD.
func _clock_seconds() -> Dictionary:
	var out: Dictionary = {}
	for slot: int in _clocks:
		out[str(slot)] = ceili(JsonUtil.as_float(_clocks[slot]["left"]))
	return out


## A guest hears the host's clocks whenever one restarts and counts down from there.
func _on_net_clocks(clocks: Dictionary) -> void:
	_clocks.clear()
	for key: Variant in clocks:
		_clocks[str(key).to_int()] = {"key": "", "left": JsonUtil.as_float(clocks[key])}


## Your own clock when the game waits for you (the shortest, with two players here), else the
## one the other side is on.
func _show_clock() -> void:
	var mine: int = -1
	var theirs: int = -1
	var who: String = ""
	for slot: int in _clocks:
		var left: int = maxi(0, ceili(JsonUtil.as_float(_clocks[slot]["left"])))
		if hud.local_slots.has(slot) and not bots.has(slot):
			mine = left if mine < 0 else mini(mine, left)
		elif theirs < 0 or left < theirs:
			theirs = left
			who = hud.player_name(slot)
	if mine >= 0:
		hud.set_clock(mine, "")
	else:
		hud.set_clock(theirs, who)


func _run_bots(delta: float) -> void:
	# Bots wait for the bands in the middle too, so the table and the words stay in step.
	if bots.is_empty() or state.is_over() or _runner.is_running() or _launching or _menu.visible or _phase_hold > 0.0 \
			or hud.is_announcing():
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
	# The end screen is up: only its buttons (the HUD) and the menu key (Marko 2026-11-08).
	if state != null and state.is_over() and _replay == null and not _menu.visible:
		if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
			_toggle_menu()
		return
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
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and hud.is_targeting():
			hud.cancel_targeting()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _sling.is_aiming():
			_sling.cancel()
			arena.set_grid_emphasis(false)
			# The ball still to throw lights up again (Marko 2026-11-01: the beam was gone).
			_refresh_target_fx()
			return
	if event is InputEventMouseMotion and not _setup_item().is_empty():
		var g: Variant = _ground_under_mouse()
		if g != null:
			var gp: Vector3 = g
			_setup_hover = arena.hex_at(gp)
	if event is InputEventMouseMotion and not _sling.is_aiming() and not cam.is_dragging():
		_set_hover(_hero_under_mouse(), true)
	# Moving the camera by hand leaves the battle camera (it stays where it was moved to).
	if cam.handle_input(event) and hud.battle_cam:
		hud.battle_cam = false
		hud.refresh()


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
			cam.begin_drag(OrbitCamera.Drag.PAN if mb.pressed else OrbitCamera.Drag.NONE)
	if event is InputEventMouseMotion and not cam.is_dragging():
		_set_hover(_hero_under_mouse(), true)
	cam.handle_input(event)


func _on_key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	match GameSettings.logical_key(k.keycode):
		KEY_ESCAPE:
			if hud.is_targeting():
				hud.cancel_targeting()
			elif _sling.is_aiming():
				_sling.cancel()
				arena.set_grid_emphasis(false)
				_refresh_target_fx()
			else:
				_toggle_menu()
		KEY_SPACE:
			if state.phase == GameState.PHASE_START:
				# Space confirms the picked hero (it used to send a Pass the engine refused with
				# "select a hero", playtest 2026-10-30).
				hud.confirm_pick()
			elif hud.local_slots.has(state.to_act) and not state.round_over:
				_apply(Move.make(Move.PASS, state.to_act))
		KEY_HOME:
			cam.reset_view()
		KEY_B:
			# Beams on or off (Settings → Interface); the rings stay.
			GameSettings.set_value("display", "beams", not GameSettings.beams())
			_refresh_target_fx()
			hud.toast("Beams %s" % ("on" if GameSettings.beams() else "off"), Palette.FG)
		KEY_C:
			_toggle_battle_cam()
		KEY_T:
			# Words over the table on or off (Marko 2026-11-01).
			GameSettings.set_value("display", "table_text", not GameSettings.table_text())
			_rebuild_tokens()
			hud.toast("Words over the table %s" % ("on" if GameSettings.table_text() else "off"), Palette.FG)
		KEY_G:
			hud.toggle_stage_strips()


func _on_left(pressed: bool) -> void:
	if pressed:
		# A click on the table puts a PASS offer away (a click on the ball offers it again).
		hud.hide_ball_pass()
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
		if not hud.choice_cores.is_empty():
			var g: Variant = _ground_under_mouse()
			if g != null:
				var gp: Vector3 = g
				var at: Vector2i = arena.hex_at(gp)
				for cid: String in hud.choice_cores:
					var c: CoreState = state.core(cid)
					if c != null and c.hex == at:
						_apply(Move.make(Move.CHOOSE, hud.choice_slot, {"value": cid}))
						return
		var id: String = _hero_under_mouse()
		if hud.is_targeting() and not id.is_empty() and hud.play_target(id):
			return
		if not id.is_empty() and (hud.choice_heroes.has(id) or hud.damage_heroes.has(id)):
			_on_hero_clicked(id)
			return
		if not id.is_empty() and _try_aim(id):
			return
		if not id.is_empty():
			_on_hero_clicked(id)
			return
		_press_on_empty = true
		# Left drag on the table pans, right drag orbits (playtest 2026-10-30: both orbited).
		cam.begin_drag(OrbitCamera.Drag.PAN)
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
	_refresh_target_fx()
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
		_refresh_target_fx()
		return
	var h: HeroState = state.hero(ball.ball_id)
	_apply(Move.make(Move.AIM, h.owner, {"dir": [dir.x, dir.z], "power": power}))


func _on_hero_clicked(id: String) -> void:
	# A card waits for a hero: clicking one it can go on plays it.
	if hud.is_targeting():
		hud.play_target(id)
		return
	# A card effect waits for a hero: a lit one answers it.
	if hud.choice_heroes.has(id):
		_apply(Move.make(Move.CHOOSE, hud.choice_slot, {"value": id}))
		return
	# A lost battle's DMG: a lit hero is picked to take it (CONFIRM in the dialog sends it).
	if hud.damage_heroes.has(id):
		hud.pick_damage_hero(id)
		return
	var h: HeroState = state.hero(id)
	if h == null:
		return
	if state.phase == GameState.PHASE_START and hud.local_slots.has(h.owner) and not state.active.has(h.owner):
		# A click only chooses (another click changes it); CONFIRM locks it in.
		var can: bool = false
		for x: HeroState in engine.selectable_heroes(state, h.owner):
			can = can or x.id == id
		if can:
			hud.picks[h.owner] = id
			hud.refresh()
			_refresh_target_fx()
		elif h.tie_turns > 0:
			hud.toast("%s is locked in a tied battle: it cannot be picked, and it fights that battle again this turn." % hud.hero_name(h))
		return
	# Preroll, your move: a click on your activated ball offers PASS under it (Marko 2026-11-06).
	if state.phase == GameState.PHASE_PREROLL and str(state.active.get(h.owner, "")) == id and hud.can_pass(h.owner) and _bodies.has(id):
		hud.offer_ball_pass(h.owner, cam.camera.unproject_position(_bodies[id].global_position) + Vector2(0, 34))
		return
	if h.is_on_map():
		cam.focus(arena.hex_center(h.hex), 14.0)


## Hover from the table or from a hero panel expands the panel and lights the ball and its range.
func _set_hover(id: String, refresh_hud: bool) -> void:
	if id == _hovered:
		return
	_hovered = id
	_update_ball_choice()
	if hud.is_targeting() or not hud.choice_heroes.is_empty() or not hud.damage_heroes.is_empty():
		_refresh_target_fx()
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


## The bots play both sides under the energy claim variant (a smoke run of the whole scene).
func demo_autoplay_energy() -> void:
	state.settings.stage_claim = MatchSettings.CLAIM_ENERGY
	state.settings.stage_goal = 14
	demo_autoplay()


## Presses CONFIRM in the energy split box (after demo_energy): the move goes through the engine.
func demo_energy_confirm() -> void:
	for c: Node in hud._dialog_box.get_children():
		if c is Button and (c as Button).theme_type_variation == &"Gold":
			(c as Button).pressed.emit()
			return
	push_error("no CONFIRM button in the energy box")


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


## Screenshot helper: every hero on the map and a heal asking player 1 for one of its heroes
## (two may take it: lit; the rest half see-through).
func demo_choose_hero() -> void:
	_demo = true
	var mid: Vector2i = arena.hex_at(Vector3.ZERO)
	var spots: Array[Vector2i] = [mid + Vector2i(-2, 1), mid + Vector2i(0, 2), mid + Vector2i(-3, -1),
		mid + Vector2i(2, -1), mid + Vector2i(1, -3), mid + Vector2i(3, 1)]
	for i: int in mini(spots.size(), state.heroes.size()):
		state.heroes[i].zone = HeroState.ZONE_MAP
		state.heroes[i].hex = spots[i]
	state.turn = 3
	state.phase = GameState.PHASE_PREROLL
	var mine := PackedStringArray()
	for h: HeroState in state.heroes:
		if h.owner == 0 and mine.size() < 2:
			mine.append(h.id)
	state.pending.append({"type": FxRuntime.DECISION_CHOOSE, "player": 0, "kind": "hero", "options": Array(mine),
		"prompt": "Choose a hero to heal", "resume": {"ctx": {}}})
	hud.local_slots = PackedInt32Array([0])
	_sync()
	cam.focus(arena.hex_center(mid), 13.0)


## Screenshot helper: a Reveal a Core asking player 1 for one of two cores on the field.
func demo_choose_core() -> void:
	demo_choose_hero()
	state.pending.clear()
	var ids: Array = []
	var mid: Vector2i = arena.hex_at(Vector3.ZERO)
	var spots: Array[Vector2i] = [mid + Vector2i(1, 0), mid + Vector2i(-1, -2)]
	for c: CoreState in state.cores:
		if ids.size() >= spots.size():
			break
		c.place = CoreState.ON_FIELD
		c.hex = spots[ids.size()]
		ids.append(c.id)
	state.pending.append({"type": FxRuntime.DECISION_CHOOSE, "player": 0, "kind": "core", "options": ids,
		"prompt": "Choose a core", "resume": {"ctx": {}}})
	_sync()


## Screenshot helper: a Discard asking player 1 for a card from a hand of five (three may go).
func demo_choose_card() -> void:
	demo_choose_hero()
	state.pending.clear()
	var p: PlayerState = state.player(0)
	while p.hand.size() < 5 and not p.deck.is_empty():
		p.hand.append(p.deck[0])
		p.deck.remove_at(0)
	state.pending.append({"type": FxRuntime.DECISION_CHOOSE, "player": 0, "kind": "card", "options": Array(p.hand.slice(0, 3)),
		"prompt": "Discard a card", "resume": {"ctx": {}}})
	_sync()


## Screenshot helper: every stage placed (first legal hex), player 1 about to place a core.
func demo_setup_cores() -> void:
	_demo = true
	var guard: int = 0
	while state.phase == GameState.PHASE_SETUP_STAGES and guard < 20:
		guard += 1
		var who: int = state.setup_turn
		var st: StageState = state.stage(MatchHud.setup_items(state, who)[0])
		for a: Vector2i in arena.map.cells():
			if engine.stage_placement_error(state, st, a).is_empty():
				engine.apply(state, Move.make(Move.PLACE_STAGE, who, {"stage": st.id, "hex": Hex.to_json(a)}))
				break
	# Player 1 places first in the core phase too.
	while state.phase == GameState.PHASE_SETUP_CORES and state.setup_turn != 0 and guard < 40:
		guard += 1
		var c: CoreState = state.core(MatchHud.setup_items(state, state.setup_turn)[0])
		for a: Vector2i in arena.map.cells():
			if engine.core_placement_error(state, c, a).is_empty():
				engine.apply(state, Move.make(Move.PLACE_CORE, state.setup_turn, {"core": c.id, "hex": Hex.to_json(a)}))
				break
	_sync()

## Screenshot helper: the stage and core boxes folded; not saved.
func demo_strip_off() -> void:
	demo_choose_hero()
	state.pending.clear()
	GameSettings.in_memory = true
	hud.toggle_stage_strips()
	_sync()

## Screenshot helper: the phase ribbon in a phase from the command line (--phase=preroll|roll|postroll|battle|end).
func demo_ribbon_shot() -> void:
	demo_choose_hero()
	state.pending.clear()
	var phase: String = GameState.PHASE_PREROLL
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.substr(8)
	state.phase = phase
	hud.refresh()

## Screenshot helper (playtest 2026-11-06): player 1's first hero is active with an evolution that has
## an ability of its own, so its panel shows two ability tabs.
func demo_evolved_tabs() -> void:
	demo_ribbon_shot()
	var h: HeroState = null
	for x: HeroState in state.heroes:
		if x.owner == 0:
			h = x
			break
	if h == null:
		return
	state.active[0] = h.id
	for c: CardDef in db.catalog.of_type("Evolution"):
		if c.effects.any(func(e: FxEffect) -> bool: return e.optional and e.cond != "WIN"):
			h.evolutions.append(c.id)
			break
	hud.refresh()


## Hits hero 0, knocks hero 1 three hexes away and knocks out hero 2.
func demo_fx_hit() -> void:
	_demo = true
	state.heroes[0].hp -= 3
	state.heroes[1].hex += Vector2i(3, 0)
	state.heroes[2].hp = 0
	state.heroes[2].zone = HeroState.ZONE_KO
	_sync()


## Screenshot helper (after demo_fx_place): the camera on the hero demo_fx_hit will KO, its
## ball open so the standee shows.
func demo_ko_focus() -> void:
	_demo = true
	var h: HeroState = state.heroes[2]
	if _views.has(h.id):
		_views[h.id].open()
	cam.focus(arena.hex_center(h.hex), 8.0)
	# At once, so a screenshot a few frames later is steady.
	cam._cur_target = cam.target
	cam._cur_distance = cam.distance
	cam._cur_pitch = cam.pitch


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
		cam.focus(arena.hex_center(field[0].hex), 3.5)


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
	state.pending = [{"type": RulesEngine.DECISION_DAMAGE, "player": 0, "amount": 5, "min_hero": 3,
		"winner": state.heroes_of(1)[0].id, "targets": mine}]
	# A hand to pick from, with one card already taking 1 DMG.
	var p: PlayerState = state.player(0)
	if p.hand.is_empty():
		p.hand = p.deck.slice(0, 5)
	# The hand only shows from turn 1; the Battle call-out band holds the dialog a few seconds.
	state.turn = maxi(state.turn, 1)
	state.phase = GameState.PHASE_BATTLE
	hud.local_slots = PackedInt32Array([0])
	hud.refresh()
	hud.pick_damage_hero(str(mine[0]))
	hud.toggle_damage_card(1)


## Screenshot helpers: the damage choice with one hero in reach; with three and none picked yet;
## and the second of two hits in a battle.
func demo_damage_one() -> void:
	demo_damage()
	state.pending[0]["targets"] = [state.heroes_of(0)[0].id]
	hud.refresh()


func demo_damage_none() -> void:
	demo_damage()
	hud.toggle_damage_card(1)
	hud.damage_target = ""
	hud.refresh()


func demo_damage_two_hits() -> void:
	demo_damage()
	state.pending.append(state.pending[0].duplicate(true))
	hud.refresh()


func demo_damage_second_hit() -> void:
	state.pending.pop_front()
	hud.refresh()


## Screenshot helpers (after demo_battle): a hand of seven with two energy, the cards it can pay
## standing higher; then the energy gone and one card played.
func demo_hand_stand() -> void:
	var p: PlayerState = state.player(0)
	p.hand = p.deck.slice(0, 7)
	# Two copies of one card: demo_hand_spent plays the left one.
	p.hand[4] = p.hand[0]
	p.energy = 2
	# The hand only shows from turn 1.
	state.turn = maxi(state.turn, 1)
	hud.refresh()


func demo_hand_spent() -> void:
	var p: PlayerState = state.player(0)
	p.hand = p.hand.slice(1)
	p.energy = 0
	hud.hand_leaving = 0
	hud.refresh()


## Screenshot helper: the ring-out's cost (1 DMG, or a card from the hand) asked of player 1.
func demo_ring_out_damage() -> void:
	_demo = true
	var h: HeroState = state.heroes_of(0)[0]
	state.pending = [{"type": RulesEngine.DECISION_DAMAGE, "player": 0, "winner": "", "by": "ring_out",
		"amount": RulesEngine.RING_OUT_DAMAGE, "targets": [h.id], "min_hero": 0, "ring_out": true}]
	var p: PlayerState = state.player(0)
	if p.hand.is_empty():
		p.hand = p.deck.slice(0, 5)
	state.turn = maxi(state.turn, 1)
	state.phase = GameState.PHASE_ROLL
	hud.local_slots = PackedInt32Array([0])
	hud.refresh()


## Screenshot helper: the energy claim variant: player 1's heroes on two open stages with energy
## in them, a third stage contested, and the End phase box splitting 6 energy.
func demo_energy() -> void:
	_demo = true
	state.settings.stage_claim = MatchSettings.CLAIM_ENERGY
	state.settings.stage_goal = 14
	var mine: Array[StageState] = []
	for st: StageState in state.stages:
		if st.owner == 0:
			mine.append(st)
	var spots: Array[Vector2i] = [Vector2i(7, 12), Vector2i(15, 12), Vector2i(11, 8)]
	for i: int in mini(3, mine.size()):
		mine[i].placed = true
		mine[i].revealed = true
		mine[i].center = Hex.offset_to_axial(spots[i].x, spots[i].y)
	mine[0].progress = {0: 6}
	mine[1].progress = {0: 9}
	mine[2].progress = {0: 4, 1: 7}
	var heroes: Array[HeroState] = state.heroes_of(0)
	for i: int in 3:
		heroes[i].zone = HeroState.ZONE_MAP
		heroes[i].hex = mine[i].center
	var enemy: HeroState = state.heroes_of(1)[0]
	enemy.zone = HeroState.ZONE_MAP
	enemy.hex = Hex.neighbor(mine[2].center, 0)
	state.turn = maxi(state.turn, 6)
	state.phase = GameState.PHASE_END
	state.pending = [{"type": RulesEngine.DECISION_STAGE_ENERGY, "player": 0, "energy": 6,
		"stages": [mine[0].id, mine[1].id], "goal": 14}]
	hud.local_slots = PackedInt32Array([0])
	_sync()
	hud.refresh()


## Screenshot helper: both stage boxes with energy in them (each side's, and both in some) and an
## assist box on each side (two on the left).
func demo_boards() -> void:
	_demo = true
	state.settings.stage_claim = MatchSettings.CLAIM_ENERGY
	state.settings.stage_goal = 14
	var spots: Array[Vector2i] = [Vector2i(7, 12), Vector2i(15, 12), Vector2i(11, 8), Vector2i(7, 10), Vector2i(15, 10), Vector2i(11, 14)]
	var progress: Array = [{0: 6}, {0: 9, 1: 3}, {0: 4, 1: 7}, {1: 11}, {0: 2, 1: 5}, {1: 4}]
	for i: int in mini(6, state.stages.size()):
		var st: StageState = state.stages[i]
		st.placed = true
		st.revealed = true
		st.center = Hex.offset_to_axial(spots[i].x, spots[i].y)
		st.progress.clear()
		var pd: Dictionary = progress[i]
		for k: Variant in pd:
			st.progress[JsonUtil.as_int(k)] = JsonUtil.as_int(pd[k])
	var assists: Array[CardDef] = engine.catalog.of_type("Assist")
	var two := PackedStringArray()
	for c: CardDef in assists:
		if two.size() < 2:
			two.append(c.id)
	state.player(0).assists = two
	if not assists.is_empty():
		state.player(1).assists = PackedStringArray([assists[assists.size() - 1].id])
	state.turn = maxi(state.turn, 6)
	state.phase = GameState.PHASE_PREROLL
	state.pending = []
	hud.local_slots = PackedInt32Array([0])
	_sync()
	hud.refresh()


## Screenshot helper: demo_boards with a tile in every state: claimed, energy just in, the other
## side's face down (a "?").
func demo_boards_states() -> void:
	demo_boards()
	state.stages[0].claimed_by = 0
	state.stages[5].revealed = false
	hud._energy_flash[state.stages[1].id] = {"until": Time.get_ticks_msec() + 60000, "start": Time.get_ticks_msec(), "amount": 3, "player": 0}
	hud.refresh()


## Screenshot helper: the deciding moment before the end screen, as in a match: the last hero
## down on the table, the camera on it, the band; the end screen (demo_defeat's) after END_HOLD_TIME
## (--frames about 120 shows the moment, 330 the screen).
func demo_end_moment() -> void:
	demo_defeat()
	var last: HeroState = state.heroes_of(0)[0]
	last.zone = HeroState.ZONE_MAP
	last.hex = Hex.offset_to_axial(11, 10)
	var other: HeroState = state.heroes_of(1)[0]
	other.zone = HeroState.ZONE_MAP
	other.hex = Hex.offset_to_axial(12, 10)
	_sync()
	last.zone = HeroState.ZONE_KO
	_end_moment()
	hud.refresh()


## Screenshot helper: the screen of a guest that dropped, as the host sees it, with the ping shown.
func demo_drop() -> void:
	demo_boards()
	hud.set_ping(42, true)
	hud.show_drop("Marin", true)


## Screenshot helper: the end screen as if player 1 won on stages (drawn only).
func demo_victory() -> void:
	_demo = true
	state.phase = GameState.PHASE_OVER
	state.winner = 0
	state.result = "stages"
	state.turn = 9
	var mine: Array[StageState] = []
	for st: StageState in state.stages:
		if st.owner == 0:
			mine.append(st)
	for i: int in mini(3, mine.size()):
		mine[i].placed = true
		mine[i].revealed = true
		mine[i].claimed_by = 0
	state.log.append({"turn": 9, "phase": "end", "type": "stage_claimed", "stage": mine[2].id if mine.size() > 2 else "", "player": 0, "energy": 14})
	hud.local_slots = PackedInt32Array([0])
	hud.end_summary = {"battles": 6, "players": [
		{"slot": 0, "name": state.player(0).name, "stages_claimed": 3, "kos_suffered": 1, "ring_outs_suffered": 0},
		{"slot": 1, "name": state.player(1).name, "stages_claimed": 1, "kos_suffered": 2, "ring_outs_suffered": 2}],
		"curve": [{"turn": 1, "hp": {0: 30, 1: 30}, "claimed": []}, {"turn": 2, "hp": {0: 30, 1: 27}, "claimed": []}, {"turn": 3, "hp": {0: 26, 1: 27}, "claimed": [0]},
			{"turn": 4, "hp": {0: 26, 1: 21}, "claimed": []}, {"turn": 5, "hp": {0: 22, 1: 21}, "claimed": [1]}, {"turn": 6, "hp": {0: 22, 1: 15}, "claimed": [0]},
			{"turn": 7, "hp": {0: 18, 1: 15}, "claimed": []}, {"turn": 8, "hp": {0: 18, 1: 9}, "claimed": []}, {"turn": 9, "hp": {0: 18, 1: 9}, "claimed": [0]}]}
	hud.refresh()


## Screenshot helper: the end screen as if player 1 lost with every hero KO.
func demo_defeat() -> void:
	_demo = true
	state.phase = GameState.PHASE_OVER
	state.winner = 1
	state.result = "ko"
	state.turn = 19
	for h: HeroState in state.heroes_of(0):
		h.hp = 0
		h.zone = HeroState.ZONE_KO
	var last: HeroState = state.heroes_of(0)[0]
	var hitter: HeroState = state.heroes_of(1)[0]
	state.log.append({"turn": 19, "phase": "battle", "type": "damage", "hero": last.id, "amount": 6, "hp": 0, "by": hitter.id})
	state.log.append({"turn": 19, "phase": "battle", "type": "ko", "hero": last.id})
	hud.local_slots = PackedInt32Array([0])
	hud.end_summary = {"battles": 11, "players": [
		{"slot": 0, "name": state.player(0).name, "stages_claimed": 1, "kos_suffered": 3, "ring_outs_suffered": 1},
		{"slot": 1, "name": state.player(1).name, "stages_claimed": 2, "kos_suffered": 1, "ring_outs_suffered": 0}],
		"curve": [{"turn": 1, "hp": {0: 30, 1: 30}, "claimed": []}, {"turn": 3, "hp": {0: 27, 1: 26}, "claimed": [1]}, {"turn": 5, "hp": {0: 21, 1: 26}, "claimed": []},
			{"turn": 7, "hp": {0: 15, 1: 22}, "claimed": [0]}, {"turn": 9, "hp": {0: 15, 1: 22}, "claimed": [1]}, {"turn": 11, "hp": {0: 9, 1: 22}, "claimed": []},
			{"turn": 13, "hp": {0: 9, 1: 22}, "claimed": []}, {"turn": 15, "hp": {0: 4, 1: 22}, "claimed": []}, {"turn": 19, "hp": {0: 0, 1: 22}, "claimed": []}]}
	hud.refresh()


## Screenshot helper: one of each banner, queued.
func demo_banners() -> void:
	_demo = true
	hud.banner("BATTLE!", Palette.ACCENT, "GIORNO\n3000", "SHANKS\n2500")
	hud.banner("RING-OUT", Palette.GOLD, "", "SHANKS")


## Screenshot helper: the pause menu with the combo list open.
func demo_combo_list() -> void:
	_demo = true
	_combo_all = true
	_toggle_menu()
	_show_combos(true)


## Screenshot helper: one band, named by `--banner=<name>` on the command line (see BUILD.md).
func demo_banner_shot() -> void:
	_demo = true
	var which: String = "battle"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--banner="):
			which = arg.substr(9)
	var win: Color = Palette.team(0).darkened(0.2)
	match which:
		"start", "preroll", "roll", "postroll", "battle_phase":
			hud.banner("%s PHASE" % which.trim_suffix("_phase").to_upper(), Palette.PANEL_SOLID, "TURN 3", "", 3.0)
		"battle":
			hud.banner("BATTLE!", Palette.ACCENT, "GIORNO + BUCCIARATI\n5000", "SHANKS\n4000", 3.0)
		"win":
			hud.banner("GIORNO WINS THE FIGHT!", win, "", "", 3.0)
		"win_team":
			hud.banner("GIORNO + BUCCIARATI WIN THE FIGHT!", win, "", "", 3.0)
		"damage":
			hud.banner("SHANKS TAKES 3 DAMAGE", Palette.ACCENT_DEEP, "", "HP 4", 3.0)
		"deck":
			hud.banner("MARKO DECKS 2!", Palette.ACCENT_DEEP, "", "17 LEFT IN THE DECK", 3.0)
		"ringout":
			hud.banner("RING-OUT", Palette.GOLD, "", "SHANKS", 3.0)
		"ko":
			hud.banner("KO", Palette.ACCENT_DEEP, "", "SHANKS", 3.0)
		"equip":
			var eq: Array[CardDef] = engine.catalog.of_type("Equipment")
			hud._announce_card({"type": "equipped", "card": eq[0].id if not eq.is_empty() else "", "hero": state.heroes_of(1)[0].id})
		"assist":
			var asl: Array[CardDef] = engine.catalog.of_type("Assist")
			hud._announce_card({"type": "assist", "card": asl[0].id if not asl.is_empty() else "", "player": 1})
		"combo":
			var combos: Array[CardDef] = engine.catalog.of_type("Combo")
			var cid: String = combos[0].id if not combos.is_empty() else ""
			hud.banner("COMBO!", Palette.GOLD, "MARKO", hud._card_name(cid).to_upper(), 3.0, cid)
		"stage":
			hud.banner("STAGE CLAIMED", Palette.GOLD, "MARKO", "DRESSROSA", 3.0)
		"triggered":
			hud.banner("GOLD EXPERIENCE", Palette.GOLD, "GIORNO", "", 3.0)
		"tie":
			hud.banner("TIE!", Palette.GOLD, "GIORNO VS SHANKS", "SAME POWER · FIGHT AGAIN NEXT TURN", 3.0)
		"tie_again":
			hud.banner("TIE AGAIN!", Palette.ACCENT, "GIORNO VS SHANKS", "BOTH KNOCKED BACK", 3.0)
		"merged_many":
			hud._grouping = true
			hud.banner("LUFFY TAKES 1 DAMAGE", Palette.ACCENT_DEEP, "", "HP 7", 1.6)
			hud.banner("GOLD EXPERIENCE", Palette.GOLD, "GIORNO", "")
			hud.banner("KO", Palette.ACCENT_DEEP, "", "SHANKS")
			hud.banner("SHANKS TAKES 2 DAMAGE", Palette.ACCENT_DEEP, "", "HP 0", 1.6)
			hud.banner("STAGE CLAIMED", Palette.GOLD, "MARKO", "ALABASTA")
			hud._grouping = false
			hud._push_group()
		_:
			demo_merged_banner()


## Screenshot helper: the bands of one moment merged into one (the winner, the blow, the KO, the claim).
func demo_merged_banner() -> void:
	_demo = true
	hud._grouping = true
	hud.banner("SHANKS TAKES 3 DAMAGE", Palette.ACCENT_DEEP, "", "HP 0", 1.6)
	hud.banner("GIORNO WINS THE FIGHT!", Palette.team(0).darkened(0.2), "", "", 2.0)
	hud.banner("KO", Palette.ACCENT_DEEP, "", "SHANKS")
	hud.banner("STAGE CLAIMED", Palette.GOLD, "MARKO", "DRESSROSA")
	hud._grouping = false
	hud._push_group()


## Screenshot helper: player 1's first hand card shown big.
func demo_big_card() -> void:
	var p: PlayerState = state.player(0)
	if not p.hand.is_empty():
		hud._show_big(p.hand[0])


## Screenshot helper: lasting effects on player 1's first hero (bonus for the phase, a status).
func demo_effects() -> void:
	_demo = true
	var h: HeroState = state.heroes[0]
	h.phase_bonus["pwr"] = 2000
	h.turn_bonus["kb"] = -1
	h.statuses["stun"] = 1
	_sync()


# --- choosing a hero for a card (mockup HUD 2) -------------------------------------------

## A beam of light and a ring on every hero the card being targeted can go on; the one under
## the mouse gets a wider, brighter beam and a second ring.
func _refresh_target_fx() -> void:
	for c: Node in _target_fx.get_children():
		if not c.has_meta("flash"):
			c.queue_free()
	for hid: String in hud.target_heroes:
		if _bodies.has(hid):
			_target_fx.add_child(_target_mark(_bodies[hid].global_position, hid == _hovered))
	# A card effect's hero choice: the same beams, and the heroes it cannot take half see-through.
	for hid: String in hud.choice_heroes + hud.damage_heroes:
		if _bodies.has(hid):
			_target_fx.add_child(_target_mark(_bodies[hid].global_position, hid == _hovered))
	# A core on the field asked for: a beam on its hex.
	for cid: String in hud.choice_cores:
		var c: CoreState = state.core(cid)
		if c != null:
			_target_fx.add_child(_target_mark(arena.hex_center(c.hex), false))
	for hid: String in _views:
		_views[hid].set_faded(not hud.choice_heroes.is_empty() and not hud.choice_heroes.has(hid))
		# A tied, locked hero cannot be picked: its ball goes dull (Marko 2026-11-02).
		var locked: HeroState = state.hero(hid)
		_views[hid].set_dimmed(locked != null and locked.tie_turns > 0 and locked.is_on_map())
	# The same light on the hero chosen in Select, and on the ball a local player has to throw.
	var lit := PackedStringArray()
	for slot: Variant in hud.picks:
		lit.append(str(hud.picks[slot]))
	if state.phase == GameState.PHASE_ROLL and not state.awaiting_roll and not _runner.is_running() and not _sling.is_aiming():
		for slot: int in hud.local_slots:
			var a: HeroState = state.active_hero(slot)
			if a != null and state.choices.get(slot, false) and not state.aims.has(slot):
				lit.append(a.id)
	for hid: String in lit:
		if _bodies.has(hid) and not hud.target_heroes.has(hid):
			_target_fx.add_child(_target_mark(_bodies[hid].global_position, true))
	# Start, nothing picked yet: every hero that can be activated pulses, so it is clear a hero
	# has to be picked and which (playtest 2026-10-30); locked or stunned ones stay dark.
	if state.phase == GameState.PHASE_START and _replay == null:
		for slot: int in hud.local_slots:
			if state.active.has(slot) or hud.picks.has(slot):
				continue
			for h: HeroState in engine.selectable_heroes(state, slot):
				if not _bodies.has(h.id) or lit.has(h.id):
					continue
				var mark: Node3D = _target_mark(_bodies[h.id].global_position, false)
				_target_fx.add_child(mark)
				var pulse: Tween = mark.create_tween().set_loops()
				pulse.tween_property(mark, "scale", Vector3(1.25, 1.0, 1.25), 0.45).set_trans(Tween.TRANS_SINE)
				pulse.tween_property(mark, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_SINE)


## Shows briefly on the hero a card just went on.
func _flash_target(hid: String, hold: float = 0.35) -> void:
	if not _bodies.has(hid):
		return
	var mark: Node3D = _target_mark(_bodies[hid].global_position, true)
	mark.set_meta("flash", true)
	_target_fx.add_child(mark)
	var t: Tween = mark.create_tween()
	t.tween_interval(hold)
	t.tween_property(mark, "scale", Vector3(1.4, 0.2, 1.4), 0.25)
	t.tween_callback(mark.queue_free)


func _target_mark(at: Vector3, chosen: bool) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(at.x, 0.0, at.z)
	var gold: Color = Color("ffd36a") if chosen else Palette.GOLD
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55 if chosen else 0.38
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 6.0 if chosen else 4.5
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.position.y = cyl.height * 0.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(gold, 0.0))
	grad.gradient.set_color(1, Color(gold, 0.85 if chosen else 0.55))
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	grad.width = 4
	grad.height = 64
	bm.albedo_texture = grad
	beam.material_override = bm
	# The beam can be switched off (Settings, key B); the rings always show.
	if GameSettings.beams():
		root.add_child(beam)
	else:
		beam.queue_free()
	for r: float in ([1.0, 0.7] if chosen else [0.85]):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = r
		torus.outer_radius = r + (0.12 if chosen else 0.09)
		ring.mesh = torus
		ring.scale = Vector3(1, 0.15, 1)
		ring.position.y = 0.04
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.material_override = MeshKit.unshaded(gold, false)
		root.add_child(ring)
	# The rings breathe.
	var t: Tween = root.create_tween().set_loops()
	t.tween_property(root, "scale", Vector3.ONE * 1.08, 0.6).set_trans(Tween.TRANS_SINE)
	t.tween_property(root, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	return root


## Screenshot helper: starts choosing a hero for the first card that can go on two, or puts
## two of player 1's heroes in a battle-like spot so one can (a throwaway match).
func demo_targeting() -> void:
	_demo = true
	var p: PlayerState = state.player(0)
	if p.hand.is_empty() or state.heroes.size() < 2:
		return
	var a: HeroState = state.active_hero(0)
	var mine: Array[String] = []
	for h: HeroState in state.heroes:
		if h.owner == 0:
			mine.append(h.id)
	hud.target_slot = 0
	hud.target_cid = p.hand[0]
	hud.target_heroes = PackedStringArray(mine.slice(0, 2))
	hud.hover_hero = mine[0]
	_hovered = mine[0]
	hud.targeting_changed.emit()
	hud.refresh()
	if a != null and _bodies.has(a.id):
		cam.focus(_bodies[a.id].global_position, 16.0)


## Screenshot helper: as demo_targeting with two copies of the card side by side; the left
## one is being played (only it may lift, the aim line comes from it).
func demo_targeting_dupe() -> void:
	var p: PlayerState = state.player(0)
	if p.hand.size() < 3:
		return
	p.hand[2] = p.hand[0]
	demo_targeting()
	hud.target_index = 0
	hud.refresh()


# --- battles on the table (mockup HUD 4) -------------------------------------------------

## A red ring that breathes under each hero of the battle being fought.
func _refresh_battle_fx() -> void:
	# Only heroes still on the map: a KO or a ring-out mid-battle takes its ring away at once
	# (playtest 2026-11-06: the ring kept breathing where the ball had burst).
	var ids := PackedStringArray()
	for hid: String in _current_battle():
		var on: HeroState = state.hero(hid)
		if on != null and on.is_on_map():
			ids.append(hid)
	var key: String = "%d:%s" % [state.battle_index, ",".join(ids)]
	if key == _battle_fx_key:
		return
	_battle_fx_key = key
	for c: Node in _battle_fx.get_children():
		c.queue_free()
	for hid: String in ids:
		var h: HeroState = state.hero(hid)
		if h == null or not h.is_on_map() or not _bodies.has(hid):
			continue
		var root := Node3D.new()
		root.position = arena.hex_center(h.hex)
		var r: float = _bodies[hid].radius() + 0.35
		for k: int in 2:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = r + k * 0.22
			torus.outer_radius = torus.inner_radius + (0.13 if k == 0 else 0.05)
			ring.mesh = torus
			ring.scale = Vector3(1, 0.15, 1)
			ring.position.y = 0.05
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.material_override = MeshKit.unshaded(Color(Palette.ACCENT, 1.0 if k == 0 else 0.6), false)
			root.add_child(ring)
		_battle_fx.add_child(root)
		var t: Tween = root.create_tween().set_loops()
		t.tween_property(root, "scale", Vector3.ONE * 1.1, 0.55).set_trans(Tween.TRANS_SINE)
		t.tween_property(root, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_SINE)


## Screenshot helper (a throwaway match): player 1's first hero and the opponent's first stand
## close, and the battle phase fights them, with a second battle waiting.
func demo_battle() -> void:
	_demo = true
	var mine: Array[HeroState] = []
	var theirs: Array[HeroState] = []
	for h: HeroState in state.heroes:
		(mine if h.owner == 0 else theirs).append(h)
	var mid: Vector2i = arena.hex_at(Vector3.ZERO)
	mine[0].zone = HeroState.ZONE_MAP
	mine[0].hex = mid
	theirs[0].zone = HeroState.ZONE_MAP
	theirs[0].hex = mid + Vector2i(2, -1)
	mine[1].zone = HeroState.ZONE_MAP
	mine[1].hex = mid + Vector2i(-4, 3)
	theirs[1].zone = HeroState.ZONE_MAP
	theirs[1].hex = mid + Vector2i(-3, 4)
	state.phase = GameState.PHASE_BATTLE
	state.battles = [{"heroes": [mine[0].id, theirs[0].id], "resolved": false, "winner_team": -1, "tie": false},
		{"heroes": [mine[1].id, theirs[1].id], "resolved": false, "winner_team": -1, "tie": false}]
	state.battle_index = 0
	# Not "": an empty highlight must still clear the last one (the setup zones stayed lit).
	_range_key = "-"
	_sync()



## Screenshot helper (after demo_battle): the side of `team` gets `power` in all for this phase,
## as a card would give it, so the tug at the top moves.
func demo_tug(team: int, power: int) -> void:
	var ids: Array[HeroState] = []
	for id: String in JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", [])):
		var h: HeroState = state.hero(id)
		if h != null and state.team_of(h.owner) == team:
			ids.append(h)
			h.phase_bonus.clear()
	var now: int = 0
	for h: HeroState in ids:
		now += engine.stat(state, h, "pwr")
	ids[0].phase_bonus["pwr"] = power - now
	hud.refresh()


## Screenshot helper (after demo_battle): the ability tabs of both battle heroes open, the bar between them.
func demo_tug_tabs() -> void:
	for slot: int in 2:
		for id: String in JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", [])):
			var h: HeroState = state.hero(id)
			if h != null and h.owner == slot:
				state.active[slot] = h.id
				for c: CardDef in db.catalog.of_type("Evolution"):
					if h.evolutions.is_empty() and c.effects.any(func(e: FxEffect) -> bool: return e.optional and e.cond != "WIN"):
						h.evolutions.append(c.id)
				break
	hud.refresh()


func demo_tug_blue() -> void:
	demo_tug(0, 6000)
	demo_tug(1, 3000)


func demo_tug_red() -> void:
	demo_tug(0, 3000)
	demo_tug(1, 6000)


func demo_tug_near() -> void:
	demo_tug(0, 5000)
	demo_tug(1, 4000)


func demo_tug_level() -> void:
	demo_tug(0, 4000)
	demo_tug(1, 4000)


## Screenshot helper (playtest 2026-11-06): demo_battle, then the opponent's hero in the first battle
## is knocked out; its battle ring must go with its ball.
func demo_battle_ko() -> void:
	demo_battle()
	var h: HeroState = state.hero(JsonUtil.as_strings(state.battles[0].get("heroes", []))[1])
	h.hp = 0
	h.zone = HeroState.ZONE_KO
	_sync()

# --- battle camera (mockup HUD 5) ---------------------------------------------------------

## As each battle starts the camera flies to it (Settings → Display); when the battles are
## over it goes back to the table.
func _update_battle_cam() -> void:
	var ids: PackedStringArray = _current_battle()
	if ids.is_empty():
		if not _cam_battle_key.is_empty():
			_cam_battle_key = ""
			if hud.battle_cam:
				# Stay on the last battle a moment, so its end can be seen, then back to the table.
				_leave_cam_later()
		return
	var key: String = "%d:%d:%s" % [state.turn, state.battle_index, ",".join(ids)]
	if key == _cam_battle_key:
		return
	var from_another: bool = not _cam_battle_key.is_empty()
	_cam_battle_key = key
	if GameSettings.battle_cam_auto() and _replay == null:
		# From one battle to the next: a moment on the one just fought first.
		if from_another and hud.battle_cam:
			await get_tree().create_timer(1.2).timeout
			if key != _cam_battle_key:
				return
		_frame_battle(ids)
		hud.refresh()


## The camera on the battle's heroes, close enough that both fill the middle.
func _frame_battle(ids: PackedStringArray) -> void:
	var points: Array[Vector3] = []
	for hid: String in ids:
		if _bodies.has(hid):
			points.append(_bodies[hid].global_position)
	if points.is_empty():
		return
	var mid := Vector3.ZERO
	for p: Vector3 in points:
		mid += p
	mid /= points.size()
	var spread: float = 0.0
	for p: Vector3 in points:
		spread = maxf(spread, Vector2(p.x - mid.x, p.z - mid.z).length())
	# Low and close, from the side of the line between the fighters, so they stand next to
	# each other and fill the screen (Marko 2026-10-26). The view turns at most 65 degrees
	# away from the player's side of the table.
	cam.pitch = deg_to_rad(BATTLE_CAM_PITCH)
	if points.size() >= 2:
		var d := Vector2(points[1].x - points[0].x, points[1].z - points[0].z)
		if d.length() > 0.01:
			var n := Vector2(d.y, -d.x).normalized()
			if n.y < 0.0:
				n = -n
			cam.yaw = clampf(atan2(n.x, n.y), deg_to_rad(-65.0), deg_to_rad(65.0))
	cam.focus(mid, clampf(spread * 2.0 + 10.0, 12.0, 26.0))
	# Aim at the figures' middle, not their feet, so heads stay in the frame.
	cam.target.y = 1.0
	hud.battle_cam = true


## Key or switch: into the battle camera, or out to the table.
func _toggle_battle_cam() -> void:
	var ids: PackedStringArray = _current_battle()
	if hud.battle_cam or ids.is_empty():
		_leave_battle_cam()
		return
	_frame_battle(ids)
	hud.refresh()


func _leave_battle_cam() -> void:
	if not hud.battle_cam:
		return
	hud.battle_cam = false
	cam.reset_view()
	hud.refresh()


## Screenshot helper: the pause menu open.
func demo_pause() -> void:
	_demo = true
	_toggle_menu()


## Screenshot helper (a throwaway match): back to Select with player 1's second hero chosen.
func demo_pick() -> void:
	_demo = true
	state.phase = GameState.PHASE_START
	state.active.erase(0)
	var mine: Array[HeroState] = state.heroes_of(0)
	hud.picks[0] = mine[1].id
	_sync()


## Screenshot helper: every stage turned face up.
func demo_reveal() -> void:
	_demo = true
	for st: StageState in state.stages:
		st.revealed = true
	_sync()


## Back to the table after BATTLE_CAM_HOLD seconds, unless a battle has started again by then.
func _leave_cam_later() -> void:
	var t: SceneTreeTimer = get_tree().create_timer(BATTLE_CAM_HOLD * GameSettings.anim_scale())
	await t.timeout
	if _current_battle().is_empty() and hud.battle_cam:
		hud.battle_cam = false
		cam.reset_view()
		hud.refresh()


## A battle was decided: once the banner has had its moment, the winners light up.
func _on_battle_resolved(index: int, winner_team: int) -> void:
	if winner_team < 0 or index < 0 or index >= state.battles.size():
		return
	var ids: PackedStringArray = JsonUtil.as_strings(state.battles[index].get("heroes", []))
	await get_tree().create_timer(0.5 * GameSettings.anim_scale()).timeout
	# The blow: every loser a winner reaches takes the strongest winner's colour burst.
	var strongest: HeroState = null
	for hid: String in ids:
		var w: HeroState = state.hero(hid)
		if w != null and state.team_of(w.owner) == winner_team and _views.has(w.id) \
				and (strongest == null or engine.stat(state, w, "pwr") > engine.stat(state, strongest, "pwr")):
			strongest = w
	if strongest != null:
		for hid: String in ids:
			var l: HeroState = state.hero(hid)
			if l != null and state.team_of(l.owner) != winner_team and _views.has(l.id) and not l.is_ko():
				_views[l.id].struck_by(_views[strongest.id])
		# The blow, for the menu's idle preview of this match.
		get_tree().create_timer(0.25).timeout.connect(_highlight_shot)
	for hid: String in ids:
		var h: HeroState = state.hero(hid)
		if h != null and state.team_of(h.owner) == winner_team:
			_flash_target(hid, 1.1)


## Screenshot helper: the move timer at three seconds, so the clock and the safe moves show.
func demo_timer() -> void:
	state.settings.timer_seconds = 3


## Screenshot helper: every knockback goes through the physics, and the bots play both sides.
func demo_physics_kb() -> void:
	state.settings.knockback = "physics"
	demo_autoplay()


## Screenshot helper: player 1's first hero stands mid-map and takes a physics knockback of
## three hexes towards the far edge, so the hit, the bounce and the landing show.
func demo_kb_hit() -> void:
	_demo = true
	state.settings.knockback = "physics"
	var h: HeroState = state.heroes_of(0)[0]
	h.zone = HeroState.ZONE_MAP
	h.hex = Hex.offset_to_axial(11, 14)
	var other: HeroState = state.heroes_of(1)[0]
	other.zone = HeroState.ZONE_MAP
	other.hex = Hex.offset_to_axial(11, 11)
	_sync()
	engine.knockback(state, h, Hex.direction_towards(other.hex, h.hex) + 3, 3)
	_sync()


## A hero's ability goes off: its colour bursts on the ball and a wave runs out to its range
## (Purple: a toxic fog over it, Purple Haze; Marko 2026-11-02).
func _ability_fx(hero_id: String, _card_id: String) -> void:
	if _quiet or not _views.has(hero_id):
		return
	var h: HeroState = state.hero(hero_id)
	if h == null or not h.is_on_map():
		return
	var v: BallView = _views[hero_id]
	ColorFx.burst(v, v._style, v._hero_color, v.radius)
	var step: float = arena.hex_center(Hex.neighbor(h.hex, 0)).distance_to(arena.hex_center(h.hex))
	var reach: float = step * (float(engine.stat(state, h, "rng")) + 0.5)
	AbilityFx.play(arena, arena.hex_center(h.hex), reach, v._hero_color, v._style)


## Screenshot helper: the first hero of player 1 on the table, its ability going off.
func demo_ability_fx() -> void:
	demo_fx_place()
	var h: HeroState = state.heroes[0]
	_ability_fx(h.id, h.card_id)


## Screenshot helper: the End phase of demo_energy with one open stage under player 1's heroes:
## the energy goes in by itself and the HUD says so.
func demo_energy_auto() -> void:
	demo_energy()
	state.pending = []
	state.heroes_of(0)[1].zone = HeroState.ZONE_STRIP
	state.player(0).energy = 3
	state.energy_banked = false
	_sync()
	hud.refresh()
	engine._bank_energy(state)
	_sync()
	hud.refresh()


## Screenshot helper (after demo_dice): player 1 throws its dice.
func demo_dice_throw() -> void:
	for n: Node in hud.get_parent().get_children():
		if n is InitiativeDice:
			(n as InitiativeDice)._throw(0)


## Screenshot helper: the dice that pick who starts (a real match shows them on its own).
func demo_dice() -> void:
	_show_initiative()


## Screenshot helper: a physics knockback straight into a wall two hexes away.
func demo_kb_wall() -> void:
	_demo = true
	state.settings.knockback = "physics"
	var h: HeroState = state.heroes_of(0)[0]
	h.zone = HeroState.ZONE_MAP
	h.hex = Hex.offset_to_axial(11, 14)
	var w := WallState.new()
	w.id = "wall:demo"
	var at: Vector2i = h.hex
	for _i: int in 2:
		at = Hex.neighbor(at, 5)
	w.hexes.append(at)
	state.walls.append(w)
	_sync()
	engine.knockback(state, h, 5, 4)
	_sync()


## A local game of a Best of 3: started from the setup as part of the series (a continued or
## replayed match is not, even while a series is open).
func _local_series() -> bool:
	return net_role == "" and MatchSeries.current != null and JsonUtil.as_bool(_config.get("series", false))


## Starts the hold when a new phase (or turn) begins; dev and demo matches do not wait.
func _run_phase_hold(delta: float) -> void:
	var key: String = "%d|%s" % [state.turn, state.phase]
	if key != _held_phase:
		_held_phase = key
		_phase_hold = 0.0 if _demo or state.turn == 0 else PHASE_HOLD
	elif _phase_hold > 0.0:
		_phase_hold = maxf(0.0, _phase_hold - delta)


## Filled hexes (a claimed stage in its owner's colour), on the marks layer.
func _fill(cells: Array[Vector2i], color: Color) -> void:
	_marks.surface_set_color(color)
	for a: Vector2i in cells:
		var c2: Vector2 = arena.map.to_world(a)
		for i: int in 6:
			var p0: Vector2 = c2 + Hex.corner(i - 1, tuning.hex_size) * 0.97
			var p1: Vector2 = c2 + Hex.corner(i, tuning.hex_size) * 0.97
			_marks.surface_add_vertex(Vector3(c2.x, 0.03, c2.y))
			_marks.surface_add_vertex(Vector3(p0.x, 0.03, p0.y))
			_marks.surface_add_vertex(Vector3(p1.x, 0.03, p1.y))


## A stage the activated hero chose Stay on (GDD 6: a second Stay in a row claims it) gets a
## thick outline in that player's colour that pulses, so standing there and trying to claim
## read differently.
func _draw_claim_marks() -> void:
	_claim_marks.clear_surfaces()
	_claim_marks.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var any: bool = false
	for st: StageState in state.stages:
		if not st.placed or st.is_claimed() or st.stay_hero.is_empty():
			continue
		var h: HeroState = state.hero(st.stay_hero)
		if h == null or h.is_ko() or not h.is_on_map() or not st.covers(h.hex):
			continue
		any = _outline(st.footprint(), Palette.team(state.team_of(h.owner)), false, _claim_marks, 0.2) or any
	if not any:
		_claim_marks.surface_add_vertex(Vector3.ZERO)
		_claim_marks.surface_add_vertex(Vector3.ZERO)
		_claim_marks.surface_add_vertex(Vector3.ZERO)
	_claim_marks.surface_end()


## Screenshot helper: one stage claimed by player 1 (filled, with a banner) and one that player
## 1's hero is trying to claim (pulsing outline).
func demo_claims() -> void:
	_demo = true
	var mine: Array[StageState] = []
	for st: StageState in state.stages:
		if st.owner == 0:
			mine.append(st)
	mine[0].placed = true
	mine[0].revealed = true
	mine[0].center = Hex.offset_to_axial(8, 11)
	mine[0].claimed_by = 0
	mine[1].placed = true
	mine[1].revealed = true
	mine[1].center = Hex.offset_to_axial(14, 11)
	var h: HeroState = state.heroes_of(0)[0]
	h.zone = HeroState.ZONE_MAP
	h.hex = mine[1].center
	mine[1].stay_hero = h.id
	mine[1].stay_turn = state.turn
	_sync()


## Screenshot helper: four stages face up, one of each terrain (Ice, Ramp, Wind, Mud).
func demo_terrain() -> void:
	_demo = true
	var ids: Array[String] = ["Stage-001", "Stage-002", "Stage-003", "Stage-004"]
	var spots: Array[Vector2i] = [Vector2i(6, 9), Vector2i(11, 8), Vector2i(16, 9), Vector2i(11, 13)]
	for i: int in mini(4, state.stages.size()):
		var st: StageState = state.stages[i]
		st.card_id = ids[i]
		st.placed = true
		st.revealed = true
		st.wind_dir = 1
		st.center = Hex.offset_to_axial(spots[i].x, spots[i].y)
	_sync()
	cam.pitch = deg_to_rad(40.0)
	cam.focus(arena.hex_center(Hex.offset_to_axial(11, 10)), 22.0)


## Start: Roll / Stay under a ball of yours that can be picked: the hovered one, else the one
## picked (they stay there once chosen, Marko 2026-10-26). While the mouse is on the buttons
## they keep their ball.
func _update_ball_choice() -> void:
	if state == null or state.phase != GameState.PHASE_START:
		hud.hide_ball_choice(true)
		return
	if hud.ball_choice_has_mouse():
		# The mouse is on the buttons: they stay with their ball when the camera moves (WASD),
		# they no longer stay under the mouse (Marko 2026-11-01).
		var on: String = hud.ball_choice_hero()
		if _bodies.has(on):
			hud.show_ball_choice(on, cam.camera.unproject_position(_bodies[on].global_position) + Vector2(0, 34))
		return
	var id: String = _hovered if _choice_ok(_hovered) else ""
	if id.is_empty():
		for slot: int in hud.local_slots:
			var picked: String = str(hud.picks.get(slot, ""))
			if _choice_ok(picked):
				id = picked
	if id.is_empty():
		hud.hide_ball_choice()
		# Still showing (the mouse near it, or its grace): it keeps its ball all the same, so a
		# camera move (W / S) cannot leave it hanging where the ball was (Marko 2026-11-02).
		var shown: String = hud.ball_choice_hero()
		if _bodies.has(shown):
			hud.move_ball_choice(cam.camera.unproject_position(_bodies[shown].global_position) + Vector2(0, 34))
		return
	hud.show_ball_choice(id, cam.camera.unproject_position(_bodies[id].global_position) + Vector2(0, 34))


## A local hero that may be picked in Start now (its owner has not confirmed yet).
func _choice_ok(id: String) -> bool:
	if id.is_empty() or not _bodies.has(id):
		return false
	var h: HeroState = state.hero(id)
	if h == null or not hud.local_slots.has(h.owner) or state.active.has(h.owner):
		return false
	for x: HeroState in engine.selectable_heroes(state, h.owner):
		if x.id == h.id:
			return true
	return false


## Screenshot helper: Start, one hero picked, the mouse over another of your balls.
func demo_start_hover() -> void:
	demo_pick()
	var mine: Array[HeroState] = state.heroes_of(0)
	_set_hover(mine[2].id, true)


## Screenshot helper: the mouse on a hero panel (the middle one of player 1) during a turn.
func demo_panel_hover() -> void:
	demo_boards()
	var mine: Array[HeroState] = state.heroes_of(0)
	for i: int in mine.size():
		mine[i].zone = HeroState.ZONE_MAP
		mine[i].hex = Hex.offset_to_axial(7 + i * 4, 15)
	_sync()
	_set_hover(mine[1].id, true)


## Screenshot helper: as demo_start_hover, then the camera pans back (as keys W / S do): the
## Roll / Stay must stay under the ball.
func demo_start_hover_pan() -> void:
	demo_start_hover()
	cam._pan(Vector2(0, 8.0))


## Screenshot helper: the first stage (or core) to place is picked in the tray.
func demo_setup_picked() -> void:
	_demo = true
	var items: PackedStringArray = MatchHud.setup_items(state, state.setup_turn)
	if not items.is_empty():
		hud.setup_pick = items[0]
	hud.refresh()


## Screenshot helper: player 1's first hero carries two equipment cards.
func demo_equip() -> void:
	_demo = true
	var h: HeroState = state.heroes_of(0)[0]
	for c: CardDef in engine.catalog.of_type("Equipment"):
		if h.equipment.size() < 2:
			h.equipment.append(c.id)
	hud.hover_hero = h.id
	_sync()


## Screenshot helper: Stay claims, player 1's first hero stayed on its stage last turn.
func demo_stay_pending() -> void:
	demo_energy()
	state.settings.stage_claim = MatchSettings.CLAIM_STAY
	state.pending = []
	for st: StageState in state.stages:
		st.progress = {}
	var h: HeroState = state.heroes_of(0)[0]
	var st0: StageState = state.stage_at(h.hex)
	st0.stay_hero = h.id
	st0.stay_turn = state.turn - 1
	state.phase = GameState.PHASE_START
	_sync()
	hud.refresh()


## Screenshot helper: as demo_equip with three equipment cards on two heroes, no panel open.
func demo_equip_rest() -> void:
	_demo = true
	for h: HeroState in state.heroes_of(0).slice(0, 2):
		for c: CardDef in engine.catalog.of_type("Equipment"):
			if h.equipment.size() < 3:
				h.equipment.append(c.id)
	_sync()


## Screenshot helper: a hero evolves on the table (aura, EVO on its panel) and an evolution card
## waits upright in the hand of a Preroll card round.
func demo_evolved() -> void:
	_demo = true
	state.turn = maxi(state.turn, 3)
	state.phase = GameState.PHASE_PREROLL
	state.to_act = 0
	for evo: CardDef in engine.catalog.of_type("Evolution"):
		for h: HeroState in state.heroes_of(0):
			var base: CardDef = engine.catalog.get_card(h.card_id)
			if base == null or base.name != evo.hero:
				continue
			h.zone = HeroState.ZONE_MAP
			h.hex = Hex.offset_to_axial(state.settings.map_size / 2, state.settings.map_size / 2 + 3)
			_sync()
			h.evolutions.append(evo.id)
			state.player(0).hand.append(evo.id)
			cam.focus(arena.hex_center(h.hex), 14.0)
			_sync()
			return


## Screenshot helper: a Preroll card round with a hand, a graveyard and the deck piles.
func demo_piles() -> void:
	_demo = true
	state.phase = GameState.PHASE_PREROLL
	state.to_act = 0
	var p: PlayerState = state.player(0)
	while p.hand.size() < 7 and not p.deck.is_empty():
		p.hand.append(p.deck[0])
		p.deck.remove_at(0)
	for i: int in 3:
		p.graveyard.append(p.deck[0])
		p.deck.remove_at(0)
	# An evolution on top: landscape cards stand upright on the pile and in the window.
	var evos: Array[CardDef] = engine.catalog.of_type("Evolution")
	if not evos.is_empty():
		p.graveyard.append(evos[0].id)
	hud.local_slots = PackedInt32Array([0])
	_sync()


## Screenshot helper: the starting hand being dealt (Mulligan) right now.
func demo_deal() -> void:
	_demo = true
	state.phase = GameState.PHASE_MULLIGAN
	var p: PlayerState = state.player(0)
	while p.hand.size() < 5 and not p.deck.is_empty():
		p.hand.append(p.deck[0])
		p.deck.remove_at(0)
	p.mulligan_done = false
	hud.local_slots = PackedInt32Array([0])
	bots.erase(0)
	_sync()


## Screenshot helper: player 1's graveyard opened.
func demo_grave() -> void:
	demo_piles()
	hud.open_graveyard(0)


## Screenshot helper: the call-out of a tied battle.
func demo_tie() -> void:
	_demo = true
	var a: HeroState = state.heroes_of(0)[0]
	var b: HeroState = state.heroes_of(1)[0]
	state.event("battle_locked", {"heroes": [a.id, b.id], "turns": 1})
	_sync()


## Heroes locked in a tied battle (GDD 10): a thick dashed red link between them, the whole
## turn, so it is clear they are tied up and will fight again.
func _lock_links() -> bool:
	var drew: bool = false
	for a: HeroState in state.heroes:
		if a.tie_turns <= 0 or not a.is_on_map() or not _bodies.has(a.id):
			continue
		for lid: String in a.locked_with:
			var b: HeroState = state.hero(lid)
			# Each pair once.
			if b == null or not b.is_on_map() or b.id < a.id or not _bodies.has(b.id):
				continue
			var from: Vector3 = arena.hex_center(a.hex) + Vector3(0, 0.07, 0)
			var to: Vector3 = arena.hex_center(b.hex) + Vector3(0, 0.07, 0)
			# Shackles (Marko 2026-11-02): a ring on the ground round each ball, the chain between.
			for h: HeroState in [a, b]:
				_ground_ring(arena.hex_center(h.hex), _bodies[h.id].radius() * 1.35, 0.12, Palette.GOLD)
			var n: int = 9
			for i: int in n:
				if i % 2 == 1:
					continue
				var p0: Vector3 = from.lerp(to, float(i) / n)
				var p1: Vector3 = from.lerp(to, float(i + 1) / n)
				MeshKit.ribbon(_marks, PackedVector3Array([p0, p1]), 0.14, Palette.GOLD)
			drew = true
	return drew


## A flat ring on the table round `center`.
func _ground_ring(center: Vector3, radius: float, width: float, color: Color) -> void:
	var pts := PackedVector3Array()
	var n: int = 28
	for i: int in n + 1:
		var ang: float = TAU * float(i) / n
		pts.append(center + Vector3(cos(ang) * radius, 0.05, sin(ang) * radius))
	MeshKit.ribbon(_marks, pts, width, color)


## Screenshot helper: two heroes locked in a tied battle, Start of the next turn.
func demo_locked() -> void:
	_demo = true
	var a: HeroState = state.heroes_of(0)[0]
	var b: HeroState = state.heroes_of(1)[0]
	a.zone = HeroState.ZONE_MAP
	a.hex = Hex.offset_to_axial(10, 11)
	b.zone = HeroState.ZONE_MAP
	b.hex = Hex.offset_to_axial(12, 11)
	a.tie_turns = 1
	b.tie_turns = 1
	a.locked_with = PackedStringArray([b.id])
	b.locked_with = PackedStringArray([a.id])
	state.phase = GameState.PHASE_START
	_sync()


## Weather on the stages whose terrain is on (playtest 2026-10-30: a label was not what was
## meant, it should look like the mockup's snow): snow falls on Ice, mud bubbles on Mud, streaks
## blow along a Wind. A Ramp is its hill. Kept between syncs so the particles do not restart.
func _refresh_terrain_fx() -> void:
	var want: Dictionary[String, bool] = {}
	for st: StageState in state.stages:
		if not st.placed or not st.revealed or world.terrain == null:
			continue
		var kind: Terrain.Type = world.terrain.at(st.center)
		if kind != Terrain.Type.ICE and kind != Terrain.Type.MUD and kind != Terrain.Type.WIND:
			continue
		var key: String = "%s|%d|%d" % [st.id, kind, world.terrain.dir_of(st.center)]
		want[key] = true
		if not _terrain_fx.has(key):
			var fx: Node3D = _terrain_effect(st, kind, world.terrain.dir_of(st.center))
			add_child(fx)
			_terrain_fx[key] = fx
	for key: String in _terrain_fx.keys():
		if not want.has(key):
			_terrain_fx[key].queue_free()
			_terrain_fx.erase(key)


func _terrain_effect(st: StageState, kind: Terrain.Type, dir: int) -> Node3D:
	var root := Node3D.new()
	root.position = arena.hex_center(st.center)
	var p := CPUParticles3D.new()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var span: float = tuning.hex_size * 2.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ramp := Gradient.new()
	match kind:
		Terrain.Type.ICE:
			# Flakes drift down over the stage and melt into the ice.
			p.amount = 70
			p.lifetime = 3.2
			p.emission_box_extents = Vector3(span, 0.2, span)
			p.position.y = 3.4
			p.direction = Vector3(0, -1, 0)
			p.spread = 18.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 0.9
			p.gravity = Vector3(0.08, -0.35, 0.04)
			var q := QuadMesh.new()
			q.size = Vector2(0.09, 0.09)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			q.surface_set_material(0, mat)
			p.mesh = q
			ramp.set_color(0, Color(1, 1, 1, 0.0))
			ramp.add_point(0.15, Color(1, 1, 1, 0.95))
			ramp.set_color(ramp.get_point_count() - 1, Color(0.85, 0.95, 1.0, 0.0))
		Terrain.Type.MUD:
			# Slow brown bubbles that swell and pop.
			p.amount = 16
			p.lifetime = 1.6
			p.emission_box_extents = Vector3(span * 0.9, 0.0, span * 0.9)
			p.position.y = 0.05
			p.direction = Vector3.UP
			p.spread = 5.0
			p.initial_velocity_min = 0.05
			p.initial_velocity_max = 0.15
			p.gravity = Vector3.ZERO
			var s := SphereMesh.new()
			s.radius = 0.09
			s.height = 0.12
			s.radial_segments = 10
			s.rings = 5
			# A flat dark brown: the ramp's vertex colour came out pale over the stage art.
			mat.vertex_color_use_as_albedo = false
			mat.albedo_color = Color("3b2412")
			s.surface_set_material(0, mat)
			p.mesh = s
			var grow := Curve.new()
			grow.add_point(Vector2(0, 0.2))
			grow.add_point(Vector2(0.85, 1.4))
			grow.add_point(Vector2(1, 0.0))
			p.scale_amount_curve = grow
			ramp.set_color(0, Color("4a2f17", 0.95))
			ramp.set_color(1, Color("7a5634", 0.9))
		Terrain.Type.WIND:
			# Thin streaks racing the way the wind blows.
			var v: Vector2 = TerrainPhysics.wind_vector(dir).normalized()
			p.amount = 34
			p.lifetime = 0.9
			p.emission_box_extents = Vector3(span, 0.6, span)
			p.position.y = 0.7
			p.direction = Vector3(v.x, 0, v.y)
			p.spread = 4.0
			p.initial_velocity_min = 4.5
			p.initial_velocity_max = 6.5
			p.gravity = Vector3.ZERO
			p.particle_flag_align_y = true
			var bar := BoxMesh.new()
			bar.size = Vector3(0.025, 0.7, 0.025)
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			bar.surface_set_material(0, mat)
			p.mesh = bar
			ramp.set_color(0, Color(0.8, 1.0, 0.95, 0.0))
			ramp.add_point(0.3, Color(0.85, 1.0, 0.97, 0.55))
			ramp.set_color(ramp.get_point_count() - 1, Color(0.8, 1.0, 0.95, 0.0))
	p.color_ramp = ramp
	p.local_coords = false
	p.preprocess = p.lifetime
	root.add_child(p)
	p.emitting = true
	return root


## A card played on a hero comes down onto it as a see-through card (playtest 2026-10-30). In a
## battle they stay fanned beside the hero until the battle is over, so both sides see what went
## in; otherwise it fades after a moment.
func _ghost_card(card_id: String, hero_id: String) -> void:
	var tex: Texture2D = db.thumb(card_id) if db != null else null
	if tex == null or not _bodies.has(hero_id):
		return
	var at: Vector3 = _bodies[hero_id].global_position
	var in_battle: bool = state.phase == GameState.PHASE_BATTLE
	var n: int = 0
	for g: Dictionary in _ghosts:
		if str(g["hero"]) == hero_id:
			n += 1
	var card := Sprite3D.new()
	card.texture = tex
	card.pixel_size = 1.5 / maxf(float(tex.get_height()), 1.0)
	card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	card.no_depth_test = true
	card.render_priority = 5
	card.modulate = Color(1, 1, 1, 0.0)
	# Fanned beside the hero, one step out per card already there.
	var rest := at + Vector3(1.1 + 0.55 * n, 1.9, -0.2 * n)
	card.position = rest + Vector3(0, 2.2, 0)
	add_child(card)
	var t: Tween = card.create_tween().set_parallel(true)
	t.tween_property(card, "position", rest, 0.45 * GameSettings.anim_scale()).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "modulate:a", 0.82, 0.3 * GameSettings.anim_scale())
	if in_battle:
		_ghosts.append({"node": card, "hero": hero_id, "battle": state.battle_index, "turn": state.turn})
		return
	var out: Tween = card.create_tween()
	out.tween_interval(1.6 * GameSettings.anim_scale())
	out.tween_property(card, "modulate:a", 0.0, 0.4)
	out.tween_callback(card.queue_free)


## Battle ghosts go once their battle is over (another battle, another phase or turn).
func _clear_ghosts() -> void:
	var keep: Array[Dictionary] = []
	for g: Dictionary in _ghosts:
		var node: Sprite3D = g["node"]
		if not is_instance_valid(node):
			continue
		var b: int = JsonUtil.as_int(g["battle"])
		var done: bool = state.phase != GameState.PHASE_BATTLE or state.turn != JsonUtil.as_int(g["turn"]) \
				or state.battle_index != b or (b >= 0 and b < state.battles.size() and JsonUtil.as_bool(state.battles[b].get("resolved", false)))
		if not done:
			keep.append(g)
			continue
		var t: Tween = node.create_tween()
		t.tween_interval(0.6 * GameSettings.anim_scale())
		t.tween_property(node, "modulate:a", 0.0, 0.35)
		t.tween_callback(node.queue_free)
	_ghosts = keep


## The table as the camera sees it, without the HUD, for the main menu's idle preview
## (playtest 2026-10-30: one picture of the end only). A second camera renders the same world
## once into its own viewport, so the screen does not flicker.
func _highlight_shot() -> void:
	if _replay != null or _demo or not is_inside_tree():
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.world_3d = get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var eye := Camera3D.new()
	vp.add_child(eye)
	add_child(vp)
	eye.global_transform = cam.camera.global_transform
	eye.fov = cam.camera.fov
	eye.current = true
	await RenderingServer.frame_post_draw
	if is_instance_valid(vp):
		ReplayStore.save_highlight(vp.get_texture().get_image())
		vp.queue_free()
