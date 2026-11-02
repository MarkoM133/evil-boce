extends GutTest
## How the bots split a lost battle's hit between the hero and cards from the hand (GDD 10,
## 2026-11-02): at least half on the hero, the rest hero or 1 card per DMG.

var catalog: CardCatalog
var engine: RulesEngine


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


## A state where p0's TA-001 (Red) lost to p1's TB-002 and owes `amount` DMG, with `hp` left and `hand`.
func _state(hp: int, hand: Array, amount: int = 3) -> GameState:
	var s: GameState = engine.start_match(MatchSettings.standard(), [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-004"], "cards": {"TX-010": 40}, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	], 1)
	var h: HeroState = s.hero("p0:TA-001")
	h.zone = HeroState.ZONE_MAP
	h.hex = Vector2i(4, 8)
	h.hp = hp
	var w: HeroState = s.hero("p1:TB-002")
	w.zone = HeroState.ZONE_MAP
	w.hex = Vector2i(6, 8)
	s.phase = GameState.PHASE_BATTLE
	s.battles = [{"heroes": [h.id, w.id], "winner_team": 1, "resolved": false}]
	s.battle_index = 0
	s.player(0).hand = PackedStringArray(hand)
	s.pending = [{"type": RulesEngine.DECISION_DAMAGE, "player": 0, "winner": w.id, "amount": amount,
		"targets": ["p0:TA-001"], "min_hero": RulesEngine.hero_share(amount)}]
	return s


func _split(level: Bot.Level, s: GameState) -> Move:
	var bot := Bot.new(7, level)
	var positions: Dictionary[String, Vector2] = {}
	var m: Move = bot.next_move(engine, s, 0, positions, PhysicsTuning.load_default())
	assert_not_null(m)
	assert_eq(m.type, Move.DAMAGE_TO)
	assert_eq(m.str_arg("target"), "p0:TA-001")
	var trial: GameState = GameState.from_dict(s.to_dict())
	assert_eq(engine.apply(trial, m), "", "the bot's split is legal")
	return m


func test_healthy_hero_takes_it_all() -> void:
	for level: Bot.Level in [Bot.Level.EASY, Bot.Level.HARD]:
		var m: Move = _split(level, _state(10, ["TX-010", "TX-010", "TA-040"]))
		assert_eq(JsonUtil.as_strings(m.data.get("cards", [])).size(), 0, "%s keeps the hand at 10 HP" % Bot.level_name(level))


func test_cards_save_the_hero_from_a_ko() -> void:
	for level: Bot.Level in [Bot.Level.EASY, Bot.Level.HARD]:
		var m: Move = _split(level, _state(3, ["TX-010", "TX-010", "TA-040"]))
		assert_eq(JsonUtil.as_strings(m.data.get("cards", [])).size(), 1, "%s gives a card to live" % Bot.level_name(level))


func test_low_hero_sheds_as_much_as_allowed() -> void:
	# 6 DMG at 5 HP: 3 must land; the other 3 go on cards, else the hero falls.
	for level: Bot.Level in [Bot.Level.EASY, Bot.Level.HARD]:
		var m: Move = _split(level, _state(5, ["TX-010", "TX-010", "TA-040", "TA-043"], 6))
		assert_eq(JsonUtil.as_strings(m.data.get("cards", [])).size(), 3, "%s sheds 3 cards" % Bot.level_name(level))


func test_dead_cards_go_first() -> void:
	# TX-011 is Blue; p0 has no Blue hero on the map... TA-002 (Blue) is KO: the card is dead.
	var s: GameState = _state(4, ["TX-010", "TX-011", "TA-040"])
	s.hero("p0:TA-002").zone = HeroState.ZONE_KO
	for level: Bot.Level in [Bot.Level.EASY, Bot.Level.HARD]:
		var m: Move = _split(level, s)
		var cards: PackedStringArray = JsonUtil.as_strings(m.data.get("cards", []))
		assert_eq(cards.size(), 1, "%s gives one card at 4 HP" % Bot.level_name(level))
		assert_eq(cards[0], "TX-011", "%s throws the dead card" % Bot.level_name(level))


func test_empty_hand_all_on_hero() -> void:
	var m: Move = _split(Bot.Level.HARD, _state(2, []))
	assert_eq(JsonUtil.as_strings(m.data.get("cards", [])).size(), 0)
