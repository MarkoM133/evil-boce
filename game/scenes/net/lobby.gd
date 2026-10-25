extends Control
## Online lobby (GDD 7, step 3): host a match on this computer or join one over Tailscale.
## The host picks the match settings and a deck, waits for the other player (or adds a bot) and
## starts; a guest picks a deck and presses Ready. The NetHost / NetClient node lives under the
## root so the match scene keeps it, and after a match the host brings everyone back here.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const MatchSetup = preload("res://scenes/match/match_setup.gd")
const RANDOM: String = "Random deck"

var db: CardDb
var decks: Array[Dictionary] = []
var host: NetHost
var client: NetClient
var _rng := RandomNumberGenerator.new()

var _name: LineEdit
var _address: LineEdit
var _status: Label
var _players: VBoxContainer
var _deck_pick: OptionButton
var _deck_problems: Label
var _loadout: LoadoutPicker
var _front: Control
var _room: Control
var _host_bits: Control
var _address_row: Control
var _address_label: Label
var _map: OptionButton
var _range: OptionButton
var _setup_mode: OptionButton
var _settings_text: Label
var _start_btn: Button
var _ready_btn: Button
var _bot_level: OptionButton
var _bot_btn: Button


func _ready() -> void:
	theme = UiTheme.get_theme()
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
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(540, 0)
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "ONLINE"
	title.theme_type_variation = &"Big"
	col.add_child(title)
	_status = Label.new()
	_status.theme_type_variation = &"Muted"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	# Before connecting: name, host or join.
	_front = VBoxContainer.new()
	_front.add_theme_constant_override("separation", 10)
	col.add_child(_front)
	_header(_front, "YOUR NAME")
	_name = LineEdit.new()
	_name.text = GameSettings.player_name()
	_name.max_length = 24
	_front.add_child(_name)
	_header(_front, "HOST")
	var host_btn := Button.new()
	host_btn.text = "Host a match on this computer (port %d)" % NetProtocol.DEFAULT_PORT
	host_btn.pressed.connect(_host)
	_front.add_child(host_btn)
	_header(_front, "JOIN")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_front.add_child(row)
	_address = LineEdit.new()
	_address.placeholder_text = "host's Tailscale address, e.g. 100.64.1.2"
	_address.text = GameSettings.last_host()
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text_submitted.connect(func(_t: String) -> void: _join())
	row.add_child(_address)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_join)
	row.add_child(join_btn)

	# Connected: address, seats, match settings, deck, bots, start / ready.
	_room = VBoxContainer.new()
	_room.add_theme_constant_override("separation", 10)
	_room.visible = false
	col.add_child(_room)
	_address_row = HBoxContainer.new()
	_address_row.add_theme_constant_override("separation", 8)
	_room.add_child(_address_row)
	_address_label = Label.new()
	_address_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_row.add_child(_address_label)
	var copy := Button.new()
	copy.text = "Copy"
	copy.tooltip_text = "Copy the address to send it to the other player"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_my_addresses()[0])
		_status.text = "Address copied.")
	_address_row.add_child(copy)

	_header(_room, "PLAYERS")
	_players = VBoxContainer.new()
	_room.add_child(_players)

	_header(_room, "MATCH")
	_settings_text = Label.new()
	_settings_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room.add_child(_settings_text)
	_host_bits = VBoxContainer.new()
	_host_bits.add_theme_constant_override("separation", 8)
	_room.add_child(_host_bits)
	_map = OptionButton.new()
	for n: int in GameSettings.MAP_SIZES:
		_map.add_item("%d × %d" % [n, n], n)
	_map.select(GameSettings.MAP_SIZES.find(MatchSettings.standard().map_size))
	_map.item_selected.connect(func(_i: int) -> void: _push_settings())
	_host_bits.add_child(_map)
	_range = OptionButton.new()
	for d: int in MatchSetup.RANGE_DELTAS:
		_range.add_item(MatchSetup.range_label(d), d + 10)
	_range.select(MatchSetup.RANGE_DELTAS.find(MatchSettings.standard().range_delta))
	_range.item_selected.connect(func(_i: int) -> void: _push_settings())
	_host_bits.add_child(_range)
	_setup_mode = OptionButton.new()
	_setup_mode.add_item("Stages and cores placed by the players in turn  ·  Standard")
	_setup_mode.add_item("Stages and cores placed at random")
	_setup_mode.item_selected.connect(func(_i: int) -> void: _push_settings())
	_host_bits.add_child(_setup_mode)
	var bots := HBoxContainer.new()
	bots.add_theme_constant_override("separation", 8)
	_host_bits.add_child(bots)
	_bot_level = OptionButton.new()
	_bot_level.add_item("Bot · Easy")
	_bot_level.add_item("Bot · Hard")
	bots.add_child(_bot_level)
	_bot_btn = Button.new()
	_bot_btn.text = "Add a bot"
	_bot_btn.tooltip_text = "Fill the other seat with a bot instead of waiting for a player"
	_bot_btn.pressed.connect(func() -> void:
		if host == null:
			return
		if host.has_bot():
			host.remove_bots()
			return
		var level: Bot.Level = Bot.Level.HARD if _bot_level.selected == 1 else Bot.Level.EASY
		var why: String = host.add_bot(Bot.level_name(level), _engine_deck(RANDOM, "Bot"))
		if not why.is_empty():
			_status.text = why)
	bots.add_child(_bot_btn)

	_header(_room, "YOUR DECK")
	_deck_pick = OptionButton.new()
	_deck_pick.add_item(RANDOM)
	for d: Dictionary in decks:
		_deck_pick.add_item(str(d["name"]))
	_deck_pick.item_selected.connect(func(_i: int) -> void: _send_deck())
	_room.add_child(_deck_pick)
	_loadout = LoadoutPicker.new()
	_loadout.setup(db.catalog, Loadout.remembered("online"), "Your stages and cores")
	_loadout.changed.connect(_send_deck)
	_room.add_child(_loadout)
	_deck_problems = Label.new()
	_deck_problems.theme_type_variation = &"Muted"
	_deck_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room.add_child(_deck_problems)
	_ready_btn = Button.new()
	_ready_btn.text = "Ready"
	_ready_btn.toggle_mode = true
	_ready_btn.toggled.connect(func(on: bool) -> void:
		_ready_btn.text = "Ready ✓" if on else "Ready"
		if client != null:
			client.send_ready(on))
	_room.add_child(_ready_btn)
	_start_btn = Button.new()
	_start_btn.text = "Start match"
	_start_btn.theme_type_variation = &"Primary"
	_start_btn.pressed.connect(_start)
	_room.add_child(_start_btn)

	var back := Button.new()
	back.text = "Leave"
	back.pressed.connect(_back)
	col.add_child(back)


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Header"
	parent.add_child(l)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func _picked_deck(pick: String) -> Dictionary:
	for d: Dictionary in decks:
		if str(d["name"]) == pick:
			return d
	return {}


