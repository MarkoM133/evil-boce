extends GutTest
## The match record: frames per phase, JSON round trip, resume and "continue from here",
## the stats summary.

var catalog: CardCatalog
var engine: RulesEngine


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


func _decks() -> Array:
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	return [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 20, "TA-012": 2, "TA-040": 4}, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-011": 20}, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	]


func _start() -> MatchRecorder:
	var settings := MatchSettings.new()
	settings.manual_setup = false
	return MatchRecorder.start(engine, settings, _decks(), 7, [{"name": "Marko"}, {"name": "Bot", "bot": true}], "0.1.0")


func _play_to_select(rec: MatchRecorder) -> void:
	assert_eq(rec.apply(Move.make(Move.MULLIGAN, 0, {"keep": true})), "")
	assert_eq(rec.apply(Move.make(Move.MULLIGAN, 1, {"keep": true})), "")


func test_frames_follow_phases_and_hold_moves() -> void:
	var rec: MatchRecorder = _start()
	assert_eq(rec.record.frame_count(), 1)
	assert_eq(str(rec.record.frames[0]["phase"]), GameState.PHASE_MULLIGAN)
	assert_true(JsonUtil.as_bool(rec.record.players[1]["bot"]))
	assert_eq(JsonUtil.as_strings(rec.record.players[0]["heroes"]), PackedStringArray(["TA-001", "TA-002", "TA-003"]))
	_play_to_select(rec)
	# mulligan (2 moves) -> start (the draw is part of it, so nothing waits before).
	assert_eq(rec.state.phase, GameState.PHASE_START)
	assert_eq(JsonUtil.as_array(rec.record.frames[0]["moves"]).size(), 2)
	var phases := PackedStringArray()
	for f: Dictionary in rec.record.frames:
		phases.append(str(f["phase"]))
	assert_eq(phases, PackedStringArray([GameState.PHASE_MULLIGAN, GameState.PHASE_START]))
	assert_eq(rec.apply(Move.make(Move.SELECT, 0, {"hero": "nope"})), "not your hero")
	assert_eq(JsonUtil.as_array(rec.record.last_frame()["moves"]).size(), 0, "refused moves are not recorded")


func test_roll_outcome_is_recorded_with_its_path() -> void:
	var rec: MatchRecorder = _start()
	_play_to_select(rec)
	rec.apply(Move.make(Move.SELECT, 0, {"hero": "p0:TA-001", "roll": true}))
	rec.apply(Move.make(Move.SELECT, 1, {"hero": "p1:TB-001", "roll": true}))
	while not rec.state.round_over:
		rec.apply(Move.make(Move.PASS, rec.state.to_act))
	rec.apply(Move.make(Move.AIM, 0, {"dir": [0, -1], "power": 1.0}))
	rec.apply(Move.make(Move.AIM, 1, {"dir": [0, 1], "power": 1.0}))
	assert_true(rec.state.awaiting_roll)
	var o := RollOutcome.new()
	o.thrower = "p0:TA-001"
	var r := RollResult.new()
	r.ball_id = "p0:TA-001"
	r.thrown = true
	r.end_hex = Vector2i(2, 12)
	r.path = PackedVector3Array([Vector3(0, 0.6, 14), Vector3(0, 0.6, 10), Vector3(0.5, 0.6, 6)])
	o.add(r)
	var r2 := RollResult.new()
	r2.ball_id = "p1:TB-001"
	r2.thrown = true
	r2.end_hex = Vector2i(6, 4)
	o.add(r2)
	assert_eq(rec.apply_roll(o), "")
	# Both roll offers declined: the roll lands in the Roll frame, then the Postroll frame opens.
	assert_eq(rec.apply(Move.make(Move.PASS, 0)), "")
	assert_eq(rec.apply(Move.make(Move.PASS, 1)), "")
	var rolls: Array = JsonUtil.as_array(rec.record.frames[rec.record.frame_count() - 2]["rolls"])
	assert_eq(rolls.size(), 1)
	var back: RollOutcome = RollOutcome.from_dict(JsonUtil.as_dict(rolls[0]))
	assert_eq(back.thrower_result().path.size(), 3)
	assert_eq(rec.state.hero("p0:TA-001").hex, Vector2i(2, 12))


