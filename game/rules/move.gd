class_name Move
extends RefCounted
## One thing a player asks the engine to do. Pure data, so it can be logged, replayed and
## sent over the network. `data` holds the type-specific fields listed below.

## Setup: {"stage": id, "hex": [q, r]} / {"core": id, "hex": [q, r]} / {"keep": bool}
const PLACE_STAGE: String = "place_stage"
const PLACE_CORE: String = "place_core"
const MULLIGAN: String = "mulligan"
## Select phase: {"hero": id} ("" when no hero can be activated).
const SELECT: String = "select"
## Preroll: {"roll": bool} for the activated hero.
## Roll: {"dir": [x, z], "power": 0..1}; the sim does the throw.
const AIM: String = "aim"
## Any card round.
const PASS: String = "pass"
## {"card": id, ...targets} (step 2b).
const PLAY_CARD: String = "play_card"
## Battle: loser picks where a hit lands: {"target": "deck"} or {"target": hero id}.
const DAMAGE_TO: String = "damage_to"
## {"core": id, "hex": [q, r]} for a core from the inventory.
const RETURN_CORE: String = "return_core"
## An optional ability of a card in play: {"hero": id, "card": id, "index": n} (index among
## that card's effects); counts as an action in the card round.
const USE_ABILITY: String = "use_ability"
## Answer to a pending "choose" decision: {"value": hero id | [q, r] | core id | card id | branch index}.
const CHOOSE: String = "choose"
const SURRENDER: String = "surrender"

var type: String = ""
var player: int = 0
var data: Dictionary = {}


static func make(type_: String, player_: int, data_: Dictionary = {}) -> Move:
	var m := Move.new()
	m.type = type_
	m.player = player_
	m.data = data_
	return m


func str_arg(key: String, fallback: String = "") -> String:
	return str(data.get(key, fallback)) if data.has(key) else fallback


func hex_arg(key: String) -> Vector2i:
	return JsonUtil.as_hex(data.get(key, null))


func bool_arg(key: String, fallback: bool = false) -> bool:
	return JsonUtil.as_bool(data.get(key, fallback), fallback)


func to_dict() -> Dictionary:
	var d: Dictionary = {"type": type, "player": player}
	for k: Variant in data:
		d[k] = data[k]
	return d


static func from_dict(d: Dictionary) -> Move:
	var m := Move.new()
	m.type = str(d.get("type", ""))
	m.player = JsonUtil.as_int(d.get("player", 0))
	for k: Variant in d:
		if k != "type" and k != "player":
			m.data[k] = d[k]
	return m
