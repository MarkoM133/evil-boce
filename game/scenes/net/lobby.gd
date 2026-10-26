extends Control
## Online lobby (GDD 7, step 3) in the menus' look: host a match on this computer or join one
## over Tailscale. In the room, your player card (deck, stages, cores) sits on the left and the
## table on the right: who is in, a bot for the empty seat, the match settings (the host
## changes them, guests see them) and the big button: START MATCH for the host, READY for a
## guest. The NetHost / NetClient node lives under the root so the match scene keeps it, and
## after a match the host brings everyone back here.

## Back goes to the Play screen (vs bot, two players, online, practice).
const MENU_SCENE: String = "res://scenes/menu/play_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const MatchSetup = preload("res://scenes/match/match_setup.gd")

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
var _players: VBoxContainer
var _address_row: Control
var _address_label: Label
var _host_bits: Control
var _settings_row: HBoxContainer
var _settings_text: Label
var _bot_row: HBoxContainer
var _start_btn: Button
var _ready_btn: Button
var _map_i: int = 0
var _range_i: int = 1
var _manual: bool = true


func _ready() -> void:
	_rng.randomize()
	db = CardDb.load_from(GameSettings.data_path())
	decks = DeckStore.load_all(db.root_dir)
	_map_i = maxi(0, GameSettings.MAP_SIZES.find(MatchSettings.standard().map_size))
	_range_i = maxi(0, MatchSetup.RANGE_DELTAS.find(MatchSettings.standard().range_delta))
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

	# Connected: your card left, the table right.
	_room = HBoxContainer.new()
	_room.add_theme_constant_override("separation", 18)
	_room.visible = false
	content.add_child(_room)
	_card = PlayerCard.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room.add_child(_card)
	_card.setup(db, decks, "You", 0, GameSettings.last_deck("online"), Loadout.remembered("online"))
	_card.changed.connect(_send_deck)

	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 12)
	table.custom_minimum_size = Vector2(520, 0)
	_room.add_child(table)
	var seats_card: VBoxContainer = MenuScreen.card(table)
	seats_card.add_child(UiTheme.label("TABLE", 15, Palette.GOLD))
	_address_row = HBoxContainer.new()
	_address_row.add_theme_constant_override("separation", 8)
	seats_card.add_child(_address_row)
	_address_label = Label.new()
	_address_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_label.add_theme_font_override("font", UiTheme.display_italic())
	_address_label.add_theme_font_size_override("font_size", 20)
	_address_row.add_child(_address_label)
	var copy := Button.new()
	copy.text = "COPY"
	copy.tooltip_text = "Copy the address to send it to the other player"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_my_addresses()[0])
		_status.text = "Address copied.")
	_address_row.add_child(copy)
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 6)
	seats_card.add_child(_players)
	_bot_row = HBoxContainer.new()
	_bot_row.add_theme_constant_override("separation", 6)
	seats_card.add_child(_bot_row)

	var match_card: VBoxContainer = MenuScreen.card(table)
	match_card.add_child(UiTheme.label("MATCH", 15, Palette.GOLD))
	_settings_text = Label.new()
	_settings_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	match_card.add_child(_settings_text)
	_host_bits = VBoxContainer.new()
	_host_bits.add_theme_constant_override("separation", 8)
	match_card.add_child(_host_bits)
	_settings_row = HBoxContainer.new()
	_host_bits.add_child(_settings_row)
	_build_settings()

	_ready_btn = Button.new()
	_ready_btn.text = "READY"
	_ready_btn.toggle_mode = true
	_ready_btn.theme_type_variation = &"Primary"
	_ready_btn.add_theme_font_size_override("font_size", 40)
	_ready_btn.toggled.connect(func(on: bool) -> void:
		_ready_btn.text = "READY ✓" if on else "READY"
		_ready_btn.theme_type_variation = &"Gold" if on else &"Primary"
		if client != null:
			client.send_ready(on))
	table.add_child(_ready_btn)
	_start_btn = Button.new()
	_start_btn.text = "START MATCH"
	_start_btn.theme_type_variation = &"Primary"
	_start_btn.add_theme_font_size_override("font_size", 40)
	_start_btn.pressed.connect(_start)
	table.add_child(_start_btn)


## The host's settings as chips that cycle (the same as Play setup).
func _build_settings() -> void:
	for c: Node in _settings_row.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_settings_row.add_child(col)
	var chip := func(text: String, step: Callable) -> void:
		var b := Button.new()
		b.text = text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.tooltip_text = "Click to change"
		b.pressed.connect(func() -> void:
			step.call()
			_push_settings()
			_build_settings())
		col.add_child(b)
	chip.call("MAP   %d × %d" % [GameSettings.MAP_SIZES[_map_i], GameSettings.MAP_SIZES[_map_i]],
		func() -> void: _map_i = (_map_i + 1) % GameSettings.MAP_SIZES.size())
	chip.call("HERO RANGE   " + MatchSetup.range_label(MatchSetup.RANGE_DELTAS[_range_i]).to_upper(),
		func() -> void: _range_i = (_range_i + 1) % MatchSetup.RANGE_DELTAS.size())
	chip.call("STAGES & CORES   " + ("PLACED BY THE PLAYERS" if _manual else "PLACED AT RANDOM"),
		func() -> void: _manual = not _manual)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func _engine_deck(saved: Dictionary, who: String, loadout: Loadout = null) -> Dictionary:
	var deck: Dictionary = saved if not saved.is_empty() else DeckCode.random_deck(db.catalog, _rng)
	return MatchLaunch.engine_deck(db.catalog, deck, who, _rng, loadout)


