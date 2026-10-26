extends GutTest
## REVERSE_ROLL (GDD 10, 2026-10-26): the activated hero goes back to where it stood as the
## Roll phase began; what the throw did to others stays.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var cards: Dictionary = {"TX-010": 40}
	var settings := MatchSettings.new()
	settings.manual_setup = false
	state = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-002"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"],
			"cores": ["CR1-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
		{"heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"],
			"cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
	], 1)
	engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true}))
	engine.apply(state, Move.make(Move.MULLIGAN, 1, {"keep": true}))
	# TA-001 gets an optional Roll ability for the test, so an offer waits after the roll and the
	# phase stays Roll until it is answered.
	engine.catalog.get_card("TA-001").build_effects("ROLL ONCE OPTIONAL IF ACTIVATED: REVERSE_ROLL")
	var h: HeroState = state.hero("p0:TA-001")
	h.zone = HeroState.ZONE_MAP
	h.hex = Vector2i(4, 10)
	engine.apply(state, Move.make(Move.SELECT, 0, {"hero": "p0:TA-001", "roll": true}))
	engine.apply(state, Move.make(Move.SELECT, 1, {"hero": "p1:TB-001", "roll": true}))
	while not state.round_over:
		engine.apply(state, Move.make(Move.PASS, state.to_act))
	assert_eq(state.phase, GameState.PHASE_ROLL)


func _roll(end_hex: Vector2i, cores: PackedStringArray = PackedStringArray()) -> void:
	engine.apply(state, Move.make(Move.AIM, 0, {"dir": [0, -1], "power": 1.0}))
	engine.apply(state, Move.make(Move.AIM, 1, {"dir": [0, 1], "power": 1.0}))
	var o := RollOutcome.new()
	o.thrower = "p0:TA-001"
	var r := RollResult.new()
	r.ball_id = "p0:TA-001"
	r.thrown = true
	r.end_hex = end_hex
	r.cores_picked = cores
	o.add(r)
	var r2 := RollResult.new()
	r2.ball_id = "p1:TB-001"
	r2.thrown = true
	r2.end_hex = Vector2i(6, 4)
	o.add(r2)
	assert_eq(engine.apply_roll(state, o), "")


func test_snapshot_is_taken_as_the_roll_phase_begins() -> void:
	assert_eq(str(state.roll_snapshot["p0:TA-001"]["zone"]), HeroState.ZONE_MAP)
	assert_eq(JsonUtil.as_hex(state.roll_snapshot["p0:TA-001"]["hex"]), Vector2i(4, 10))
	assert_eq(str(state.roll_snapshot["p1:TB-001"]["zone"]), HeroState.ZONE_STRIP)


func test_reverse_roll_puts_only_the_hero_back_and_keeps_its_cores() -> void:
	# The core the throw picked up stays on the hero; the hero returns to (4, 10).
	var core: CoreState = state.cores[6]
	core.place = CoreState.ON_FIELD
	core.hex = Vector2i(3, 8)
	_roll(Vector2i(2, 12), PackedStringArray([core.id]))
	var h: HeroState = state.hero("p0:TA-001")
	assert_eq(h.hex, Vector2i(2, 12))
	assert_true(h.cores.has(core.id))
	assert_eq(state.phase, GameState.PHASE_ROLL)
	assert_eq(str(state.pending[0]["type"]), RulesEngine.DECISION_ROLL_OFFER)
	assert_eq(engine.apply(state, Move.make(Move.USE_ABILITY, 0, {"hero": "p0:TA-001", "card": "TA-001", "index": 0})), "")
	assert_eq(h.hex, Vector2i(4, 10))
	assert_eq(h.zone, HeroState.ZONE_MAP)
	assert_true(h.cores.has(core.id), "the core stays")
	assert_eq(state.hero("p1:TB-001").hex, Vector2i(6, 4), "the other hero stays where it rolled")
	assert_eq(state.phase, GameState.PHASE_POSTROLL, "the offer answered, on to Postroll")


func test_reverse_roll_only_after_the_roll() -> void:
	assert_ne(engine.reverse_roll(state, 0), "")
