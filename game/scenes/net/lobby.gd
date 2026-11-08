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
const REPLAYS_SCENE: String = "res://scenes/replays/replays_menu.tscn"

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
## The room fits under its title without scrolling with heroes this tall.
const ROOM_PORTRAIT_H: float = 224.0

var _card: PlayerCard
var _opp: PlayerCard
var _wait: PanelContainer
var _series: Label
var _join_btn: Button
var _address_join: Button
var _recent_box: VBoxContainer
## Nobody joined yet: the hint shows and the address field moves up under the title.
var _join_hint: Label
var _join_gap: Control
var _address_title: Label
var _matches_box: VBoxContainer
## Where the last JOIN went (remembered with the host's name once it answers).
var _joining: String = ""
## READY over the other player's card, in the style of CLAIMED.
var _ready_stamp: UiShape
## Under JOIN: connecting, or why it failed (Marko 2026-11-07: by the button, not at the top).
var _join_status: Label
var _join_tween: Tween
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
		_status.text = ""
	elif c is NetClient:
		client = c
		_wire_client()
		_enter_room(false)
		_status.text = ""


func _build() -> void:
	var frame: Dictionary = MenuScreen.build(self, db, "Online", "One hosts, the other joins.", _back, 1300.0)
	var content: VBoxContainer = frame["content"]
	_status = Label.new()
	_status.add_theme_color_override("font_color", Palette.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)

	# Before connecting: your name, then two big cards (Marko 2026-11-08, from the mockups).
	_front = VBoxContainer.new()
	_front.add_theme_constant_override("separation", 14)
	content.add_child(_front)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	_front.add_child(name_row)
	name_row.add_child(UiTheme.label("PLAYING AS", 18, Palette.GOLD))
	_name = LineEdit.new()
	_name.text = GameSettings.player_name()
	_name.max_length = 24
	_name.custom_minimum_size = Vector2(300, 0)
	_name.add_theme_font_size_override("font_size", 22)
	name_row.add_child(_name)
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 18)
	_front.add_child(pair)
	var host_card: VBoxContainer = MenuScreen.card(pair, 34, true)
	host_card.custom_minimum_size.y = 520
	host_card.add_theme_constant_override("separation", 16)
	host_card.add_child(UiTheme.label("HOST", 56))
	host_card.add_child(UiTheme.label("YOUR ADDRESS", 15, Palette.GOLD))
	var addr_line := HBoxContainer.new()
	addr_line.add_theme_constant_override("separation", 14)
	host_card.add_child(addr_line)
	var my_addr: String = _my_addresses()[0]
	var addr_l: Label = UiTheme.label(my_addr, 38 if not my_addr.begins_with("(") else 22, Palette.GOLD)
	addr_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_line.add_child(addr_l)
	var addr_copy := Button.new()
	addr_copy.text = "COPY"
	addr_copy.disabled = my_addr.begins_with("(")
	addr_copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	addr_copy.add_theme_font_size_override("font_size", 22)
	addr_copy.pressed.connect(func() -> void: _copy_address(addr_copy, "COPY"))
	addr_line.add_child(addr_copy)
	var host_btn := Button.new()
	host_btn.text = "HOST A MATCH"
	host_btn.theme_type_variation = &"Primary"
	host_btn.add_theme_font_size_override("font_size", 44)
	host_btn.pressed.connect(_host)
	host_card.add_child(host_btn)
	_matches_box = VBoxContainer.new()
	_matches_box.add_theme_constant_override("separation", 10)
	host_card.add_child(_matches_box)
	_fill_matches()
	var join_card: VBoxContainer = MenuScreen.card(pair, 34, true)
	join_card.add_theme_constant_override("separation", 16)
	join_card.add_child(UiTheme.label("JOIN", 56))
	_recent_box = VBoxContainer.new()
	_recent_box.add_theme_constant_override("separation", 12)
	join_card.add_child(_recent_box)
	_join_hint = _muted("Ask your friend for their address.", 20)
	join_card.add_child(_join_hint)
	_join_gap = Control.new()
	_join_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	join_card.add_child(_join_gap)
	_address_title = UiTheme.label("ANOTHER ADDRESS", 15, Palette.GOLD)
	join_card.add_child(_address_title)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	join_card.add_child(join_row)
	_address = LineEdit.new()
	_address.placeholder_text = "their address"
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.add_theme_font_size_override("font_size", 22)
	_address.text_submitted.connect(func(_t: String) -> void: _join())
	join_row.add_child(_address)
	_address_join = Button.new()
	_address_join.text = "JOIN"
	_address_join.theme_type_variation = &"Gold"
	_address_join.add_theme_font_size_override("font_size", 26)
	_address_join.pressed.connect(func() -> void:
		_join_btn = _address_join
		_join())
	join_row.add_child(_address_join)
	_join_btn = _address_join
	_join_status = Label.new()
	_join_status.add_theme_color_override("font_color", Palette.GOLD)
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_status.visible = false
	join_card.add_child(_join_status)
	var watch_btn := Button.new()
	watch_btn.text = "WATCH INSTEAD"
	watch_btn.flat = true
	watch_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	watch_btn.tooltip_text = "Join as a spectator: see the match with both hands hidden"
	watch_btn.add_theme_font_size_override("font_size", 15)
	watch_btn.pressed.connect(func() -> void:
		_join_btn = _address_join
		_join(true))
	join_card.add_child(watch_btn)
	_fill_recent()

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
	_card.portrait_h = ROOM_PORTRAIT_H
	vs_row.add_child(_card)
	_card.setup(db, decks, GameSettings.player_name(), 0, GameSettings.last_deck("online"), Loadout.remembered("online"))
	_card.restore_random(GameSettings.random_deck("online"))
	_card.changed.connect(_send_deck)
	var vs: Label = UiTheme.label("VS", 64, Palette.ACCENT)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vs.add_theme_color_override("font_outline_color", Color.BLACK)
	vs.add_theme_constant_override("outline_size", 8)
	vs_row.add_child(vs)
	_opp = PlayerCard.new()
	_opp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opp.portrait_h = ROOM_PORTRAIT_H
	vs_row.add_child(_opp)
	_opp.setup(db, decks, "Opponent", 1, "", Loadout.new())
	_opp.show_only({})
	var opp_layer := Control.new()
	opp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opp.add_child(opp_layer)
	_ready_stamp = UiShape.chip("READY", Palette.GOLD, Color.BLACK, 76, 108.0, 34.0)
	_ready_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_stamp.pivot_offset = _ready_stamp.custom_minimum_size * 0.5
	_ready_stamp.rotation_degrees = -8.0
	_ready_stamp.visible = false
	opp_layer.add_child(_ready_stamp)
	var place_stamp := func() -> void: _ready_stamp.position = (opp_layer.size - _ready_stamp.custom_minimum_size) * 0.5
	opp_layer.resized.connect(place_stamp)
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
	col.add_theme_constant_override("separation", 18)
	_wait.add_child(col)
	col.add_child(UiTheme.label("WAITING FOR A PLAYER…", 40, Palette.FG))
	_wait_host = VBoxContainer.new()
	_wait_host.add_theme_constant_override("separation", 8)
	col.add_child(_wait_host)
	_wait_host.add_theme_constant_override("separation", 18)
	_wait_host.add_child(_muted("Send them this address. They press JOIN and paste it.", 19))
	_address_label = UiTheme.label("", 64, Palette.GOLD)
	_address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wait_host.add_child(_address_label)
	var copy := Button.new()
	copy.text = "COPY ADDRESS"
	copy.theme_type_variation = &"Gold"
	copy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	copy.add_theme_font_size_override("font_size", 30)
	copy.tooltip_text = "Copy the address to send it to the other player"
	copy.pressed.connect(func() -> void: _copy_address(copy, "COPY ADDRESS"))
	_wait_host.add_child(copy)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_wait_host.add_child(gap)
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 10)
	_wait_host.add_child(low)
	var nobody: Label = _muted("Nobody around?", 16)
	nobody.autowrap_mode = TextServer.AUTOWRAP_OFF
	nobody.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	low.add_child(nobody)
	_bot_row = HBoxContainer.new()
	_bot_row.add_theme_constant_override("separation", 8)
	low.add_child(_bot_row)
	for hard: bool in [false, true]:
		var b := Button.new()
		b.text = "BOT · HARD" if hard else "PLAY A BOT · EASY"
		b.theme_type_variation = &"Ghost"
		b.add_theme_font_size_override("font_size", 16)
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
	# Over 40 only a random deck grows (Marko 2026-10-30); a saved deck plays its 40.
	if saved.is_empty() and _rules != null and _rules.settings.deck_size > DeckCode.DECK_SIZE:
		deck = DeckCode.fill_deck(db.catalog, deck, _rules.settings.deck_size, _rng)
	return MatchLaunch.engine_deck(db.catalog, deck, who, _rng, loadout)


