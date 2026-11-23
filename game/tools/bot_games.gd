extends SceneTree
## Bot-against-bot matches through the rules engine alone (no scene, no physics: grid knockback
## and the analytic roll of tests/test_bot.gd), counting how a rule change shifts the game.
## godot_console --headless --path game -s res://tools/bot_games.gd -- [--games=20] [--seed=1]
##     [--level=hard] [--max-turns=60] [--fixtures] [--claim=stay|energy|ring] [--goal=14] [--report=<file.json>] [--force=<card id>]
##     [--drafts[=<id prefix>]]
## Random decks from the shared folder's cards (`--fixtures`: the test fixtures). Reports, over
## all games: hero damage taken and from what (battle, wall, trap, card), cards discarded for
## battle hits, KOs, how the matches ended, turns, cards played and the energy they took; with
## who started the match against who won it; with energy claims (the shared ring is the default, goal `--goal`; `--claim=energy` each side its own, `--claim=stay` the first rule) also the energy put into stages,
## heroes knocked off a stage and the energy that cost, contested stages. The same seed gives the
## same maps and decks whatever the rules, so runs compare game by game. Nothing is saved, except with
## --report: per hero, card and stage how often it was in a deck, won, and (cards) was played, as JSON.
## --force=<card id>: three copies of that card go into every deck, and it is played (and its optional abilities
## used) whenever the rules allow, before the bot is asked: a card the bots see no gain in still gets its rules run
## through whole matches (companions, 2026-11-21).

const MAX_STEPS: int = 6000

