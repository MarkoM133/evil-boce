class_name NetHost
extends Node
## The host side of an online match (docs/net.md): owns the lobby, the MatchRecorder, the bots'
## seat and the one true state. Clients send moves; after every accepted one the host sends each
## client the state as that player may see it. The match scene on the host plays its own moves
## through `apply()` like the clients do, and feeds ball positions and roll outcomes.

signal lobby_changed
signal match_started
signal state_changed
signal paused_changed(paused: bool, by: int)
signal player_changed(slot: int, connected: bool)

## Seats at the table: 1v1 until 2v2 comes (step 4).
const MAX_SEATS: int = 2

var link: NetLink
var engine: RulesEngine
var recorder: MatchRecorder
var settings: MatchSettings = MatchSettings.standard()
var game_version: String = ""
var cards_version: int = 0
## Seats: [{slot, name, peer (0 = host, -1 = bot), ready, bot, bot_level, deck, connected}]
var seats: Array[Dictionary] = []
var host_slot: int = 0
var started: bool = false
var paused: bool = false
var paused_by: int = -1
var _ping: float = 0.0


func _init(engine_: RulesEngine, host_name: String, game_version_: String, cards_version_: int) -> void:
	engine = engine_
	game_version = game_version_
	cards_version = cards_version_
	link = NetLink.new()
	link.name = "Link"
	add_child(link)
	link.received.connect(_on_message)
	link.peer_left.connect(_on_peer_left)
	seats.append({"slot": 0, "name": host_name, "peer": 0, "ready": false, "bot": false, "bot_level": "", "deck": {}, "connected": true})


func listen(port: int = NetProtocol.DEFAULT_PORT) -> String:
	return link.host(port)


func state() -> GameState:
	return recorder.state if recorder != null else null


# --- lobby ----------------------------------------------------------------------------------

func seat_of_peer(peer: int) -> Dictionary:
	for s: Dictionary in seats:
		if JsonUtil.as_int(s.get("peer", -2)) == peer:
			return s
	return {}


func seat(slot: int) -> Dictionary:
	for s: Dictionary in seats:
		if JsonUtil.as_int(s.get("slot", -1)) == slot:
			return s
	return {}


## The host's own deck and readiness.
func set_my_deck(deck: Dictionary) -> void:
	seat(host_slot)["deck"] = deck
	_lobby()


func add_bot(level: String, deck: Dictionary) -> String:
	if seats.size() >= MAX_SEATS:
		return "the table is full"
	seats.append({"slot": seats.size(), "name": "Bot (%s)" % level.capitalize(), "peer": -1, "ready": true,
		"bot": true, "bot_level": level, "deck": deck, "connected": true})
	_lobby()
	return ""


func can_start() -> String:
	if seats.size() < 2:
		return "nobody to play against"
	for s: Dictionary in seats:
		if JsonUtil.as_dict(s.get("deck", {})).is_empty():
			return "%s has no deck" % str(s.get("name", ""))
		if not JsonUtil.as_bool(s.get("bot", false)) and not JsonUtil.as_bool(s.get("ready", false)) \
				and JsonUtil.as_int(s.get("slot", -1)) != host_slot:
			return "%s is not ready" % str(s.get("name", ""))
	return ""


func start(seed: int) -> String:
	var why: String = can_start()
	if not why.is_empty():
		return why
	var decks: Array = []
	var players: Array = []
	for s: Dictionary in seats:
		decks.append(JsonUtil.as_dict(s["deck"]))
		players.append({"name": s["name"], "bot": s["bot"], "bot_level": s["bot_level"], "deck_name": JsonUtil.as_dict(s["deck"]).get("deck_name", "")})
	recorder = MatchRecorder.start(engine, settings, decks, seed, players, game_version)
	started = true
	link.broadcast({"t": NetProtocol.START, "settings": settings.to_dict(), "players": recorder.record.players,
		"seed": seed, "cards_version": cards_version})
	match_started.emit()
	_send_states()
	return ""


