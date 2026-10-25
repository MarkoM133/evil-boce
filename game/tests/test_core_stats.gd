extends GutTest
## Cores in a hero's slots count in its stats (GDD 7.4), a Debuff never pulls a stat under 0,
## and a core that leaves the hero stops counting.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	var settings := MatchSettings.new()
	settings.manual_setup = false
	state = engine.start_match(settings, [
		{"name": "A", "heroes": ["TA-001", "TA-003"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"],
			"cores": ["CR1-001", "CR1-002", "CR1-003", "CR1-004", "CR0-005", "CR0-006"]},
		{"name": "B", "heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"],
			"cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
	], 1)


func _give(h: HeroState, core_id: String) -> void:
	var c: CoreState = state.core(core_id)
	c.place = CoreState.ON_HERO
	c.holder = h.id
	c.face_up = true
	h.cores.append(core_id)


func test_cores_add_to_the_stats() -> void:
	var h: HeroState = state.hero("p0:TA-001")
	assert_eq(engine.stat(state, h, "pwr"), 2000)
	assert_eq(engine.stat(state, h, "dmg"), 3)
	_give(h, "core:p0:1")
	_give(h, "core:p0:2")
	assert_eq(engine.stat(state, h, "pwr"), 6000, "+4000 Power core")
	assert_eq(engine.stat(state, h, "dmg"), 5, "+2 Damage core")
	assert_eq(engine.stat(state, h, "kb"), 2, "no core touches KB")


func test_a_debuff_never_pulls_a_stat_under_zero() -> void:
	var h: HeroState = state.hero("p0:TA-003")
	assert_eq(engine.stat(state, h, "dmg"), 2)
	_give(h, "core:p0:3")
	assert_eq(engine.stat(state, h, "dmg"), 0, "2 − 2")
	_give(h, "core:p0:4")
	assert_eq(engine.stat(state, h, "kb"), 0, "1 − 1 stays at 0, not −1")


func test_a_core_that_leaves_stops_counting() -> void:
	var h: HeroState = state.hero("p0:TA-001")
	_give(h, "core:p0:1")
	assert_eq(engine.stat(state, h, "pwr"), 6000)
	h.cores.remove_at(0)
	state.core("core:p0:1").place = CoreState.ON_FIELD
	assert_eq(engine.stat(state, h, "pwr"), 2000)


func test_a_core_without_a_bonus_changes_nothing() -> void:
	var h: HeroState = state.hero("p0:TA-001")
	_give(h, "core:p0:5")
	assert_eq(engine.stat(state, h, "pwr"), 2000)
	assert_eq(engine.stat(state, h, "dmg"), 3)