var _rng := RandomNumberGenerator.new()
var _tuning: PhysicsTuning
var _force: String = ""
## Forced plays and ability uses that went in, and what the companions did (from the log).
var _forced: Dictionary[String, int] = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var opts: Dictionary[String, String] = {"games": "20", "seed": "1", "level": "hard", "max-turns": "60", "fixtures": "0",
		"claim": MatchSettings.CLAIM_RING, "goal": "14"}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			opts[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
		elif arg.begins_with("--"):
			opts[arg.substr(2)] = "1"
	GameSettings.in_memory = true
	_rng.seed = int(opts["seed"])
	_tuning = PhysicsTuning.load_default()
	var catalog: CardCatalog
	if opts["fixtures"] == "1":
		catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	else:
		var db: CardDb = CardDb.load_from(GameSettings.data_path())
		if db == null or db.catalog == null:
			push_error("No card catalog (is the shared folder set?); try --fixtures")
			quit(1)
			return
		catalog = db.catalog
	# --drafts[=<id prefix>]: the Card Studio drafts play too (those whose id starts with the prefix; all without one),
	# in place of a published card with the same id: a set gets its rules run through whole matches before it is
	# published. A draft the game cannot read yet is left out and named.
	if opts.has("drafts") and opts["fixtures"] != "1":
		var data: String = GameSettings.data_path().path_join("data")
		var doc: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(data.path_join("cards.json"))))
		var drafts: Dictionary = JsonUtil.as_dict(JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(data.path_join("editor/drafts.json")))).get("cards", {}))
		var prefix: String = "" if opts["drafts"] == "1" else opts["drafts"]
		var list: Array = JsonUtil.as_array(doc.get("cards", []))
		var added: int = 0
		for key: Variant in drafts:
			var rec: Dictionary = JsonUtil.as_dict(drafts[key]).duplicate()
			rec["id"] = str(rec.get("id", key))
			if not str(rec["id"]).begins_with(prefix):
				continue
			var probe: CardDef = CardDef.from_card(rec)
			if not probe.is_ready():
				print("draft not ready, left out: %s %s %s" % [rec["id"], probe.name, str(probe.unparsed)])
				continue
			list = list.filter(func(c: Variant) -> bool: return str(JsonUtil.as_dict(c).get("id", "")) != str(rec["id"]))
			list.append(rec)
			added += 1
		doc["cards"] = list
		catalog = CardCatalog.from_doc(doc)
		print("drafts in play: %d" % added)
	var level: Bot.Level = Bot.level_from(opts["level"])
	_force = str(opts.get("force", ""))
	var games: int = int(opts["games"])
	var claim: String = opts["claim"]
	var goal: int = int(opts["goal"])
	var totals: Dictionary = {
		"hero_dmg": 0, "battle_hero_dmg": 0, "wall_dmg": 0, "trap_dmg": 0, "card_dmg": 0,
		"hand_cards": 0, "deck_cards": 0, "hits": 0, "hits_with_cards": 0, "all_on_hero": 0, "kos": 0, "ring_outs": 0,
		"turns": 0, "finished": 0, "results": {}, "stuck": 0, "first_won": 0, "first_lost": 0, "seat0_won": 0,
		"cards_played": 0, "energy_cards": 0, "energy_banked": 0, "energy_wasted": 0, "knocked_off": 0, "knocked_off_lost": 0,
		"progress_lost": 0, "contested": 0, "claims": 0, "energy_taken": 0, "turn_list": [],
	}
	var lines := PackedStringArray()
	# Balance per hero, card and stage (Marko 2026-11-16): in how many decks, how many of those won, and how
	# often a card was played. A draw counts as a game, not a win.
	var by_hero: Dictionary = {}
	var by_card: Dictionary = {}
	var by_stage: Dictionary = {}
	for g: int in games:
		var r: Dictionary = _game(catalog, level, int(opts["max-turns"]), claim, goal)
		_tally(r, by_hero, by_card, by_stage)
		for k: String in ["hero_dmg", "battle_hero_dmg", "wall_dmg", "trap_dmg", "card_dmg", "hand_cards", "deck_cards", "hits", "hits_with_cards", "all_on_hero", "kos", "ring_outs", "turns",
			"cards_played", "energy_cards", "energy_banked", "energy_wasted", "knocked_off", "knocked_off_lost", "progress_lost",
			"contested", "claims", "energy_taken"]:
			totals[k] = JsonUtil.as_int(totals[k]) + JsonUtil.as_int(r[k])
		if not str(r["result"]).is_empty():
			var tl: Array = totals["turn_list"]
			tl.append(JsonUtil.as_int(r["turns"]))
		if str(r["result"]).is_empty():
			totals["stuck"] = JsonUtil.as_int(totals["stuck"]) + 1
		else:
			totals["finished"] = JsonUtil.as_int(totals["finished"]) + 1
			var res: Dictionary = totals["results"]
			res[r["result"]] = JsonUtil.as_int(res.get(r["result"], 0)) + 1
			# Who started (the initiative at match start, drawn by lot) against who won (Marko 2026-11-16).
			var w: int = JsonUtil.as_int(r["winner"])
			if w >= 0:
				totals["first_won" if w == JsonUtil.as_int(r["first"]) else "first_lost"] = JsonUtil.as_int(totals["first_won" if w == JsonUtil.as_int(r["first"]) else "first_lost"]) + 1
				if w == 0:
					totals["seat0_won"] = JsonUtil.as_int(totals["seat0_won"]) + 1
		lines.append("game %2d: %2d turns, %-9s hero dmg %3d (battle %3d) · hand cards %2d · KO %d · ring-outs %d · cards played %2d · stage energy %2d · knocked off %d (-%d) · contested %d" % [
			g + 1, r["turns"], (str(r["result"]) + (" p%d" % JsonUtil.as_int(r["winner"]))) if not str(r["result"]).is_empty() else "unfinished",
			r["hero_dmg"], r["battle_hero_dmg"], r["hand_cards"], r["kos"], r["ring_outs"], r["cards_played"], r["energy_banked"],
			r["knocked_off"], r["progress_lost"], r["contested"]])
	for l: String in lines:
		print(l)
	var n: int = maxi(games, 1)
	print("")
	print("%d games, %s vs %s, seed %s, %s cards, stage claims: %s" % [games, Bot.level_name(level), Bot.level_name(level), opts["seed"],
		"fixture" if opts["fixtures"] == "1" else "shared-folder", ("%s, goal %d" % [claim, goal]) if claim != MatchSettings.CLAIM_STAY else claim])
	_print_balance(catalog, by_hero, by_card)
	if opts.has("report"):
		var f := FileAccess.open(opts["report"], FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"games": games, "level": Bot.level_name(level), "seed": opts["seed"], "claim": claim,
				"heroes": by_hero, "cards": by_card, "stages": by_stage}, "  "))
			f.close()
			print("report: " + opts["report"])
		else:
			push_error("cannot write " + opts["report"])
	if not _force.is_empty():
		print("forced %s: %s" % [_force, JSON.stringify(_forced)])
	elif not _forced.is_empty():
		print("companions: %s" % JSON.stringify(_forced))
	var decided: int = JsonUtil.as_int(totals["first_won"]) + JsonUtil.as_int(totals["first_lost"])
	if decided > 0:
		print("who started won %d of %d (%.1f%%); seat 0 won %d (%.1f%%)" % [totals["first_won"], decided, 100.0 * JsonUtil.as_int(totals["first_won"]) / decided,
			totals["seat0_won"], 100.0 * JsonUtil.as_int(totals["seat0_won"]) / decided])
	var results: Dictionary = totals["results"]
	print("finished %d (%s)%s" % [totals["finished"], _results_line(results), (", unfinished %d" % JsonUtil.as_int(totals["stuck"])) if JsonUtil.as_int(totals["stuck"]) > 0 else ""])
	print("turns: %.1f per game" % (float(JsonUtil.as_int(totals["turns"])) / n))
	var tl_all: Array = totals["turn_list"]
	if not tl_all.is_empty():
		tl_all.sort()
		var sum_t: int = 0
		for x: Variant in tl_all:
			sum_t += JsonUtil.as_int(x)
		print("finished games: %.1f turns on average, median %d, shortest %d, longest %d" % [float(sum_t) / tl_all.size(),
			JsonUtil.as_int(tl_all[tl_all.size() / 2]), JsonUtil.as_int(tl_all[0]), JsonUtil.as_int(tl_all[tl_all.size() - 1])])
	print("battle hits: %d; with cards from the hand %d, all on the hero %d" % [totals["hits"], totals["hits_with_cards"], totals["all_on_hero"]])
	print("hero damage: %d in all (%.1f per game): battle %d, wall %d, trap %d, cards %d" % [totals["hero_dmg"], float(JsonUtil.as_int(totals["hero_dmg"])) / n,
		totals["battle_hero_dmg"], totals["wall_dmg"], totals["trap_dmg"], totals["card_dmg"]])
	print("hand cards discarded for hits: %d (%.1f per game)" % [totals["hand_cards"], float(JsonUtil.as_int(totals["hand_cards"])) / n])
	if JsonUtil.as_int(totals["deck_cards"]) > 0:
		print("deck damage (old rule): %d cards (%.1f per game)" % [totals["deck_cards"], float(JsonUtil.as_int(totals["deck_cards"])) / n])
	print("KOs: %d (%.2f per game); ring-outs: %d" % [totals["kos"], float(JsonUtil.as_int(totals["kos"])) / n, totals["ring_outs"]])
	var turns_all: float = maxf(float(JsonUtil.as_int(totals["turns"])), 1.0)
	print("cards played: %d (%.2f per turn, both players); energy spent on cards and abilities: %d (%.2f per turn)" % [
		totals["cards_played"], JsonUtil.as_int(totals["cards_played"]) / turns_all, totals["energy_cards"], JsonUtil.as_int(totals["energy_cards"]) / turns_all])
	print("stages claimed: %d (%.1f per game)" % [totals["claims"], float(JsonUtil.as_int(totals["claims"])) / n])
	if claim != MatchSettings.CLAIM_STAY:
		if claim == MatchSettings.CLAIM_RING:
			print("places taken from the other side: %d (%.1f per game)" % [totals["energy_taken"], float(JsonUtil.as_int(totals["energy_taken"])) / n])
		print("energy into stages: %d (%.1f per game, %.2f per turn); over the goal and lost: %d" % [totals["energy_banked"],
			float(JsonUtil.as_int(totals["energy_banked"])) / n, JsonUtil.as_int(totals["energy_banked"]) / turns_all, totals["energy_wasted"]])
		print("knocked off a stage by the other side: %d (%d of them with energy in it), energy lost: %d" % [totals["knocked_off"],
			totals["knocked_off_lost"], totals["progress_lost"]])
		print("contested stages at End phases: %d (%.1f per game)" % [totals["contested"], float(JsonUtil.as_int(totals["contested"])) / n])
	quit(0)


