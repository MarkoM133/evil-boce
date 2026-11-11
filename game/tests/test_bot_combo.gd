extends GutTest
## How the bots answer a combo offer (Marko 2026-11-11): Easy takes the first combo, Hard pays only when the
## combo leaves it better off than the two cards as they are. The state is scenario 57's, up to the offer.

const SCENARIO: String = "res://tests/scenarios/57_combo_offer_accept.json"

var catalog: CardCatalog
var engine: RulesEngine


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


## Scenario 57's steps up to the combo offer.
func _offer_state() -> GameState:
	var doc: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(SCENARIO)))
	var s: GameState = null
	for step: Variant in JsonUtil.as_array(doc.get("steps", [])):
		var st: Dictionary = JsonUtil.as_dict(step)
		if st.has("setup"):
			var settings: MatchSettings = MatchSettings.new()
			settings.manual_setup = false
			var decks: Array = [
				{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 20, "TX-011": 20},
					"stages": ["TS-001", "TS-002", "TS-003"], "cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
				{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-010": 20, "TX-011": 20},
					"stages": ["TS-004", "TS-005", "TS-006"], "cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
			]
			s = engine.start_match(settings, decks, JsonUtil.as_int(JsonUtil.as_dict(st["setup"]).get("seed", 1), 1))
		elif st.has("set"):
			var d: Dictionary = s.to_dict()
			var changes: Dictionary = JsonUtil.as_dict(st["set"])
			for path: Variant in changes:
				var keys: PackedStringArray = str(path).split(".")
				var node: Dictionary = d
				for i: int in keys.size() - 1:
					if not node.has(keys[i]):
						node[keys[i]] = {}
					node = node[keys[i]]
				node[keys[keys.size() - 1]] = changes[path]
			s = GameState.from_dict(d)
		elif st.has("move"):
			assert_eq(engine.apply(s, Move.from_dict(JsonUtil.as_dict(st["move"]))), "")
		elif st.has("pass_round"):
			var n: int = 0
			var phase: String = s.phase
			while not s.round_over and s.pending.is_empty() and n < 16 and s.phase == phase:
				engine.apply(s, Move.make(Move.PASS, s.to_act))
				n += 1
		if not s.pending.is_empty() and str(s.pending[0].get("type", "")) == RulesEngine.DECISION_COMBO:
			return s
	return null


func _answer(level: Bot.Level, s: GameState) -> Move:
	var bot := Bot.new(7, level)
	var positions: Dictionary[String, Vector2] = {}
	return bot.next_move(engine, s, 0, positions, PhysicsTuning.load_default())


func test_easy_takes_the_combo() -> void:
	var s: GameState = _offer_state()
	assert_not_null(s, "scenario 57 reaches the offer")
	var m: Move = _answer(Bot.Level.EASY, s)
	assert_eq(m.type, Move.CHOOSE)
	assert_eq(str(m.data.get("value", "")), "TC-001")


func test_hard_pays_when_the_combo_is_worth_more() -> void:
	var s: GameState = _offer_state()
	var m: Move = _answer(Bot.Level.HARD, s)
	var trial: GameState = GameState.from_dict(s.to_dict())
	assert_eq(engine.apply(trial, m), "", "the answer is legal")
	var bot := Bot.new(7, Bot.Level.HARD)
	var took: GameState = GameState.from_dict(s.to_dict())
	engine.apply(took, Move.make(Move.CHOOSE, 0, {"value": "TC-001"}))
	var left: GameState = GameState.from_dict(s.to_dict())
	engine.apply(left, Move.make(Move.PASS, 0))
	var combo_better: bool = bot.evaluate(engine, took, 0) > bot.evaluate(engine, left, 0)
	assert_true(combo_better, "here the combo wins the battle harder")
	assert_eq(m.type, Move.CHOOSE, "Hard takes it")


func test_hard_keeps_the_cards_when_the_combo_costs_more_than_it_gives() -> void:
	var s: GameState = _offer_state()
	# Energy claims with a hero on an open stage: the extra energy would have gone into that stage, and the
	# battle is already won without the combo's bonus (the opponent's hero is off the map).
	s.settings.stage_claim = MatchSettings.CLAIM_RING
	var st: StageState = s.stage("stage:p0:1")
	st.placed = true
	st.revealed = true
	st.center = s.hero("p0:TA-001").hex
	for h: HeroState in s.heroes_of(1):
		h.zone = HeroState.ZONE_STRIP
	var m: Move = _answer(Bot.Level.HARD, s)
	var bot := Bot.new(7, Bot.Level.HARD)
	var took: GameState = GameState.from_dict(s.to_dict())
	engine.apply(took, Move.make(Move.CHOOSE, 0, {"value": "TC-001"}))
	var left: GameState = GameState.from_dict(s.to_dict())
	engine.apply(left, Move.make(Move.PASS, 0))
	assert_true(bot.evaluate(engine, took, 0) < bot.evaluate(engine, left, 0), "the energy is worth more in the stage")
	assert_eq(m.type, Move.PASS, "Hard plays the two cards as they are")
