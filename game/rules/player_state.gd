class_name PlayerState
extends RefCounted
## One slot in a match: deck, hand, energy, what it brought and what it holds.

var slot: int = 0
var team: int = 0
var name: String = ""
## Card ids, top of the deck first.
var deck: PackedStringArray = PackedStringArray()
var hand: PackedStringArray = PackedStringArray()
var graveyard: PackedStringArray = PackedStringArray()
var energy: int = 0
## Assist card ids in play.
var assists: PackedStringArray = PackedStringArray()
## Core ids waiting to be put back on the table (see CoreState.picked_by).
var inventory: PackedStringArray = PackedStringArray()
## Stage and core card ids this player brought (placed during setup).
var stage_cards: PackedStringArray = PackedStringArray()
var core_cards: PackedStringArray = PackedStringArray()
var mulligan_done: bool = false
var surrendered: bool = false


func to_dict() -> Dictionary:
	return {
		"slot": slot,
		"team": team,
		"name": name,
		"deck": Array(deck),
		"hand": Array(hand),
		"graveyard": Array(graveyard),
		"energy": energy,
		"assists": Array(assists),
		"inventory": Array(inventory),
		"stage_cards": Array(stage_cards),
		"core_cards": Array(core_cards),
		"mulligan_done": mulligan_done,
		"surrendered": surrendered,
	}


static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.slot = JsonUtil.as_int(d.get("slot", 0))
	p.team = JsonUtil.as_int(d.get("team", p.slot), p.slot)
	p.name = str(d.get("name", ""))
	p.deck = JsonUtil.as_strings(d.get("deck", []))
	p.hand = JsonUtil.as_strings(d.get("hand", []))
	p.graveyard = JsonUtil.as_strings(d.get("graveyard", []))
	p.energy = JsonUtil.as_int(d.get("energy", 0))
	p.assists = JsonUtil.as_strings(d.get("assists", []))
	p.inventory = JsonUtil.as_strings(d.get("inventory", []))
	p.stage_cards = JsonUtil.as_strings(d.get("stage_cards", []))
	p.core_cards = JsonUtil.as_strings(d.get("core_cards", []))
	p.mulligan_done = JsonUtil.as_bool(d.get("mulligan_done", false))
	p.surrendered = JsonUtil.as_bool(d.get("surrendered", false))
	return p
