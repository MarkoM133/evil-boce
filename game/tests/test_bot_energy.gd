extends GutTest
## How the bots split the End phase energy between two open stages (energy claim variant,
## Marko and Tarik 2026-11-02): finish a stage when the energy reaches, else all into one.

var catalog: CardCatalog
var engine: RulesEngine


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


## p0's TA-001 on stage:p0:1 and TA-003 on stage:p0:2 (energy `a` and `b` in them), `energy` to put in.
func _state(a: int, b: int, energy: int) -> GameState:
	var settings: MatchSettings = MatchSettings.new()
	settings.manual_setup = false
	settings.stage_claim = MatchSettings.CLAIM_ENERGY
	settings.stage_goal = 14
	var s: GameState = engine.start_match(settings, [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": ["TS-001", "TS-002"], "cores": []},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-004"], "cards": {"TX-010": 40}, "stages": ["TS-004"], "cores": []},
	], 1)
	var one: StageState = s.stage("stage:p0:1")
	var two: StageState = s.stage("stage:p0:2")
	one.placed = true
	one.center = Vector2i(4, 8)
	two.placed = true
	two.center = Vector2i(12, 8)
	s.stage("stage:p1:1").placed = false
	one.progress = {0: a}
	two.progress = {0: b}
	var h1: HeroState = s.hero("p0:TA-001")
	h1.zone = HeroState.ZONE_MAP
	h1.hex = one.center
	var h3: HeroState = s.hero("p0:TA-003")
	h3.zone = HeroState.ZONE_MAP
	h3.hex = two.center
	s.phase = GameState.PHASE_END
	s.turn = 6
	s.energy_banked = true
	s.player(0).energy = energy
	s.pending = [{"type": RulesEngine.DECISION_STAGE_ENERGY, "player": 0, "energy": energy,
		"stages": ["stage:p0:1", "stage:p0:2"], "goal": 14}]
	return s


func _split(level: Bot.Level, s: GameState) -> Dictionary:
	var bot := Bot.new(7, level)
	var positions: Dictionary[String, Vector2] = {}
	var m: Move = bot.next_move(engine, s, 0, positions, PhysicsTuning.load_default())
	assert_not_null(m)
	assert_eq(m.type, Move.STAGE_ENERGY)
	var trial: GameState = GameState.from_dict(s.to_dict())
	assert_eq(engine.apply(trial, m), "", "the bot's split is legal")
	return JsonUtil.as_dict(m.data.get("split", {}))


func test_finishes_a_stage_and_keeps_the_rest() -> void:
	for level: Bot.Level in [Bot.Level.EASY, Bot.Level.HARD]:
		var split: Dictionary = _split(level, _state(10, 2, 6))
		assert_eq(JsonUtil.as_int(split.get("stage:p0:1", 0)), 4, "%s finishes the stage at 10/14" % Bot.level_name(level))
		assert_eq(JsonUtil.as_int(split.get("stage:p0:2", 0)), 2, "%s puts the other 2 into the second" % Bot.level_name(level))


func test_all_into_the_fuller_stage() -> void:
	for level: Bot.Level in [Bot.Level.EASY, Bot.Level.HARD]:
		var split: Dictionary = _split(level, _state(5, 8, 3))
		assert_eq(JsonUtil.as_int(split.get("stage:p0:2", 0)), 3, "%s puts all 3 into 8/14" % Bot.level_name(level))
		assert_false(split.has("stage:p0:1"))


func test_the_claim_lands() -> void:
	var s: GameState = _state(12, 0, 4)
	var bot := Bot.new(7, Bot.Level.HARD)
	var positions: Dictionary[String, Vector2] = {}
	var m: Move = bot.next_move(engine, s, 0, positions, PhysicsTuning.load_default())
	assert_eq(engine.apply(s, m), "")
	assert_eq(s.stage("stage:p0:1").claimed_by, 0)
	assert_eq(s.stage("stage:p0:2").progress_of(0), 2)
