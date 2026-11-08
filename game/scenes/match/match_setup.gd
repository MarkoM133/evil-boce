class_name MatchSetup
extends Control
## Before a match (GDD 7; Marko 2026-11-08, from the mockups), as a match screen: player cards face
## each other across a VS (deck, stages and cores each). Against a bot you get most of the screen and
## the bot a column that says who it is; with a second player (or to set the bot up) the two sides are
## equal, and the screen moves between the two. Then the map and the match rules (MatchRules) beside
## a big START MATCH.
## Online play has its own lobby, which looks the same.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const DRAFT_SCENE: String = "res://scenes/match/draft.tscn"
## Back goes to the Play screen (local, online, practice).
const MENU_SCENE: String = "res://scenes/menu/play_menu.tscn"
const OPPONENTS: Array[String] = ["BOT · EASY", "BOT · HARD", "PLAYER 2"]
const CONTENT_W: float = 1500.0
const ROW_GAP: int = 14
## How wide the first player's heroes are: they fit half the screen too, so only the panels move.
const HEROES_W: float = 630.0
const OPPONENT_COLUMN_W: float = 340.0
## The move between the column and two equal sides: what goes out fades, the panels slide, what comes in fades.
const SPLIT_FADE: float = 0.1
const SPLIT_TIME: float = 0.34

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
var _vs: Label
## The opponent's column, in place of its side while it is a bot nobody is setting up.
var _compact: VBoxContainer
var _compact_why: Label
var _compact_heroes: HBoxContainer
var _compact_more: Button
var _opp_open: bool = false
var _head_buttons: Array[Button] = []
var _column_buttons: Array[Button] = []
var _hide_btn: Button
var _split_tween: Tween
var _half_shown: bool = false


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
		func() -> void: get_tree().change_scene_to_file(MENU_SCENE), CONTENT_W)
	var content: VBoxContainer = frame["content"]
	if not db.is_ok():
		var err := Label.new()
		err.text = db.error
		err.add_theme_color_override("font_color", Palette.GOLD)
		content.add_child(err)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_GAP)
	content.add_child(row)
	for slot: int in 2:
		var card := PlayerCard.new()
		# The second side's width is set (and moved) from here; the first takes what is left.
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL if slot == 0 else Control.SIZE_FILL
		if slot == 0:
			card.heroes_width = HEROES_W
		row.add_child(card)
		card.setup(db, decks, "Player %d" % (slot + 1), slot, GameSettings.last_deck("p%d" % (slot + 1)),
			Loadout.remembered("p%d" % (slot + 1)))
		card.changed.connect(_check)
		_cards.append(card)
		if _in_series and slot < series.decks.size():
			card.set_fixed_deck(JsonUtil.as_dict(series.decks[slot]))
			# A bot keeps its deck; players may swap with their sideboard.
			var has_side: bool = slot < series.sideboards.size() and not JsonUtil.as_dict(series.sideboards[slot]).is_empty()
			if has_side and not (slot == 1 and _opponent < 2):
				card.swap_handler = _swap.bind(slot)
				card.set_fixed_deck(JsonUtil.as_dict(series.decks[slot]))
		if slot == 0:
			_vs = UiTheme.label("VS", 96, Palette.ACCENT)
			_vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_vs.add_theme_color_override("font_outline_color", Color.BLACK)
			_vs.add_theme_constant_override("outline_size", 8)
			row.add_child(_vs)
	_cards[1].changed.connect(_refresh_compact)
	_build_opponent_choice()

	_problems = Label.new()
	_problems.add_theme_color_override("font_color", Palette.MUTED)
	_problems.add_theme_font_size_override("font_size", 13)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.visible = false
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
	_refresh_compact()
	_half_shown = not _wants_half()
	_apply_split(false)


