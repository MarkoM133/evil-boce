extends GutTest
## A colorless Assist like Rayleigh: "Your {Haki} cards cost 1 less to play. Cyan Bonus: This card
## costs 1 less to play." (PASSIVE: COST ME -1 {Haki} / PLAY BONUS: OWN_COST -1). An assist helps
## the player, not one hero: the discount counts for every Haki card of its owner, for any hero.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine
var s: GameState


func before_each() -> void:
	var db: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var list: Array = db["cards"]
	list.append({"id": "TR-010", "name": "Rayleigh", "type": "Assist", "color": "None", "bonusColors": ["Cyan"], "cost": 3,
		"traits": ["Haki"], "text": "x", "fx": "PASSIVE: COST ME -1 {Haki}\nPLAY BONUS: OWN_COST -1"})
	engine = RulesEngine.new(CardCatalog.from_json_text(JSON.stringify(db)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	s = engine.start_match(settings, [
		{"name": "A", "heroes": ["TA-001", "TB-004", "TA-005"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	], 1)


func _cost(slot: int, card: String, hero: String) -> int:
	return engine.card_cost(s, s.player(slot), engine.catalog.get_card(card), s.hero(hero))


func test_the_cyan_bonus_lowers_its_own_price_only_for_a_cyan_hero() -> void:
	assert_eq(_cost(0, "TR-010", "p0:TB-004"), 2, "Cyan hero: 1 less")
	assert_eq(_cost(0, "TR-010", "p0:TA-001"), 3, "Red hero: full price")


func test_in_play_every_haki_card_of_its_owner_costs_less_for_any_hero() -> void:
	assert_eq(_cost(0, "TA-049", "p0:TA-001"), 3)
	s.player(0).assists.append("TR-010")
	assert_eq(_cost(0, "TA-049", "p0:TA-001"), 2, "a Haki card for one Red hero")
	assert_eq(_cost(0, "TA-049", "p0:TA-005"), 2, "and for the other")
	assert_eq(_cost(1, "TA-049", "p1:TB-001"), 3, "not the opponent's cards")
	assert_eq(_cost(0, "TX-010", "p0:TA-001"), 1, "not cards without Haki")
