class_name WallState
extends RefCounted
## A wall put down by a card: one or more hexes that block movement and knockback.

var id: String = ""
var hexes: Array[Vector2i] = []


func covers(a: Vector2i) -> bool:
	return hexes.has(a)


func to_dict() -> Dictionary:
	var list: Array = []
	for a: Vector2i in hexes:
		list.append(Hex.to_json(a))
	return {"id": id, "hexes": list}


static func from_dict(d: Dictionary) -> WallState:
	var w := WallState.new()
	w.id = str(d.get("id", ""))
	for v: Variant in JsonUtil.as_array(d.get("hexes", [])):
		w.hexes.append(JsonUtil.as_hex(v))
	return w
