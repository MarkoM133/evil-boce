class_name NetProtocol
extends RefCounted
## What host and clients say to each other (docs/net.md). Every message is a Dictionary with
## "t" (type) sent as JSON over ENet; the host is the only authority and the only one that
## runs the rules engine, the physics and the bots. Clients render the state they are sent.

const VERSION: int = 1
const DEFAULT_PORT: int = 7777

# client -> host
const HELLO: String = "hello"          # {name, game_version, cards_version, net_version}
const MOVE: String = "move"            # {move: Move dict}
const PAUSE: String = "pause"          # {}
const RESUME: String = "resume"        # {}
const DECK: String = "deck"            # {deck: engine deck dict}  (lobby)
const READY: String = "ready"          # {ready: bool}            (lobby)

# host -> client
const WELCOME: String = "welcome"      # {slot, name, players: [...], settings}
const REJECT: String = "reject"        # {reason}
const LOBBY: String = "lobby"          # {players: [{slot, name, ready, bot, connected}], settings}
const START: String = "start"          # {settings, players, seed, cards_version}
const STATE: String = "state"          # {state: redacted GameState dict}
const REFUSED: String = "refused"      # {move: Move dict, reason}
const BALLS: String = "balls"          # {p: {hero id: [x, y, z]}}  (unreliable, during a roll)
const ROLL: String = "roll"            # {outcome: RollOutcome dict}  (after a roll, for the paths)
const PAUSED: String = "paused"        # {by: slot, name}
const RESUMED: String = "resumed"      # {}
const PLAYER: String = "player"        # {slot, name, connected}  (someone came or went)
const OVER: String = "over"            # {summary}
const PING: String = "ping"            # {} every few seconds, so a dead link shows up

const PLACEHOLDER_CARD: String = "?"


static func encode(msg: Dictionary) -> PackedByteArray:
	return JSON.stringify(msg).to_utf8_buffer()


static func decode(bytes: PackedByteArray) -> Dictionary:
	return JsonUtil.as_dict(JSON.parse_string(bytes.get_string_from_utf8()))


## The state as player `slot` may see it (GDD 11: of the opponent you see hand size, energy,
## deck size and the graveyard; aims are secret; face-down cores stay unknown).
static func redact(state_dict: Dictionary, slot: int) -> Dictionary:
	var d: Dictionary = state_dict.duplicate(true)
	var players: Dictionary = JsonUtil.as_dict(d.get("players", {}))
	for key: Variant in players:
		var p: Dictionary = JsonUtil.as_dict(players[key])
		var other: bool = JsonUtil.as_int(p.get("slot", -1)) != slot
		# Nobody sees the order of a deck; the opponent's hand is just a count.
		p["deck"] = _blank(JsonUtil.as_array(p.get("deck", [])).size())
		if other:
			p["hand"] = _blank(JsonUtil.as_array(p.get("hand", [])).size())
		players[key] = p
	d["players"] = players
	var aims: Dictionary = JsonUtil.as_dict(d.get("aims", {}))
	for key: Variant in aims:
		if str(key).to_int() != slot:
			aims[key] = {}
	d["aims"] = aims
	var cores: Dictionary = JsonUtil.as_dict(d.get("cores", {}))
	for key: Variant in cores:
		var c: Dictionary = JsonUtil.as_dict(cores[key])
		if not JsonUtil.as_bool(c.get("face_up", false)) and str(c.get("place", "")) != CoreState.ON_HERO:
			c["card"] = PLACEHOLDER_CARD
			cores[key] = c
	d["cores"] = cores
	# Decisions of the others may list their hand (a discard): keep only that one is pending.
	var pending: Array = JsonUtil.as_array(d.get("pending", []))
	for i: int in pending.size():
		var dec: Dictionary = JsonUtil.as_dict(pending[i])
		if JsonUtil.as_int(dec.get("player", -1), -1) != slot and str(dec.get("kind", "")) == "card":
			dec["options"] = _blank(JsonUtil.as_array(dec.get("options", [])).size())
			pending[i] = dec
	d["pending"] = pending
	return d


static func _blank(n: int) -> Array:
	var out: Array = []
	for _i: int in n:
		out.append(PLACEHOLDER_CARD)
	return out
