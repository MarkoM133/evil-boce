class_name DraftScreen
extends Control
## The Draft mode (GDD 13): heroes in snake order, then four packs of ten picked one card at a
## time; the rest of a pack goes to the other player. Each side's heroes and cards fill a panel
## on its side, the heroes on offer or the open pack sit in the middle. Local: the Play setup
## leaves the match it would start in `local`, a bot picks at random after a short wait, two
## players here take turns. Online: the host's NetHost runs the draft (bots too), a guest only
## shows it and sends its picks. The move timer, when on, makes a random pick. When the draft
## is done the match starts with the drafted decks and everyone's stages and cores.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const SETUP_SCENE: String = "res://scenes/match/match_setup.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
const BOT_WAIT: float = 0.8
const CARD := Vector2(146, 204)
const HERO_TILE := Vector2(200, 112)

## A local draft from the Play setup: {"settings": MatchSettings, "loadouts": [Loadout, Loadout],
## "names": [String, String], "bot": bool, "bot_level": String}. Cleared when taken.
static var local: Dictionary = {}

var db: CardDb
var draft: DraftState
var host: NetHost
var client: NetClient
## Slots picked from this screen, and the local bots (online the host runs its bots).
var my_slots: PackedInt32Array = PackedInt32Array()
var bot_slots: PackedInt32Array = PackedInt32Array()
var names: PackedStringArray = PackedStringArray(["Player 1", "Player 2"])
var _local: Dictionary = {}
var _limit: int = 0
var _clock_left: float = 0.0
var _wait_key: String = ""
var _bot_wait: float = 0.0
var _bot_delay: float = BOT_WAIT
var _done: bool = false
var _rng := RandomNumberGenerator.new()

var _status: Label
var _clock: Label
var _steps: HBoxContainer
var _center: VBoxContainer
var _sides: Array[VBoxContainer] = []


func _ready() -> void:
	_rng.randomize()
	db = CardDb.load_from(GameSettings.data_path())
	var h: Node = get_tree().root.get_node_or_null("NetHost")
	var c: Node = get_tree().root.get_node_or_null("NetClient")
	if h is NetHost and (h as NetHost).draft != null:
		host = h
		draft = DraftState.from_dict(host.draft.to_dict(), db.catalog)
		my_slots = PackedInt32Array([host.host_slot])
		_limit = host.settings.timer_seconds
		for s: Dictionary in host.seats:
			var slot: int = JsonUtil.as_int(s.get("slot", 0))
			if slot < names.size():
				names[slot] = str(s.get("name", names[slot]))
		host.draft_changed.connect(_on_host_draft)
		host.match_started.connect(func() -> void:
			MatchLaunch.config = {"net": {"role": "host", "node": host}, "settings": host.settings, "decks": [], "bots": PackedInt32Array(), "seed": 0}
			get_tree().change_scene_to_file(MATCH_SCENE))
	elif c is NetClient and not (c as NetClient).draft.is_empty():
		client = c
		draft = DraftState.from_dict(client.draft, db.catalog)
		my_slots = PackedInt32Array([client.slot])
		_limit = MatchSettings.from_dict(client.settings).timer_seconds
		for p: Variant in client.players:
			var d: Dictionary = JsonUtil.as_dict(p)
			var slot: int = JsonUtil.as_int(d.get("slot", 0))
			if slot < names.size():
				names[slot] = str(d.get("name", names[slot]))
		client.draft_changed.connect(func(d: Dictionary) -> void:
			draft = DraftState.from_dict(d, db.catalog)
			_refresh())
		client.state_received.connect(func(_s: GameState) -> void:
			if client.started and get_tree().current_scene == self:
				MatchLaunch.config = {"net": {"role": "client", "node": client}, "settings": MatchSettings.from_dict(client.settings), "decks": [], "bots": PackedInt32Array(), "seed": 0}
				get_tree().change_scene_to_file(MATCH_SCENE))
		client.disconnected.connect(func(_why: String) -> void: get_tree().change_scene_to_file(LOBBY_SCENE))
	elif not local.is_empty():
		_take_local()
	else:
		# Nothing to draft (opened by hand): back to the setup, unless a screenshot helper fills it first.
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if draft == null:
				get_tree().change_scene_to_file(SETUP_SCENE))
		return
	_build()
	_refresh()


## A local draft from `local` (the Play setup).
func _take_local() -> void:
	_local = local
	local = {}
	var settings: MatchSettings = _local["settings"]
	_limit = settings.timer_seconds
	draft = DraftState.start(db.catalog, _rng.randi(), _rng.randi_range(0, 1), settings.deck_size)
	names = JsonUtil.as_strings(_local["names"])
	if JsonUtil.as_bool(_local.get("bot", true)):
		my_slots = PackedInt32Array([0])
		bot_slots = PackedInt32Array([1])
	else:
		my_slots = PackedInt32Array([0, 1])


