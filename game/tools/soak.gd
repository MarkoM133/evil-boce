extends SceneTree
## Long bot matches to hunt errors: Hard bots play both sides of the real match scene (physics,
## timers, effects) in every game mode and the tool reports errors, stalls and results.
## godot_console --headless --fixed-fps 60 --path game -s res://tools/soak.gd --
##     [--modes=standard,fast,chaos,bo3,draft,physics] [--games=2] [--seed=1]
##     [--max-minutes=40] [--stall-minutes=3]
## "physics" is Standard with the physical knockback. A Best of 3 counts as one game. Minutes
## are game time (60 frames a second); with --fixed-fps the tool runs faster than that.
## Nothing is saved (dev matches). Exit code 1 when anything went wrong.

const MATCH_SCENE: String = "res://scenes/match/match.tscn"


class Catcher extends Logger:
	var lines: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text: String = rationale if not rationale.is_empty() else code
		_mutex.lock()
		lines.append("%s (%s:%d %s)" % [text, file.get_file(), line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> Array[String]:
		_mutex.lock()
		var out: Array[String] = lines.duplicate()
		lines.clear()
		_mutex.unlock()
		return out


var _catcher := Catcher.new()
var _rng := RandomNumberGenerator.new()
var _problems: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var opts: Dictionary[String, String] = {
		"modes": "standard,fast,chaos,bo3,draft,physics",
		"games": "2",
		"seed": "1",
		"max-minutes": "40",
		"stall-minutes": "3",
	}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			opts[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	OS.add_logger(_catcher)
	GameSettings.in_memory = true
	GameSettings.set_value("display", "anim_speed", "fast")
	_rng.seed = int(opts["seed"])
	var db: CardDb = CardDb.load_from(GameSettings.data_path())
	if db == null or db.catalog == null:
		push_error("No card catalog (is the shared folder set?)")
		quit(1)
		return
	var catalog: CardCatalog = db.catalog
	var limits := Vector2i(int(opts["max-minutes"]) * 3600, int(opts["stall-minutes"]) * 3600)
	var started: int = Time.get_ticks_msec()
	for mode: String in opts["modes"].split(",", false):
		for g: int in int(opts["games"]):
			if mode == "bo3":
				await _series(catalog, limits, g)
			else:
				await _game(catalog, mode, limits, "%s #%d" % [mode, g + 1], -1)
	print("SOAK done in %.1f min, %d problem(s)" % [(Time.get_ticks_msec() - started) / 60000.0, _problems])
	quit(1 if _problems > 0 else 0)


func _settings(mode: String) -> MatchSettings:
	var s: MatchSettings = MatchSettings.preset("standard" if mode == "physics" else mode)
	if mode == "physics":
		s.knockback = "physics"
		s.mode = "custom"
	s.resolve_map(_rng, GameSettings.MAP_SIZES)
	return s


func _decks(catalog: CardCatalog, mode: String, settings: MatchSettings) -> Array:
	var raw: Array[Dictionary] = []
	if mode == "draft":
		var d: DraftState = DraftState.start(catalog, _rng.randi(), _rng.randi_range(0, 1), settings.deck_size)
		var guard: int = 0
		while d.phase != DraftState.PHASE_DONE and guard < 500:
			guard += 1
			var slot: int = d.waiting_on()
			var err: String = d.pick(slot, Bot.draft_pick(catalog, d, slot, _rng))
			if not err.is_empty():
				push_error("draft pick refused: " + err)
				break
		raw = d.decks()
	else:
		for slot: int in 2:
			raw.append(DeckCode.random_deck(catalog, _rng))
	var out: Array = []
	for slot: int in 2:
		out.append(MatchLaunch.engine_deck(catalog, raw[slot], "Bot %d" % (slot + 1), _rng))
	return out


## One game; returns the winner (-1 a draw, -2 when it did not finish).
func _game(catalog: CardCatalog, mode: String, limits: Vector2i, label: String, first: int,
		settings: MatchSettings = null, decks: Array = []) -> int:
	if settings == null:
		settings = _settings(mode)
	if decks.is_empty():
		decks = _decks(catalog, mode, settings)
	settings.first_initiative = first
	var seed_: int = _rng.randi()
	MatchLaunch.config = {
		"settings": settings,
		"decks": decks,
		"bots": PackedInt32Array([0, 1]),
		"bot_level": "hard",
		"seed": seed_,
		"dev": true,
	}
	var errors: Array[String] = _catcher.take()
	if not errors.is_empty():
		_report(label + " (before the match)", errors)
	var node: Node = (load(MATCH_SCENE) as PackedScene).instantiate()
	root.add_child(node)
	current_scene = node
	var frames: int = 0
	var still: int = 0
	var last: String = ""
	var outcome: String = "timeout"
	while frames < limits.x:
		await process_frame
		frames += 1
		var state: GameState = node.get("state")
		if state == null:
			continue
		if state.is_over():
			outcome = "over"
			break
		var rec: MatchRecorder = node.get("recorder")
		var key: String = "%d|%s|%d|%d" % [state.turn, state.phase, state.pending.size(),
			rec.record.frame_count() if rec != null else 0]
		if key == last:
			still += 1
			if still >= limits.y:
				outcome = "stall"
				break
		else:
			still = 0
			last = key
	var state: GameState = node.get("state")
	var winner: int = -2
	var line: String = "%s  map %d  seed %d  " % [label, settings.map_size, seed_]
	if outcome == "over":
		winner = state.winner
		line += "turn %d  %s  %s  (%.1f game min)" % [state.turn,
			"draw" if winner < 0 else "slot %d won" % winner, state.result, frames / 3600.0]
	else:
		line += "%s at turn %d phase %s pending %d to_act %d" % [outcome.to_upper(),
			state.turn if state != null else -1, state.phase if state != null else "?",
			state.pending.size() if state != null else -1, state.to_act if state != null else -1]
		_problems += 1
	print(line)
	_report(label, _catcher.take())
	node.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	return winner


func _series(catalog: CardCatalog, limits: Vector2i, g: int) -> void:
	var settings: MatchSettings = _settings("bo3")
	var series := MatchSeries.new(settings.series_wins)
	var decks: Array = _decks(catalog, "bo3", settings)
	var game: int = 0
	while not series.is_over() and game < 6:
		game += 1
		var s: MatchSettings = MatchSettings.from_dict(settings.to_dict())
		var first: int = series.next_initiative() if game > 1 else -1
		# Stages and cores are picked again for every game (all random here).
		var again: Array = []
		for slot: int in 2:
			var deck: Dictionary = JsonUtil.as_dict(decks[slot]).duplicate()
			var picks: Dictionary = Loadout.random().resolve(catalog, _rng)
			deck["stages"] = picks["stages"]
			deck["cores"] = picks["cores"]
			again.append(deck)
		var w: int = await _game(catalog, "bo3", limits, "bo3 #%d game %d" % [g + 1, game], first, s, again)
		if w == -2:
			return
		series.record(w)
	print("bo3 #%d  series %s  %s" % [g + 1, series.score(),
		"draw" if series.winner() < 0 else "slot %d takes it" % series.winner()])
	if not series.is_over():
		print("  PROBLEM: the series did not end after %d games" % game)
		_problems += 1


func _report(label: String, errors: Array[String]) -> void:
	if errors.is_empty():
		return
	_problems += 1
	var counts: Dictionary[String, int] = {}
	for e: String in errors:
		counts[e] = counts.get(e, 0) + 1
	print("  %s: %d error(s)" % [label, errors.size()])
	for e: String in counts:
		print("    %dx %s" % [counts[e], e])
