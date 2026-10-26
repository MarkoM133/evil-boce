extends GutTest
## Automatic setup keeps the GDD distances on every map size.

var catalog: CardCatalog


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))


func test_auto_setup_keeps_stage_gaps() -> void:
	var engine := RulesEngine.new(catalog)
	for n: int in [15, 17, 23]:
		var core_relaxed: int = 0
		for seed_: int in [1, 2, 3, 4, 5]:
			var settings := MatchSettings.new()
			settings.map_size = n
			settings.manual_setup = false
			var s: GameState = engine.start_match(settings, _decks(), seed_)
			var gap: int = settings.effective_stage_gap()
			for e: Dictionary in s.log:
				if str(e.get("type", "")) != "setup_gap_relaxed":
					continue
				assert_false(e.has("stage"), "%dx%d seed %d had to relax a stage gap" % [n, n, seed_])
				core_relaxed += 1
			for a: StageState in s.stages:
				assert_true(a.placed)
				for b: StageState in s.stages:
					if a != b:
						# Empty hexes between edges = centre distance - 3.
						assert_true(Hex.distance(a.center, b.center) - 3 >= gap, "%dx%d stages too close" % [n, n])
			for c: CoreState in s.cores:
				assert_eq(c.place, CoreState.ON_FIELD)
				assert_null(s.stage_at(c.hex), "core on a stage")
		gut.p("%dx%d: %d core placements needed a smaller gap over 5 setups" % [n, n, core_relaxed])


static func _decks() -> Array:
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	return [
		{"heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-010": 40}, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	]


func test_a_smaller_deck_is_drawn_from_the_full_one() -> void:
	var engine := RulesEngine.new(catalog)
	var settings := MatchSettings.new()
	settings.manual_setup = false
	settings.deck_size = 20
	var s: GameState = engine.start_match(settings, _decks(), 3)
	# The starting hand is already drawn from it.
	for p: PlayerState in s.players:
		assert_eq(p.deck.size() + p.hand.size(), 20)
	var again: GameState = engine.start_match(settings, _decks(), 3)
	assert_eq(again.players[0].deck, s.players[0].deck, "the same seed draws the same twenty")
	settings.deck_size = 40
	var full: PlayerState = engine.start_match(settings, _decks(), 3).players[0]
	assert_eq(full.deck.size() + full.hand.size(), 40)
