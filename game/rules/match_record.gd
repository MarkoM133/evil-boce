class_name MatchRecord
extends RefCounted
## One match as a file (docs/replay.md): who played with what, the cards as they were, and a
## frame per phase holding the state at the start of that phase plus the moves and roll outcomes
## applied during it. The same record is a replay (step through frames), a save (resume from
## the last frame) and a "continue from here" (resume from any frame). Pure data; the engine
## never reads it.

const FORMAT: int = 1

var format: int = FORMAT
var game_version: String = ""
var cards_version: int = 0
## ISO 8601 (UTC) when the match started.
var created: String = ""
var settings: Dictionary = {}
## Per slot: {"slot", "name", "team", "bot", "deck_name", "heroes": [...], "stages": [...]}.
var players: Array[Dictionary] = []
## The engine deck dicts the match was started with (RulesEngine.start_match).
var decks: Array = []
var seed: int = 0
## cards.json records of every card the match uses, so a replay rebuilds its own catalog and
## still plays correctly after the cards change.
var cards: Dictionary = {}
## {"index", "turn", "phase", "state": GameState dict, "moves": [Move dicts], "rolls": [RollOutcome dicts]}
var frames: Array[Dictionary] = []
var finished: bool = false
var winner: int = -1
var result: String = ""


func frame_count() -> int:
	return frames.size()


func last_frame() -> Dictionary:
	return frames[frames.size() - 1] if not frames.is_empty() else {}


## The state at the start of frame `i` (a fresh copy).
func state_at(i: int) -> GameState:
	if i < 0 or i >= frames.size():
		return null
	return GameState.from_dict(JsonUtil.as_dict(frames[i].get("state", {})))


## The last frame whose turn is `turn`, or -1.
func frame_of_turn(turn: int) -> int:
	for i: int in range(frames.size() - 1, -1, -1):
		if JsonUtil.as_int(frames[i].get("turn", -1)) == turn:
			return i
	return -1


func catalog() -> CardCatalog:
	var list: Array = []
	for k: Variant in cards:
		list.append(cards[k])
	return CardCatalog.from_doc({"version": cards_version, "cards": list})


## Short description for lists: players, heroes, outcome.
func title() -> String:
	var names := PackedStringArray()
	for p: Dictionary in players:
		names.append(str(p.get("name", "?")))
	return " vs ".join(names)


func player_name(slot: int) -> String:
	for p: Dictionary in players:
		if JsonUtil.as_int(p.get("slot", -1)) == slot:
			return str(p.get("name", ""))
	return "Player %d" % (slot + 1)


## A copy up to and including frame `i`, unfinished, for "continue from here".
func branch_at(i: int) -> MatchRecord:
	var r: MatchRecord = MatchRecord.from_dict(to_dict())
	r.frames = r.frames.slice(0, i + 1)
	# The branch starts fresh in that phase: moves made there are not replayed.
	if not r.frames.is_empty():
		var f: Dictionary = r.frames[r.frames.size() - 1]
		f["moves"] = []
		f["rolls"] = []
	r.finished = false
	r.winner = -1
	r.result = ""
	r.created = Time.get_datetime_string_from_system(true) + "Z"
	return r


# --- stats --------------------------------------------------------------------------

