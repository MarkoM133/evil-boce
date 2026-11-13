extends GutTest
## Manual setup never boxes a piece out (Marko 2026-11-13: the sixth stage had no legal hex and the bot stood
## still): a spot that would leave the pieces still to come without room is refused, so placing at random, hex by
## hex, always gets every stage and every core onto the map.

var catalog: CardCatalog
var engine: RulesEngine


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


func _decks() -> Array:
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	return [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-010": 40}, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	]


## Places everything at random legal hexes; returns {"stuck": what had no hex or "", "refused": spots the look-ahead
## refused, "relaxed": pieces placed at a smaller gap}.
func _random_setup(map_size: int, seed_: int) -> Dictionary:
	var settings: MatchSettings = MatchSettings.standard()
	settings.map_size = map_size
	settings.manual_setup = true
	var s: GameState = engine.start_match(settings, _decks(), seed_)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 31 + 7
	var refused: int = 0
	var guard: int = 0
	while (s.phase == GameState.PHASE_SETUP_STAGES or s.phase == GameState.PHASE_SETUP_CORES) and guard < 40:
		guard += 1
		var who: int = s.setup_turn
		var legal: Array[Vector2i] = []
		var move: String = Move.PLACE_STAGE
		var id: String = ""
		if s.phase == GameState.PHASE_SETUP_STAGES:
			var st: StageState = null
			for x: StageState in s.stages:
				if x.owner == who and not x.placed:
					st = x
					break
			id = st.id
			for a: Vector2i in s.map().cells():
				var err: String = engine.stage_placement_error(s, st, a)
				if err.is_empty():
					legal.append(a)
				elif err.begins_with("no room"):
					refused += 1
		else:
			move = Move.PLACE_CORE
			var c: CoreState = null
			for x: CoreState in s.cores:
				if x.owner == who and x.place == CoreState.UNPLACED:
					c = x
					break
			id = c.id
			for a: Vector2i in s.map().cells():
				var err: String = engine.core_placement_error(s, c, a)
				if err.is_empty():
					legal.append(a)
				elif err.begins_with("no room"):
					refused += 1
		if legal.is_empty():
			return {"stuck": id, "refused": refused, "relaxed": 0}
		var key: String = "stage" if move == Move.PLACE_STAGE else "core"
		var why: String = engine.apply(s, Move.make(move, who, {key: id, "hex": Hex.to_json(legal[rng.randi_range(0, legal.size() - 1)])}))
		if not why.is_empty():
			return {"stuck": "%s refused: %s" % [id, why], "refused": refused, "relaxed": 0}
	var relaxed: int = 0
	for e: Dictionary in s.log:
		if str(e.get("type", "")) == "setup_gap_relaxed":
			relaxed += 1
	return {"stuck": "" if guard < 40 else "never finished", "refused": refused, "relaxed": relaxed}


func test_random_setups_always_finish_on_the_standard_map() -> void:
	var refused: int = 0
	var relaxed: int = 0
	var t0: int = Time.get_ticks_msec()
	for seed_: int in range(1, 61):
		var r: Dictionary = _random_setup(23, seed_)
		assert_eq(str(r["stuck"]), "", "seed %d" % seed_)
		refused += JsonUtil.as_int(r["refused"])
		relaxed += JsonUtil.as_int(r["relaxed"])
	gut.p("60 setups on 23x23: %d ms, %d spots refused by the look-ahead, %d pieces at a smaller gap" % [Time.get_ticks_msec() - t0, refused, relaxed])
	assert_gt(refused, 0, "the look-ahead had something to refuse")
	assert_eq(relaxed, 0, "Standard never needs the smaller gap")


func test_random_setups_finish_on_every_map() -> void:
	for map_size: int in [15, 17, 25, 27]:
		for seed_: int in range(1, 13):
			assert_eq(str(_random_setup(map_size, seed_)["stuck"]), "", "map %d seed %d" % [map_size, seed_])


func test_fits_counts_what_still_fits() -> void:
	# A row of ten hexes, pieces at least 3 apart: four fit (0, 3, 6, 9), five do not.
	var row: Array[Vector2i] = []
	for x: int in 10:
		row.append(Vector2i(x, 0))
	assert_true(SetupFit.fits(row, 4, 3))
	assert_false(SetupFit.fits(row, 5, 3))
	# With hex 1 taken, 4 and 7 are left for two more, not three.
	var rest: Array[Vector2i] = SetupFit.without(row, Vector2i(1, 0), 3)
	assert_true(SetupFit.fits(rest, 2, 3))
	assert_false(SetupFit.fits(rest, 3, 3))
