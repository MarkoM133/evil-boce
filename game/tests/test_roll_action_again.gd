extends GutTest
## A "Roll Phase:" Action needs no OPTIONAL: playing it from the roll offer is the "may", and
## passing the offer is the "no" (fx-keywords: an Action's WHEN only says when it may be played).
## ROLL_AGAIN rolls the activated hero once more right after its roll.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var state: GameState


func _action(id: String, fx: String) -> Dictionary:
	return {"id": id, "name": id, "type": "Action", "color": "Red", "cost": 1, "traits": ["General"], "text": "x", "fx": fx}


func before_each() -> void:
	var db: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var list: Array = db["cards"]
	list.append(_action("TR-001", "ROLL: ROLL_AGAIN"))
	list.append(_action("TR-002", "ROLL OPTIONAL: ROLL_AGAIN"))
	engine = RulesEngine.new(CardCatalog.from_json_text(JSON.stringify(db)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 40}
	state = engine.start_match(settings, [
		{"heroes": ["TA-001", "TA-005"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"heroes": ["TB-001", "TB-002"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	], 1)
	state.active[0] = "p0:TA-001"
	state.active[1] = "p1:TB-001"
	state.choices[0] = true
	state.choices[1] = true
	state.phase = GameState.PHASE_ROLL
	state.rolled = true
	for p: PlayerState in state.players:
		p.energy = 5
	state.pending.clear()


func _play_from_offer(card: String) -> void:
	state.player(0).hand = PackedStringArray([card])
	engine._offer_roll_effects(state)
	var mine: Dictionary = state.pending[engine.roll_offer_index(state, 0)]
	assert_eq(JsonUtil.as_strings(mine["cards"]), PackedStringArray([card]), "offered")
	assert_eq(engine.apply(state, Move.make(Move.PLAY_CARD, 0, {"card": card, "hero": "p0:TA-001"})), "")


func test_a_roll_action_without_optional_rolls_again_when_played() -> void:
	_play_from_offer("TR-001")
	assert_false(state.rolled, "the hero is to roll again")
	assert_eq(state.pending_rolls, PackedStringArray(["p0:TA-001"]))
	assert_eq(engine.roll_offer_index(state, 1), -1, "the other offers of this stop fall away")


func test_optional_on_an_action_changes_nothing() -> void:
	_play_from_offer("TR-002")
	assert_false(state.rolled)
	assert_eq(state.pending_rolls, PackedStringArray(["p0:TA-001"]))


func test_passing_the_offer_is_the_no() -> void:
	state.player(0).hand = PackedStringArray(["TR-001"])
	engine._offer_roll_effects(state)
	assert_eq(engine.apply(state, Move.make(Move.PASS, 0)), "")
	assert_true(state.rolled, "no new roll")
	assert_eq(state.player(0).hand, PackedStringArray(["TR-001"]), "the card stays in hand")


func test_only_the_hero_rolling_again_is_thrown_again() -> void:
	# Both aims of the first roll are still there (playtest 2026-11-06: Luffy rolled again and the
	# opponent's Zoro was thrown a second and third time with its old aim, once out of the arena).
	state.aims[0] = {"dir": [0.0, 1.0], "power": 0.6}
	state.aims[1] = {"dir": [0.0, -1.0], "power": 0.5}
	_play_from_offer("TR-001")
	assert_false(state.aims.has(0), "the roller aims again")
	assert_true(JsonUtil.as_bool(state.aims[1].get("skip", false)), "the opponent's ball stays where it stopped")
