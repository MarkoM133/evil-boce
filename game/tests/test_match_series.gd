extends GutTest
## A series of games (Best of 3, GDD 13): the score, the loser's first move, draws, the cap,
## and the first move handed to the engine.

const FIXTURE: String = "res://tests/fixtures/cards.json"


func test_first_to_two_wins_and_the_loser_starts_the_next_game() -> void:
	var s := MatchSeries.new(2)
	assert_eq(s.max_games, 5)
	assert_eq(s.next_initiative(), -1, "lots at first")
	s.record(1)
	assert_eq(s.score(), "0–1")
	assert_eq(s.next_initiative(), 0, "the loser starts")
	assert_false(s.is_over())
	s.record(0)
	assert_eq(s.next_initiative(), 1)
	assert_eq(s.winner(), -1, "level")
	s.record(0)
	assert_true(s.is_over())
	assert_eq(s.winner(), 0)


func test_a_draw_counts_for_nobody_and_the_cap_ends_it() -> void:
	var s := MatchSeries.new(2)
	s.record(-1)
	assert_eq(s.score(), "0–0")
	assert_eq(s.next_initiative(), -1, "lots after a draw")
	for _i: int in 4:
		s.record(-1)
	assert_true(s.is_over(), "five games played")
	assert_eq(s.winner(), -1, "a drawn series")
	var again := MatchSeries.new(2)
	again.record(1)
	for _i: int in 4:
		again.record(-1)
	assert_true(again.is_over())
	assert_eq(again.winner(), 1, "more wins after the cap")


func test_round_trip_keeps_the_decks() -> void:
	var s := MatchSeries.new(2)
	s.decks = [{"name": "A", "heroes": ["TA-001"], "cards": {"TX-010": 40}}, {"name": "B", "heroes": ["TB-001"], "cards": {}}]
	s.record(0)
	var back: MatchSeries = MatchSeries.from_dict(s.to_dict())
	assert_eq(back.score(), "1–0")
	assert_eq(back.next_initiative(), 1)
	assert_eq(str(JsonUtil.as_dict(back.decks[0]).get("name", "")), "A")


func test_the_engine_takes_the_first_move_from_the_settings() -> void:
	var engine := RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	settings.first_initiative = 1
	var cards: Dictionary = {"TX-010": 40}
	var decks: Array = [
		{"heroes": ["TA-001"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"heroes": ["TB-001"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	]
	assert_eq(engine.start_match(settings, decks, 4).initiative, 1)
	settings.first_initiative = -1
	var seen: Dictionary = {}
	for seed: int in 12:
		seen[engine.start_match(settings, decks, seed).initiative] = true
	assert_eq(seen.size(), 2, "lots when nobody is named")
