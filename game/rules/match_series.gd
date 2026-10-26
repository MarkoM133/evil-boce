class_name MatchSeries
extends RefCounted
## A series of games (Best of 3, GDD 13, 2026-10-26): wins per seat, the decks of game one
## (stages and cores are picked again before every game), the loser of a game starts the next,
## a draw counts for nobody, and the series ends at `target` wins or after `max_games` games
## (then more wins, else a drawn series). No sideboard yet.

## The local series while the game runs; the host keeps its own in NetHost.
static var current: MatchSeries

var target: int = 2
var max_games: int = 5
var wins: PackedInt32Array = PackedInt32Array([0, 0])
var games: int = 0
var last_loser: int = -1
## {name, heroes, cards} per seat, as game one played them.
var decks: Array = []
## Local play: who plays the second seat (MatchSetup.last_opponent), kept through the series.
var opponent: int = 0


func _init(target_: int = 2) -> void:
	target = maxi(1, target_)
	max_games = target * 2 + 1


## A game ended: `winner` is its seat, -1 for a draw.
func record(winner: int) -> void:
	games += 1
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
		"last_loser": last_loser, "decks": decks.duplicate(true), "opponent": opponent}


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
	return s
