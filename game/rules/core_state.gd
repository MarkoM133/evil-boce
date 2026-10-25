class_name CoreState
extends RefCounted
## One core token. Where it is: "field" (on a hex), "hero" (in a hero's slots), "inventory"
## (waiting for its owner to put it back) or "unplaced" (setup not done yet).

const ON_FIELD: String = "field"
const ON_HERO: String = "hero"
const IN_INVENTORY: String = "inventory"
const UNPLACED: String = "unplaced"

var id: String = ""
var card_id: String = ""
## Slot of the player who brought it.
var owner: int = 0
var place: String = UNPLACED
var hex: Vector2i = Vector2i.ZERO
var face_up: bool = false
## Hero holding it (place == ON_HERO).
var holder: String = ""
## Hero that picked it up when it went to the inventory; it must come back within that
## hero's range. Empty when it fell off a KO'd or ringed-out hero (anywhere on the owner's half).
var picked_by: String = ""


func to_dict() -> Dictionary:
	return {
		"id": id,
		"card": card_id,
		"owner": owner,
		"place": place,
		"hex": Hex.to_json(hex),
		"face_up": face_up,
		"holder": holder,
		"picked_by": picked_by,
	}


static func from_dict(d: Dictionary) -> CoreState:
	var c := CoreState.new()
	c.id = str(d.get("id", ""))
	c.card_id = str(d.get("card", ""))
	c.owner = JsonUtil.as_int(d.get("owner", 0))
	c.place = str(d.get("place", UNPLACED))
	c.hex = JsonUtil.as_hex(d.get("hex", null))
	c.face_up = JsonUtil.as_bool(d.get("face_up", false))
	c.holder = str(d.get("holder", ""))
	c.picked_by = str(d.get("picked_by", ""))
	return c