func _lobby() -> void:
	var msg: Dictionary = {"t": NetProtocol.LOBBY, "players": public_seats(), "settings": settings.to_dict()}
	link.broadcast(msg)
	lobby_changed.emit()


func public_seats() -> Array:
	var out: Array = []
	for s: Dictionary in seats:
		out.append({"slot": s["slot"], "name": s["name"], "ready": s["ready"], "bot": s["bot"], "connected": s["connected"],
			"has_deck": not JsonUtil.as_dict(s["deck"]).is_empty()})
	return out


# --- the match --------------------------------------------------------------------------------

## A move from the host's own seat (or a bot): applied and broadcast like a client's.
func apply(m: Move) -> String:
	if recorder == null:
		return "no match"
	if paused:
		return "paused"
	var err: String = recorder.apply(m)
	if err.is_empty():
		_send_states()
	return err


func apply_roll(o: RollOutcome) -> String:
	var err: String = recorder.apply_roll(o)
	if err.is_empty():
		link.broadcast({"t": NetProtocol.ROLL, "outcome": o.to_dict()})
		_send_states()
	return err


## Ball positions while the physics runs on the host (unreliable, ~20 Hz).
func send_balls(positions: Dictionary) -> void:
	link.broadcast_fast({"t": NetProtocol.BALLS, "p": positions})


func set_paused(on: bool, by: int) -> String:
	if on == paused:
		return ""
	if not on and paused_by != by and by != host_slot:
		return "only %s or the host can resume" % str(seat(paused_by).get("name", "?"))
	paused = on
	paused_by = by if on else -1
	if on:
		link.broadcast({"t": NetProtocol.PAUSED, "by": by, "name": str(seat(by).get("name", ""))})
	else:
		link.broadcast({"t": NetProtocol.RESUMED})
	paused_changed.emit(on, by)
	return ""


func _send_states() -> void:
	if recorder == null:
		return
	var full: Dictionary = recorder.state.to_dict()
	for s: Dictionary in seats:
		var p: int = JsonUtil.as_int(s.get("peer", -1))
		if p > 0 and JsonUtil.as_bool(s.get("connected", false)):
			link.send(p, {"t": NetProtocol.STATE, "state": NetProtocol.redact(full, JsonUtil.as_int(s["slot"]))})
	if recorder.state.is_over():
		link.broadcast({"t": NetProtocol.OVER, "summary": recorder.record.summary()})
	state_changed.emit()


# --- messages ---------------------------------------------------------------------------------

func _on_message(peer: int, msg: Dictionary) -> void:
	var t: String = str(msg.get("t", ""))
	if t == NetProtocol.HELLO:
		_on_hello(peer, msg)
		return
	var s: Dictionary = seat_of_peer(peer)
	if s.is_empty():
		link.send(peer, {"t": NetProtocol.REJECT, "reason": "say hello first"})
		return
	var slot: int = JsonUtil.as_int(s["slot"])
	match t:
		NetProtocol.DECK:
			if started:
				return
			s["deck"] = JsonUtil.as_dict(msg.get("deck", {}))
			_lobby()
		NetProtocol.READY:
			if started:
				return
			s["ready"] = JsonUtil.as_bool(msg.get("ready", false))
			_lobby()
		NetProtocol.MOVE:
			if recorder == null:
				return
			var m: Move = Move.from_dict(JsonUtil.as_dict(msg.get("move", {})))
			if m.player != slot:
				link.send(peer, {"t": NetProtocol.REFUSED, "move": m.to_dict(), "reason": "that is not your seat"})
				return
			if paused:
				link.send(peer, {"t": NetProtocol.REFUSED, "move": m.to_dict(), "reason": "paused"})
				return
			var err: String = recorder.apply(m)
			if err.is_empty():
				_send_states()
			else:
				link.send(peer, {"t": NetProtocol.REFUSED, "move": m.to_dict(), "reason": err})
		NetProtocol.PAUSE:
			set_paused(true, slot)
		NetProtocol.RESUME:
			var why: String = set_paused(false, slot)
			if not why.is_empty():
				link.send(peer, {"t": NetProtocol.REFUSED, "reason": why})
		NetProtocol.PING:
			pass