func _engine_deck(pick: String, who: String, loadout: Loadout = null) -> Dictionary:
	var deck: Dictionary = _picked_deck(pick)
	if deck.is_empty():
		deck = DeckCode.random_deck(db.catalog, _rng)
	return MatchLaunch.engine_deck(db.catalog, deck, who, _rng, loadout)


## Room view: the host sees the settings and the bot row, a guest the Ready button.
func _enter_room(as_host: bool) -> void:
	_front.visible = false
	_room.visible = true
	_host_bits.visible = as_host
	_address_row.visible = as_host
	_start_btn.visible = as_host
	_ready_btn.visible = not as_host
	_ready_btn.set_pressed_no_signal(false)
	_ready_btn.text = "Ready"
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
	_map.select(maxi(0, GameSettings.MAP_SIZES.find(s.map_size)))
	_range.select(maxi(0, MatchSetup.RANGE_DELTAS.find(s.range_delta)))
	_setup_mode.select(0 if s.manual_setup else 1)
	_address_label.text = "Your address:  %s  ·  port %d" % [", ".join(_my_addresses()), NetProtocol.DEFAULT_PORT]
	_enter_room(true)


func _push_settings() -> void:
	if host == null:
		return
	var s: MatchSettings = MatchSettings.standard()
	s.map_size = _map.get_selected_id()
	s.range_delta = _range.get_selected_id() - 10
	s.manual_setup = _setup_mode.selected == 0
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
			_ready_btn.text = "Ready"
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
	var pick: String = _deck_pick.get_item_text(_deck_pick.selected)
	var saved: Dictionary = _picked_deck(pick)
	var problems := PackedStringArray()
	if not saved.is_empty():
		problems = DeckCode.check(db.catalog, JsonUtil.as_strings(saved["heroes"]), JsonUtil.as_dict(saved["cards"]))
	var text: String = ("This deck breaks the deck rules: " + "; ".join(problems)) if not problems.is_empty() else ""
	# Stages and cores: the picker shows its own problems; they also hold the deck back.
	problems.append_array(_loadout.problems())
	_deck_problems.text = text
	_deck_problems.visible = not text.is_empty()
	_ready_btn.disabled = not problems.is_empty()
	if problems.is_empty():
		_loadout.loadout.remember("online")
	var deck: Dictionary = _engine_deck(pick, GameSettings.player_name(), _loadout.loadout) if problems.is_empty() else {}
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
		var bits := PackedStringArray()
		bits.append("deck" if JsonUtil.as_bool(d.get("has_deck", false)) else "no deck yet")
		if JsonUtil.as_bool(d.get("bot", false)):
			bits.append("bot")
		elif slot == 0:
			bits.append("host")
		else:
			bits.append("ready" if JsonUtil.as_bool(d.get("ready", false)) else "not ready")
		if not JsonUtil.as_bool(d.get("connected", true)):
			bits.append("away")
		var l := Label.new()
		l.text = "%d. %s%s  ·  %s" % [slot + 1, str(d.get("name", "")), "  (you)" if slot == my_slot else "", ", ".join(bits)]
		l.add_theme_color_override("font_color", Palette.team(slot))
		_players.add_child(l)
	if seats.size() < NetHost.MAX_SEATS:
		var wait := Label.new()
		wait.text = "Waiting for a player…"
		wait.theme_type_variation = &"Muted"
		_players.add_child(wait)
	var settings: MatchSettings = host.settings if host != null else MatchSettings.from_dict(client.settings if client != null else {})
	_settings_text.text = _describe(settings)
	_settings_text.visible = host == null
	if host != null:
		_bot_btn.text = "Remove the bot" if host.has_bot() else "Add a bot"
		_bot_level.disabled = host.has_bot()
		var why: String = host.can_start()
		_start_btn.disabled = not why.is_empty()
		_start_btn.text = "Start match" if why.is_empty() else "Start match  ·  %s" % why


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
		host.add_bot("hard", _engine_deck(RANDOM, "Bot"))