func test_json_round_trip_and_resume() -> void:
	var rec: MatchRecorder = _start()
	_play_to_select(rec)
	rec.apply(Move.make(Move.SELECT, 0, {"hero": "p0:TA-001", "roll": true}))
	var json: String = JSON.stringify(rec.record.to_dict())
	var loaded: MatchRecord = MatchRecord.from_dict(JsonUtil.as_dict(JSON.parse_string(json)))
	assert_eq(loaded.frame_count(), rec.record.frame_count())
	assert_eq(loaded.cards.size(), rec.record.cards.size())
	assert_true(loaded.cards.has("TA-001") and loaded.cards.has("TX-010") and loaded.cards.has("TS-004"))
	# Resume from the last frame: the state is the start of the Start phase, before p0's pick.
	var again: MatchRecorder = MatchRecorder.resume(RulesEngine.new(loaded.catalog()), loaded)
	assert_eq(again.state.phase, GameState.PHASE_START)
	assert_false(again.state.active.has(0))
	assert_eq(again.apply(Move.make(Move.SELECT, 0, {"hero": "p0:TA-002"})), "")
	assert_eq(again.record.frame_count(), loaded.frame_count())
	# The replay's own catalog knows the cards and their effects.
	assert_eq(loaded.catalog().get_card("TA-001").effects.size(), 1)
	assert_eq(loaded.catalog().get_card("TS-001").terrain, Terrain.Type.ICE)


func test_continue_from_an_earlier_frame() -> void:
	var rec: MatchRecorder = _start()
	_play_to_select(rec)
	rec.apply(Move.make(Move.SELECT, 0, {"hero": "p0:TA-001", "roll": true}))
	rec.apply(Move.make(Move.SELECT, 1, {"hero": "p1:TB-001", "roll": true}))
	assert_eq(rec.state.phase, GameState.PHASE_PREROLL)
	var branch: MatchRecorder = MatchRecorder.resume(engine, rec.record, 0)
	assert_eq(branch.state.phase, GameState.PHASE_MULLIGAN)
	assert_eq(branch.record.frame_count(), 1)
	assert_false(branch.record.finished)
	assert_eq(JsonUtil.as_array(branch.record.frames[0]["moves"]).size(), 0)
	assert_eq(branch.apply(Move.make(Move.MULLIGAN, 0, {"keep": false})), "")
	# The original is untouched.
	assert_eq(rec.record.frame_count(), 3)


func test_header_and_summary() -> void:
	var rec: MatchRecorder = _start()
	_play_to_select(rec)
	assert_eq(rec.apply(Move.make(Move.SURRENDER, 1)), "")
	assert_true(rec.record.finished)
	assert_eq(rec.record.winner, 0)
	assert_eq(rec.record.result, "surrender")
	var h: Dictionary = MatchRecord.header_from_dict(rec.record.to_dict())
	assert_eq(str(h["title"]), "Marko vs Bot")
	assert_eq(JsonUtil.as_int(h["turns"]), 1)
	assert_eq(JsonUtil.as_strings(h["names"]), PackedStringArray(["Marko", "Bot"]))
	assert_false(ReplayStore.is_match_against_someone(h, "Marko"), "a bot is not someone")
	assert_true(JsonUtil.as_bool(h["finished"]))
	var s: Dictionary = rec.record.summary()
	assert_eq(JsonUtil.as_int(s["winner"]), 0)
	assert_eq(str(s["result"]), "surrender")
	assert_eq(JsonUtil.as_int(s["turns"]), 1)
	var players: Array = s["players"]
	assert_eq(players.size(), 2)
	assert_true(JsonUtil.as_bool(JsonUtil.as_dict(players[1])["bot"]))
	assert_eq(JsonUtil.as_dict(s["cards_played"]).size(), 0)
	# How it went (the end screen's graph, 2026-11-08): one point per turn with each team's HP.
	var curve: Array = s["curve"]
	assert_eq(curve.size(), 1, "one turn, one point")
	var pt: Dictionary = JsonUtil.as_dict(curve[0])
	assert_eq(JsonUtil.as_int(pt["turn"]), 1)
	var hp: Dictionary = JsonUtil.as_dict(pt["hp"])
	assert_true(JsonUtil.as_int(hp.get(0, hp.get("0", 0))) > 0, "team 0 has HP")
	assert_true(JsonUtil.as_int(hp.get(1, hp.get("1", 0))) > 0, "team 1 has HP")
	assert_eq(JsonUtil.as_array(pt["claimed"]).size(), 0)