## A client introduces itself: version checks, then a seat (the old one when it comes back).
func _on_hello(peer: int, msg: Dictionary) -> void:
	if JsonUtil.as_int(msg.get("net_version", 0)) != NetProtocol.VERSION or str(msg.get("game_version", "")) != game_version:
		link.send(peer, {"t": NetProtocol.REJECT, "reason": "update the game (host has v%s)" % game_version})
		return
	if JsonUtil.as_int(msg.get("cards_version", -1)) != cards_version:
		link.send(peer, {"t": NetProtocol.REJECT, "reason": "sync the shared folder and join again (cards v%d, host has v%d)" % [JsonUtil.as_int(msg.get("cards_version", -1)), cards_version]})
		return
	var name: String = str(msg.get("name", "")).strip_edges()
	if name.is_empty():
		name = "Player %d" % (seats.size() + 1)
	var s: Dictionary = {}
	for x: Dictionary in seats:
		if str(x.get("name", "")) == name and not JsonUtil.as_bool(x.get("bot", false)) and JsonUtil.as_int(x.get("slot", -1)) != host_slot:
			s = x
	if s.is_empty():
		if started:
			link.send(peer, {"t": NetProtocol.REJECT, "reason": "the match has started; use the name you joined with"})
			return
		if seats.size() >= MAX_SEATS:
			link.send(peer, {"t": NetProtocol.REJECT, "reason": "the table is full"})
			return
		s = {"slot": seats.size(), "name": name, "peer": peer, "ready": false, "bot": false, "bot_level": "", "deck": {}, "connected": true}
		seats.append(s)
	elif JsonUtil.as_bool(s.get("connected", false)) and JsonUtil.as_int(s.get("peer", -1)) != peer:
		link.send(peer, {"t": NetProtocol.REJECT, "reason": "someone with that name is already here"})
		return
	s["peer"] = peer
	s["connected"] = true
	var slot: int = JsonUtil.as_int(s["slot"])
	link.send(peer, {"t": NetProtocol.WELCOME, "slot": slot, "name": name, "players": public_seats(), "settings": settings.to_dict()})
	if started:
		link.send(peer, {"t": NetProtocol.START, "settings": settings.to_dict(), "players": recorder.record.players,
			"seed": recorder.record.seed, "cards_version": cards_version})
		link.send(peer, {"t": NetProtocol.STATE, "state": NetProtocol.redact(recorder.state.to_dict(), slot)})
		if paused:
			link.send(peer, {"t": NetProtocol.PAUSED, "by": paused_by, "name": str(seat(paused_by).get("name", ""))})
		link.broadcast({"t": NetProtocol.PLAYER, "slot": slot, "name": name, "connected": true})
		player_changed.emit(slot, true)
	else:
		_lobby()


## A client dropped: in a match the game pauses and waits (GDD 11), in the lobby the seat goes.
func _on_peer_left(peer: int) -> void:
	var s: Dictionary = seat_of_peer(peer)
	if s.is_empty():
		return
	s["connected"] = false
	s["peer"] = -2
	var slot: int = JsonUtil.as_int(s["slot"])
	if started:
		link.broadcast({"t": NetProtocol.PLAYER, "slot": slot, "name": s["name"], "connected": false})
		player_changed.emit(slot, false)
		set_paused(true, host_slot)
	else:
		seats.erase(s)
		for i: int in seats.size():
			seats[i]["slot"] = i
		_lobby()


func _process(delta: float) -> void:
	_ping += delta
	if _ping >= 3.0:
		_ping = 0.0
		link.broadcast({"t": NetProtocol.PING})