func _results_line(results: Dictionary) -> String:
	var parts := PackedStringArray()
	var keys: Array = results.keys()
	keys.sort()
	for k: Variant in keys:
		parts.append("%s %d" % [k, results[k]])
	return ", ".join(parts) if not parts.is_empty() else "none"


func _decks(catalog: CardCatalog) -> Array:
	var out: Array = []
	for slot: int in 2:
		var raw: Dictionary = DeckCode.random_deck(catalog, _rng)
		if not _force.is_empty():
			var forced: Dictionary = JsonUtil.as_dict(raw.get("cards", {}))
			forced[_force] = 3
			raw["cards"] = forced
		out.append(MatchLaunch.engine_deck(catalog, raw, "Bot %d" % (slot + 1), _rng))
	return out


## One match; counts from its log.
func _game(catalog: CardCatalog, level: Bot.Level, max_turns: int, claim: String, goal: int) -> Dictionary:
	var engine := RulesEngine.new(catalog)
	var settings: MatchSettings = MatchSettings.standard()
	settings.knockback = "grid"
	settings.stage_claim = claim
	settings.stage_goal = goal
	settings.manual_setup = true
	settings.resolve_map(_rng, GameSettings.MAP_SIZES)
	var seed_: int = _rng.randi()
	var decks: Array = _decks(catalog)
	var s: GameState = engine.start_match(settings, decks, seed_)
	var first: int = s.initiative
	var played: Array[Dictionary] = [{}, {}]
	var bots: Array[Bot] = [Bot.new(seed_, level), Bot.new(seed_ + 1, level)]
	var steps: int = 0
	var cards_played: int = 0
	var energy_cards: int = 0
	while not s.is_over() and s.turn <= max_turns and steps < MAX_STEPS:
		steps += 1
		if s.awaiting_roll:
			var err_r: String = engine.apply_roll(s, _roll(s, engine))
			if not err_r.is_empty():
				push_error("roll refused: " + err_r)
				break
			continue
		if not _force.is_empty() and s.pending.is_empty() and _play_forced(engine, s):
			continue
		var moved: bool = false
		for slot: int in 2:
			var m: Move = bots[slot].next_move(engine, s, slot, _positions(s), _tuning)
			if m == null:
				continue
			var before: int = s.player(m.player).energy
			var err: String = engine.apply(s, m)
			if err.is_empty() and (m.type == Move.PLAY_CARD or m.type == Move.USE_ABILITY):
				if m.type == Move.PLAY_CARD:
					cards_played += 1
					var pd: Dictionary = played[m.player]
					pd[m.str_arg("card")] = JsonUtil.as_int(pd.get(m.str_arg("card"), 0)) + 1
				energy_cards += maxi(before - s.player(m.player).energy, 0)
			if not err.is_empty():
				push_error("turn %d %s: %s refused: %s" % [s.turn, s.phase, JSON.stringify(m.to_dict()), err])
				continue
			moved = true
			break
		if not moved:
			push_error("nobody can move in turn %d %s (pending %d)" % [s.turn, s.phase, s.pending.size()])
			break
	var r: Dictionary = {
		"hero_dmg": 0, "battle_hero_dmg": 0, "wall_dmg": 0, "trap_dmg": 0, "card_dmg": 0,
		"hand_cards": 0, "deck_cards": 0, "hits": 0, "hits_with_cards": 0, "all_on_hero": 0, "kos": 0, "ring_outs": 0,
		"turns": s.turn, "result": s.result if s.is_over() else "", "winner": s.winner, "first": first, "decks": decks, "played": played,
		"cards_played": cards_played, "energy_cards": energy_cards, "energy_banked": 0, "energy_wasted": 0,
		"knocked_off": 0, "knocked_off_lost": 0, "progress_lost": 0, "contested": 0, "claims": 0, "energy_taken": 0,
	}
	# A battle hit is one damage event by a hero in the Battle phase, plus any hand_damage right before it.
	var pending_cards: int = 0
	for e: Dictionary in s.log:
		if str(e.get("type", "")) in ["companion", "sheltered", "left_shelter", "companion_moved", "companion_gone", "companion_fell", "combo"]:
			_forced[str(e["type"])] = _forced.get(str(e["type"]), 0) + 1
		var t: String = str(e.get("type", ""))
		var by: String = str(e.get("by", ""))
		var amount: int = JsonUtil.as_int(e.get("amount", 0))
		match t:
			"damage":
				r["hero_dmg"] = JsonUtil.as_int(r["hero_dmg"]) + amount
				if by == "wall":
					r["wall_dmg"] = JsonUtil.as_int(r["wall_dmg"]) + amount
				elif by == "trap":
					r["trap_dmg"] = JsonUtil.as_int(r["trap_dmg"]) + amount
				elif str(e.get("phase", "")) == GameState.PHASE_BATTLE and s.hero(by) != null and not e.has("card"):
					r["battle_hero_dmg"] = JsonUtil.as_int(r["battle_hero_dmg"]) + amount
					r["hits"] = JsonUtil.as_int(r["hits"]) + 1
					if pending_cards > 0:
						r["hits_with_cards"] = JsonUtil.as_int(r["hits_with_cards"]) + 1
					else:
						r["all_on_hero"] = JsonUtil.as_int(r["all_on_hero"]) + 1
					pending_cards = 0
				else:
					r["card_dmg"] = JsonUtil.as_int(r["card_dmg"]) + amount
			"hand_damage":
				r["hand_cards"] = JsonUtil.as_int(r["hand_cards"]) + amount
				pending_cards = amount
			"deck_damage":
				# The rule before 2026-11-02 (for a baseline run on an old checkout).
				r["deck_cards"] = JsonUtil.as_int(r["deck_cards"]) + amount
				r["hits"] = JsonUtil.as_int(r["hits"]) + 1
			"ko":
				r["kos"] = JsonUtil.as_int(r["kos"]) + 1
			"ring_out":
				r["ring_outs"] = JsonUtil.as_int(r["ring_outs"]) + 1
			"stage_energy":
				r["energy_banked"] = JsonUtil.as_int(r["energy_banked"]) + amount
				r["energy_wasted"] = JsonUtil.as_int(r["energy_wasted"]) + JsonUtil.as_int(e.get("wasted", 0))
				r["energy_taken"] = JsonUtil.as_int(r["energy_taken"]) + JsonUtil.as_int(e.get("taken", 0))
			"stage_knocked_off":
				var lost: int = JsonUtil.as_int(e.get("lost", 0))
				r["knocked_off"] = JsonUtil.as_int(r["knocked_off"]) + 1
				r["progress_lost"] = JsonUtil.as_int(r["progress_lost"]) + lost
				if lost > 0:
					r["knocked_off_lost"] = JsonUtil.as_int(r["knocked_off_lost"]) + 1
			"stage_contested":
				r["contested"] = JsonUtil.as_int(r["contested"]) + 1
			"stage_claimed":
				r["claims"] = JsonUtil.as_int(r["claims"]) + 1
	return r


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
			out[h.id] = Vector2((i - 1) * 4.0 * _tuning.hex_spacing(), z)
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
		var full: float = _tuning.full_power_hexes(card.wt if card != null else 2) * _tuning.hex_spacing()
		var from: Vector2 = pos[id]
		var end: Vector2 = from + dir * JsonUtil.as_float(aim.get("power", 1.0)) * full
		var r := RollResult.new()
		r.ball_id = id
		r.thrown = true
		var a: Vector2i = m.from_world(end)
		if m.contains(a):
			for cell: Vector2i in Hex.spiral(a, 3):
				if s.is_free(cell, h.big, h):
					a = cell
					break
			r.end_area = BallWorld.Area.MAP
			r.end_hex = a
		elif m.contains(m.from_world(from)) or from.distance_to(end) > 3.0 * _tuning.hex_spacing():
			r.ring_out = true
			r.ring_out_reason = "edge"
			r.end_area = BallWorld.Area.VOID
		else:
			r.end_area = BallWorld.Area.STRIP
		if o.thrower.is_empty():
			o.thrower = id
		o.add(r)
	return o