func test_which_replays_are_matches_against_someone() -> void:
	var h: Dictionary = {"finished": true, "result": "ko", "names": ["Marko", "Luka"], "bots": [false, false]}
	assert_true(ReplayStore.is_match_against_someone(h, "Marko"))
	assert_false(ReplayStore.is_match_against_someone(h, "Ivan"), "not one of the seats")
	var open: Dictionary = h.duplicate()
	open["finished"] = false
	assert_false(ReplayStore.is_match_against_someone(open, "Marko"), "not finished")
	var local: Dictionary = h.duplicate()
	local["names"] = ["Marko", "Player 2"]
	assert_false(ReplayStore.is_match_against_someone(local, "Marko"), "two seats at one screen")


func test_store_round_trip() -> void:
	var rec: MatchRecorder = _start()
	_play_to_select(rec)
	rec.apply(Move.make(Move.SURRENDER, 0))
	var path: String = ReplayStore.save_replay(rec.record)
	assert_true(FileAccess.file_exists(path), path)
	var listed: Array[Dictionary] = ReplayStore.list_replays()
	assert_true(listed.any(func(e: Dictionary) -> bool: return str(e["path"]) == path))
	var back: MatchRecord = ReplayStore.load_record(path)
	assert_eq(back.frame_count(), rec.record.frame_count())
	assert_true(ReplayStore.delete(path))
	assert_false(FileAccess.file_exists(path))
	ReplayStore.save_current(rec.record)
	assert_true(ReplayStore.has_current())
	assert_eq(ReplayStore.load_current().winner, 1)
	ReplayStore.clear_current()
	assert_false(ReplayStore.has_current())
	var stats: String = ReplayStore.write_stats(rec.record, ProjectSettings.globalize_path("user://"))
	assert_true(FileAccess.file_exists(stats))
	DirAccess.remove_absolute(stats)


func test_the_record_keeps_every_hero_a_first_tag_names() -> void:
	# "Alpha & Hotel" on TF-006: Hotel (TA-005) is in no deck, but a resumed match must still
	# read the tag as a hero tag, so the record carries Hotel too.
	var decks: Array = _decks()
	decks[0]["cards"] = {"TX-010": 19, "TF-006": 1}
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var rec: MatchRecorder = MatchRecorder.start(engine, settings, decks, 7, [{"name": "A"}, {"name": "B"}], "0.1.0")
	var back: CardCatalog = rec.record.catalog()
	assert_not_null(back.hero_named("Hotel"), "Hotel travels with the record")
	var k: Dictionary = FirstTag.kind_of(back, back.get_card("TF-006"))
	assert_eq(str(k["kind"]), FirstTag.HEROES)