func _build() -> void:
	var frame: Dictionary = MenuScreen.build(self, db, "Draft",
		"Heroes in turn, then four packs of ten: take one card, the rest goes to the other player.", _back, 1440.0)
	var content: VBoxContainer = frame["content"]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	content.add_child(top)
	_status = UiTheme.label("", 30)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)
	_clock = UiTheme.label("", 24, Palette.GOLD)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_clock)
	_steps = HBoxContainer.new()
	_steps.add_theme_constant_override("separation", 6)
	content.add_child(_steps)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	for slot: int in 2:
		var panel := PanelContainer.new()
		var sb: StyleBoxFlat = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 16, 14)
		sb.border_color = Palette.team(slot)
		sb.border_width_top = 4
		panel.add_theme_stylebox_override("panel", sb)
		panel.custom_minimum_size = Vector2(250, 0)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		panel.add_child(col)
		_sides.append(col)
		if slot == 0:
			row.add_child(panel)
			_center = VBoxContainer.new()
			_center.add_theme_constant_override("separation", 10)
			_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(_center)
		else:
			row.add_child(panel)


## Whose pick it is, what is on offer, and both sides' picks so far.
func _refresh() -> void:
	if _status == null:
		return
	var who: int = draft.waiting_on()
	var mine: bool = my_slots.has(who)
	if draft.phase == DraftState.PHASE_DONE:
		_status.text = "DRAFT DONE  ·  THE MATCH STARTS…"
		_status.add_theme_color_override("font_color", Palette.GOLD)
	elif mine:
		_status.text = ("%s: YOUR PICK" % names[who].to_upper()) if my_slots.size() > 1 else "YOUR PICK"
		_status.add_theme_color_override("font_color", Palette.FG)
	else:
		_status.text = "%s IS PICKING…" % names[who].to_upper()
		_status.add_theme_color_override("font_color", Palette.MUTED)
	_fill_steps(who)
	for slot: int in 2:
		_fill_side(slot)
	for n: Node in _center.get_children():
		n.queue_free()
	if draft.phase == DraftState.PHASE_HEROES:
		_fill_heroes(who, mine)
	elif draft.phase == DraftState.PHASE_PACKS:
		_fill_pack(who, mine)
	if draft.phase == DraftState.PHASE_DONE and not _local.is_empty() and not _done:
		_done = true
		get_tree().create_timer(1.2).timeout.connect(_start_local)


## The hero order A B B A A B with the current pick lit, then the packs.
func _fill_steps(who: int) -> void:
	for n: Node in _steps.get_children():
		n.queue_free()
	_steps.add_child(UiTheme.label("HEROES", 14, Palette.GOLD))
	for i: int in DraftState.HERO_ORDER.size():
		var slot: int = draft.first if DraftState.HERO_ORDER[i] == 0 else 1 - draft.first
		var now: bool = draft.phase == DraftState.PHASE_HEROES and i == draft.hero_picks
		var done: bool = i < draft.hero_picks or draft.phase != DraftState.PHASE_HEROES
		var fill: Color = Palette.team(slot) if now else (Palette.team(slot).darkened(0.55) if done else Palette.SURFACE_2)
		_steps.add_child(UiShape.chip(str(i + 1), fill, Palette.FG if now or done else Palette.DIM, 14, 26.0 if now else 22.0, 9.0))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(24, 0)
	_steps.add_child(gap)
	_steps.add_child(UiTheme.label("PACKS", 14, Palette.GOLD))
	for k: int in DraftState.PACKS:
		var opener: int = draft.first if k % 2 == 0 else 1 - draft.first
		var now: bool = draft.phase == DraftState.PHASE_PACKS and k == draft.pack_index
		var done: bool = draft.phase == DraftState.PHASE_DONE or (draft.phase == DraftState.PHASE_PACKS and k < draft.pack_index)
		var fill: Color = Palette.team(opener) if now else (Palette.team(opener).darkened(0.55) if done else Palette.SURFACE_2)
		var text: String = "%d  ·  %d LEFT" % [k + 1, draft.current_pack().size()] if now else str(k + 1)
		_steps.add_child(UiShape.chip(text, fill, Palette.FG if now or done else Palette.DIM, 14, 26.0 if now else 22.0, 9.0))
	if who >= 0:
		var turn_gap := Control.new()
		turn_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_steps.add_child(turn_gap)


