extends Control
## Online lobby (GDD 7, step 3) in the menus' look: host a match on this computer or join one
## over Tailscale. The room looks like Local play: your player card (deck, stages, cores) on the
## left, VS, the other player's picks on the right (or, while the seat is empty, the address to
## send and a bot to fill it), the map and match rules under them (the host changes them,
## guests see them) and the big button: START MATCH for the host, READY for a guest. The
## NetHost / NetClient node lives under the root so the match scene keeps it, and after a
## match the host brings everyone back here.

## Back goes to the Play screen (local, online, practice).
const MENU_SCENE: String = "res://scenes/menu/play_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const DRAFT_SCENE: String = "res://scenes/match/draft.tscn"

var db: CardDb
var decks: Array[Dictionary] = []
var host: NetHost
var client: NetClient
var _rng := RandomNumberGenerator.new()

var _name: LineEdit
var _address: LineEdit
var _status: Label
var _front: Control
var _room: Control
var _card: PlayerCard
var _opp: PlayerCard
var _wait: PanelContainer
var _series: Label
var _wait_host: Control
var _address_label: Label
var _bot_row: HBoxContainer
var _rules: MatchRules
var _start_btn: Button
var _ready_btn: Button


func _ready() -> void:
	_rng.randomize()
	db = CardDb.load_from(GameSettings.data_path())
	decks = DeckStore.load_all(db.root_dir)
	_build()
	if not db.is_ok():
		_status.text = db.error
	# Back from a match: the session is still up.
	var h: Node = get_tree().root.get_node_or_null("NetHost")
	var c: Node = get_tree().root.get_node_or_null("NetClient")
	if h is NetHost:
		host = h
		_wire_host()
		_status.text = "Back in the lobby. Pick a deck and start again."
	elif c is NetClient:
		client = c
		_wire_client()
		_enter_room(false)
		_status.text = "Back in the lobby. Press Ready when you are."


func _build() -> void:
	var frame: Dictionary = MenuScreen.build(self, db, "Online", "Play over Tailscale: one hosts, the other joins.", _back, 1300.0)
	var content: VBoxContainer = frame["content"]
	_status = Label.new()
	_status.add_theme_color_override("font_color", Palette.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)

	# Before connecting: your name, then host or join.
	_front = VBoxContainer.new()
	_front.add_theme_constant_override("separation", 14)
	content.add_child(_front)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	_front.add_child(name_row)
	name_row.add_child(UiTheme.label("YOUR NAME", 18, Palette.GOLD))
	_name = LineEdit.new()
	_name.text = GameSettings.player_name()
	_name.max_length = 24
	_name.custom_minimum_size = Vector2(360, 0)
	_name.add_theme_font_size_override("font_size", 22)
	name_row.add_child(_name)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 18)
	_front.add_child(pair)
	var host_card: VBoxContainer = MenuScreen.card(pair, 26, true)
	host_card.add_child(UiTheme.label("HOST", 40))
	var host_info := Label.new()
	host_info.text = "Open a table on this computer (port %d). Send the other player your Tailscale address." % NetProtocol.DEFAULT_PORT
	host_info.add_theme_color_override("font_color", Palette.MUTED)
	host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_card.add_child(host_info)
	var host_btn := Button.new()
	host_btn.text = "HOST A MATCH"
	host_btn.theme_type_variation = &"Primary"
	host_btn.add_theme_font_size_override("font_size", 30)
	host_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	host_btn.pressed.connect(_host)
	host_card.add_child(host_btn)
	var join_card: VBoxContainer = MenuScreen.card(pair, 26, true)
	join_card.add_child(UiTheme.label("JOIN", 40))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	join_card.add_child(join_row)
	_address = LineEdit.new()
	_address.placeholder_text = "host's Tailscale address, e.g. 100.64.1.2"
	_address.text = GameSettings.last_host()
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.add_theme_font_size_override("font_size", 22)
	_address.text_submitted.connect(func(_t: String) -> void: _join())
	join_row.add_child(_address)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.theme_type_variation = &"Gold"
	join_btn.add_theme_font_size_override("font_size", 26)
	join_btn.pressed.connect(_join)
	join_row.add_child(join_btn)
	var join_info := Label.new()
	join_info.text = "Both need the same game version and the shared folder synced."
	join_info.add_theme_color_override("font_color", Palette.MUTED)
	join_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	join_card.add_child(join_info)

	# Connected: you VS the other seat, the map and rules under them.
	_room = VBoxContainer.new()
	_room.add_theme_constant_override("separation", 14)
	_room.visible = false
	content.add_child(_room)
	_series = UiTheme.label("", 18, Palette.GOLD)
	_series.visible = false
	_room.add_child(_series)
	var vs_row := HBoxContainer.new()
	vs_row.add_theme_constant_override("separation", 18)
	_room.add_child(vs_row)
	_card = PlayerCard.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vs_row.add_child(_card)
	_card.setup(db, decks, GameSettings.player_name(), 0, GameSettings.last_deck("online"), Loadout.remembered("online"))
	_card.changed.connect(_send_deck)
	var vs: Label = UiTheme.label("VS", 64, Palette.ACCENT)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vs.add_theme_color_override("font_outline_color", Color.BLACK)
	vs.add_theme_constant_override("outline_size", 8)
	vs_row.add_child(vs)
	_opp = PlayerCard.new()
	_opp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vs_row.add_child(_opp)
	_opp.setup(db, decks, "Opponent", 1, "", Loadout.new())
	_opp.show_only({})
	_build_wait(vs_row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	_room.add_child(bottom)
	_rules = MatchRules.new()
	_rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_rules)
	_rules.setup(GameSettings.match_rules("online"), false)
	_rules.changed.connect(_push_settings)
	_ready_btn = Button.new()
	_ready_btn.text = "READY"
	_ready_btn.toggle_mode = true
	_ready_btn.theme_type_variation = &"Primary"
	_ready_btn.add_theme_font_size_override("font_size", 40)
	_ready_btn.custom_minimum_size = Vector2(380, 0)
	_ready_btn.toggled.connect(func(on: bool) -> void:
		_ready_btn.text = "READY ✓" if on else "READY"
		_ready_btn.theme_type_variation = &"Gold" if on else &"Primary"
		if client != null:
			client.send_ready(on))
	bottom.add_child(_ready_btn)
	_start_btn = Button.new()
	_start_btn.text = "START MATCH"
	_start_btn.theme_type_variation = &"Primary"
	_start_btn.add_theme_font_size_override("font_size", 40)
	_start_btn.custom_minimum_size = Vector2(380, 0)
	_start_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_btn.pressed.connect(_start)
	bottom.add_child(_start_btn)


