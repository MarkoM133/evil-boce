class_name MatchSetup
extends Control
## Before a match (GDD 7), as a match screen: two player cards face each other across a VS
## (deck, stages and cores each), who plays the second seat (bot Easy / Hard or a second player
## on this computer), then the map and the match rules (MatchRules) beside a big START MATCH.
## Online play has its own lobby, which looks the same.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const DRAFT_SCENE: String = "res://scenes/match/draft.tscn"
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
var _in_series: bool = false
var _problems: Label
var _start_btn: Button


func _ready() -> void:
	_opponent = last_opponent
	db = CardDb.load_from(GameSettings.data_path())
	decks = DeckStore.load_all(db.root_dir)
	# A series (Best of 3): the next game keeps the decks and the opponent, only stages and cores change.
	var series: MatchSeries = MatchSeries.current
	_in_series = series != null and series.games > 0 and not series.is_over()
	if _in_series:
		_opponent = series.opponent
	var title: String = ("Game %d" % (series.games + 1)) if _in_series else "New match"
	var subtitle: String = ("Series %s. The decks stay; pick your stages and cores." % series.score()) if _in_series else "Decks, stages and cores, then start."
	var frame: Dictionary = MenuScreen.build(self, db, title, subtitle,
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
		if _in_series and slot < series.decks.size():
			card.set_fixed_deck(JsonUtil.as_dict(series.decks[slot]))
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
		b.disabled = _in_series
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
	_rules.setup(GameSettings.match_rules("local"), not _in_series)
	_rules.changed.connect(func() -> void:
		GameSettings.set_match_rules("local", _rules.settings)
		_lock_cards())
	_lock_cards()
	_start_btn = Button.new()
	_start_btn.text = ("START GAME %d" % (series.games + 1)) if _in_series else "START MATCH"
	_start_btn.theme_type_variation = &"Primary"
	_start_btn.add_theme_font_size_override("font_size", 40)
	_start_btn.custom_minimum_size = Vector2(380, 0)
	_start_btn.pressed.connect(_start)
	bottom.add_child(_start_btn)
	_check()


## Chaos (GDD 13): both sides play random decks, stages and cores; Draft: the decks are drafted.
func _lock_cards() -> void:
	var chaos: bool = _rules.settings.mode == "chaos"
	var drafted: bool = _rules.settings.mode == "draft"
	for card: PlayerCard in _cards:
		var a: bool = card.set_locked_random(chaos)
		var b: bool = card.set_drafted(drafted)
		if a or b:
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
	settings.resolve_map(rng, GameSettings.MAP_SIZES)
	GameSettings.set_map_size(settings.map_size)
	if settings.mode == "draft":
		_start_draft(settings)
		return
	var series: MatchSeries = MatchSeries.current
	if _in_series:
		settings.first_initiative = series.next_initiative()
	else:
		settings.first_initiative = -1
		series = MatchSeries.new(settings.series_wins) if settings.series_wins > 1 else null
		if series != null:
			series.opponent = _opponent
		MatchSeries.current = series
	var bot: bool = _opponent < 2
	var level: String = "hard" if _opponent == 1 else "easy"
	var engine_decks: Array = []
	for slot: int in 2:
		var card: PlayerCard = _cards[slot]
		var saved: Dictionary = card.saved_deck()
		var deck: Dictionary = DeckCode.random_deck(db.catalog, rng) if saved.is_empty() else saved
		if series != null and not _in_series:
			series.decks.append({"name": str(deck.get("name", "")), "heroes": deck.get("heroes", []), "cards": deck.get("cards", {})})
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


## Draft (GDD 13): the draft screen first, with the stages, cores and seats chosen here.
func _start_draft(settings: MatchSettings) -> void:
	MatchSeries.current = null
	settings.first_initiative = -1
	var bot: bool = _opponent < 2
	var level: String = "hard" if _opponent == 1 else "easy"
	var loadouts: Array = []
	for slot: int in 2:
		_cards[slot].loadout.remember("p%d" % (slot + 1))
		loadouts.append(_cards[slot].loadout)
	DraftScreen.local = {"settings": settings, "loadouts": loadouts,
		"names": ["Player 1", ("Bot (%s)" % level.capitalize()) if bot else "Player 2"], "bot": bot, "bot_level": level}
	get_tree().change_scene_to_file(DRAFT_SCENE)


## Screenshot helper: opens player 1's stage picker.
func demo_loadout() -> void:
	_cards[0]._pick_stage(0)


func demo_rules() -> void:
	_rules.open_rules()


func demo_maps() -> void:
	_rules.open_map_picker()


## Screenshot helpers: player 1 builds a random deck around the first hero; the leader picker.
func demo_leader() -> void:
	_cards[0].deck_index = 0
	_cards[0].leader = db.catalog.of_type("Hero")[0].id
	_cards[0]._build_random()
	_cards[1].deck_index = 0
	_cards[1]._rebuild()


func demo_leader_pick() -> void:
	_cards[1].deck_index = 0
	_cards[1]._pick_leader()


## Screenshot helper: the Chaos mode (everything random, the map drawn at the start).
func demo_chaos() -> void:
	GameSettings.in_memory = true
	_rules.settings = MatchSettings.preset("chaos")
	_rules._changed()


## Screenshot helper: game two of a Best of 3, the bot one up; the decks of game one stay.
func demo_series() -> void:
	GameSettings.in_memory = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var s := MatchSeries.new(2)
	for _i: int in 2:
		var d: Dictionary = DeckCode.random_deck(db.catalog, rng)
		s.decks.append({"name": str(d["name"]), "heroes": d["heroes"], "cards": d["cards"]})
	s.opponent = 1
	s.record(1)
	MatchSeries.current = s
	get_tree().reload_current_scene()
