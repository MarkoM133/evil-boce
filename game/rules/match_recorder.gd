class_name MatchRecorder
extends RefCounted
## Runs a match through the RulesEngine and writes a MatchRecord as it goes: every accepted
## move and roll outcome lands in the current frame, and each new phase opens a new frame with
## a snapshot of the state (GDD 2: save/load and replays snapshot between phases, never mid
## physics). The match scene, the bots and later the network host all drive the engine
## through this, so every match is recorded the same way.

var engine: RulesEngine
var state: GameState
var record: MatchRecord


## Starts a new match. `players` describe the seats: [{"name", "bot": bool, "deck_name"}] by slot.
static func start(engine_: RulesEngine, settings: MatchSettings, decks: Array, seed: int,
		players: Array, game_version: String = "") -> MatchRecorder:
	var rec := MatchRecorder.new()
	rec.engine = engine_
	rec.state = engine_.start_match(settings, decks, seed)
	var r := MatchRecord.new()
	r.game_version = game_version
	r.cards_version = engine_.catalog.version
	r.created = Time.get_datetime_string_from_system(true) + "Z"
	r.settings = settings.to_dict()
	r.decks = decks.duplicate(true)
	r.seed = seed
	for i: int in decks.size():
		var d: Dictionary = JsonUtil.as_dict(decks[i])
		var meta: Dictionary = JsonUtil.as_dict(players[i]) if i < players.size() else {}
		r.players.append({
			"slot": i,
			"name": str(meta.get("name", d.get("name", "Player %d" % (i + 1)))),
			"team": rec.state.team_of(i),
			"bot": JsonUtil.as_bool(meta.get("bot", false)),
			"deck_name": str(meta.get("deck_name", d.get("deck_name", ""))),
			"heroes": Array(JsonUtil.as_strings(d.get("heroes", []))),
			"stages": Array(JsonUtil.as_strings(d.get("stages", []))),
		})
	r.cards = _used_cards(engine_.catalog, decks)
	rec.record = r
	rec._open_frame()
	return rec


## Continues a recorded match from frame `index` (the last one for a plain load). The record
## keeps the frames up to there and grows from the resumed state.
static func resume(engine_: RulesEngine, record_: MatchRecord, index: int = -1) -> MatchRecorder:
	var rec := MatchRecorder.new()
	rec.engine = engine_
	var i: int = index if index >= 0 else record_.frame_count() - 1
	rec.record = record_.branch_at(i)
	rec.state = rec.record.state_at(i)
	return rec


## Applies a move; "" or the engine's refusal. Accepted moves are recorded.
func apply(m: Move) -> String:
	var err: String = engine.apply(state, m)
	if not err.is_empty():
		return err
	var f: Dictionary = record.last_frame()
	JsonUtil.as_array(f.get("moves", [])).append(m.to_dict())
	_after()
	return ""


## Feeds a roll outcome; "" or the engine's refusal. Accepted outcomes are recorded with
## their paths, so a replay shows the roll without re-running the physics.
func apply_roll(o: RollOutcome) -> String:
	var err: String = engine.apply_roll(state, o)
	if not err.is_empty():
		return err
	var f: Dictionary = record.last_frame()
	JsonUtil.as_array(f.get("rolls", [])).append(o.to_dict())
	_after()
	return ""


func _after() -> void:
	var f: Dictionary = record.last_frame()
	if state.phase != str(f.get("phase", "")) or state.turn != JsonUtil.as_int(f.get("turn", -1)):
		_open_frame()
	if state.is_over() and not record.finished:
		record.finished = true
		record.winner = state.winner
		record.result = state.result


func _open_frame() -> void:
	record.frames.append({
		"index": record.frames.size(),
		"turn": state.turn,
		"phase": state.phase,
		"state": state.to_dict(),
		"moves": [],
		"rolls": [],
	})


## Card records (as in cards.json) of every card the decks, stages and cores refer to.
static func _used_cards(catalog: CardCatalog, decks: Array) -> Dictionary:
	var out: Dictionary = {}
	for d: Variant in decks:
		var dd: Dictionary = JsonUtil.as_dict(d)
		var ids := PackedStringArray()
		ids.append_array(JsonUtil.as_strings(dd.get("heroes", [])))
		ids.append_array(JsonUtil.as_strings(dd.get("stages", [])))
		ids.append_array(JsonUtil.as_strings(dd.get("cores", [])))
		for k: Variant in JsonUtil.as_dict(dd.get("cards", {})):
			ids.append(str(k))
		for id: String in ids:
			var c: CardDef = catalog.get_card(id)
			if c != null and not out.has(id):
				out[id] = c.to_record()
				# Evolutions refer to their hero by name; keep the hero too.
				if c.type == "Evolution":
					var h: CardDef = catalog.hero_named(c.hero)
					if h != null and not out.has(h.id):
						out[h.id] = h.to_record()
	return out