## Code review 2026-11-13: a state that went through JSON (to a guest, into a record) had its heroes by id, the
## host's own as dealt: start-zone spots and the order of battles differed between the two.
func test_heroes_keep_their_order_through_json() -> void:
	var decks: Array = _decks()
	decks[0]["heroes"] = ["TA-003", "TA-001", "TA-002"]
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var rec: MatchRecorder = MatchRecorder.start(engine, settings, decks, 7, [{"name": "Marko"}, {"name": "Bot", "bot": true}], "0.1.0")
	var fresh := PackedStringArray()
	for h: HeroState in rec.state.heroes:
		fresh.append(h.id)
	assert_eq(fresh.slice(0, 3), PackedStringArray(["p0:TA-003", "p0:TA-001", "p0:TA-002"]), "as in the deck")
	var text: String = JSON.stringify(rec.state.to_dict())
	var loaded: GameState = GameState.from_dict(JsonUtil.as_dict(JSON.parse_string(text)))
	var after := PackedStringArray()
	for h: HeroState in loaded.heroes:
		after.append(h.id)
	assert_eq(after, fresh, "the same order on the other side of JSON")
	# What a guest gets (redacted) and what a record keeps, the same way.
	var guest: GameState = GameState.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(NetProtocol.redact(rec.state.to_dict(), 1, catalog)))))
	assert_eq(guest.heroes_of(0)[0].id, "p0:TA-003")
	var back: MatchRecord = MatchRecord.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(rec.record.to_dict()))))
	assert_eq(back.state_at(0).heroes_of(0)[0].id, "p0:TA-003")
	# A state written before the order was kept still loads, by id.
	var old: Dictionary = rec.state.to_dict()
	old.erase("hero_order")
	assert_eq(GameState.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(old)))).heroes.size(), 6)


## Code review 2026-11-13: a Combo is in no deck, so the record's own catalog had none and a match carried on
## from it never offered one.
func test_a_record_keeps_the_combos_its_cards_make() -> void:
	var decks: Array = _decks()
	decks[0]["cards"] = {"TX-010": 20, "TA-040": 4, "TA-042": 4}
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var rec: MatchRecorder = MatchRecorder.start(engine, settings, decks, 7, [{"name": "Marko"}, {"name": "Bot", "bot": true}], "0.1.0")
	var back: MatchRecord = MatchRecord.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(rec.record.to_dict()))))
	var combos: Array[CardDef] = back.catalog().of_type("Combo")
	assert_eq(combos.size(), 1)
	assert_eq(combos[0].id, "TC-001")
	assert_eq(combos[0].ingredients, PackedStringArray(["TA-040", "TA-042"]))
	assert_eq(combos[0].extra_cost, 1)
	assert_true(combos[0].is_ready(), "and it can be offered")
	# With only one of its two cards in the match it stays out.
	assert_eq(_start().record.catalog().of_type("Combo").size(), 0)


## Code review 2026-11-13: every list parsed every replay (2 MB each). A header is read from its file once and
## kept (ReplayStore.HEADERS) for as long as the file is the same.
func test_a_replays_header_is_read_once_and_again_when_the_file_changes() -> void:
	var rec: MatchRecorder = _start()
	_play_to_select(rec)
	rec.apply(Move.make(Move.SURRENDER, 0))
	var path: String = ReplayStore.save_replay(rec.record)
	var first: Dictionary = ReplayStore.header_of(path)
	assert_eq(str(first["title"]), "Marko vs Bot")
	assert_true(ReplayStore._headers.has(path.get_file()), "remembered")
	assert_eq(ReplayStore.header_of(path), first, "the same from memory")
	# As after a restart: from the file of headers.
	ReplayStore._keep_headers()
	ReplayStore._headers = {}
	ReplayStore._headers_read = false
	var cold: Dictionary = ReplayStore.header_of(path)
	assert_eq(cold, first, "the same from HEADERS, numbers and names as they were")
	assert_false(ReplayStore._headers_dirty, "and the replay itself was not read again")
	# Another match under the same name: read anew.
	var other: MatchRecorder = MatchRecorder.start(engine, MatchSettings.new(), _decks(), 9, [{"name": "Someone else"}, {"name": "Bot", "bot": true}], "0.1.0")
	ReplayStore._write_json(path, other.record.to_dict())
	assert_eq(str(ReplayStore.header_of(path)["title"]), "Someone else vs Bot")
	# Gone: a list forgets it.
	assert_true(ReplayStore.delete(path))
	ReplayStore.list_replays()
	assert_false(ReplayStore._headers.has(path.get_file()))
