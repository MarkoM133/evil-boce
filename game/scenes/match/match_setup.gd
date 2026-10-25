extends Control
## Before a match: deck, stages and cores per player (saved decks from the shared folder, or
## random), who plays the second seat (bot or a second local player) and the map size.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
const RANDOM: String = "Random deck"
## Offered changes to every hero's printed range (Standard is -1, see MatchSettings.standard).
const RANGE_DELTAS: Array[int] = [-2, -1, 0, 1]

var db: CardDb
var decks: Array[Dictionary] = []
var _deck_pick: Array[OptionButton] = []
var _loadouts: Array[LoadoutPicker] = []
var _start_btn: Button
var _opponent: OptionButton
var _map: OptionButton
var _range: OptionButton
var _setup_mode: OptionButton
var _problems: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	db = CardDb.load_from(GameSettings.data_path())
	decks = DeckStore.load_all(db.root_dir)

	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var title := Label.new()
	title.text = "NEW MATCH"
	title.theme_type_variation = &"Big"
	col.add_child(title)
	if not db.is_ok():
		var err := Label.new()
		err.text = db.error
		err.add_theme_color_override("font_color", Palette.GOLD)
		col.add_child(err)

	for slot: int in 2:
		_header(col, "PLAYER %d DECK" % (slot + 1))
		var pick := OptionButton.new()
		pick.add_item(RANDOM)
		for d: Dictionary in decks:
			pick.add_item(str(d["name"]))
		pick.item_selected.connect(func(_i: int) -> void: _check())
		col.add_child(pick)
		_deck_pick.append(pick)
		var lp := LoadoutPicker.new()
		lp.setup(db.catalog, Loadout.remembered("p%d" % (slot + 1)), "Stages and cores")
		lp.changed.connect(_check)
		col.add_child(lp)
		_loadouts.append(lp)

	_header(col, "PLAYER 2 IS")
	_opponent = OptionButton.new()
	_opponent.add_item("Bot · Easy")
	_opponent.add_item("Bot · Hard")
	_opponent.add_item("Second player on this computer")
	col.add_child(_opponent)

	_header(col, "MAP")
	_map = OptionButton.new()
	for n: int in GameSettings.MAP_SIZES:
		_map.add_item("%d × %d" % [n, n], n)
	_map.select(GameSettings.MAP_SIZES.find(GameSettings.map_size()))
	col.add_child(_map)

	_header(col, "HERO RANGE")
	_range = OptionButton.new()
	for d: int in RANGE_DELTAS:
		_range.add_item(range_label(d), d + 10)
	_range.select(RANGE_DELTAS.find(MatchSettings.standard().range_delta))
	col.add_child(_range)

	_header(col, "PLACING STAGES AND CORES")
	_setup_mode = OptionButton.new()
	_setup_mode.add_item("Placed by the players in turn  ·  Standard")
	_setup_mode.add_item("Placed at random")
	col.add_child(_setup_mode)

	_problems = Label.new()
	_problems.theme_type_variation = &"Muted"
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_problems)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	row.add_child(back)
	var online := Button.new()
	online.text = "Online…"
	online.tooltip_text = "Host a match or join one over Tailscale"
	online.pressed.connect(func() -> void: get_tree().change_scene_to_file(LOBBY_SCENE))
	row.add_child(online)
	_start_btn = Button.new()
	_start_btn.text = "Start match"
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.theme_type_variation = &"Primary"
	_start_btn.pressed.connect(_start)
	row.add_child(_start_btn)
	_check()


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Header"
	parent.add_child(l)


## Shows what the deck check says about the chosen saved decks (random decks are always legal).
func _check() -> void:
	var lines := PackedStringArray()
	for slot: int in _deck_pick.size():
		var i: int = _deck_pick[slot].selected
		if i <= 0:
			continue
		var d: Dictionary = decks[i - 1]
		var errs: PackedStringArray = DeckCode.check(db.catalog, JsonUtil.as_strings(d["heroes"]), JsonUtil.as_dict(d["cards"]))
		for e: String in errs:
			lines.append("Player %d: %s" % [slot + 1, e])
	var blocked: bool = false
	for slot: int in _loadouts.size():
		for e: String in _loadouts[slot].problems():
			lines.append("Player %d: %s" % [slot + 1, e])
			blocked = true
	if _start_btn != null:
		_start_btn.disabled = blocked
	_problems.text = "\n".join(lines) if not lines.is_empty() else "Cards whose text effects are not ready yet are refused when played."


func _start() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var settings: MatchSettings = MatchSettings.standard()
	settings.map_size = _map.get_selected_id()
	settings.range_delta = _range.get_selected_id() - 10
	settings.manual_setup = _setup_mode.selected == 0
	GameSettings.set_map_size(settings.map_size)
	var bot: bool = _opponent.selected < 2
	var level: String = "hard" if _opponent.selected == 1 else "easy"
	var engine_decks: Array = []
	for slot: int in 2:
		var i: int = _deck_pick[slot].selected
		var deck: Dictionary = DeckCode.random_deck(db.catalog, rng) if i <= 0 else decks[i - 1]
		var who: String = ("Bot (%s)" % level.capitalize()) if bot and slot == 1 else "Player %d" % (slot + 1)
		_loadouts[slot].loadout.remember("p%d" % (slot + 1))
		engine_decks.append(MatchLaunch.engine_deck(db.catalog, deck, who, rng, _loadouts[slot].loadout))
	MatchLaunch.config = {
		"settings": settings,
		"decks": engine_decks,
		"bots": PackedInt32Array([1]) if bot else PackedInt32Array(),
		"bot_level": level,
		"seed": rng.randi(),
	}
	get_tree().change_scene_to_file(MATCH_SCENE)


static func range_label(d: int) -> String:
	var label: String = "As printed on the cards" if d == 0 else "%+d to every hero (never below 2)" % d if d < 0 else "%+d to every hero" % d
	if d == MatchSettings.standard().range_delta:
		label += "  ·  Standard"
	return label


## Screenshot helper: opens player 1's stages and cores.
func demo_loadout() -> void:
	_loadouts[0].get_child(0).emit_signal("pressed")