## The empty seat: waiting, and for the host the address to send and a bot to fill it.
func _build_wait(parent: Control) -> void:
	_wait = PanelContainer.new()
	_wait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 26, 22)
	sb.border_color = Palette.DIM
	sb.border_width_top = 4
	_wait.add_theme_stylebox_override("panel", sb)
	parent.add_child(_wait)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	_wait.add_child(col)
	col.add_child(UiTheme.label("WAITING FOR A PLAYER…", 34, Palette.DIM))
	_wait_host = VBoxContainer.new()
	_wait_host.add_theme_constant_override("separation", 8)
	col.add_child(_wait_host)
	_wait_host.add_child(UiTheme.label("SEND THEM YOUR ADDRESS", 13, Palette.GOLD))
	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 8)
	_wait_host.add_child(addr_row)
	_address_label = Label.new()
	_address_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_address_label.add_theme_font_override("font", UiTheme.display_italic())
	_address_label.add_theme_font_size_override("font_size", 24)
	addr_row.add_child(_address_label)
	var copy := Button.new()
	copy.text = "COPY"
	copy.tooltip_text = "Copy the address to send it to the other player"
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_my_addresses()[0])
		_status.text = "Address copied.")
	addr_row.add_child(copy)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_wait_host.add_child(gap)
	_wait_host.add_child(UiTheme.label("OR PLAY A BOT", 13, Palette.GOLD))
	_bot_row = HBoxContainer.new()
	_bot_row.add_theme_constant_override("separation", 8)
	_wait_host.add_child(_bot_row)
	for hard: bool in [false, true]:
		var b := Button.new()
		b.text = "BOT · HARD" if hard else "BOT · EASY"
		b.add_theme_font_size_override("font_size", 20)
		b.tooltip_text = "Fill the other seat with a bot instead of waiting for a player"
		b.pressed.connect(func() -> void:
			if host == null:
				return
			var why: String = host.add_bot(Bot.level_name(Bot.Level.HARD if hard else Bot.Level.EASY), _engine_deck({}, "Bot"))
			if not why.is_empty():
				_status.text = why)
		_bot_row.add_child(b)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func _engine_deck(saved: Dictionary, who: String, loadout: Loadout = null) -> Dictionary:
	var deck: Dictionary = saved if not saved.is_empty() else DeckCode.random_deck(db.catalog, _rng)
	return MatchLaunch.engine_deck(db.catalog, deck, who, _rng, loadout)


