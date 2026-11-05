extends GutTest
## A stage's BATTLE duel (Elbaph, 2026-11-05): DUEL_TOP PWR 2000 PICK asks the winner which of their heroes in the
## battle gets the bonus; a tie gives nothing and the top cards stay on the decks.

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
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": cards, "stages": ["TS-008", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	], 1)
	for id: String in ["p0:TA-001", "p0:TA-002", "p1:TB-001"]:
		s.hero(id).zone = "map"
	s.hero("p0:TA-001").hex = Vector2i(4, 8)
	s.hero("p0:TA-002").hex = Vector2i(5, 9)
	s.hero("p1:TB-001").hex = Vector2i(6, 8)
	var st: StageState = s.stages[0]
	st.placed = true
	st.revealed = true
	st.center = Vector2i(5, 8)
	s.battles = [{"heroes": ["p0:TA-001", "p0:TA-002", "p1:TB-001"], "resolved": false, "winner_team": -1, "tie": false}]
	s.battle_index = 0
	s.phase = GameState.PHASE_BATTLE


func _ctx() -> Dictionary:
	return {"player": -1, "hero": "", "card": "TS-008", "stage": s.stages[0].id, "battle": 0}


func test_the_winner_picks_one_of_their_heroes_in_the_battle() -> void:
	s.player(0).deck = PackedStringArray(["TA-049", "TX-010"])
	s.player(1).deck = PackedStringArray(["TX-010", "TX-010"])
	var e: FxEffect = FxEffect.parse_line("BATTLE: DUEL_TOP PWR 2000 PICK")
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	assert_eq(s.pending.size(), 1, "the winner is asked")
	var d: Dictionary = s.pending[0]
	assert_eq(JsonUtil.as_int(d["player"]), 0)
	assert_eq(JsonUtil.as_array(d["options"]), ["p0:TA-001", "p0:TA-002"])
	s.pending.pop_front()
	assert_eq(engine.fx.resume(s, d, "p0:TA-002"), "")
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-002").phase_bonus.get("pwr", 0)), 2000, "the picked hero")
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-001").phase_bonus.get("pwr", 0)), 0, "not the other")
	assert_eq(s.player(0).deck[0], "TA-049", "the shown card stays on top")


func test_a_tie_gives_nothing() -> void:
	s.player(0).deck = PackedStringArray(["TX-010"])
	s.player(1).deck = PackedStringArray(["TX-010"])
	var e: FxEffect = FxEffect.parse_line("BATTLE: DUEL_TOP PWR 2000 PICK")
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	assert_eq(s.pending.size(), 0)
	for id: String in ["p0:TA-001", "p0:TA-002", "p1:TB-001"]:
		assert_eq(JsonUtil.as_int(s.hero(id).phase_bonus.get("pwr", 0)), 0, id)


func test_most_energy_buffs_the_richer_players_heroes_in_the_battle() -> void:
	s.player(0).energy = 3
	s.player(1).energy = 1
	var e: FxEffect = FxEffect.parse_line("BATTLE: BUFF MOST_ENERGY PWR 3000")
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-001").phase_bonus.get("pwr", 0)), 3000)
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-002").phase_bonus.get("pwr", 0)), 3000, "both heroes of the richer player in the battle")
	assert_eq(JsonUtil.as_int(s.hero("p1:TB-001").phase_bonus.get("pwr", 0)), 0)
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-003").phase_bonus.get("pwr", 0)), 0, "not a hero outside the battle")


func test_most_energy_tie_gives_nothing() -> void:
	s.player(0).energy = 2
	s.player(1).energy = 2
	var e: FxEffect = FxEffect.parse_line("BATTLE: BUFF MOST_ENERGY PWR 3000")
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	for id: String in ["p0:TA-001", "p0:TA-002", "p1:TB-001"]:
		assert_eq(JsonUtil.as_int(s.hero(id).phase_bonus.get("pwr", 0)), 0, id)


func test_pick_lets_the_richer_player_choose_one_hero() -> void:
	s.player(0).energy = 3
	s.player(1).energy = 1
	var e: FxEffect = FxEffect.parse_line("BATTLE: BUFF MOST_ENERGY PWR 3000 PICK")
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	assert_eq(s.pending.size(), 1, "the richer player is asked")
	var d: Dictionary = s.pending[0]
	assert_eq(JsonUtil.as_int(d["player"]), 0)
	assert_eq(JsonUtil.as_array(d["options"]), ["p0:TA-001", "p0:TA-002"])
	s.pending.pop_front()
	assert_eq(engine.fx.resume(s, d, "p0:TA-002"), "")
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-002").phase_bonus.get("pwr", 0)), 3000, "the picked hero")
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-001").phase_bonus.get("pwr", 0)), 0, "not the other")
	# One hero in the battle: no question.
	s.battles[0]["heroes"] = ["p0:TA-001", "p1:TB-001"]
	s.hero("p0:TA-002").phase_bonus.clear()
	assert_eq(engine.fx.run(s, _ctx(), e), "")
	assert_eq(s.pending.size(), 0)
	assert_eq(JsonUtil.as_int(s.hero("p0:TA-001").phase_bonus.get("pwr", 0)), 3000)