## Adds one game to the balance counts: every hero, card and stage of each deck gets a game, a win when
## its side won, and (cards) the times it was played.
func _tally(r: Dictionary, by_hero: Dictionary, by_card: Dictionary, by_stage: Dictionary) -> void:
	if str(r["result"]).is_empty():
		return
	var winner: int = JsonUtil.as_int(r["winner"])
	var decks: Array = r["decks"]
	var played: Array = r["played"]
	for slot: int in decks.size():
		var d: Dictionary = decks[slot]
		var won: int = 1 if winner == slot else 0
		for id: String in JsonUtil.as_strings(d.get("heroes", [])):
			_count(by_hero, id, won, 0)
		var cards: Dictionary = JsonUtil.as_dict(d.get("cards", {}))
		var pd: Dictionary = played[slot]
		for id: Variant in cards:
			_count(by_card, str(id), won, JsonUtil.as_int(pd.get(id, 0)), JsonUtil.as_int(cards[id]))
		for id: String in JsonUtil.as_strings(d.get("stages", [])):
			_count(by_stage, id, won, 0)


func _count(into: Dictionary, id: String, won: int, played: int, copies: int = 0) -> void:
	var row: Dictionary = into.get(id, {"games": 0, "wins": 0, "played": 0, "copies": 0})
	row["games"] = JsonUtil.as_int(row["games"]) + 1
	row["wins"] = JsonUtil.as_int(row["wins"]) + won
	row["played"] = JsonUtil.as_int(row["played"]) + played
	row["copies"] = JsonUtil.as_int(row["copies"]) + copies
	into[id] = row