## Room view: the host sees the settings and the bot row, a guest the Ready button.
func _enter_room(as_host: bool) -> void:
	_front.visible = false
	_room.visible = true
	_host_bits.visible = as_host
	_bot_row.visible = as_host
	_address_row.visible = as_host
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
	var s: MatchSettings = host.settings
	_map_i = maxi(0, GameSettings.MAP_SIZES.find(s.map_size))
	_range_i = maxi(0, MatchSetup.RANGE_DELTAS.find(s.range_delta))
	_manual = s.manual_setup
	_build_settings()
	_address_label.text = "%s  ·  PORT %d" % [", ".join(_my_addresses()), NetProtocol.DEFAULT_PORT]
	_enter_room(true)


func _push_settings() -> void:
	if host == null:
		return
	var s: MatchSettings = MatchSettings.standard()
	s.map_size = GameSettings.MAP_SIZES[_map_i]
	s.range_delta = MatchSetup.RANGE_DELTAS[_range_i]
	s.manual_setup = _manual
	GameSettings.set_map_size(s.map_size)
	host.set_settings(s)


func _my_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.begins_with("100."):
			out.append(a)
	return out if not out.is_empty() else PackedStringArray(["(no Tailscale address found)"])


func _start() -> void:
	if host == null:
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

func _send_deck() -> void:
	var problems: PackedStringArray = _card.problems()
	_ready_btn.disabled = not problems.is_empty()
	var saved: Dictionary = _card.saved_deck()
	if problems.is_empty():
		_card.loadout.remember("online")
		GameSettings.set_last_deck("online", "" if saved.is_empty() else str(saved["name"]))
	var deck: Dictionary = _engine_deck(saved, GameSettings.player_name(), _card.loadout) if problems.is_empty() else {}
	if host != null:
		host.set_my_deck(deck)
	elif client != null:
		if not problems.is_empty() and _ready_btn.button_pressed:
			_ready_btn.button_pressed = false
		client.send_deck(deck)


func _refresh() -> void:
	for c: Node in _players.get_children():
		c.queue_free()
	var seats: Array = host.public_seats() if host != null else (client.players if client != null else [])
	var my_slot: int = host.host_slot if host != null else (client.slot if client != null else -1)
	for s: Variant in seats:
		var d: Dictionary = JsonUtil.as_dict(s)
		var slot: int = JsonUtil.as_int(d.get("slot", 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_players.add_child(row)
		var who: String = str(d.get("name", "")).to_upper() + ("  (YOU)" if slot == my_slot else "")
		row.add_child(UiShape.chip(who, Palette.team(slot), Palette.FG, 20, 34.0, 16.0))
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(gap)
		var tag: String = ""
		var tag_bg: Color = Palette.SURFACE_2
		var tag_fg: Color = Palette.MUTED
		if JsonUtil.as_bool(d.get("bot", false)):
			tag = "BOT"
		elif slot == 0:
			tag = "HOST"
		elif JsonUtil.as_bool(d.get("ready", false)):
			tag = "READY"
			tag_bg = Palette.GOLD
			tag_fg = Color.BLACK
		else:
			tag = "NOT READY"
		if not JsonUtil.as_bool(d.get("connected", true)):
			tag = "AWAY"
		if not JsonUtil.as_bool(d.get("has_deck", false)):
			row.add_child(UiShape.chip("NO DECK", Palette.ACCENT_DEEP, Palette.FG, 14, 26.0, 10.0))
		row.add_child(UiShape.chip(tag, tag_bg, tag_fg, 14, 26.0, 10.0))
	if seats.size() < NetHost.MAX_SEATS:
		var wait := UiTheme.label("WAITING FOR A PLAYER…", 20, Palette.DIM)
		_players.add_child(wait)
	var settings: MatchSettings = host.settings if host != null else MatchSettings.from_dict(client.settings if client != null else {})
	_settings_text.text = _describe(settings)
	_settings_text.visible = host == null
	if host != null:
		_refresh_bot_row()
		var why: String = host.can_start()
		_start_btn.disabled = not why.is_empty()
		_start_btn.tooltip_text = why
		_start_btn.text = "START MATCH" if why.is_empty() else why.to_upper()
		_start_btn.add_theme_font_size_override("font_size", 40 if why.is_empty() else 22)


## Host: fill the empty seat with a bot (Easy / Hard), or free it again.
func _refresh_bot_row() -> void:
	for c: Node in _bot_row.get_children():
		c.queue_free()
	if host.has_bot():
		var rm := Button.new()
		rm.text = "REMOVE THE BOT"
		rm.pressed.connect(func() -> void: host.remove_bots())
		_bot_row.add_child(rm)
		return
	if host.seats.size() >= NetHost.MAX_SEATS:
		return
	_bot_row.add_child(UiTheme.label("OR PLAY A BOT", 16, Palette.MUTED))
	for hard: bool in [false, true]:
		var b := Button.new()
		b.text = "BOT · HARD" if hard else "BOT · EASY"
		b.tooltip_text = "Fill the other seat with a bot instead of waiting for a player"
		b.pressed.connect(func() -> void:
			var why: String = host.add_bot(Bot.level_name(Bot.Level.HARD if hard else Bot.Level.EASY), _engine_deck({}, "Bot"))
			if not why.is_empty():
				_status.text = why)
		_bot_row.add_child(b)


static func _describe(s: MatchSettings) -> String:
	var setup: String = "stages and cores placed by the players" if s.manual_setup else "stages and cores placed at random"
	return "%d × %d map  ·  range: %s  ·  %s" % [s.map_size, s.map_size, MatchSetup.range_label(s.range_delta).to_lower(), setup]


func _back() -> void:
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
