extends GutTest
## Energy claims (Marko and Tarik 2026-11-02) under physics knockback: whose doing each knocked
## hero's leaving a stage is. A tie-break sends each side back by the other's doing, so both
## lose half of their energy; a ball a knocked hero hits off a stage is the same team's doing.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState
var stage: StageState


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	settings.knockback = "physics"
	settings.stage_claim = MatchSettings.CLAIM_ENERGY
	settings.stage_goal = 14
	var cards: Dictionary = {"TX-010": 40}
	state = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-002"], "cards": cards, "stages": ["TS-001"], "cores": []},
		{"heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-006"], "cores": []},
	], 1)
	stage = state.stage("stage:p0:1")
	stage.center = Vector2i(4, 8)
	stage.placed = true
	stage.revealed = true
	state.stage("stage:p1:1").placed = false
	_on_map("p0:TA-001", Vector2i(3, 8))
	_on_map("p1:TB-001", Vector2i(5, 8))


func _on_map(id: String, hex: Vector2i) -> void:
	var h: HeroState = state.hero(id)
	h.zone = HeroState.ZONE_MAP
	h.hex = hex


func _result(id: String, end_hex: Vector2i, hits: PackedStringArray = PackedStringArray()) -> RollResult:
	var r := RollResult.new()
	r.ball_id = id
	r.end_area = BallWorld.Area.MAP
	r.end_hex = end_hex
	r.collisions = hits
	return r


func _knocked_off(id: String) -> Dictionary:
	for e: Dictionary in state.log:
		if str(e.get("type", "")) == "stage_knocked_off" and str(e.get("hero", "")) == id:
			return e
	return {}


func test_a_tie_break_costs_both_sides_half() -> void:
	stage.progress = {0: 7, 1: 6}
	# What _battle_tie queues on the second tie: each side back by the other's doing.
	engine.knockback(state, state.hero("p0:TA-001"), 1, 2, 1)
	engine.knockback(state, state.hero("p1:TB-001"), 4, 2, 0)
	assert_eq(state.pending_knockbacks.size(), 2)
	var o := RollOutcome.new()
	o.add(_result("p0:TA-001", Vector2i(1, 8)))
	o.add(_result("p1:TB-001", Vector2i(7, 8)))
	assert_eq(engine.apply_knockback(state, o), "")
	assert_eq(stage.progress_of(0), 4, "player 0 lost half of 7, rounded down")
	assert_eq(stage.progress_of(1), 3, "player 1 lost half of 6")
	assert_eq(JsonUtil.as_int(_knocked_off("p0:TA-001").get("by_team", -1)), 1)
	assert_eq(JsonUtil.as_int(_knocked_off("p1:TB-001").get("by_team", -1)), 0)


func test_a_ball_the_knocked_hero_hits_off_a_stage_is_the_same_doing() -> void:
	stage.progress = {0: 7}
	state.hero("p1:TB-001").zone = HeroState.ZONE_STRIP
	var other: StageState = state.stage("stage:p1:1")
	other.center = Vector2i(1, 10)
	other.placed = true
	other.revealed = true
	other.progress = {0: 8, 1: 5}
	_on_map("p0:TA-002", Vector2i(1, 9))
	_on_map("p1:TB-002", Vector2i(2, 10))
	# Team 1 knocks TA-001 off its stage; it rolls on into TA-002 and TB-002 on the other one.
	engine.knockback(state, state.hero("p0:TA-001"), 3, 3, 1)
	var o := RollOutcome.new()
	o.add(_result("p0:TA-001", Vector2i(1, 8), PackedStringArray(["p0:TA-002", "p1:TB-002"])))
	o.add(_result("p0:TA-002", Vector2i(1, 12), PackedStringArray(["p0:TA-001"])))
	o.add(_result("p1:TB-002", Vector2i(4, 10), PackedStringArray(["p0:TA-001"])))
	assert_eq(engine.apply_knockback(state, o), "")
	assert_eq(stage.progress_of(0), 4, "knocked off by team 1")
	assert_eq(other.progress_of(0), 4, "pushed off through team 1's knockback: half gone")
	assert_eq(other.progress_of(1), 5, "team 1's own knockback moved its own ball: nothing lost")
	assert_eq(JsonUtil.as_int(_knocked_off("p0:TA-002").get("by_team", -1)), 1)
	assert_true(_knocked_off("p1:TB-002").is_empty())


func test_a_knocked_hero_that_stays_on_the_stage_loses_nothing() -> void:
	stage.progress = {0: 7}
	engine.knockback(state, state.hero("p0:TA-001"), 1, 1, 1)
	var o := RollOutcome.new()
	o.add(_result("p0:TA-001", Vector2i(4, 7)))
	assert_eq(engine.apply_knockback(state, o), "")
	assert_eq(stage.progress_of(0), 7)
	assert_true(_knocked_off("p0:TA-001").is_empty())