## Who plays the second seat: chips in its side's header, big buttons in its column.
func _build_opponent_choice() -> void:
	var p2: PlayerCard = _cards[1]
	var head_group := ButtonGroup.new()
	_hide_btn = Button.new()
	_hide_btn.text = "HIDE"
	_hide_btn.theme_type_variation = &"Ghost"
	_hide_btn.tooltip_text = "Back to the small column for the bot"
	_hide_btn.add_theme_font_size_override("font_size", 15)
	_hide_btn.pressed.connect(func() -> void:
		_opp_open = false
		_apply_split(true))
	p2.header_extra.add_child(_hide_btn)
	for i: int in OPPONENTS.size():
		var b := _opponent_button(i, 15, head_group)
		p2.header_extra.add_child(b)
		_head_buttons.append(b)
	_compact = VBoxContainer.new()
	_compact.add_theme_constant_override("separation", 12)
	p2.add_child(_compact)
	_compact.add_child(UiShape.chip("OPPONENT", Palette.team(1), Palette.FG, 22, 34.0, 18.0))
	var column_group := ButtonGroup.new()
	for i: int in OPPONENTS.size():
		var b := _opponent_button(i, 30, column_group)
		_compact.add_child(b)
		_column_buttons.append(b)
	_compact_why = Label.new()
	_compact_why.add_theme_color_override("font_color", Palette.MUTED)
	_compact_why.add_theme_font_size_override("font_size", 18)
	_compact_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compact.add_child(_compact_why)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_compact.add_child(gap)
	_compact_heroes = HBoxContainer.new()
	_compact_heroes.add_theme_constant_override("separation", 2)
	_compact.add_child(_compact_heroes)
	_compact_more = Button.new()
	_compact_more.text = "CHOOSE ITS DECK AND STAGES"
	_compact_more.add_theme_font_size_override("font_size", 17)
	_compact_more.pressed.connect(func() -> void:
		_opp_open = true
		_apply_split(true))
	_compact.add_child(_compact_more)