## Room view: the host changes the rules and starts, a guest sees the rules and gets Ready.
func _enter_room(as_host: bool) -> void:
	_front.visible = false
	_room.visible = true
	_wait_host.visible = as_host
	_rules.set_editable(as_host)
	_start_btn.visible = as_host
	_ready_btn.visible = not as_host
	_ready_btn.set_pressed_no_signal(false)
	_ready_btn.text = "READY"
	_ready_btn.theme_type_variation = &"Primary"
	_send_deck()
	_refresh()


# --- host -------------------------------------------------------------------------------

func _host() -> void:
	GameSettings.set_player_name(_name.text)
	host = NetHost.new(RulesEngine.new(db.catalog), GameSettings.player_name(), _version(), db.version)
	host.name = "NetHost"
	var err: String = host.listen()
	if not err.is_empty():
		_status.text = err
		host.free()
		host = null
		return
	get_tree().root.add_child(host)
	_push_settings()
	_wire_host()
	_status.text = "Hosting. Send the other player your address."


func _wire_host() -> void:
	host.lobby_changed.connect(_refresh)
	_rules.set_settings(MatchSettings.from_dict(host.settings.to_dict()))
	_address_label.text = "%s  ·  PORT %d" % [", ".join(_my_addresses()), NetProtocol.DEFAULT_PORT]
	_enter_room(true)


## The host's rules to the table (a copy: the panel keeps editing its own).
func _push_settings() -> void:
	if host == null:
		return
	GameSettings.set_match_rules("online", _rules.settings)
	host.set_settings(MatchSettings.from_dict(_rules.settings.to_dict()))


func _my_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.begins_with("100."):
			out.append(a)
	return out if not out.is_empty() else PackedStringArray(["(no Tailscale address found)"])


func _start() -> void:
	if host == null:
		return
	# A random map is drawn now, so everyone starts on the same one (the START message carries it).
	host.settings.resolve_map(_rng, GameSettings.MAP_SIZES)
	if host.settings.mode == "draft":
		# Draft (GDD 13): everyone goes to the draft; the host starts the match when it is done.
		var why: String = host.start_draft(_rng.randi())
		if not why.is_empty():
			_status.text = why
			return
		get_tree().change_scene_to_file(DRAFT_SCENE)
		return
	var err: String = host.start(_rng.randi())
	if not err.is_empty():
		_status.text = err
		return
	MatchLaunch.config = {"net": {"role": "host", "node": host}, "settings": host.settings, "decks": [], "bots": PackedInt32Array(), "seed": 0}
	get_tree().change_scene_to_file(MATCH_SCENE)


# --- join -------------------------------------------------------------------------------

func _join() -> void:
	if client != null:
		return
	var address: String = _address.text.strip_edges()
	if address.is_empty():
		_status.text = "Type the host's Tailscale address first."
		return
	GameSettings.set_player_name(_name.text)
	GameSettings.set_last_host(address)
	client = NetClient.new(GameSettings.player_name(), _version(), db.version)
	client.name = "NetClient"
	var err: String = client.connect_to(address)
	if not err.is_empty():
		_status.text = err
		client.free()
		client = null
		return
	get_tree().root.add_child(client)
	_wire_client()
	_status.text = "Connecting to %s…" % address


func _wire_client() -> void:
	client.welcomed.connect(func(_slot: int) -> void:
		_status.text = "Connected. Pick a deck and press Ready."
		_enter_room(false))
	client.rejected.connect(func(why: String) -> void:
		_status.text = "Rejected: " + why
		_drop_client())
	client.disconnected.connect(func(why: String) -> void:
		_status.text = why
		_drop_client())
	client.lobby_changed.connect(func(_p: Array, _s: Dictionary) -> void:
		# The host changed the settings: it un-readied us, so the button follows.
		if not _me_ready():
			_ready_btn.set_pressed_no_signal(false)
			_ready_btn.text = "READY"
			_ready_btn.theme_type_variation = &"Primary"
		_refresh())
	# Draft (GDD 13): the host opened the draft, everyone goes there.
	client.draft_changed.connect(func(_d: Dictionary) -> void:
		if get_tree().current_scene == self:
			get_tree().change_scene_to_file(DRAFT_SCENE))
	# The match scene needs a state to draw: go when the first one after START is in.
	client.state_received.connect(func(_s: GameState) -> void:
		if client.started and get_tree().current_scene == self:
			MatchLaunch.config = {"net": {"role": "client", "node": client}, "settings": MatchSettings.from_dict(client.settings), "decks": [], "bots": PackedInt32Array(), "seed": 0}
			get_tree().change_scene_to_file(MATCH_SCENE))


