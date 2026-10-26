extends GutTest
## Roll offers (GDD 8, 2026-10-26): what goes on one, how the clock keys them, and where the
## decisions an answer asks for go.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 40}
	state = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-005"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	], 1)
	state.active[0] = "p0:TA-001"
	state.active[1] = "p1:TB-001"
	for p: PlayerState in state.players:
		p.energy = 5


func _offers() -> void:
	state.pending.clear()
	engine._offer_roll_effects(state)


func test_only_cards_the_first_tag_lets_the_hero_play_are_offered() -> void:
	# TF-007 is for Hotel only, TF-008 for any Red hero; Alpha is the activated hero.
	state.player(0).hand = PackedStringArray(["TF-007", "TF-008", "TF-004"])
	_offers()
	assert_eq(state.pending.size(), 2, "one offer per player")
	var mine: Dictionary = state.pending[engine.roll_offer_index(state, 0)]
	assert_eq(JsonUtil.as_strings(mine["cards"]), PackedStringArray(["TF-008"]))


func test_the_other_player_answering_keeps_my_offer_key() -> void:
	_offers()
	var before: String = MatchClock.wait_key(engine, state, 0)
	assert_true(before.begins_with("offer|"))
	assert_eq(engine.apply(state, Move.make(Move.PASS, 1)), "")
	assert_eq(MatchClock.wait_key(engine, state, 0), before, "my clock does not restart")
	assert_eq(MatchClock.wait_key(engine, state, 1), "", "the other has answered")
	assert_eq(engine.apply(state, Move.make(Move.PASS, 0)), "")
	assert_true(state.pending.is_empty())


func test_the_decisions_an_answer_asks_for_come_first() -> void:
	state.pending = [{"type": "roll_offer", "player": 0}, {"type": "choose", "player": 1}] as Array[Dictionary]
	engine._decisions_first(state, 1)
	assert_eq(str(state.pending[0]["type"]), "choose", "the answering player's choice is up")
	assert_eq(str(state.pending[1]["type"]), "roll_offer")
	engine._decisions_first(state, 2)
	assert_eq(str(state.pending[0]["type"]), "choose", "nothing added, nothing moves")