## Room view: the host changes the rules and starts, a guest sees the rules and gets Ready.
func _enter_room(as_host: bool) -> void:
	_front.visible = false
	_room.visible = true
	_wait_host.visible = as_host
	_rules.set_editable(as_host)
	_start_btn.visible = as_host
	_ready_btn.visible = not as_host and not _watching()
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
	_status.text = ""


## Opens the table with the saved online match and goes straight to it; it waits paused for the others.
func _host_resume(record: MatchRecord) -> void:
	GameSettings.set_player_name(_name.text)
	host = NetHost.new(RulesEngine.new(record.catalog()), GameSettings.player_name(), _version(), db.version)
	host.name = "NetHost"
	var err: String = host.listen()
	if err.is_empty():
		err = host.resume_match(record)
	if not err.is_empty():
		_status.text = err
		host.link.close()
		host.free()
		host = null
		return
	get_tree().root.add_child(host)
	MatchLaunch.config = {"net": {"role": "host", "node": host}, "settings": host.settings, "decks": [], "bots": PackedInt32Array(), "seed": 0}
	get_tree().change_scene_to_file(MATCH_SCENE)


func _muted(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.MUTED)
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## One slanted row: a big line, a small line and what goes at its end.
func _row(parent: Control, big: String, small: String) -> HBoxContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiTheme.slant(Palette.SURFACE_2, 22, 10))
	parent.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(names)
	names.add_child(UiTheme.label(big, 28))
	names.add_child(_muted(small, 15))
	return h


