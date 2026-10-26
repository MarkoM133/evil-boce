class_name StageState
extends RefCounted
## One stage tile: 7 hexes around `center`, face down until a ball stops on it.

var id: String = ""
var card_id: String = ""
var owner: int = 0
var placed: bool = false
var center: Vector2i = Vector2i.ZERO
var revealed: bool = false
## Slot that claimed it, or -1.
var claimed_by: int = -1
## The activated hero that chose Stay on this stage last turn, and that turn: a second Stay in
## a row by the same hero claims it (GDD 6).
var stay_hero: String = ""
var stay_turn: int = -1
## After a claim the terrain lingers through this turn, then goes.
var terrain_until_turn: int = -1
## Wind stages: the direction drawn when the stage was revealed (a Hex.DIRECTIONS index), -1 before.
var wind_dir: int = -1


func footprint() -> Array[Vector2i]:
	return Hex.spiral(center, 1)


func covers(a: Vector2i) -> bool:
	return placed and Hex.distance(a, center) <= 1


func is_claimed() -> bool:
	return claimed_by >= 0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"card": card_id,
		"owner": owner,
		"placed": placed,
		"center": Hex.to_json(center),
		"revealed": revealed,
		"claimed_by": claimed_by,
		"stay_hero": stay_hero,
		"stay_turn": stay_turn,
		"terrain_until_turn": terrain_until_turn,
		"wind_dir": wind_dir,
	}


static func from_dict(d: Dictionary) -> StageState:
	var s := StageState.new()
	s.id = str(d.get("id", ""))
	s.card_id = str(d.get("card", ""))
	s.owner = JsonUtil.as_int(d.get("owner", 0))
	s.placed = JsonUtil.as_bool(d.get("placed", false))
	s.center = JsonUtil.as_hex(d.get("center", null))
	s.revealed = JsonUtil.as_bool(d.get("revealed", false))
	s.wind_dir = JsonUtil.as_int(d.get("wind_dir", -1), -1)
	s.claimed_by = JsonUtil.as_int(d.get("claimed_by", -1), -1)
	s.stay_hero = str(d.get("stay_hero", ""))
	s.stay_turn = JsonUtil.as_int(d.get("stay_turn", -1), -1)
	s.terrain_until_turn = JsonUtil.as_int(d.get("terrain_until_turn", -1), -1)
	return s
