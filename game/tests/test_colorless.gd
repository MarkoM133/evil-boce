extends GutTest
## Colorless cards (2026-11-01): the fx grammar for BONUS / INSTEAD / OWN_COST, the price in the
## hand per hero, and an equipment's stat bonus for a hero of the bonus colour.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var catalog: CardCatalog
var engine: RulesEngine


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE))
	engine = RulesEngine.new(catalog)


func test_fx_grammar_round_trip() -> void:
	for line: String in ["PLAY BONUS RED: OWN_COST -1", "PASSIVE BONUS: BUFF EQUIPPED DMG 1",
			"PREROLL RANGE INSTEAD BONUS: HEAL FRIENDLY 4", "BATTLE INSTEAD BONUS IF ACTIVATED: BUFF SELF PWR 2000"]:
		var e: FxEffect = FxEffect.parse_line(line)
		assert_not_null(e, line)
		if e != null:
			assert_eq(e.to_fx(), line)
	assert_null(FxEffect.parse_line("PLAY BONUS ORANGE: OWN_COST -1"), "an unknown colour is not a flag")


func test_text_of_the_fixture_cards() -> void:
	assert_eq(catalog.get_card("TF-020").fx, "PREROLL: HEAL SELF 5\nPLAY BONUS RED: OWN_COST -1")
	assert_eq(catalog.get_card("TF-021").fx, "PASSIVE BONUS RED: BUFF EQUIPPED DMG 1")
	assert_eq(catalog.get_card("TF-022").fx, "PREROLL: HEAL SELF 2\nPREROLL INSTEAD BONUS: HEAL SELF 4")
	assert_eq(catalog.get_card("TF-023").fx, "PREROLL: HEAL SELF 1\nPREROLL BONUS YELLOW: CHARGE ME 1")
	for id: String in ["TF-020", "TF-021", "TF-022", "TF-023"]:
		assert_true(catalog.get_card(id).is_ready(), id + " ready")


func _preroll() -> GameState:
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	var decks: Array = [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"],
			"cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"],
			"cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
	]
	var s: GameState = engine.start_match(settings, decks, 1)
	for slot: int in 2:
		assert_eq(engine.apply(s, Move.from_dict({"type": "mulligan", "player": slot, "keep": true})), "")
	for id: String in ["p0:TA-001", "p1:TB-002"]:
		var h: HeroState = s.hero(id)
		h.zone = "map"
		h.hex = Vector2i(4, 10) if id.begins_with("p0") else Vector2i(6, 4)
	s.initiative = 0
	assert_eq(engine.apply(s, Move.from_dict({"type": "select", "player": 0, "hero": "p0:TA-001", "roll": false})), "")
	assert_eq(engine.apply(s, Move.from_dict({"type": "select", "player": 1, "hero": "p1:TB-002", "roll": false})), "")
	assert_eq(s.phase, GameState.PHASE_PREROLL)
	return s


func test_price_in_the_hand_follows_the_activated_hero() -> void:
	var s: GameState = _preroll()
	var card: CardDef = catalog.get_card("TF-020")
	assert_eq(engine.card_cost(s, s.player(0), card), 2, "a Red hero gets the Red bonus")
	assert_eq(engine.card_cost(s, s.player(1), card), 3, "a Cyan hero pays the full price")
	assert_eq(engine.card_cost(s, s.player(0), card, s.hero("p1:TB-002")), 3, "the price is per hero")


func test_equipment_stat_bonus_only_for_the_bonus_colour() -> void:
	var s: GameState = _preroll()
	var red: HeroState = s.hero("p0:TA-001")
	var cyan: HeroState = s.hero("p1:TB-002")
	var before_red: int = engine.stat(s, red, "dmg")
	var before_cyan: int = engine.stat(s, cyan, "dmg")
	red.equipment.append("TF-021")
	cyan.equipment.append("TF-021")
	assert_eq(engine.stat(s, red, "dmg"), before_red + 3, "+2 on the card and +1 Red bonus")
	assert_eq(engine.stat(s, cyan, "dmg"), before_cyan + 2, "+2 on the card only")