func _opponent_button(i: int, font_size: int, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = OPPONENTS[i]
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = i == _opponent
	b.disabled = _in_series
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(func() -> void: _set_opponent(i))
	return b


func _set_opponent(i: int) -> void:
	if i == _opponent:
		return
	# To or from a second player the bot's column comes back folded.
	if i == 2 or _opponent == 2:
		_opp_open = false
	_opponent = i
	last_opponent = i
	_apply_split(true)


func _wants_half() -> bool:
	return _in_series or _opponent == 2 or _opp_open


func _half_width() -> float:
	return (CONTENT_W - 2.0 * ROW_GAP - _vs.get_combined_minimum_size().x) * 0.5


func _set_split(t: float) -> void:
	_cards[0].set_split(t)


## The second side as a column or as an equal half. Animated, what is showing fades, the panels
## slide (the first player's stages move with them), then the new content fades in. A click in the
## middle of it carries on from wherever the panels are.
func _apply_split(animate: bool) -> void:
	var half: bool = _wants_half()
	for list: Array[Button] in [_head_buttons, _column_buttons]:
		for i: int in list.size():
			list[i].set_pressed_no_signal(i == _opponent)
	_hide_btn.visible = _opp_open and _opponent < 2 and not _in_series
	if half == _half_shown:
		return
	_half_shown = half
	if _split_tween != null:
		_split_tween.kill()
		_split_tween = null
	var p2: PlayerCard = _cards[1]
	var width: float = _half_width() if half else OPPONENT_COLUMN_W
	var target: float = 1.0 if half else 0.0
	var coming: Control = p2.side if half else _compact
	if not animate:
		_set_split(target)
		p2.custom_minimum_size.x = width
		p2.side.visible = half
		p2.side.modulate.a = 1.0
		_compact.visible = not half
		_compact.modulate.a = 1.0
		return
	var going: Control = _compact if _compact.visible else (p2.side if p2.side.visible else null)
	_split_tween = create_tween()
	if going != null:
		_split_tween.tween_property(going, "modulate:a", 0.0, SPLIT_FADE)
		_split_tween.tween_callback(going.hide)
	_split_tween.tween_property(p2, "custom_minimum_size:x", width, SPLIT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_split_tween.parallel().tween_method(_set_split, _cards[0].split, target, SPLIT_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_split_tween.tween_callback(func() -> void:
		coming.modulate.a = 0.0
		coming.show())
	_split_tween.tween_property(coming, "modulate:a", 1.0, SPLIT_FADE * 1.5)


## What the opponent's column says about the bot, and its heroes when they are known.
func _refresh_compact() -> void:
	if _compact_why == null or _rules == null:
		return
	var p2: PlayerCard = _cards[1]
	var mode: String = _rules.settings.mode
	_compact_more.visible = mode != "chaos"
	if mode == "chaos":
		_compact_why.text = "Chaos: everything is random."
	elif mode == "draft":
		_compact_why.text = "Drafts its deck with you."
	else:
		var d: Dictionary = p2.saved_deck()
		var deck: String = "a random deck" if d.is_empty() else str(d.get("name", "its deck"))
		var picked: bool = not "".join(p2.loadout.stages).is_empty() or not "".join(p2.loadout.cores).is_empty()
		_compact_why.text = "Plays %s, with %s stages and cores." % [deck, "the chosen" if picked else "random"]
	for c: Node in _compact_heroes.get_children():
		_compact_heroes.remove_child(c)
		c.queue_free()
	var ids: PackedStringArray = JsonUtil.as_strings(p2.picks().get("heroes", []))
	for i: int in DeckCode.HERO_COUNT:
		_compact_heroes.add_child(_compact_hero(ids[i] if i < ids.size() else ""))


func _compact_hero(id: String) -> HeroSlice:
	var s := HeroSlice.new()
	s.custom_minimum_size = Vector2(98, 116)
	s.art_w = PlayerCard.ALL_PICTURE
	s.set_mirrored(false)
	var card: CardDef = db.catalog.get_card(id) if not id.is_empty() else null
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	if card != null:
		s.art = db.thumb(id)
		s.art_region = HeroSlice.region_for(s.art)
		s.color_edge = Palette.hero(card.color)
		s.tooltip_text = card.name
		return s
	s.art_fallback = Palette.team(1).darkened(0.74)
	var q: Label = UiTheme.label("?", 48, Palette.team(1).lightened(0.15))
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.content.add_child(q)
	return s


## Chaos (GDD 13): both sides play random decks, stages and cores; Draft: the decks are drafted.
func _lock_cards() -> void:
	var chaos: bool = _rules.settings.mode == "chaos"
	var drafted: bool = _rules.settings.mode == "draft"
	for card: PlayerCard in _cards:
		var a: bool = card.set_locked_random(chaos)
		var b: bool = card.set_drafted(drafted)
		card.set_sideboard_mode(_rules.settings.series_wins > 1 and not _in_series and not drafted and not chaos)
		if a or b:
			_check()
	_refresh_compact()


## Problems of both sides; any one keeps START MATCH off.
func _check() -> void:
	var lines := PackedStringArray()
	for slot: int in _cards.size():
		for e: String in _cards[slot].problems():
			lines.append("Player %d: %s" % [slot + 1, e])
	if _start_btn != null:
		_start_btn.disabled = not lines.is_empty()
	_problems.text = "\n".join(lines)
	_problems.visible = not lines.is_empty()
	_problems.add_theme_color_override("font_color", Palette.GOLD)


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
		# Over 40 only a random deck grows (Marko 2026-10-30); a saved deck plays its 40.
		if card.deck_index == 0 and settings.deck_size > DeckCode.DECK_SIZE:
			deck = DeckCode.fill_deck(db.catalog, deck, settings.deck_size, rng)
		if series != null and not _in_series:
			series.decks.append({"name": str(deck.get("name", "")), "heroes": deck.get("heroes", []), "cards": deck.get("cards", {})})
			var side: Dictionary = card.sideboard if not saved.is_empty() else {}
			if not MatchSeries.sideboard_error(db.catalog, JsonUtil.as_strings(deck.get("heroes", [])), side).is_empty():
				side = {}
			series.sideboards.append(side)
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
		"series": series != null,
	}
	get_tree().change_scene_to_file(MATCH_SCENE)


## Best of 3 between games: deck and sideboard trade cards (up to five); the deck of the next
## game changes for good.
func _swap(slot: int) -> void:
	var series: MatchSeries = MatchSeries.current
	var base: Dictionary = JsonUtil.as_dict(series.break_decks[slot]) if slot < series.break_decks.size() else {}
	var now: Dictionary = JsonUtil.as_dict(series.decks[slot])
	SideboardPanel.open_swap(self, db, JsonUtil.as_strings(now.get("heroes", [])), JsonUtil.as_dict(base.get("cards", {})),
		JsonUtil.as_dict(series.break_sides[slot]) if slot < series.break_sides.size() else {}, JsonUtil.as_dict(now.get("cards", {})),
		func(cards: Dictionary) -> void:
			var err: String = series.set_cards(db.catalog, slot, cards)
			if not err.is_empty():
				_problems.text = "Player %d: %s" % [slot + 1, err]
				_problems.add_theme_color_override("font_color", Palette.GOLD)
				_problems.visible = true
				return
			_cards[slot].set_fixed_deck(JsonUtil.as_dict(series.decks[slot]))
			_check())


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


## Screenshot helpers: the move to two equal sides, and back to the bot's column.
func demo_player2() -> void:
	_set_opponent(2)


func demo_bot() -> void:
	_set_opponent(0)


## Screenshot helper: opens player 1's stage picker.
func demo_loadout() -> void:
	_cards[0]._pick_stage(0)


## Screenshot helper: player 1's core picker.
func demo_cores() -> void:
	_cards[0]._open_core_picker()


func demo_rules() -> void:
	_rules.open_rules()


func demo_maps() -> void:
	_rules.open_map_picker()


## Screenshot helpers: player 1 builds a random deck with its first hero picked; the hero picker.
func demo_heroes() -> void:
	_cards[0].deck_index = 0
	_cards[0].chosen = PackedStringArray([db.catalog.of_type("Hero")[0].id, "", ""])
	_cards[0]._build_random()
	_cards[1].deck_index = 0
	_cards[1]._rebuild()


func demo_hero_pick() -> void:
	_cards[1].deck_index = 0
	_cards[1]._pick_hero(1)


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
	s.sideboards = [_demo_side(s, 0), {}]
	s.record(1)
	MatchSeries.current = s
	get_tree().reload_current_scene()


## Up to ten legal cards for seat `slot` of the series, the ones the deck holds fewest of first.
func _demo_side(s: MatchSeries, slot: int) -> Dictionary:
	var d: Dictionary = JsonUtil.as_dict(s.decks[slot])
	var cards: Dictionary = JsonUtil.as_dict(d["cards"])
	var heroes: Array[CardDef] = []
	for id: String in JsonUtil.as_strings(d["heroes"]):
		heroes.append(db.catalog.get_card(id))
	var side: Dictionary = {}
	var n: int = 0
	for c: CardDef in DeckCode._pool(db.catalog, heroes):
		if n < 6 and JsonUtil.as_int(cards.get(c.id, 0)) < DeckCode.LIMITS[c.type]:
			side[c.id] = 1
			n += 1
	return side


## Screenshot helper: the sideboard builder for player 1's deck (a random one stands in).
func demo_sideboard() -> void:
	GameSettings.in_memory = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var d: Dictionary = DeckCode.random_deck(db.catalog, rng)
	var s := MatchSeries.new(2)
	s.decks = [{"name": "x", "heroes": d["heroes"], "cards": d["cards"]}]
	SideboardPanel.open_build(self, db, JsonUtil.as_strings(d["heroes"]), JsonUtil.as_dict(d["cards"]), _demo_side(s, 0), func(_x: Dictionary) -> void: pass)


## Screenshot helper: swapping between games, one swap made.
func demo_swap() -> void:
	GameSettings.in_memory = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var d: Dictionary = DeckCode.random_deck(db.catalog, rng)
	var s := MatchSeries.new(2)
	s.decks = [{"name": "x", "heroes": d["heroes"], "cards": d["cards"]}]
	var side: Dictionary = _demo_side(s, 0)
	var p: SideboardPanel = SideboardPanel.open_swap(self, db, JsonUtil.as_strings(d["heroes"]), JsonUtil.as_dict(d["cards"]), side, JsonUtil.as_dict(d["cards"]), func(_x: Dictionary) -> void: pass)
	p._swap(str(JsonUtil.as_dict(d["cards"]).keys()[0]), str(side.keys()[0]))
	p._fill()


## Screenshot helper: the Buff core picker of player 1 is open.
func demo_core_pick() -> void:
	_cards[0].call("_open_core_picker")


## Screenshot helper: the core picker with ROLL pressed on every row (the reels running).
func demo_core_roll() -> void:
	_cards[0].call("_open_core_picker")
	await get_tree().process_frame
	for b: Node in _cards[0].find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("ROLL "):
			(b as Button).pressed.emit()
			break
