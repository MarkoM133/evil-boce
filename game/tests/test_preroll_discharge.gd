extends GutTest
## An equipment like Enma: "Preroll Phase: You must discharge 1 Energy if the equipped Hero is
## activated." (PREROLL IF ACTIVATED: DISCHARGE ME 1). It fires as the Preroll phase starts, after the
## turn's energy came in, and drains its owner's energy, never the opponent's; on a hero that is not
## activated it does nothing.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var engine: RulesEngine


func _to_preroll(holder: String) -> GameState:
	var db: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var list: Array = db["cards"]
	list.append({"id": "TE-001", "name": "Enma", "type": "Equipment", "color": "None", "bonusColors": ["Yellow"], "cost": 2,
		"traits": ["Sword"], "bonus": {"pwr": 2000}, "text": "x", "fx": "PREROLL IF ACTIVATED: DISCHARGE ME 1\nPASSIVE BONUS: BUFF EQUIPPED PWR 1000"})
	engine = RulesEngine.new(CardCatalog.from_json_text(JSON.stringify(db)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	var s: GameState = engine.start_match(settings, [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	], 1)
	for slot: int in 2:
		assert_eq(engine.apply(s, Move.from_dict({"type": "mulligan", "player": slot, "keep": true})), "")
	for id: String in ["p0:TA-001", "p1:TB-002"]:
		var h: HeroState = s.hero(id)
		h.zone = "map"
		h.hex = Vector2i(4, 10) if id.begins_with("p0") else Vector2i(6, 4)
	s.hero(holder).equipment.append("TE-001")
	s.initiative = 0
	assert_eq(engine.apply(s, Move.from_dict({"type": "select", "player": 0, "hero": "p0:TA-001", "roll": false})), "")
	assert_eq(engine.apply(s, Move.from_dict({"type": "select", "player": 1, "hero": "p1:TB-002", "roll": false})), "")
	assert_eq(s.phase, GameState.PHASE_PREROLL)
	return s


func test_on_the_activated_hero_it_drains_its_owner() -> void:
	var s: GameState = _to_preroll("p0:TA-001")
	var full: int = mini(s.turn, s.settings.max_energy)
	assert_eq(s.player(0).energy, full - 1, "the owner discharges 1")
	assert_eq(s.player(1).energy, full, "the opponent keeps all")


func test_on_a_hero_that_is_not_activated_it_does_nothing() -> void:
	var s: GameState = _to_preroll("p0:TA-002")
	assert_eq(s.player(0).energy, mini(s.turn, s.settings.max_energy))
