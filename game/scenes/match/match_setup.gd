class_name MatchSetup
extends Control
## Before a match (GDD 7), as a match screen: two player cards face each other across a VS
## (deck, stages and cores each), who plays the second seat (bot Easy / Hard or a second player
## on this computer), then the map and the match rules (MatchRules) beside a big START MATCH.
## Online play has its own lobby, which looks the same.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
## Back goes to the Play screen (local, online, practice).
const MENU_SCENE: String = "res://scenes/menu/play_menu.tscn"
const OPPONENTS: Array[String] = ["BOT · EASY", "BOT · HARD", "PLAYER 2"]

var db: CardDb
var decks: Array[Dictionary] = []
var _cards: Array[PlayerCard] = []
var _opponent: int = 0
## Who plays the second seat, kept between visits while the game runs: 0 bot Easy, 1 Hard, 2 a second player here.
static var last_opponent: int = 0
var _rules: MatchRules
var _problems: Label
var _start_btn: Button


func _ready() -> void:
	_opponent = last_opponent
	db = CardDb.load_from(GameSettings.data_path())
	decks = DeckStore.load_all(db.root_dir)
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
		b.pressed.connect(func() -> void:
			_opponent = i
			last_opponent = i)
		_cards[1].header_extra.add_child(b)

	_problems = Label.new()
	_problems.add_theme_color_override("font_color", Palette.MUTED)
	_problems.add_theme_font_size_override("font_size", 13)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_problems)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	content.add_child(bottom)
	_rules = MatchRules.new()
	_rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_rules)
	_rules.setup(GameSettings.match_rules("local"), true)
	_rules.changed.connect(func() -> void: GameSettings.set_match_rules("local", _rules.settings))
	_start_btn = Button.new()
	_start_btn.text = "START MATCH"
	_start_btn.theme_type_variation = &"Primary"
	_start_btn.add_theme_font_size_override("font_size", 40)
	_start_btn.custom_minimum_size = Vector2(380, 0)
	_start_btn.pressed.connect(_start)
	bottom.add_child(_start_btn)
	_check()


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
	var settings: MatchSettings = MatchSettings.from_dict(_rules.settings.to_dict())
	GameSettings.set_match_rules("local", settings)
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


## Screenshot helper: opens player 1's stage picker.
func demo_loadout() -> void:
	_cards[0]._pick_stage(0)


func demo_rules() -> void:
	_rules.open_rules()


func demo_maps() -> void:
	_rules.open_map_picker()
