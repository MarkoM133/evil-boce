class_name MatchSeries
extends RefCounted
## A series of games (Best of 3, GDD 13, 2026-10-26): wins per seat, the decks of game one
## (stages and cores are picked again before every game), the loser of a game starts the next,
## a draw counts for nobody, and the series ends at `target` wins or after `max_games` games
## (then more wins, else a drawn series). Each seat may bring a sideboard of up to
## SIDEBOARD cards and swap up to SWAPS of them in between two games; the swaps stay.

## The local series while the game runs; the host keeps its own in NetHost.
static var current: MatchSeries
const SIDEBOARD: int = 10
const SWAPS: int = 5

var target: int = 2
var max_games: int = 5
var wins: PackedInt32Array = PackedInt32Array([0, 0])
var games: int = 0
var last_loser: int = -1
## {name, heroes, cards} per seat, as game one played them.
var decks: Array = []
## Up to SIDEBOARD cards per seat (id -> copies), and the deck and sideboard as each break began.
var sideboards: Array = []
var break_decks: Array = []
var break_sides: Array = []
## Local play: who plays the second seat (MatchSetup.last_opponent), kept through the series.
var opponent: int = 0


func _init(target_: int = 2) -> void:
	target = maxi(1, target_)
	max_games = target * 2 + 1


## A game ended: `winner` is its seat, -1 for a draw.
func record(winner: int) -> void:
	games += 1
	# A new break: swaps are counted from the decks as they are now.
	break_decks = decks.duplicate(true)
	break_sides = sideboards.duplicate(true)
	while break_sides.size() < break_decks.size():
		break_sides.append({})
	while sideboards.size() < decks.size():
		sideboards.append({})
	if winner >= 0 and winner < wins.size():
		wins[winner] += 1
		last_loser = 1 - winner if wins.size() == 2 else -1
	else:
		last_loser = -1


func is_over() -> bool:
	for w: int in wins:
		if w >= target:
			return true
	return games >= max_games


## The seat with most wins, -1 while nobody leads.
func winner() -> int:
	var best: int = -1
	var tied: bool = false
	for i: int in wins.size():
		if best < 0 or wins[i] > wins[best]:
			best = i
			tied = false
		elif wins[i] == wins[best]:
			tied = true
	return -1 if tied else best


## Who starts the next game: the loser of the last one, random (-1) after a draw or at first.
func next_initiative() -> int:
	return last_loser


func score() -> String:
	return "%d–%d" % [wins[0], wins[1]] if wins.size() == 2 else ", ".join(Array(wins))


func to_dict() -> Dictionary:
	return {"target": target, "max_games": max_games, "wins": Array(wins), "games": games,
		"last_loser": last_loser, "decks": decks.duplicate(true), "opponent": opponent,
		"sideboards": sideboards.duplicate(true), "break_decks": break_decks.duplicate(true), "break_sides": break_sides.duplicate(true)}


static func from_dict(d: Dictionary) -> MatchSeries:
	var s := MatchSeries.new(JsonUtil.as_int(d.get("target", 2), 2))
	s.max_games = JsonUtil.as_int(d.get("max_games", s.max_games), s.max_games)
	var w: Array = JsonUtil.as_array(d.get("wins", [0, 0]))
	s.wins = PackedInt32Array()
	for x: Variant in w:
		s.wins.append(JsonUtil.as_int(x))
	if s.wins.size() < 2:
		s.wins = PackedInt32Array([0, 0])
	s.games = JsonUtil.as_int(d.get("games", 0))
	s.last_loser = JsonUtil.as_int(d.get("last_loser", -1), -1)
	for x: Variant in JsonUtil.as_array(d.get("decks", [])):
		s.decks.append(JsonUtil.as_dict(x))
	s.opponent = JsonUtil.as_int(d.get("opponent", 0))
	for field: String in ["sideboards", "break_decks", "break_sides"]:
		var arr: Array = []
		for x: Variant in JsonUtil.as_array(d.get(field, [])):
			arr.append(JsonUtil.as_dict(x))
		s.set(field, arr)
	return s


# --- the sideboard (GDD 13, 2026-10-26) ----------------------------------------------------

