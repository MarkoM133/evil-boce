extends GutTest
## A thrown hero that stays in its start strip throws again (Marko 2026-10-26): the roll does not
## count, only that player aims again, and the others are not thrown a second time.

const FIXTURE: String = "res://tests/fixtures/cards.json"


func test_a_throw_that_stays_in_the_strip_is_thrown_again() -> void:
	var engine := RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 40}
	var s: GameState = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-002", "TA-003"], "cards": cards, "stages": [], "cores": []},
		{"heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": [], "cores": []},
	], 1)
	assert_eq(engine.apply(s, Move.make(Move.MULLIGAN, 0, {"keep": true})), "")
	assert_eq(engine.apply(s, Move.make(Move.MULLIGAN, 1, {"keep": true})), "")
	assert_eq(engine.apply(s, Move.make(Move.SELECT, 0, {"hero": "p0:TA-001", "roll": true})), "")
	assert_eq(engine.apply(s, Move.make(Move.SELECT, 1, {"hero": "p1:TB-001", "roll": true})), "")
	while s.phase == GameState.PHASE_PREROLL:
		assert_eq(engine.apply(s, Move.make(Move.PASS, s.to_act)), "")
	assert_eq(s.phase, GameState.PHASE_ROLL)
	for slot: int in 2:
		assert_eq(engine.apply(s, Move.make(Move.AIM, slot, {"dir": [0.0, 1.0], "power": 0.5})), "")
	assert_true(s.awaiting_roll)
	var weak := RollResult.new()
	weak.ball_id = "p0:TA-001"
	weak.thrown = true
	weak.end_area = BallWorld.Area.STRIP
	var good := RollResult.new()
	good.ball_id = "p1:TB-001"
	good.thrown = true
	good.end_area = BallWorld.Area.MAP
	good.end_hex = Vector2i(5, 5)
	var o := RollOutcome.new()
	o.results = [weak, good] as Array[RollResult]
	assert_eq(engine.apply_roll(s, o), "")
	assert_false(s.rolled, "the roll does not count")
	assert_false(s.awaiting_roll)
	assert_false(s.aims.has(0), "player 0 aims again")
	assert_true(JsonUtil.as_bool(JsonUtil.as_dict(s.aims.get(1, {})).get("skip", false)), "player 1 is not thrown again")
	assert_eq(s.hero("p1:TB-001").hex, Vector2i(5, 5), "the other stays where it stopped")
	assert_eq(engine.apply(s, Move.make(Move.AIM, 0, {"dir": [0.0, 1.0], "power": 1.0})), "")
	assert_true(s.awaiting_roll, "the second throw starts")
