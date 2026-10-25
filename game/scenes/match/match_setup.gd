extends Control
## Before a match: deck per player (saved decks from the shared folder, or random), who plays
## the second seat (bot or a second local player) and the map size.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const RANDOM: String = "Random deck"
## Offered changes to every hero's printed range (Standard is -1, see MatchSettings.standard).
const RANGE_DELTAS: Array[int] = [-2, -1, 0, 1]

var db: CardDb
var decks: Array[Dictionary] = []
var _deck_pick: Array[OptionButton] = []
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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(440, 0)
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
		_range.add_item(_range_label(d), d + 10)
	_range.select(RANGE_DELTAS.find(MatchSettings.standard().range_delta))
	col.add_child(_range)

	_header(col, "STAGES AND CORES")
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
	var start := Button.new()
	start.text = "Start match"
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(_start)
	row.add_child(start)
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
		engine_decks.append(MatchLaunch.engine_deck(db.catalog, deck, who, rng))
	MatchLaunch.config = {
		"settings": settings,
		"decks": engine_decks,
		"bots": PackedInt32Array([1]) if bot else PackedInt32Array(),
		"bot_level": level,
		"seed": rng.randi(),
	}
	get_tree().change_scene_to_file(MATCH_SCENE)


static func _range_label(d: int) -> String:
	var label: String = "As printed on the cards" if d == 0 else "%+d to every hero (never below 2)" % d if d < 0 else "%+d to every hero" % d
	if d == MatchSettings.standard().range_delta:
		label += "  ·  Standard"
	return label