## What is wrong with a sideboard for these heroes: at most SIDEBOARD cards, each one a card
## the deck could hold (colour, evolution, hero-only), no more copies than its limit.
static func sideboard_error(catalog: CardCatalog, heroes: PackedStringArray, side: Dictionary) -> String:
	var total: int = 0
	var hero_defs: Array[CardDef] = []
	var names := PackedStringArray()
	var colors := PackedStringArray()
	for id: String in heroes:
		var h: CardDef = catalog.get_card(id)
		if h != null:
			names.append(h.name)
			colors.append(h.color)
			hero_defs.append(h)
	for k: Variant in side:
		var n: int = JsonUtil.as_int(side[k])
		if n <= 0:
			continue
		total += n
		var c: CardDef = catalog.get_card(str(k))
		if c == null or not DeckCode.DECK_TYPES.has(c.type):
			return "%s cannot go in a sideboard" % str(k)
		# The first tag rule (FirstTag); a card an Evolution unlocks may wait here for it.
		var v: Dictionary = FirstTag.deck_verdict(catalog, c, hero_defs, DeckCode.hero_evolutions(catalog, hero_defs))
		if not JsonUtil.as_bool(v["ok"]):
			return "%s: %s" % [c.name, str(v["why"])]
		if n > DeckCode.LIMITS[c.type]:
			return "%s: at most %d" % [c.name, DeckCode.LIMITS[c.type]]
	if total > SIDEBOARD:
		return "at most %d cards in the sideboard" % SIDEBOARD
	return ""


## Cards swapped in so far this break (between two games) by `slot`.
func swaps_used(slot: int) -> int:
	if slot >= break_decks.size():
		return 0
	return _swaps(JsonUtil.as_dict(JsonUtil.as_dict(break_decks[slot]).get("cards", {})), JsonUtil.as_dict(JsonUtil.as_dict(decks[slot]).get("cards", {})))


static func _swaps(before: Dictionary, after: Dictionary) -> int:
	var added: int = 0
	for k: Variant in after:
		added += maxi(0, JsonUtil.as_int(after[k]) - JsonUtil.as_int(before.get(k, 0)))
	return added


## Why `slot` may not play `cards` next game ("" when it may): only cards of this break's deck
## and sideboard, at most SWAPS swapped in, the deck still legal.
func swap_error(catalog: CardCatalog, slot: int, cards: Dictionary) -> String:
	if games == 0 or is_over() or slot >= decks.size() or slot >= break_decks.size():
		return "cards are swapped between the games of a series"
	var deck: Dictionary = JsonUtil.as_dict(break_decks[slot])
	var before: Dictionary = JsonUtil.as_dict(deck.get("cards", {}))
	var side: Dictionary = JsonUtil.as_dict(break_sides[slot]) if slot < break_sides.size() else {}
	for k: Variant in cards:
		var n: int = JsonUtil.as_int(cards[k])
		if n > JsonUtil.as_int(before.get(k, 0)) + JsonUtil.as_int(side.get(k, 0)):
			return "%s is not in your deck or sideboard" % str(k)
	if _swaps(before, cards) > SWAPS:
		return "at most %d cards swapped between games" % SWAPS
	var errs: PackedStringArray = DeckCode.check(catalog, JsonUtil.as_strings(deck.get("heroes", [])), cards)
	return errs[0] if not errs.is_empty() else ""


## Plays `cards` from the next game on; the cards taken out go to the sideboard.
func set_cards(catalog: CardCatalog, slot: int, cards: Dictionary) -> String:
	var err: String = swap_error(catalog, slot, cards)
	if not err.is_empty():
		return err
	var deck: Dictionary = JsonUtil.as_dict(break_decks[slot])
	var pool: Dictionary = JsonUtil.as_dict(deck.get("cards", {})).duplicate()
	var side0: Dictionary = JsonUtil.as_dict(break_sides[slot])
	for k: Variant in side0:
		pool[k] = JsonUtil.as_int(pool.get(k, 0)) + JsonUtil.as_int(side0[k])
	var side: Dictionary = {}
	for k: Variant in pool:
		var left: int = JsonUtil.as_int(pool[k]) - JsonUtil.as_int(cards.get(k, 0))
		if left > 0:
			side[k] = left
	var now: Dictionary = JsonUtil.as_dict(decks[slot]).duplicate(true)
	now["cards"] = cards.duplicate()
	decks[slot] = now
	sideboards[slot] = side
	return ""
