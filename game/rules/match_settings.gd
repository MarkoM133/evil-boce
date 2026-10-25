class_name MatchSettings
extends RefCounted
## Everything a game mode can change. A mode is a saved combination of these.

var map_size: int = 17
var stages_to_win: int = 3
var deck_size: int = 40
var start_hand: int = 5
var max_energy: int = 8
var core_slots: int = 3
var equipment_limit: int = 3
var assist_limit: int = 3
## "grid", "physics" or "mixed".
var knockback: String = "grid"
## Damage per knockback step a hero could not take (wall, hero).
var wall_damage: int = 2
## Fewest empty hexes between stage edges, and between a core and other cores or stages.
var stage_gap: int = 3
var core_gap: int = 3
## Stages, then cores, placed by the players in turn; false places them automatically.
var manual_setup: bool = true
var timer_seconds: int = 0
## Turns a locked (tied) battle may repeat before both sides are knocked back.
var max_tie_turns: int = 2


func to_dict() -> Dictionary:
	return {
		"map_size": map_size,
		"stages_to_win": stages_to_win,
		"deck_size": deck_size,
		"start_hand": start_hand,
		"max_energy": max_energy,
		"core_slots": core_slots,
		"equipment_limit": equipment_limit,
		"assist_limit": assist_limit,
		"knockback": knockback,
		"wall_damage": wall_damage,
		"stage_gap": stage_gap,
		"core_gap": core_gap,
		"manual_setup": manual_setup,
		"timer_seconds": timer_seconds,
		"max_tie_turns": max_tie_turns,
	}


static func from_dict(d: Dictionary) -> MatchSettings:
	var s := MatchSettings.new()
	s.map_size = JsonUtil.as_int(d.get("map_size", s.map_size), s.map_size)
	s.stages_to_win = JsonUtil.as_int(d.get("stages_to_win", s.stages_to_win), s.stages_to_win)
	s.deck_size = JsonUtil.as_int(d.get("deck_size", s.deck_size), s.deck_size)
	s.start_hand = JsonUtil.as_int(d.get("start_hand", s.start_hand), s.start_hand)
	s.max_energy = JsonUtil.as_int(d.get("max_energy", s.max_energy), s.max_energy)
	s.core_slots = JsonUtil.as_int(d.get("core_slots", s.core_slots), s.core_slots)
	s.equipment_limit = JsonUtil.as_int(d.get("equipment_limit", s.equipment_limit), s.equipment_limit)
	s.assist_limit = JsonUtil.as_int(d.get("assist_limit", s.assist_limit), s.assist_limit)
	s.knockback = str(d.get("knockback", s.knockback))
	s.wall_damage = JsonUtil.as_int(d.get("wall_damage", s.wall_damage), s.wall_damage)
	s.stage_gap = JsonUtil.as_int(d.get("stage_gap", s.stage_gap), s.stage_gap)
	s.core_gap = JsonUtil.as_int(d.get("core_gap", s.core_gap), s.core_gap)
	s.manual_setup = JsonUtil.as_bool(d.get("manual_setup", s.manual_setup), s.manual_setup)
	s.timer_seconds = JsonUtil.as_int(d.get("timer_seconds", s.timer_seconds), s.timer_seconds)
	s.max_tie_turns = JsonUtil.as_int(d.get("max_tie_turns", s.max_tie_turns), s.max_tie_turns)
	return s
