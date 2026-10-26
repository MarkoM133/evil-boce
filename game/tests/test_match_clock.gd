extends GutTest
## The move timer's helpers (GDD 8, 2026-10-26): whom the game waits for, what for, and the safe
## move made when the time runs out. No time passes here; the scene keeps the clocks.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState
var rng := RandomNumberGenerator.new()


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	rng.seed = 5
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 40}
	state = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-002"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	], 1)


func _apply_timeout(slot: int, hint: Dictionary = {}) -> Move:
	var m: Move = MatchClock.timeout_move(engine, state, slot, rng, hint)
	assert_not_null(m, "a move for slot %d" % slot)
	if m != null:
		assert_eq(engine.apply(state, m), "", "the timeout move is legal")
	return m


func test_mulligan_waits_for_both_and_keeps_on_timeout() -> void:
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([0, 1]))
	assert_eq(MatchClock.wait_key(engine, state, 0), "mulligan")
	var m: Move = _apply_timeout(0)
	assert_eq(m.type, Move.MULLIGAN)
	assert_true(JsonUtil.as_bool(m.data["keep"]))
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([1]), "the other still has to answer")


func test_start_confirms_the_marked_hero_else_a_random_one_that_stays() -> void:
	engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true}))
	engine.apply(state, Move.make(Move.MULLIGAN, 1, {"keep": true}))
	assert_eq(state.phase, GameState.PHASE_START)
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([0, 1]))
	var marked: Move = MatchClock.timeout_move(engine, state, 0, rng, {"hero": "p0:TA-002", "roll": true})
	assert_eq(marked.str_arg("hero"), "p0:TA-002", "the marked hero is confirmed")
	assert_true(JsonUtil.as_bool(marked.data["roll"]), "a hero in the start zone rolls")
	# On the map, an unmarked hero stays.
	var h: HeroState = state.hero("p1:TB-001")
	h.zone = HeroState.ZONE_MAP
	h.hex = Vector2i(6, 4)
	state.hero("p1:TB-002").zone = HeroState.ZONE_KO
	var m: Move = _apply_timeout(1)
	assert_eq(m.str_arg("hero"), "p1:TB-001")
	assert_false(JsonUtil.as_bool(m.data["roll"]), "stays when it may")
	assert_eq(MatchClock.wait_key(engine, state, 1), "", "slot 1 has picked")
	assert_eq(MatchClock.wait_key(engine, state, 0), "start|1")


func test_a_missed_aim_is_a_missed_roll_and_the_card_round_passes() -> void:
	engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true}))
	engine.apply(state, Move.make(Move.MULLIGAN, 1, {"keep": true}))
	engine.apply(state, Move.make(Move.SELECT, 0, {"hero": "p0:TA-001", "roll": true}))
	engine.apply(state, Move.make(Move.SELECT, 1, {"hero": "p1:TB-001", "roll": true}))
	assert_eq(state.phase, GameState.PHASE_PREROLL)
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([state.initiative]), "only the player to act")
	var key: String = MatchClock.wait_key(engine, state, state.initiative)
	assert_true(key.begins_with("card|"))
	_apply_timeout(state.initiative)
	assert_true(MatchClock.wait_key(engine, state, state.to_act) != key, "a new wait, a new key")
	_apply_timeout(state.to_act)
	assert_eq(state.phase, GameState.PHASE_ROLL)
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([0, 1]), "both aim at once")
	var m: Move = _apply_timeout(0)
	assert_eq(m.type, Move.AIM)
	assert_true(JsonUtil.as_bool(state.aims[0]["skip"]), "a missed roll, not a throw")
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([1]))
	var last: Dictionary = state.log[state.log.size() - 1]
	assert_eq(str(last.get("type", "")), "roll_missed")


func test_a_roll_offer_is_declined_and_damage_goes_to_the_deck() -> void:
	engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true}))
	engine.apply(state, Move.make(Move.MULLIGAN, 1, {"keep": true}))
	state.pending.append({"type": RulesEngine.DECISION_ROLL_OFFER, "player": 1, "hero": "p1:TB-001", "abilities": [], "cards": []})
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([1]), "only whoever has an offer")
	var m: Move = MatchClock.timeout_move(engine, state, 1, rng)
	assert_eq(m.type, Move.PASS)
	state.pending.clear()
	state.pending.append({"type": RulesEngine.DECISION_DAMAGE, "player": 0, "winner": "p1:TB-001", "amount": 2, "targets": ["p0:TA-001"]})
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([0]))
	m = MatchClock.timeout_move(engine, state, 0, rng)
	assert_eq(m.type, Move.DAMAGE_TO)
	assert_eq(m.str_arg("target"), "deck")


func test_nobody_is_waited_for_while_the_balls_roll_or_after_the_end() -> void:
	engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true}))
	engine.apply(state, Move.make(Move.MULLIGAN, 1, {"keep": true}))
	state.phase = GameState.PHASE_ROLL
	state.awaiting_roll = true
	assert_true(MatchClock.waiting_on(engine, state).is_empty())
	state.awaiting_roll = false
	state.player(1).surrendered = true
	state.phase = GameState.PHASE_MULLIGAN
	state.player(1).mulligan_done = false
	assert_eq(MatchClock.waiting_on(engine, state), PackedInt32Array([]), "a surrendered player is never waited for")
