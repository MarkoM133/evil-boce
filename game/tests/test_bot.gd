extends GutTest
## Whole matches between two bots without graphics: throws land where the analytic model says
## (straight line, no bounces). Checks that the bots never get stuck and matches reach an end.

const MAX_STEPS: int = 4000

var catalog: CardCatalog
var tuning: PhysicsTuning


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	tuning = PhysicsTuning.load_default()


func _decks() -> Array:
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	return [
		{"name": "Easy", "heroes": ["TA-001", "TA-005", "TA-003"], "cards": {"TA-040": 4, "TA-043": 4, "TA-044": 4, "TA-020": 4, "TA-045": 4, "TX-010": 20},
			"stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "Hard", "heroes": ["TB-001", "TB-002", "TB-004"], "cards": {"TA-040": 4, "TA-043": 4, "TA-047": 4, "TA-051": 4, "TX-010": 24},
			"stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	]


func test_bots_finish_matches() -> void:
	var results := PackedStringArray()
	for seed_: int in [3, 11, 29]:
		var engine := RulesEngine.new(catalog)
		var settings: MatchSettings = MatchSettings.standard()
		settings.manual_setup = true
		var s: GameState = engine.start_match(settings, _decks(), seed_)
		var bots: Array[Bot] = [Bot.new(seed_, Bot.Level.EASY), Bot.new(seed_ + 1, Bot.Level.HARD)]
		var steps: int = 0
		while not s.is_over() and s.turn <= 30 and steps < MAX_STEPS:
			steps += 1
			if s.awaiting_roll:
				assert_eq(engine.apply_roll(s, _roll(s, engine)), "")
				continue
			var moved: bool = false
			for slot: int in 2:
				var m: Move = bots[slot].next_move(engine, s, slot, _positions(s), tuning)
				if m == null:
					continue
				var err: String = engine.apply(s, m)
				assert_eq(err, "", "seed %d turn %d %s: %s refused: %s" % [seed_, s.turn, s.phase, JSON.stringify(m.to_dict()), err])
				if not err.is_empty():
					return
				moved = true
				break
			if not moved:
				fail_test("seed %d: nobody can move in turn %d %s (pending %d)" % [seed_, s.turn, s.phase, s.pending.size()])
				return
		assert_true(s.is_over() or s.turn > 30, "seed %d got stuck after %d steps" % [seed_, steps])
		assert_true(s.turn >= 3, "seed %d ended too early" % seed_)
		results.append("seed %d: turn %d, %s" % [seed_, s.turn, ("winner p%d (%s)" % [s.winner, s.result]) if s.is_over() else "no winner yet"])
	gut.p("Easy (p0) vs Hard (p1): " + "; ".join(results))


## Where each hero is in the world; heroes on a strip stand in a row behind their edge.
func _positions(s: GameState) -> Dictionary[String, Vector2]:
	var out: Dictionary[String, Vector2] = {}
	var m: HexMap = s.map()
	var lo: float = INF
	var hi: float = -INF
	for a: Vector2i in m.cells():
		var p: Vector2 = m.to_world(a)
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	for h: HeroState in s.heroes:
		if h.is_on_map():
			out[h.id] = m.to_world(h.hex)
		else:
			var i: int = s.heroes_of(h.owner).find(h)
			var z: float = hi + 2.0 if s.team_of(h.owner) == 0 else lo - 2.0
			out[h.id] = Vector2((i - 1) * 4.0 * tuning.hex_spacing(), z)
	return out


## The analytic roll: each thrower goes straight for power x full range.
func _roll(s: GameState, engine: RulesEngine) -> RollOutcome:
	var o := RollOutcome.new()
	var pos: Dictionary[String, Vector2] = _positions(s)
	var m: HexMap = s.map()
	for id: String in s.pending_rolls:
		var h: HeroState = s.hero(id)
		var aim: Dictionary = s.aims.get(h.owner, {})
		var dir_a: Array = JsonUtil.as_array(aim.get("dir", [0, -1]))
		var dir := Vector2(JsonUtil.as_float(dir_a[0]), JsonUtil.as_float(dir_a[1])).normalized()
		var card: CardDef = engine.catalog.get_card(h.card_id)
		var full: float = tuning.full_power_hexes(card.wt if card != null else 2) * tuning.hex_spacing()
		var from: Vector2 = pos[id]
		var end: Vector2 = from + dir * JsonUtil.as_float(aim.get("power", 1.0)) * full
		var r := RollResult.new()
		r.ball_id = id
		r.thrown = true
		var a: Vector2i = m.from_world(end)
		if m.contains(a):
			# Snap to the nearest free hex, as the sim does.
			for cell: Vector2i in Hex.spiral(a, 3):
				if s.is_free(cell, h.big, h):
					a = cell
					break
			r.end_area = BallWorld.Area.MAP
			r.end_hex = a
		elif m.contains(m.from_world(from)) or from.distance_to(end) > 3.0 * tuning.hex_spacing():
			r.ring_out = true
			r.ring_out_reason = "edge"
			r.end_area = BallWorld.Area.VOID
		else:
			r.end_area = BallWorld.Area.STRIP
		if o.thrower.is_empty():
			o.thrower = id
		o.add(r)
	return o