## Copies this computer's address; the button says so for a moment.
func _copy_address(button: Button, idle: String) -> void:
	DisplayServer.clipboard_set(_my_addresses()[0])
	button.text = "COPIED"
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(button):
			button.text = idle)


## The HOST card's list (Marko 2026-11-08), three rows at most: the saved online match first
## (CONTINUE opens the table, DISCARD forgets it), then the last matches against someone (WATCH).
func _fill_matches() -> void:
	for c: Node in _matches_box.get_children():
		_matches_box.remove_child(c)
		c.queue_free()
	var me: String = GameSettings.player_name()
	var saved: MatchRecord = ReplayStore.load_current_online()
	var has_saved: bool = saved != null and saved.frame_count() > 0 and not saved.finished and saved.game_version == _version()
	var played: Array[Dictionary] = ReplayStore.recent_against_someone(me, 2 if has_saved else 3)
	_matches_box.add_child(UiTheme.label("RECENT MATCHES", 15, Palette.GOLD))
	if not has_saved and played.is_empty():
		_matches_box.add_child(_muted("Your matches will show here.", 18))
		return
	if has_saved:
		var others := PackedStringArray()
		for p: Dictionary in saved.players:
			if str(p.get("name", "")) != me:
				others.append(str(p.get("name", "")).to_upper())
		var last: GameState = saved.state_at(saved.frame_count() - 1)
		var when: String = ("Turn %d" % last.turn) if last != null and last.turn > 0 else "Setup"
		var h: HBoxContainer = _row(_matches_box, "VS " + " + ".join(others), "%s  ·  waiting where you left it" % when)
		_row_chip(h, "SAVED", Palette.SURFACE_2.lightened(0.15), Palette.FG)
		var cont := Button.new()
		cont.text = "CONTINUE"
		cont.theme_type_variation = &"Gold"
		cont.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cont.add_theme_font_size_override("font_size", 20)
		cont.pressed.connect(func() -> void: _host_resume(saved))
		h.add_child(cont)
		var drop := Button.new()
		drop.text = "DISCARD"
		drop.theme_type_variation = &"Ghost"
		drop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		drop.add_theme_font_size_override("font_size", 14)
		drop.tooltip_text = "Forget this match"
		drop.pressed.connect(func() -> void:
			ReplayStore.clear_current_online()
			_fill_matches())
		h.add_child(drop)
	var now: int = int(Time.get_unix_time_from_system())
	var why: Dictionary = {"ko": "All heroes KO", "stages": "Stages claimed", "stages_energy": "More energy", "surrender": "Surrender", "draw": "Draw"}
	for m: Dictionary in played:
		var names: PackedStringArray = JsonUtil.as_strings(m.get("names", []))
		var mine: int = names.find(me)
		var at: int = Time.get_unix_time_from_datetime_string(str(m.get("created", "")).trim_suffix("Z"))
		var result: String = str(m.get("result", ""))
		var h: HBoxContainer = _row(_matches_box, "VS " + names[1 - mine].to_upper(),
			"%s  ·  turn %d  ·  %s" % [str(why.get(result, result.capitalize())), JsonUtil.as_int(m.get("turns", 0)), GameSettings.ago_text(now - at)])
		var winner: int = JsonUtil.as_int(m.get("winner", -1), -1)
		if winner < 0:
			_row_chip(h, "DRAW", Palette.SURFACE_2.lightened(0.15), Palette.FG)
		elif winner == mine:
			_row_chip(h, "WIN", Palette.GOLD, Color.BLACK)
		else:
			_row_chip(h, "LOSS", Palette.ACCENT_DEEP, Palette.FG)
		var watch := Button.new()
		watch.text = "WATCH"
		watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		watch.add_theme_font_size_override("font_size", 20)
		var path: String = str(m["path"])
		watch.pressed.connect(func() -> void: _watch_replay(path))
		h.add_child(watch)


