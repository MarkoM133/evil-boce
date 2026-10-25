extends Control
## Online lobby (GDD 7, step 3): host a match on this computer or join one over Tailscale.
## The host picks a deck, waits for the others (or adds a bot) and starts; a guest picks a deck
## and presses Ready. The NetHost / NetClient node moves to the root so the match scene keeps it.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
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
var _front: Control
var _room: Control
var _start_btn: Button
var _ready_btn: Button
var _bot_level: OptionButton


func _ready() -> void:
	theme = UiTheme.get_theme()
	_rng.randomize()
	db = CardDb.load_from(GameSettings.data_path())
	decks = DeckStore.load_all(db.root_dir)
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
	col.custom_minimum_size = Vector2(520, 0)
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
	row.add_child(_address)
	var join_btn := Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_join)
	row.add_child(join_btn)

	# Connected: seats, deck, bots, start / ready.
	_room = VBoxContainer.new()
	_room.add_theme_constant_override("separation", 10)
	_room.visible = false
	col.add_child(_room)
	_header(_room, "PLAYERS")
	_players = VBoxContainer.new()
	_room.add_child(_players)
	_header(_room, "YOUR DECK")
	_deck_pick = OptionButton.new()
	_deck_pick.add_item(RANDOM)
	for d: Dictionary in decks:
		_deck_pick.add_item(str(d["name"]))
	_deck_pick.item_selected.connect(func(_i: int) -> void: _send_deck())
	_room.add_child(_deck_pick)
	var bots := HBoxContainer.new()
	bots.add_theme_constant_override("separation", 8)
	_room.add_child(bots)
	_bot_level = OptionButton.new()
	_bot_level.add_item("Easy")
	_bot_level.add_item("Hard")
	bots.add_child(_bot_level)
	var add_bot := Button.new()
	add_bot.text = "Add a bot"
	add_bot.pressed.connect(func() -> void:
		if host != null:
			var why: String = host.add_bot(Bot.level_name(Bot.Level.HARD if _bot_level.selected == 1 else Bot.Level.EASY), _engine_deck(RANDOM, "Bot"))
			if not why.is_empty():
				_status.text = why)
	bots.add_child(add_bot)
	_ready_btn = Button.new()
	_ready_btn.text = "Ready"
	_ready_btn.toggle_mode = true
	_ready_btn.toggled.connect(func(on: bool) -> void: if client != null: client.send_ready(on))
	_room.add_child(_ready_btn)
	_start_btn = Button.new()
	_start_btn.text = "Start match"
	_start_btn.pressed.connect(_start)
	_room.add_child(_start_btn)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_back)
	col.add_child(back)
	if not db.is_ok():
		_status.text = db.error


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Header"
	parent.add_child(l)


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


func _engine_deck(pick: String, who: String) -> Dictionary:
	var deck: Dictionary = DeckCode.random_deck(db.catalog, _rng)
	for d: Dictionary in decks:
		if str(d["name"]) == pick:
			deck = d
	return MatchLaunch.engine_deck(db.catalog, deck, who, _rng)


# --- host -------------------------------------------------------------------------------

func _host() -> void:
	GameSettings.set_player_name(_name.text)
	host = NetHost.new(RulesEngine.new(db.catalog), GameSettings.player_name(), _version(), db.version)
	host.name = "NetHost"
	host.settings = MatchSettings.standard()
	host.settings.map_size = GameSettings.map_size()
	var err: String = host.listen()
	if not err.is_empty():
		_status.text = err
		host.queue_free()
		host = null
		return
	get_tree().root.add_child(host)
	host.lobby_changed.connect(_refresh)
	_status.text = "Hosting. Others join with your Tailscale address: %s" % ", ".join(_my_addresses())
	_front.visible = false
	_room.visible = true
	_ready_btn.visible = false
	_send_deck()
	_refresh()


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
	GameSettings.set_player_name(_name.text)
	GameSettings.set_last_host(_address.text)
	client = NetClient.new(GameSettings.player_name(), _version(), db.version)
	client.name = "NetClient"
	var err: String = client.connect_to(_address.text.strip_edges())
	if not err.is_empty():
		_status.text = err
		client.queue_free()
		client = null
		return
	get_tree().root.add_child(client)
	client.welcomed.connect(func(_slot: int) -> void:
		_status.text = "Connected. Pick a deck and press Ready."
		_front.visible = false
		_room.visible = true
		_start_btn.visible = false
		_send_deck()
		_refresh())
	client.rejected.connect(func(why: String) -> void:
		_status.text = "Rejected: " + why
		_drop_client())
	client.disconnected.connect(func(why: String) -> void:
		_status.text = why
		_drop_client())
	client.lobby_changed.connect(func(_p: Array, _s: Dictionary) -> void: _refresh())
	# The match scene needs a state to draw: go when the first one after START is in.
	client.state_received.connect(func(_s: GameState) -> void:
		if client.started and get_tree().current_scene == self:
			MatchLaunch.config = {"net": {"role": "client", "node": client}, "settings": MatchSettings.from_dict(client.settings), "decks": [], "bots": PackedInt32Array(), "seed": 0}
			get_tree().change_scene_to_file(MATCH_SCENE))
	_status.text = "Connecting to %s…" % _address.text


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
	var deck: Dictionary = _engine_deck(pick, GameSettings.player_name())
	if host != null:
		host.set_my_deck(deck)
	elif client != null:
		client.send_deck(deck)


func _refresh() -> void:
	for c: Node in _players.get_children():
		c.queue_free()
	var seats: Array = host.public_seats() if host != null else (client.players if client != null else [])
	for s: Variant in seats:
		var d: Dictionary = JsonUtil.as_dict(s)
		var l := Label.new()
		var bits := PackedStringArray()
		bits.append("deck" if JsonUtil.as_bool(d.get("has_deck", false)) else "no deck")
		if JsonUtil.as_bool(d.get("bot", false)):
			bits.append("bot")
		elif JsonUtil.as_bool(d.get("ready", false)):
			bits.append("ready")
		if not JsonUtil.as_bool(d.get("connected", true)):
			bits.append("away")
		l.text = "%d. %s  ·  %s" % [JsonUtil.as_int(d.get("slot", 0)) + 1, str(d.get("name", "")), ", ".join(bits)]
		_players.add_child(l)
	if host != null:
		var why: String = host.can_start()
		_start_btn.disabled = not why.is_empty()
		_start_btn.tooltip_text = why


func _back() -> void:
	if host != null:
		host.link.close()
		host.queue_free()
	if client != null:
		client.link.close()
		client.queue_free()
	get_tree().change_scene_to_file(MENU_SCENE)
