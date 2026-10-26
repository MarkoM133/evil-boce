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
const LOBBY: String = "lobby"          # {players: [{slot, name, ready, bot, connected}], settings, again}
const START: String = "start"          # {settings, players, seed, cards_version}
const STATE: String = "state"          # {state: redacted GameState dict}
const REFUSED: String = "refused"      # {move: Move dict, reason}
const BALLS: String = "balls"          # {p: {hero id: [x, y, z]}}  (unreliable, during a roll)
const ROLL: String = "roll"            # {outcome: RollOutcome dict}  (after a roll, for the paths)
const PAUSED: String = "paused"        # {by: slot, name}
const RESUMED: String = "resumed"      # {}
const PLAYER: String = "player"        # {slot, name, connected}  (someone came or went)
const OVER: String = "over"            # {summary, record: the full MatchRecord, nothing is hidden now}
const PING: String = "ping"            # {} every few seconds, so a dead link shows up

const PLACEHOLDER_CARD: String = "?"
## Packets longer than this go out gzipped, behind a 0x01 byte (JSON always starts with "{").
const COMPRESS_OVER: int = 8192
const COMPRESSED: int = 1


static func encode(msg: Dictionary) -> PackedByteArray:
	var raw: PackedByteArray = JSON.stringify(msg).to_utf8_buffer()
	if raw.size() <= COMPRESS_OVER:
		return raw
	var out := PackedByteArray([COMPRESSED])
	out.append_array(raw.compress(FileAccess.COMPRESSION_GZIP))
	return out


static func decode(bytes: PackedByteArray) -> Dictionary:
	if not bytes.is_empty() and bytes[0] == COMPRESSED:
		bytes = bytes.slice(1).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
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
	# Start: the others' hero and Roll / Stay stay secret until everyone has picked (GDD 8);
	# then the engine moves on to Preroll and everything shows.
	if str(d.get("phase", "")) == GameState.PHASE_START:
		for field: String in ["active", "choices"]:
			var picks: Dictionary = JsonUtil.as_dict(d.get(field, {}))
			for key: Variant in picks.keys():
				if str(key).to_int() != slot:
					picks.erase(key)
			d[field] = picks
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
		# A roll offer lists cards from the hand of whoever it is for; the others see an empty
		# offer, not even how much is on it (everyone gets one, GDD 8).
		if JsonUtil.as_int(dec.get("player", -1), -1) != slot and str(dec.get("type", "")) == RulesEngine.DECISION_ROLL_OFFER:
			dec["cards"] = []
			dec["abilities"] = []
			pending[i] = dec
	d["pending"] = pending
	return d


static func _blank(n: int) -> Array:
	var out: Array = []
	for _i: int in n:
		out.append(PLACEHOLDER_CARD)
	return out