## Heroes by how often their side won, and the cards played least per game they were in a deck.
func _print_balance(catalog: CardCatalog, by_hero: Dictionary, by_card: Dictionary) -> void:
	var name_of := func(id: String) -> String:
		var c: CardDef = catalog.get_card(id)
		return c.name if c != null else id
	var heroes: Array = by_hero.keys()
	heroes.sort_custom(func(a: String, b: String) -> bool:
		return _rate(JsonUtil.as_dict(by_hero[a]), "wins") > _rate(JsonUtil.as_dict(by_hero[b]), "wins"))
	print("")
	print("heroes (won / games):")
	for id: String in heroes:
		var h: Dictionary = by_hero[id]
		print("  %-26s %3d / %3d  %5.1f%%" % [name_of.call(id), h["wins"], h["games"], 100.0 * _rate(h, "wins")])
	var cards: Array = by_card.keys()
	cards.sort_custom(func(a: String, b: String) -> bool:
		return _rate(JsonUtil.as_dict(by_card[a]), "played") < _rate(JsonUtil.as_dict(by_card[b]), "played"))
	print("cards played least (times played per game in a deck):")
	for id: String in cards.slice(0, 12):
		var c: Dictionary = by_card[id]
		print("  %-26s %.2f  (%d games)" % [name_of.call(id), _rate(c, "played"), c["games"]])