## One side: name, the drafted heroes, its colours and its cards so far.
func _fill_side(slot: int) -> void:
	var col: VBoxContainer = _sides[slot]
	for n: Node in col.get_children():
		n.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	head.add_child(UiShape.chip(names[slot].to_upper(), Palette.team(slot), Palette.FG, 18, 30.0, 14.0))
	if draft.waiting_on() == slot:
		head.add_child(UiShape.chip("PICKING", Palette.GOLD, Color.BLACK, 12, 22.0, 8.0))
	col.add_child(UiTheme.label("HEROES", 13, Palette.GOLD))
	var picked: PackedStringArray = draft.heroes[slot]
	for i: int in 3:
		col.add_child(_hero_slice(picked[i] if i < picked.size() else ""))
	var count: int = draft.card_count(slot)
	col.add_child(UiTheme.label("CARDS  %d / %d" % [count, draft.deck_size], 13, Palette.GOLD))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 160)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var cards: Dictionary = draft.cards[slot]
	var ids: Array = cards.keys()
	ids.sort()
	for id: Variant in ids:
		var card: CardDef = db.catalog.get_card(str(id))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		list.add_child(line)
		var dot := ColorRect.new()
		dot.color = Palette.hero(card.color if card != null else "")
		dot.custom_minimum_size = Vector2(4, 18)
		line.add_child(dot)
		var l := Label.new()
		l.text = "%d×  %s" % [JsonUtil.as_int(cards[id]), card.name if card != null else str(id)]
		l.add_theme_font_size_override("font_size", 14)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = card.text if card != null else ""
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(l)


func _hero_slice(id: String) -> Control:
	var s := HeroSlice.new()
	s.custom_minimum_size = Vector2(218, 52)
	var card: CardDef = db.catalog.get_card(id) if not id.is_empty() else null
	s.art = db.thumb(id) if card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = Palette.hero(card.color).darkened(0.3) if card != null else Palette.SURFACE_2
	var l: Label = UiTheme.label(card.name if card != null else "?", 15 if card != null else 24, Palette.FG if card != null else Palette.DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.content.add_child(l)
	if card != null:
		s.tooltip_text = "%s  ·  %s\n%s" % [card.name, card.color, card.text]
	return s


## The heroes still on offer; a click takes one when it is this screen's pick.
func _fill_heroes(who: int, mine: bool) -> void:
	_center.add_child(UiTheme.label("PICK A HERO" if mine else "HEROES ON OFFER", 18, Palette.GOLD))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_center.add_child(grid)
	for id: String in draft.hero_pool:
		var tile: Control = PlayerCard.card_tile(db, id, HERO_TILE,
			(func() -> void: _pick(who, id)) if mine else Callable())
		var card: CardDef = db.catalog.get_card(id)
		if card != null:
			var chip: UiShape = UiShape.chip(card.color.to_upper(), Palette.hero(card.color), Palette.FG, 11, 18.0, 7.0)
			chip.position = Vector2(14, -8)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(chip)
		grid.add_child(tile)


## The open pack: the cards the picker may take are lit, the others dim with the reason.
func _fill_pack(who: int, mine: bool) -> void:
	_center.add_child(UiTheme.label(("TAKE ONE CARD" if mine else "THE PACK") + "  ·  THE REST GOES TO %s" % names[1 - who].to_upper(), 18, Palette.GOLD))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_center.add_child(grid)
	for id: String in draft.current_pack():
		grid.add_child(_pack_card(id, who, mine))


func _pack_card(id: String, who: int, mine: bool) -> Control:
	var card: CardDef = db.catalog.get_card(id)
	var why: String = draft.why_not(who, id)
	var box := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 0, 0)
	sb.set_border_width_all(3)
	sb.border_color = Color(0, 0, 0, 0)
	box.add_theme_stylebox_override("panel", sb)
	var pic := TextureRect.new()
	pic.texture = db.large(id) if db.large(id) != null else db.thumb(id)
	pic.custom_minimum_size = CARD
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	if pic.texture == null:
		var l: Label = UiTheme.label(card.name if card != null else id, 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	var tip: String = ("%s  ·  %s %s  ·  cost %d\n%s" % [card.name, card.color, card.type, card.cost, card.text]) if card != null else id
	if not why.is_empty():
		box.modulate = Color(1, 1, 1, 0.35)
		tip += "\n\n%s cannot take it: %s" % [names[who], why]
	box.tooltip_text = tip
	if mine and why.is_empty():
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.mouse_entered.connect(func() -> void:
			sb.border_color = Palette.GOLD
			box.queue_redraw())
		box.mouse_exited.connect(func() -> void:
			sb.border_color = Color(0, 0, 0, 0)
			box.queue_redraw())
		box.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_pick(who, id))
	return box


# --- picks, bots, the timer ---------------------------------------------------------------

