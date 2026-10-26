extends GutTest
## What a guest may see (NetProtocol.redact): the others' Start pick stays secret until all
## have picked; a roll offer does not show the other player's hand cards.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState


func before_each() -> void:
	engine = RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 40}
	state = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-002"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	], 1)
	engine.apply(state, Move.make(Move.MULLIGAN, 0, {"keep": true}))
	engine.apply(state, Move.make(Move.MULLIGAN, 1, {"keep": true}))


func test_the_others_start_pick_is_hidden_until_all_picked() -> void:
	assert_eq(engine.apply(state, Move.make(Move.SELECT, 0, {"hero": "p0:TA-001", "roll": true})), "")
	var for_guest: Dictionary = NetProtocol.redact(state.to_dict(), 1)
	assert_false(JsonUtil.as_dict(for_guest["active"]).has("0"), "the host's hero is not shown yet")
	assert_false(JsonUtil.as_dict(for_guest["choices"]).has("0"), "nor its Roll / Stay")
	var for_host: Dictionary = NetProtocol.redact(state.to_dict(), 0)
	assert_true(JsonUtil.as_dict(for_host["active"]).has("0"), "own pick is shown")
	assert_eq(engine.apply(state, Move.make(Move.SELECT, 1, {"hero": "p1:TB-001", "roll": false})), "a hero in the start zone must roll")
	assert_eq(engine.apply(state, Move.make(Move.SELECT, 1, {"hero": "p1:TB-001", "roll": true})), "")
	for_guest = NetProtocol.redact(state.to_dict(), 1)
	assert_eq(str(for_guest["phase"]), GameState.PHASE_PREROLL)
	assert_true(JsonUtil.as_dict(for_guest["active"]).has("0"), "out together once all picked")


func test_a_roll_offer_hides_the_others_cards() -> void:
	state.pending.append({"type": RulesEngine.DECISION_ROLL_OFFER, "player": 0, "hero": "p0:TA-001",
		"abilities": [], "cards": ["TA-048"]})
	var for_guest: Dictionary = NetProtocol.redact(state.to_dict(), 1)
	var offer: Dictionary = JsonUtil.as_dict(JsonUtil.as_array(for_guest["pending"])[0])
	assert_eq(JsonUtil.as_strings(offer["cards"]), PackedStringArray([NetProtocol.PLACEHOLDER_CARD]))
	var for_host: Dictionary = NetProtocol.redact(state.to_dict(), 0)
	offer = JsonUtil.as_dict(JsonUtil.as_array(for_host["pending"])[0])
	assert_eq(JsonUtil.as_strings(offer["cards"]), PackedStringArray(["TA-048"]))
