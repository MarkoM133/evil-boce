class_name CompanionState
extends RefCounted
## A companion on the map (GDD 10, 2026-11-21; the first is Coco Jumbo): a token, not a hero. It has no HP,
## holds no stage and joins no battle. It is there while its Assist card is in play, one per player. Balls
## push it (the sim reports where it stopped under its id); off the table it is gone with its Assist.
## One hero of its owner may hide inside (HeroState.ZONE_SHELTER).

var id: String = ""
var owner: int = 0
## The Assist card that put it on the table.
var card_id: String = ""
var hex: Vector2i = Vector2i.ZERO
## Id of the hero hidden inside ("" = empty).
var inside: String = ""


static func id_for(slot: int) -> String:
	return "companion:%d" % slot


func to_dict() -> Dictionary:
	return {"id": id, "owner": owner, "card": card_id, "hex": Hex.to_json(hex), "inside": inside}


static func from_dict(d: Dictionary) -> CompanionState:
	var c := CompanionState.new()
	c.id = str(d.get("id", ""))
	c.owner = JsonUtil.as_int(d.get("owner", 0))
	c.card_id = str(d.get("card", ""))
	c.hex = JsonUtil.as_hex(d.get("hex", null))
	c.inside = str(d.get("inside", ""))
	return c