func _pick(slot: int, id: String) -> void:
	if id.is_empty() or draft.phase == DraftState.PHASE_DONE:
		return
	if client != null:
		client.send_draft_pick(id)
		return
	if host != null:
		var why: String = host.apply_draft_pick(slot, id)
		if not why.is_empty():
			_status.text = why.to_upper()
		return
	if draft.pick(slot, id).is_empty():
		_refresh()


func _on_host_draft() -> void:
	if host.draft != null:
		draft = DraftState.from_dict(host.draft.to_dict(), db.catalog)
		_refresh()


func _process(delta: float) -> void:
	if draft == null or _status == null or draft.phase == DraftState.PHASE_DONE:
		if _clock != null:
			_clock.text = ""
		return
	var who: int = draft.waiting_on()
	var key: String = "%d|%d|%d|%d" % [draft.hero_picks, draft.pack_index, draft.current_pack().size(), who]
	if key != _wait_key:
		_wait_key = key
		_clock_left = float(_limit)
		_bot_wait = _bot_delay
	# A local bot takes a random legal pick after a short wait (online the host does it).
	if bot_slots.has(who):
		_bot_wait -= delta
		if _bot_wait <= 0.0:
			_bot_wait = _bot_delay
			_pick(who, draft.timeout_pick(who, _rng))
		return
	if _limit <= 0:
		_clock.text = ""
		return
	_clock_left = maxf(0.0, _clock_left - delta)
	var left: int = ceili(_clock_left)
	_clock.text = "TIME  %d" % left
	_clock.add_theme_color_override("font_color", Palette.ACCENT_HOVER if left <= 5 else Palette.GOLD)
	# Whoever runs the draft makes the random pick; a guest only shows the time.
	if _clock_left <= 0.0 and client == null:
		_clock_left = float(_limit)
		var guest: bool = host != null and not my_slots.has(who)
		if guest:
			host.apply_draft_pick(who, draft.timeout_pick(who, _rng))
		else:
			_pick(who, draft.timeout_pick(who, _rng))


## Local: the drafted decks with each side's stages and cores, into the match.
func _start_local() -> void:
	var settings: MatchSettings = _local["settings"]
	var loadouts: Array = _local["loadouts"]
	var engine_decks: Array = []
	var drafted: Array[Dictionary] = draft.decks()
	for slot: int in 2:
		var lo: Loadout = loadouts[slot] if slot < loadouts.size() else null
		engine_decks.append(MatchLaunch.engine_deck(db.catalog, drafted[slot], names[slot], _rng, lo))
	var bot: bool = JsonUtil.as_bool(_local.get("bot", true))
	MatchLaunch.config = {
		"settings": settings,
		"decks": engine_decks,
		"bots": PackedInt32Array([1]) if bot else PackedInt32Array(),
		"bot_level": str(_local.get("bot_level", "easy")),
		"seed": _rng.randi(),
	}
	get_tree().change_scene_to_file(MATCH_SCENE)


func _back() -> void:
	if client != null or host != null:
		# Leaving an online draft leaves the table, as the lobby's back does.
		if host != null:
			host.link.close()
			host.queue_free()
		if client != null:
			client.link.close()
			client.queue_free()
		get_tree().change_scene_to_file("res://scenes/menu/play_menu.tscn")
		return
	get_tree().change_scene_to_file(SETUP_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
		_back()


# --- screenshot helpers (tools/screenshot.gd --call=...) -----------------------------------

## A local draft against the bot with a 30 s timer.
func demo_local() -> void:
	var s: MatchSettings = MatchSettings.preset("draft")
	s.timer_seconds = 30
	local = {"settings": s, "loadouts": [Loadout.random(), Loadout.random()], "names": ["Player 1", "Bot (Easy)"], "bot": true, "bot_level": "easy"}
	_take_local()
	# A screenshot keeps the draft still: nobody is a bot, and no match starts.
	bot_slots = PackedInt32Array()
	_build()
	_refresh()


## Heroes done and the first pack open (both pick at random up to there).
func demo_packs() -> void:
	while draft.phase == DraftState.PHASE_HEROES:
		draft.pick(draft.waiting_on(), draft.timeout_pick(draft.waiting_on(), _rng))
	for _i: int in 3:
		if draft.phase == DraftState.PHASE_PACKS:
			draft.pick(draft.waiting_on(), draft.timeout_pick(draft.waiting_on(), _rng))
	bot_slots = PackedInt32Array()
	my_slots = PackedInt32Array([0, 1])
	_refresh()


## Bots draft both sides quickly; when the draft is done the match starts (a full run).
func demo_bots() -> void:
	my_slots = PackedInt32Array()
	bot_slots = PackedInt32Array([0, 1])
	_bot_delay = 0.05
	_refresh()