func _row_chip(h: HBoxContainer, text: String, col: Color, fg: Color) -> void:
	var chip: UiShape = UiShape.chip(text, col, fg, 15, 26.0, 10.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	h.move_child(chip, 0)


func _watch_replay(path: String) -> void:
	var record: MatchRecord = ReplayStore.load_record(path)
	if record == null or record.frame_count() == 0:
		_status.text = "That replay could not be read."
		return
	MatchLaunch.config = MatchLaunch.from_record(record, 0, true)
	get_tree().change_scene_to_file(MATCH_SCENE)


## The hosts joined before, one click each; none yet: the last address (from before this list) waits in the field.
func _fill_recent() -> void:
	for c: Node in _recent_box.get_children():
		c.queue_free()
	var recent: Array = GameSettings.recent_hosts()
	_recent_box.visible = not recent.is_empty()
	_address.text = "" if not recent.is_empty() else GameSettings.last_host()
	_join_hint.visible = recent.is_empty()
	_address_title.text = "ANOTHER ADDRESS" if not recent.is_empty() else "THEIR ADDRESS"
	var card: Node = _join_gap.get_parent()
	card.move_child(_join_gap, _join_hint.get_index() + 1 if not recent.is_empty() else card.get_child_count() - 1)
	if recent.is_empty():
		return
	_recent_box.add_child(UiTheme.label("RECENT", 15, Palette.GOLD))
	var now: int = int(Time.get_unix_time_from_system())
	for e: Variant in recent.slice(0, 3):
		var d: Dictionary = JsonUtil.as_dict(e)
		var addr: String = str(d.get("address", ""))
		var h: HBoxContainer = _row(_recent_box, str(d.get("name", "?")).to_upper(),
			"%s  ·  %s" % [addr, GameSettings.ago_text(now - JsonUtil.as_int(d.get("at", now)))])
		var b := Button.new()
		b.text = "JOIN"
		b.theme_type_variation = &"Gold"
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(func() -> void:
			_join_btn = b
			_address.text = addr
			_join())
		h.add_child(b)


## READY over the other player's card; it lands like a stamp.
func _set_ready_stamp(on: bool) -> void:
	if on == _ready_stamp.visible:
		return
	_ready_stamp.visible = on
	if on:
		_ready_stamp.scale = Vector2(1.8, 1.8)
		_ready_stamp.modulate.a = 0.0
		var t: Tween = _ready_stamp.create_tween().set_parallel(true)
		t.tween_property(_ready_stamp, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(_ready_stamp, "modulate:a", 1.0, 0.1)


func _wire_host() -> void:
	host.lobby_changed.connect(_refresh)
	_rules.set_settings(MatchSettings.from_dict(host.settings.to_dict()))
	_address_label.text = _my_addresses()[0]
	if _address_label.text.begins_with("("):
		_address_label.add_theme_font_size_override("font_size", 30)
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

func _join(spectate: bool = false) -> void:
	if client != null:
		return
	var address: String = _address.text.strip_edges()
	if address.is_empty() and spectate:
		address = GameSettings.last_host()
	if address.is_empty():
		_join_note("Type the host's Tailscale address first.")
		return
	GameSettings.set_player_name(_name.text)
	GameSettings.set_last_host(address)
	_joining = address
	client = NetClient.new(GameSettings.player_name(), _version(), db.version)
	client.name = "NetClient"
	var err: String = client.connect_to(address, NetProtocol.DEFAULT_PORT, spectate)
	if not err.is_empty():
		_join_note(err)
		client.free()
		client = null
		return
	get_tree().root.add_child(client)
	_wire_client()
	_join_note("Connecting to %s…" % address)
	_connecting(true)


## The line under JOIN ("" hides it).
func _join_note(text: String) -> void:
	_join_status.text = text
	_join_status.visible = not text.is_empty()


## JOIN while a connection is tried: CONNECTING… and a slow pulse, and it cannot be pressed again.
func _connecting(on: bool) -> void:
	if _join_tween != null and _join_tween.is_valid():
		_join_tween.kill()
	_join_btn.disabled = on
	_join_btn.text = "CONNECTING…" if on else "JOIN"
	_join_btn.modulate.a = 1.0
	if on:
		_join_tween = _join_btn.create_tween().set_loops()
		_join_tween.tween_property(_join_btn, "modulate:a", 0.45, 0.5).set_trans(Tween.TRANS_SINE)
		_join_tween.tween_property(_join_btn, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)


func _wire_client() -> void:
	client.welcomed.connect(func(_slot: int) -> void:
		_connecting(false)
		_join_note("")
		if not _joining.is_empty():
			var host_name: String = "?"
			for p: Variant in client.players:
				if JsonUtil.as_int(JsonUtil.as_dict(p).get("slot", -1)) == 0:
					host_name = str(JsonUtil.as_dict(p).get("name", "?"))
			GameSettings.remember_host(host_name, _joining, int(Time.get_unix_time_from_system()))
			_joining = ""
		_status.text = "Watching. The match starts when the host presses START." if client.spectating else ""
		_enter_room(false))
	client.move_refused.connect(func(move: Dictionary, why: String) -> void:
		if str(move.get("t", "")) == NetProtocol.DECK:
			_status.text = why)
	client.rejected.connect(func(why: String) -> void:
		_connecting(false)
		_join_note("Rejected: " + why)
		_status.text = ""
		_drop_client())
	client.disconnected.connect(func(why: String) -> void:
		_connecting(false)
		_join_note(why)
		_status.text = ""
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
	if _watching():
		return
	var problems: PackedStringArray = _card.problems()
	_ready_btn.disabled = not problems.is_empty()
	var saved: Dictionary = _card.saved_deck()
	if problems.is_empty():
		_card.loadout.remember("online")
		GameSettings.set_last_deck("online", "" if saved.is_empty() else str(saved["name"]))
		GameSettings.set_random_deck("online", _card.random_state())
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
	var watching: bool = _watching()
	for s: Variant in seats:
		var d: Dictionary = JsonUtil.as_dict(s)
		var slot: int = JsonUtil.as_int(d.get("slot", 0))
		if slot == my_slot or (watching and slot == 0):
			# A spectator sees seat 0 on the left and seat 1 on the right, both read-only.
			_card.set_header(str(d.get("name", GameSettings.player_name())), slot)
			if watching:
				_card.show_only(JsonUtil.as_dict(d.get("shown", {})))
			_tags(_card, d, not watching)
		elif other.is_empty():
			other = d
	_opp.visible = not other.is_empty()
	_wait.visible = other.is_empty()
	_set_ready_stamp(not other.is_empty() and JsonUtil.as_bool(other.get("ready", false)) \
			and not JsonUtil.as_bool(other.get("bot", false)) and JsonUtil.as_int(other.get("slot", 0)) != 0)
	if not other.is_empty():
		_opp.set_header(str(other.get("name", "")), JsonUtil.as_int(other.get("slot", 1)))
		_opp.show_only(JsonUtil.as_dict(other.get("shown", {})))
		_tags(_opp, other, false)
	# A series (Best of 3): the decks of game one stay, stages and cores are picked again.
	var sd: Dictionary = host.series.to_dict() if host != null and host.series != null else (client.series if client != null else {})
	var series: MatchSeries = MatchSeries.from_dict(sd) if not sd.is_empty() else null
	var in_series: bool = series != null and series.games > 0 and not series.is_over()
	_series.visible = in_series
	if in_series and not watching:
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
	elif not watching:
		var m: String = _rules.settings.mode
		_card.set_sideboard_mode(_rules.settings.series_wins > 1 and m != "draft" and m != "chaos")
	_rules.set_editable(host != null and not in_series)
	if host == null:
		_rules.set_settings(MatchSettings.from_dict(client.settings if client != null else {}))
	# Chaos (GDD 13): everyone plays random decks, stages and cores; a locked card is sent again.
	var locked_a: bool = not watching and _card.set_locked_random(_rules.settings.mode == "chaos")
	var locked_b: bool = not watching and _card.set_drafted(_rules.settings.mode == "draft")
	if locked_a or locked_b:
		_send_deck()
	if host != null:
		var why: String = host.can_start()
		_start_btn.disabled = not why.is_empty()
		_start_btn.tooltip_text = why
		var label: String = why.to_upper()
		for tail: String in [" IS NOT READY", " HAS NO DECK"]:
			if label.ends_with(tail):
				label = "WAITING FOR " + label.trim_suffix(tail)
		_start_btn.text = (("START GAME %d" % (series.games + 1)) if in_series else "START MATCH") if why.is_empty() else label
		_start_btn.add_theme_font_size_override("font_size", 40 if _start_btn.text.length() <= 20 else 26)


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


## Joined as a spectator (WATCH): no deck, no Ready, both seats shown read-only.
func _watching() -> bool:
	return client != null and client.spectating


## A seat's state as chips in its card header: host, bot, ready, away, no deck; the host can
## free a bot's seat from there.
func _tags(card: PlayerCard, d: Dictionary, mine: bool) -> void:
	for c: Node in card.header_extra.get_children():
		c.queue_free()
	var slot: int = JsonUtil.as_int(d.get("slot", 0))
	var bot: bool = JsonUtil.as_bool(d.get("bot", false))
	if not JsonUtil.as_bool(d.get("has_deck", false)):
		card.header_extra.add_child(UiShape.chip("NO DECK", Palette.ACCENT_DEEP, Palette.FG, 14, 26.0, 10.0))
	var tag: String = "NOT READY" if mine else "PICKING…"
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
	# The other player's READY is the stamp over their card.
	if not mine and tag == "READY":
		return
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
## Screenshot helper: JOIN with people joined before (only in memory when run with --setting=).
func demo_recent() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	GameSettings.remember_host("Luka", "100.71.3.90", now - 700000)
	GameSettings.remember_host("Marin", "100.88.12.4", now - 180000)
	_fill_recent()


## Screenshot helper: the room with the other side's READY stamp.
func demo_ready() -> void:
	demo_room()
	_set_ready_stamp(true)


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
