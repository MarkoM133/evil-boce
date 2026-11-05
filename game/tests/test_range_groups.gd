extends GutTest
## ALL_ENEMY_IN_RANGE holds every enemy in SELF's range, not KO (Conqueror's Haki, 2026-11-05); a stage with
## one blocked and one free hero of a player still claims. ENGAGED (Intercept) is a friendly hero an enemy has
## in range, whether or not it reaches the enemy itself.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var s: GameState


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	s = engine.start_match(settings, [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	], 1)
	for id: String in ["p0:TA-001", "p0:TA-002", "p1:TB-001", "p1:TB-002", "p1:TB-003"]:
		s.hero(id).zone = "map"
	# TA-001 (range 3) at (5,8): TB-001 two away, TB-002 three away, TB-003 far; TA-002 (range 2) at (5,10).
	s.hero("p0:TA-001").hex = Vector2i(5, 8)
	s.hero("p0:TA-002").hex = Vector2i(5, 10)
	s.hero("p1:TB-001").hex = Vector2i(7, 8)
	s.hero("p1:TB-002").hex = Vector2i(8, 8)
	s.hero("p1:TB-003").hex = Vector2i(14, 14)


func _ctx() -> Dictionary:
	return {"player": 0, "hero": "p0:TA-001", "card": "TA-059", "stage": ""}


func test_all_enemy_in_range_holds_the_enemies_self_reaches() -> void:
	var e: FxEffect = FxEffect.parse_line("POSTROLL: NO_CLAIM ALL_ENEMY_IN_RANGE")
	assert_not_null(e)
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	assert_true(s.hero("p1:TB-001").has_status("no_claim"), "two hexes away")
	assert_true(s.hero("p1:TB-002").has_status("no_claim"), "three hexes away, range 3")
	assert_false(s.hero("p1:TB-003").has_status("no_claim"), "out of range")
	assert_false(s.hero("p0:TA-002").has_status("no_claim"), "friendly heroes are never in it")
	var ko: HeroState = s.hero("p1:TB-001")
	ko.statuses.clear()
	ko.hp = 0
	ko.zone = HeroState.ZONE_KO
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	assert_false(ko.has_status("no_claim"), "a KO hero is not in it")


func test_a_stage_claims_while_one_of_the_players_heroes_on_it_is_free() -> void:
	var st: StageState = s.stages[3]
	st.placed = true
	st.revealed = true
	st.center = Vector2i(7, 8)
	s.hero("p1:TB-002").hex = Vector2i(7, 9)
	s.hero("p1:TB-001").statuses["no_claim"] = 1
	assert_false(engine._claim_blocked(s, 1, st), "TB-002 on the stage is free")
	s.hero("p1:TB-002").statuses["no_claim"] = 1
	assert_true(engine._claim_blocked(s, 1, st), "both blocked")
	assert_false(engine._claim_blocked(s, 0, st), "the other player is not")
	s.hero("p1:TB-002").hex = Vector2i(14, 10)
	assert_true(engine._claim_blocked(s, 1, st), "only the blocked hero is left on it")


func test_engaged_is_a_friendly_hero_an_enemy_reaches() -> void:
	# TA-002 (range 2) at (5,10): TB-002 (range 3) at (8,8) reaches it? distance 3: yes; TA-002 does not reach back.
	s.hero("p1:TB-001").hex = Vector2i(14, 14)
	assert_eq(Hex.distance(Vector2i(5, 10), Vector2i(8, 8)), 3)
	assert_true(engine.fx._engaged(s, s.hero("p0:TA-002")), "an enemy with range 3 has it in range")
	s.hero("p1:TB-002").hex = Vector2i(14, 10)
	assert_false(engine.fx._engaged(s, s.hero("p0:TA-002")), "nobody reaches it")
	# Reaching an enemy itself is not enough any more: TA-001 (range 3) at (5,8) reaches TB-002 at (8,8) with range… put TB-002 at range 4 from a range-3 enemy.
	s.hero("p1:TB-002").hex = Vector2i(5, 12)
	assert_eq(Hex.distance(Vector2i(5, 10), Vector2i(5, 12)), 2)
	assert_true(engine.fx._engaged(s, s.hero("p0:TA-002")), "two away: both reach")