## What goes into EvilBoce/stats/: enough for the Balance tab, nothing a player has to keep.
func summary() -> Dictionary:
	var final: Dictionary = JsonUtil.as_dict(last_frame().get("state", {}))
	var log: Array = JsonUtil.as_array(final.get("log", []))
	var played: Dictionary = {}
	var kos: Dictionary = {}
	var ring_outs: Dictionary = {}
	var claims: Dictionary = {}
	var battles: int = 0
	for e: Variant in log:
		var ev: Dictionary = JsonUtil.as_dict(e)
		var t: String = str(ev.get("type", ""))
		match t:
			"action", "equipped", "evolved", "assist":
				var cid: String = str(ev.get("card", ""))
				played[cid] = JsonUtil.as_int(played.get(cid, 0)) + 1
			"ko":
				var owner: String = _owner_of(str(ev.get("hero", "")))
				kos[owner] = JsonUtil.as_int(kos.get(owner, 0)) + 1
			"ring_out":
				var owner2: String = _owner_of(str(ev.get("hero", "")))
				ring_outs[owner2] = JsonUtil.as_int(ring_outs.get(owner2, 0)) + 1
			"stage_claimed":
				var who: String = "p%d" % JsonUtil.as_int(ev.get("player", 0))
				claims[who] = JsonUtil.as_int(claims.get(who, 0)) + 1
			"battle":
				battles += 1
	var slots: Array = []
	for p: Dictionary in players:
		var key: String = "p%d" % JsonUtil.as_int(p.get("slot", 0))
		slots.append({
			"slot": p.get("slot", 0),
			"name": p.get("name", ""),
			"bot": p.get("bot", false),
			"deck_name": p.get("deck_name", ""),
			"heroes": p.get("heroes", []),
			"stages": p.get("stages", []),
			"kos_suffered": JsonUtil.as_int(kos.get(key, 0)),
			"ring_outs_suffered": JsonUtil.as_int(ring_outs.get(key, 0)),
			"stages_claimed": JsonUtil.as_int(claims.get(key, 0)),
		})
	return {
		"format": FORMAT,
		"game_version": game_version,
		"cards_version": cards_version,
		"created": created,
		"map_size": JsonUtil.as_int(settings.get("map_size", 0)),
		"turns": JsonUtil.as_int(final.get("turn", 0)),
		"winner": winner,
		"result": result,
		"battles": battles,
		"players": slots,
		"cards_played": played,
	}


static func _owner_of(hero_id: String) -> String:
	return hero_id.get_slice(":", 0) if hero_id.contains(":") else ""


# --- serialisation ------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"format": format,
		"game_version": game_version,
		"cards_version": cards_version,
		"created": created,
		"settings": settings.duplicate(true),
		"players": players.duplicate(true),
		"decks": decks.duplicate(true),
		"seed": seed,
		"cards": cards.duplicate(true),
		"frames": frames.duplicate(true),
		"finished": finished,
		"winner": winner,
		"result": result,
	}


## Only what lists need, without parsing frames into states.
static func header_from_dict(d: Dictionary) -> Dictionary:
	var names := PackedStringArray()
	var heroes: Array = []
	for p: Variant in JsonUtil.as_array(d.get("players", [])):
		var pd: Dictionary = JsonUtil.as_dict(p)
		names.append(str(pd.get("name", "?")))
		heroes.append(JsonUtil.as_array(pd.get("heroes", [])))
	var frames: Array = JsonUtil.as_array(d.get("frames", []))
	var last: Dictionary = JsonUtil.as_dict(frames[frames.size() - 1]) if not frames.is_empty() else {}
	return {
		"created": str(d.get("created", "")),
		"title": " vs ".join(names),
		"heroes": heroes,
		"turns": JsonUtil.as_int(last.get("turn", 0)),
		"frames": frames.size(),
		"finished": JsonUtil.as_bool(d.get("finished", false)),
		"winner": JsonUtil.as_int(d.get("winner", -1), -1),
		"result": str(d.get("result", "")),
		"cards_version": JsonUtil.as_int(d.get("cards_version", 0)),
		"game_version": str(d.get("game_version", "")),
	}


static func from_dict(d: Dictionary) -> MatchRecord:
	var r := MatchRecord.new()
	r.format = JsonUtil.as_int(d.get("format", FORMAT), FORMAT)
	r.game_version = str(d.get("game_version", ""))
	r.cards_version = JsonUtil.as_int(d.get("cards_version", 0))
	r.created = str(d.get("created", ""))
	r.settings = JsonUtil.as_dict(d.get("settings", {}))
	for p: Variant in JsonUtil.as_array(d.get("players", [])):
		r.players.append(JsonUtil.as_dict(p))
	r.decks = JsonUtil.as_array(d.get("decks", []))
	r.seed = JsonUtil.as_int(d.get("seed", 0))
	r.cards = JsonUtil.as_dict(d.get("cards", {}))
	for f: Variant in JsonUtil.as_array(d.get("frames", [])):
		r.frames.append(JsonUtil.as_dict(f))
	r.finished = JsonUtil.as_bool(d.get("finished", false))
	r.winner = JsonUtil.as_int(d.get("winner", -1), -1)
	r.result = str(d.get("result", ""))
	return r
