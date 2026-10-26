class_name MatchSetup
extends Control
## Before a match (GDD 7), as a match screen: two player cards face each other across a VS
## (deck, stages and cores each), who plays the second seat (bot Easy / Hard or a second player
## on this computer), the map, the hero range and how stages and cores are placed, then a big
## START MATCH. Online play has its own lobby.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
## Back goes to the Play screen (vs bot, two players, online, practice).
const MENU_SCENE: String = "res://scenes/menu/play_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
## Offered changes to every hero's printed range (Standard is -1, see MatchSettings.standard).
const RANGE_DELTAS: Array[int] = [-2, -1, 0, 1]
const OPPONENTS: Array[String] = ["BOT · EASY", "BOT · HARD", "PLAYER 2"]

var db: CardDb
var decks: Array[Dictionary] = []
var _cards: Array[PlayerCard] = []
var _opponent: int = 0
## Set by the Play screen before opening this one: 0 bot (easy), 2 a second player here.
static var preset_opponent: int = 0
var _map_i: int = 0
var _range_i: int = 1
var _manual: bool = true
var _problems: Label
var _start_btn: Button


func _ready() -> void:
	_opponent = preset_opponent
	db = CardDb.load_from(GameSettings.data_path())
	decks = DeckStore.load_all(db.root_dir)
	_map_i = maxi(0, GameSettings.MAP_SIZES.find(GameSettings.map_size()))
	_range_i = maxi(0, RANGE_DELTAS.find(MatchSettings.standard().range_delta))
	var frame: Dictionary = MenuScreen.build(self, db, "New match", "Decks, stages and cores, then start.",
		func() -> void: get_tree().change_scene_to_file(MENU_SCENE), 1300.0)
	var content: VBoxContainer = frame["content"]
	if not db.is_ok():
		var err := Label.new()
		err.text = db.error
		err.add_theme_color_override("font_color", Palette.GOLD)
		content.add_child(err)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	for slot: int in 2:
		var card := PlayerCard.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		card.setup(db, decks, "Player %d" % (slot + 1), slot, GameSettings.last_deck("p%d" % (slot + 1)),
			Loadout.remembered("p%d" % (slot + 1)))
		card.changed.connect(_check)
		_cards.append(card)
		if slot == 0:
			var vs: Label = UiTheme.label("VS", 64, Palette.ACCENT)
			vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			vs.add_theme_color_override("font_outline_color", Color.BLACK)
			vs.add_theme_constant_override("outline_size", 8)
			row.add_child(vs)
	# Who plays the second seat: chips in its header.
	var group := ButtonGroup.new()
	for i: int in OPPONENTS.size():
		var b := Button.new()
		b.text = OPPONENTS[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == _opponent
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func() -> void: _opponent = i)
		_cards[1].header_extra.add_child(b)

	# Match settings: chips that cycle through their values.
	MenuScreen.heading(content, "Match")
	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 10)
	content.add_child(settings)
	_cycle(settings, "MAP", func() -> String: return "%d × %d" % [GameSettings.MAP_SIZES[_map_i], GameSettings.MAP_SIZES[_map_i]],
		func() -> void: _map_i = (_map_i + 1) % GameSettings.MAP_SIZES.size())
	_cycle(settings, "HERO RANGE", func() -> String: return range_label(RANGE_DELTAS[_range_i]),
		func() -> void: _range_i = (_range_i + 1) % RANGE_DELTAS.size())
	_cycle(settings, "STAGES & CORES", func() -> String: return "placed by the players  ·  Standard" if _manual else "placed at random",
		func() -> void: _manual = not _manual)

	_problems = Label.new()
	_problems.add_theme_color_override("font_color", Palette.MUTED)
	_problems.add_theme_font_size_override("font_size", 13)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_problems)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	content.add_child(bottom)
	var online := Button.new()
	online.text = "ONLINE…"
	online.tooltip_text = "Host a match or join one over Tailscale"
	online.add_theme_font_size_override("font_size", 20)
	online.pressed.connect(func() -> void: get_tree().change_scene_to_file(LOBBY_SCENE))
	bottom.add_child(online)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	_start_btn = Button.new()
	_start_btn.text = "START MATCH"
	_start_btn.theme_type_variation = &"Primary"
	_start_btn.add_theme_font_size_override("font_size", 40)
	_start_btn.custom_minimum_size = Vector2(380, 0)
	_start_btn.pressed.connect(_start)
	bottom.add_child(_start_btn)
	_check()


## A chip "LABEL  value" that steps to the next value on click.
func _cycle(parent: Control, label: String, value: Callable, step: Callable) -> void:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 19)
	var show := func() -> void: b.text = "%s   %s" % [label, str(value.call()).to_upper()]
	show.call()
	b.tooltip_text = "Click to change"
	b.pressed.connect(func() -> void:
		step.call()
		show.call())
	parent.add_child(b)


## Problems of both sides; any one keeps START MATCH off.
func _check() -> void:
	var lines := PackedStringArray()
	for slot: int in _cards.size():
		for e: String in _cards[slot].problems():
			lines.append("Player %d: %s" % [slot + 1, e])
	if _start_btn != null:
		_start_btn.disabled = not lines.is_empty()
	_problems.text = "\n".join(lines) if not lines.is_empty() else "Cards whose text effects are not ready yet are refused when played."
	_problems.add_theme_color_override("font_color", Palette.GOLD if not lines.is_empty() else Palette.MUTED)


func _start() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var settings: MatchSettings = MatchSettings.standard()
	settings.map_size = GameSettings.MAP_SIZES[_map_i]
	settings.range_delta = RANGE_DELTAS[_range_i]
	settings.manual_setup = _manual
	GameSettings.set_map_size(settings.map_size)
	var bot: bool = _opponent < 2
	var level: String = "hard" if _opponent == 1 else "easy"
	var engine_decks: Array = []
	for slot: int in 2:
		var card: PlayerCard = _cards[slot]
		var saved: Dictionary = card.saved_deck()
		var deck: Dictionary = DeckCode.random_deck(db.catalog, rng) if saved.is_empty() else saved
		var who: String = ("Bot (%s)" % level.capitalize()) if bot and slot == 1 else "Player %d" % (slot + 1)
		card.loadout.remember("p%d" % (slot + 1))
		GameSettings.set_last_deck("p%d" % (slot + 1), "" if saved.is_empty() else str(saved["name"]))
		engine_decks.append(MatchLaunch.engine_deck(db.catalog, deck, who, rng, card.loadout))
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


## Screenshot helper: opens player 1's stage picker.
func demo_loadout() -> void:
	_cards[0]._pick_stage(0)