## A count per game the row was in a deck.
func _rate(row: Dictionary, key: String) -> float:
	return float(JsonUtil.as_int(row.get(key, 0))) / maxi(JsonUtil.as_int(row.get("games", 0)), 1)


## Plays the forced card for whoever may, else uses one of its optional abilities; true when a move went in.
func _play_forced(engine: RulesEngine, s: GameState) -> bool:
	for slot: int in 2:
		if s.player(slot).hand.has(_force):
			var err: String = engine.apply(s, Move.make(Move.PLAY_CARD, slot, {"card": _force}))
			# A play that asks one more thing (who takes it, which Assist goes): the first answer.
			for head: String in ["say who takes it: ", "choose an assist to replace: "]:
				if err.begins_with(head):
					var first: String = err.trim_prefix(head).split(", ")[0]
					err = engine.apply(s, Move.make(Move.PLAY_CARD, slot, {"card": _force, "wearer" if head.begins_with("say") else "replace": first}))
			if err.is_empty():
				_forced["played"] = _forced.get("played", 0) + 1
				return true
		for a: Dictionary in engine.fx.usable_abilities(s, slot):
			if str(a["card"]) == _force and engine.apply(s, Move.make(Move.USE_ABILITY, slot, {"hero": a["hero"], "card": a["card"], "index": a["index"]})).is_empty():
				_forced["abilities"] = _forced.get("abilities", 0) + 1
				return true
	return false
