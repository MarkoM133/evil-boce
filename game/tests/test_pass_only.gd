extends GutTest
## Down to Pass or an Assist (RulesEngine.pass_only; Marko and Tarik 2026-11-13): for the rest of the turn where
## cards go to the activated hero, in the Battle phase only in the battle it fell in.

var catalog: CardCatalog
var engine: RulesEngine


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
	for id: String in ["p0:TA-001", "p0:TA-002", "p0:TA-003", "p1:TB-001", "p1:TB-002"]:
		s.hero(id).zone = HeroState.ZONE_MAP
	s.player(0).hand = PackedStringArray()
	return s


func test_fallen_in_a_battle_it_holds_in_that_battle_only() -> void:
	var s: GameState = _state()
	s.phase = GameState.PHASE_BATTLE
	s.battles = [{"heroes": ["p0:TA-001", "p0:TA-002", "p1:TB-001"]}, {"heroes": ["p0:TA-003", "p1:TB-002"]}]
	s.battle_index = 0
	assert_false(engine.pass_only(s, 0))
	engine.ring_out(s, s.hero("p0:TA-001"), "knockback")
	assert_true(s.only_pass.has(0))
	var fell: int = s.only_pass_battle[0]
	assert_eq(fell, 0, "the battle it fell in")
	assert_true(engine.pass_only(s, 0), "in that battle: also for its other hero there")
	assert_false(engine.pass_only(s, 1), "the other player is not touched")
	# Through JSON, as a guest and a record get it.
	var back: GameState = GameState.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(s.to_dict()))))
	assert_true(engine.pass_only(back, 0))
	s.battle_index = 1
	assert_false(engine.pass_only(s, 0), "the next battle: its other heroes play as ever")
	back.battle_index = 1
	assert_false(engine.pass_only(back, 0))
	# The next turn clears it.
	s.reset_turn_data()
	assert_false(s.only_pass.has(0))
	assert_true(s.only_pass_battle.is_empty())


func test_fallen_before_the_battles_no_battle_is_closed_but_the_other_phases_are() -> void:
	var s: GameState = _state()
	s.phase = GameState.PHASE_ROLL
	engine.ring_out(s, s.hero("p0:TA-001"), "edge")
	assert_true(s.only_pass.has(0))
	assert_true(s.only_pass_battle.is_empty())
	assert_true(engine.pass_only(s, 0), "the Roll phase")
	s.phase = GameState.PHASE_POSTROLL
	assert_true(engine.pass_only(s, 0), "and Postroll: cards go to the activated hero there, and it is gone")
	s.phase = GameState.PHASE_BATTLE
	s.battles = [{"heroes": ["p0:TA-002", "p1:TB-001"]}]
	s.battle_index = 0
	assert_false(engine.pass_only(s, 0), "its other hero's battle is played as ever")


func test_a_hero_that_is_not_the_activated_one_leaves_its_player_free() -> void:
	var s: GameState = _state()
	s.phase = GameState.PHASE_BATTLE
	s.battles = [{"heroes": ["p0:TA-002", "p1:TB-001"]}]
	s.battle_index = 0
	engine.ring_out(s, s.hero("p0:TA-002"), "knockback")
	assert_false(s.only_pass.has(0))
	assert_false(engine.pass_only(s, 0))
