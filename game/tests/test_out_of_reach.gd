extends GutTest
## A battle the winner cannot hit from (playtest 2026-11-06, Kaido range 2 against Luffy range 3 three
## hexes away): no damage decision, and the log says why, so a win with nothing after it is not a mystery.

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
	for id: String in ["p0:TA-001", "p1:TB-001"]:
		s.hero(id).zone = "map"
	# Three hexes apart: both reach (range 3) until the winner's range drops.
	s.hero("p0:TA-001").hex = Vector2i(4, 8)
	s.hero("p1:TB-001").hex = Vector2i(7, 8)
	s.battles = [{"heroes": ["p0:TA-001", "p1:TB-001"], "resolved": false, "winner_team": -1, "tie": false}]
	s.battle_index = 0
	s.phase = GameState.PHASE_BATTLE


func _events(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in s.log:
		if str(e.get("type", "")) == type:
			out.append(e)
	return out


func test_a_winner_out_of_reach_deals_no_hit_and_the_log_says_so() -> void:
	s.hero("p0:TA-001").turn_bonus = {"pwr": 2000, "rng": -1}
	engine._resolve_battle(s, 0)
	assert_eq(s.pending.size(), 0, "no damage decision")
	var far: Array[Dictionary] = _events("out_of_reach")
	assert_eq(far.size(), 1)
	assert_eq(str(far[0].get("hero", "")), "p0:TA-001")
	assert_eq(JsonUtil.as_strings(far[0].get("losers", [])), PackedStringArray(["p1:TB-001"]))


func test_a_winner_in_reach_hits_and_says_nothing_extra() -> void:
	s.hero("p0:TA-001").turn_bonus = {"pwr": 2000}
	engine._resolve_battle(s, 0)
	assert_eq(s.pending.size(), 1, "the loser places the hit")
	assert_eq(_events("out_of_reach").size(), 0)
