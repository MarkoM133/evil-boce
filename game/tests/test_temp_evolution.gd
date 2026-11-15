extends GutTest
## Temporary evolutions (GDD 10, Marko 2026-11-15): an Evolution card with `tempTurns` goes on any level of its
## hero and is gone at the end of its last turn. Scenarios 83 and 84 play them through turns; this file holds the
## single rules that those do not reach.

var catalog: CardCatalog
var engine: RulesEngine

const TEMP: String = "TA-061"
const EVO: String = "TA-012"


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


func _state() -> GameState:
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var decks: Array = [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": [], "cores": []},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-010": 40}, "stages": [], "cores": []},
	]
	var s: GameState = engine.start_match(settings, decks, 3)
	s.active = {0: "p0:TA-001", 1: "p1:TB-001"}
	for id: String in ["p0:TA-001", "p1:TB-001"]:
		s.hero(id).zone = HeroState.ZONE_MAP
	s.phase = GameState.PHASE_PREROLL
	return s


func test_the_card_says_how_long_it_lasts() -> void:
	assert_eq(catalog.get_card(TEMP).temp_turns, 2)
	assert_eq(catalog.get_card(EVO).temp_turns, 0, "an evolution that stays")
	assert_eq(JsonUtil.as_int(catalog.get_card(TEMP).to_record().get("tempTurns", 0)), 2, "a record carries it")
	assert_false(catalog.get_card(EVO).to_record().has("tempTurns"))
	var action := CardDef.from_card({"id": "X-1", "name": "X", "type": "Action", "tempTurns": 3})
	assert_eq(action.temp_turns, 0, "only an Evolution can be temporary")


func test_the_hero_reads_the_temporary_card_and_a_saved_match_keeps_it() -> void:
	var s: GameState = _state()
	var h: HeroState = s.hero("p0:TA-001")
	h.evolutions = PackedStringArray([EVO])
	h.temp_evo = TEMP
	h.temp_until = 4
	assert_eq(engine.stat_card(h).id, TEMP, "the temporary card is on top of the level under it")
	assert_eq(engine.max_hp(s, h), 8)
	var back: HeroState = HeroState.from_dict(h.to_dict())
	assert_eq(back.temp_evo, TEMP)
	assert_eq(back.temp_until, 4)
	assert_eq(HeroState.from_dict({"id": "x"}).temp_evo, "", "an older record has none")


func test_a_ko_sends_it_to_the_graveyard_with_the_rest() -> void:
	var s: GameState = _state()
	var h: HeroState = s.hero("p0:TA-001")
	h.evolutions = PackedStringArray([EVO])
	h.temp_evo = TEMP
	h.temp_until = 4
	engine.knock_out(s, h)
	assert_eq(h.temp_evo, "")
	assert_true(s.player(0).graveyard.has(TEMP))
	assert_true(s.player(0).graveyard.has(EVO))


func test_it_goes_only_when_its_last_turn_ends() -> void:
	var s: GameState = _state()
	var h: HeroState = s.hero("p0:TA-001")
	h.temp_evo = TEMP
	h.temp_until = s.turn + 1
	engine._expire_temp_evolutions(s)
	assert_eq(h.temp_evo, TEMP, "one more turn")
	s.turn += 1
	engine._expire_temp_evolutions(s)
	assert_eq(h.temp_evo, "")
	var last: Dictionary = s.log[s.log.size() - 1]
	assert_eq(str(last.get("type", "")), "evolution_removed")
	assert_eq(str(last.get("why", "")), "expired")
	assert_true(JsonUtil.as_bool(last.get("temporary", false)))
