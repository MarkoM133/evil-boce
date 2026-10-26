extends GutTest
## Physics knockback (GDD 10, 2026-10-26): in the "physics" mode, or for a Launch in "mixed",
## a knockback waits for the sim; its outcome lands the balls the way a roll does, and the
## knocked hero takes wall damage once per ball it hit.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState
var hero: HeroState


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	settings.knockback = "physics"
	var cards: Dictionary = {"TX-010": 40}
	state = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-002"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	], 1)
	hero = state.hero("p0:TA-001")
	hero.zone = HeroState.ZONE_MAP
	hero.hex = Vector2i(4, 10)


func _outcome(end_hex: Vector2i, hits: PackedStringArray = PackedStringArray(), ring_out: bool = false) -> RollOutcome:
	var o := RollOutcome.new()
	o.thrower = hero.id
	var r := RollResult.new()
	r.ball_id = hero.id
	r.end_area = BallWorld.Area.MAP
	r.end_hex = end_hex
	r.collisions = hits
	r.ring_out = ring_out
	o.add(r)
	return o


func test_a_physics_knockback_waits_for_the_sim_and_blocks_moves() -> void:
	engine.knockback(state, hero, 0, 3)
	assert_eq(hero.hex, Vector2i(4, 10), "not moved on the grid")
	assert_eq(state.pending_knockbacks.size(), 1)
	assert_eq(JsonUtil.as_int(state.pending_knockbacks[0]["steps"]), 3)
	assert_eq(engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true})), "waiting for the knockback")
	var hp: int = hero.hp
	assert_eq(engine.apply_knockback(state, _outcome(Vector2i(7, 10), PackedStringArray(["p1:TB-001"]))), "")
	assert_eq(hero.hex, Vector2i(7, 10), "lands where the sim stopped it")
	assert_eq(hero.hp, hp - state.settings.wall_damage, "wall damage once per ball hit")
	assert_true(state.pending_knockbacks.is_empty())
	assert_eq(engine.apply_knockback(state, _outcome(Vector2i(7, 10))), "no knockback waiting")
	assert_eq(engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true})), "", "moves again")


func test_no_hit_no_damage_and_a_ring_out_counts() -> void:
	engine.knockback(state, hero, 2, 2)
	var hp: int = hero.hp
	assert_eq(engine.apply_knockback(state, _outcome(Vector2i(4, 12))), "")
	assert_eq(hero.hp, hp, "a clean slide hurts nobody")
	engine.knockback(state, hero, 2, 2)
	assert_eq(engine.apply_knockback(state, _outcome(Vector2i(4, 14), PackedStringArray(), true)), "")
	assert_false(hero.is_on_map(), "off the table is a ring-out")


func test_grid_stays_grid_and_mixed_only_launches() -> void:
	state.settings.knockback = "grid"
	engine.knockback(state, hero, 0, 2)
	assert_true(state.pending_knockbacks.is_empty())
	assert_ne(hero.hex, Vector2i(4, 10), "moved on the grid")
	state.settings.knockback = "mixed"
	var at: Vector2i = hero.hex
	engine.knockback(state, hero, 0, 1)
	assert_true(state.pending_knockbacks.is_empty(), "a plain knockback stays on the grid in mixed")
	assert_ne(hero.hex, at)
	engine.knockback(state, hero, 0, 1, true)
	assert_eq(state.pending_knockbacks.size(), 1, "a Launch goes to the sim")
	var e: FxEffect = FxEffect.parse_line("BATTLE LAUNCH IF WIN: KNOCKBACK ENEMY 3")
	assert_not_null(e)
	assert_true(e.launch)
	assert_eq(e.to_fx(), "BATTLE LAUNCH IF WIN: KNOCKBACK ENEMY 3")