func _me_ready() -> bool:
	for p: Variant in client.players:
		var d: Dictionary = JsonUtil.as_dict(p)
		if JsonUtil.as_int(d.get("slot", -1), -1) == client.slot:
			return JsonUtil.as_bool(d.get("ready", false))
	return false


func _drop_client() -> void:
	if client != null:
		client.link.close()
		client.queue_free()
		client = null
	_front.visible = true
	_room.visible = false


# --- both -------------------------------------------------------------------------------

## Your deck to the table, with your picks as the other player sees them (random stays "?").
func _send_deck() -> void:
	var problems: PackedStringArray = _card.problems()
	_ready_btn.disabled = not problems.is_empty()
	var saved: Dictionary = _card.saved_deck()
	if problems.is_empty():
		_card.loadout.remember("online")
		GameSettings.set_last_deck("online", "" if saved.is_empty() else str(saved["name"]))
	var deck: Dictionary = _engine_deck(saved, GameSettings.player_name(), _card.loadout) if problems.is_empty() else {}
	if not deck.is_empty():
		deck["shown"] = _card.picks()
		# Best of 3: the sideboard goes with the deck (the host keeps it for the series).
		if _rules.settings.series_wins > 1:
			deck["sideboard"] = _card.sideboard
	if host != null:
		host.set_my_deck(deck)
	elif client != null:
		if not problems.is_empty() and _ready_btn.button_pressed:
			_ready_btn.button_pressed = false
		client.send_deck(deck)


func _refresh() -> void:
	var seats: Array = host.public_seats() if host != null else (client.players if client != null else [])
	var my_slot: int = host.host_slot if host != null else (client.slot if client != null else -1)
	var other: Dictionary = {}
	for s: Variant in seats:
		var d: Dictionary = JsonUtil.as_dict(s)
		var slot: int = JsonUtil.as_int(d.get("slot", 0))
		if slot == my_slot:
			_card.set_header(str(d.get("name", GameSettings.player_name())), slot)
			_tags(_card, d, true)
		elif other.is_empty():
			other = d
	_opp.visible = not other.is_empty()
	_wait.visible = other.is_empty()
	if not other.is_empty():
		_opp.set_header(str(other.get("name", "")), JsonUtil.as_int(other.get("slot", 1)))
		_opp.show_only(JsonUtil.as_dict(other.get("shown", {})))
		_tags(_opp, other, false)
	# A series (Best of 3): the decks of game one stay, stages and cores are picked again.
	var sd: Dictionary = host.series.to_dict() if host != null and host.series != null else (client.series if client != null else {})
	var series: MatchSeries = MatchSeries.from_dict(sd) if not sd.is_empty() else null
	var in_series: bool = series != null and series.games > 0 and not series.is_over()
	_series.visible = in_series
	if in_series:
		_series.text = "SERIES %s  ·  GAME %d NEXT  ·  THE DECKS STAY, PICK YOUR STAGES AND CORES" % [series.score(), series.games + 1]
		if my_slot >= 0 and my_slot < series.decks.size():
			var want: Dictionary = JsonUtil.as_dict(series.decks[my_slot])
			var have: Dictionary = JsonUtil.as_dict(_card.built.get("cards", {}))
			var cards: Dictionary = JsonUtil.as_dict(want.get("cards", {}))
			var has_side: bool = my_slot < series.sideboards.size() and not JsonUtil.as_dict(series.sideboards[my_slot]).is_empty()
			if not _card.deck_fixed() or MatchSeries._swaps(have, cards) > 0 or MatchSeries._swaps(cards, have) > 0:
				_card.swap_handler = _swap if has_side else Callable()
				_card.set_fixed_deck(want)
				_send_deck()
	else:
		var m: String = _rules.settings.mode
		_card.set_sideboard_mode(_rules.settings.series_wins > 1 and m != "draft" and m != "chaos")
	_rules.set_editable(host != null and not in_series)
	if host == null:
		_rules.set_settings(MatchSettings.from_dict(client.settings if client != null else {}))
	# Chaos (GDD 13): everyone plays random decks, stages and cores; a locked card is sent again.
	var locked_a: bool = _card.set_locked_random(_rules.settings.mode == "chaos")
	var locked_b: bool = _card.set_drafted(_rules.settings.mode == "draft")
	if locked_a or locked_b:
		_send_deck()
	if host != null:
		var why: String = host.can_start()
		_start_btn.disabled = not why.is_empty()
		_start_btn.tooltip_text = why
		_start_btn.text = (("START GAME %d" % (series.games + 1)) if in_series else "START MATCH") if why.is_empty() else why.to_upper()
		_start_btn.add_theme_font_size_override("font_size", 40 if why.is_empty() else 22)


