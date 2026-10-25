class_name HeroState
extends RefCounted
## One hero in a match. Stats come from the card (or the top evolution) plus equipment and
## temporary bonuses, see RulesEngine.stat().

const ZONE_STRIP: String = "strip"
const ZONE_MAP: String = "map"
const ZONE_KO: String = "ko"

var id: String = ""
var owner: int = 0
var card_id: String = ""
## Covers 7 hexes (WT 4+); set from the card when the hero is created.
var big: bool = false
var zone: String = ZONE_STRIP
## Centre hex while on the map.
var hex: Vector2i = Vector2i.ZERO
var hp: int = 0
## Core ids held (up to MatchSettings.core_slots).
var cores: PackedStringArray = PackedStringArray()
## Equipment card ids in play on this hero.
var equipment: PackedStringArray = PackedStringArray()
## Evolution card ids, level 1 first.
var evolutions: PackedStringArray = PackedStringArray()
## Status name -> turns left (-1 = until removed).
var statuses: Dictionary[String, int] = {}
## Stat bonuses that end with the phase / with the turn: {"pwr": 2000, ...}.
var phase_bonus: Dictionary[String, int] = {}
var turn_bonus: Dictionary[String, int] = {}
## Turns this hero has been locked in a tied battle (0 = free).
var tie_turns: int = 0
## Ids of the heroes it is locked with.
var locked_with: PackedStringArray = PackedStringArray()


func is_on_map() -> bool:
	return zone == ZONE_MAP


func is_ko() -> bool:
	return zone == ZONE_KO


func has_status(name: String) -> bool:
	return statuses.has(name)


func add_bonus(target: Dictionary[String, int], stat: String, amount: int) -> void:
	target[stat] = target.get(stat, 0) + amount


func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"card": card_id,
		"big": big,
		"zone": zone,
		"hex": Hex.to_json(hex),
		"hp": hp,
		"cores": Array(cores),
		"equipment": Array(equipment),
		"evolutions": Array(evolutions),
		"statuses": statuses.duplicate(),
		"phase_bonus": phase_bonus.duplicate(),
		"turn_bonus": turn_bonus.duplicate(),
		"tie_turns": tie_turns,
		"locked_with": Array(locked_with),
	}


static func _int_dict(v: Variant, fallback: int) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var d: Dictionary = JsonUtil.as_dict(v)
	for k: Variant in d:
		out[str(k)] = JsonUtil.as_int(d[k], fallback)
	return out


static func from_dict(d: Dictionary) -> HeroState:
	var h := HeroState.new()
	h.id = str(d.get("id", ""))
	h.owner = JsonUtil.as_int(d.get("owner", 0))
	h.card_id = str(d.get("card", ""))
	h.big = JsonUtil.as_bool(d.get("big", false))
	h.zone = str(d.get("zone", ZONE_STRIP))
	h.hex = JsonUtil.as_hex(d.get("hex", null))
	h.hp = JsonUtil.as_int(d.get("hp", 0))
	h.cores = JsonUtil.as_strings(d.get("cores", []))
	h.equipment = JsonUtil.as_strings(d.get("equipment", []))
	h.evolutions = JsonUtil.as_strings(d.get("evolutions", []))
	h.statuses = _int_dict(d.get("statuses", {}), -1)
	h.phase_bonus = _int_dict(d.get("phase_bonus", {}), 0)
	h.turn_bonus = _int_dict(d.get("turn_bonus", {}), 0)
	h.tie_turns = JsonUtil.as_int(d.get("tie_turns", 0))
	h.locked_with = JsonUtil.as_strings(d.get("locked_with", []))
	return h