## Best of 3 between games: swap with the sideboard; the host checks the swap and sends the
## series back, which sets the deck shown here.
func _swap() -> void:
	var sd: Dictionary = host.series.to_dict() if host != null and host.series != null else (client.series if client != null else {})
	if sd.is_empty():
		return
	var series: MatchSeries = MatchSeries.from_dict(sd)
	var slot: int = host.host_slot if host != null else client.slot
	if slot < 0 or slot >= series.decks.size() or slot >= series.break_decks.size():
		return
	var now: Dictionary = JsonUtil.as_dict(series.decks[slot])
	SideboardPanel.open_swap(self, db, JsonUtil.as_strings(now.get("heroes", [])),
		JsonUtil.as_dict(JsonUtil.as_dict(series.break_decks[slot]).get("cards", {})),
		JsonUtil.as_dict(series.break_sides[slot]) if slot < series.break_sides.size() else {}, JsonUtil.as_dict(now.get("cards", {})),
		func(cards: Dictionary) -> void:
			var err: String = series.set_cards(db.catalog, slot, cards)
			if not err.is_empty():
				_status.text = err
				return
			_card.set_fixed_deck(JsonUtil.as_dict(series.decks[slot]))
			_send_deck())


## A seat's state as chips in its card header: host, bot, ready, away, no deck; the host can
## free a bot's seat from there.
func _tags(card: PlayerCard, d: Dictionary, mine: bool) -> void:
	for c: Node in card.header_extra.get_children():
		c.queue_free()
	var slot: int = JsonUtil.as_int(d.get("slot", 0))
	var bot: bool = JsonUtil.as_bool(d.get("bot", false))
	if not JsonUtil.as_bool(d.get("has_deck", false)):
		card.header_extra.add_child(UiShape.chip("NO DECK", Palette.ACCENT_DEEP, Palette.FG, 14, 26.0, 10.0))
	var tag: String = "NOT READY"
	var bg: Color = Palette.SURFACE_2
	var fg: Color = Palette.MUTED
	if bot:
		tag = "BOT"
	elif slot == 0:
		tag = "HOST"
	elif JsonUtil.as_bool(d.get("ready", false)):
		tag = "READY"
		bg = Palette.GOLD
		fg = Color.BLACK
	if not JsonUtil.as_bool(d.get("connected", true)):
		tag = "AWAY"
	if mine and tag == "NOT READY":
		return
	card.header_extra.add_child(UiShape.chip(tag, bg, fg, 14, 26.0, 10.0))
	if bot and host != null:
		var rm := Button.new()
		rm.text = "REMOVE"
		rm.tooltip_text = "Free the seat for a player"
		rm.add_theme_font_size_override("font_size", 14)
		rm.pressed.connect(func() -> void: host.remove_bots())
		card.header_extra.add_child(rm)


func _back() -> void:
	if _rules.is_open():
		return
	if host != null:
		host.link.close()
		host.queue_free()
		host = null
	if client != null:
		client.link.close()
		client.queue_free()
		client = null
	get_tree().change_scene_to_file(MENU_SCENE)


# --- screenshot helpers (tools/screenshot.gd --call=...) -----------------------------------

## Hosts on the default port and seats a Hard bot, to show the room.
func demo_room() -> void:
	_host()
	if host != null:
		host.add_bot("hard", _engine_deck({}, "Bot"))


## Hosts and waits: the empty seat.
func demo_waiting() -> void:
	_host()


func demo_rules() -> void:
	demo_room()
	_rules.open_rules()


func demo_maps() -> void:
	demo_room()
	_rules.open_map_picker()
