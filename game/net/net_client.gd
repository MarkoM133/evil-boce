class_name NetClient
extends Node
## The client side of an online match (docs/net.md): says hello, sends moves, and renders
## whatever state the host sends. It never runs the rules engine for real; it keeps a
## RulesEngine only to read cards, stats and legal targets for the HUD.

signal welcomed(slot: int)
signal rejected(reason: String)
signal lobby_changed(players: Array, settings: Dictionary)
signal match_started(info: Dictionary)
signal state_received(state: GameState)
## The host's move timer: seconds left per slot, sent whenever one restarts.
signal clocks_received(clocks: Dictionary)
signal draft_changed(draft: Dictionary)
signal move_refused(move: Dictionary, reason: String)
signal balls_received(positions: Dictionary)
signal roll_received(outcome: RollOutcome)
signal paused_changed(paused: bool, by: int, name: String)
signal player_changed(slot: int, name: String, connected: bool)
signal match_over(summary: Dictionary, record: MatchRecord)
## The host took everyone back to the lobby after a match.
signal back_in_lobby
signal disconnected(reason: String)

var link: NetLink
var my_name: String = ""
var game_version: String = ""
var cards_version: int = 0
var slot: int = -1
var players: Array = []
var settings: Dictionary = {}
## The host's series (Best of 3) as last sent (LOBBY, OVER); {} for single games.
var series: Dictionary = {}
## The draft as the host last sent it (Draft mode); {} otherwise.
var draft: Dictionary = {}
var state: GameState
var started: bool = false
## Only watching (joined with spectate): slot -1, no moves.
var spectating: bool = false
## The host is streaming a replay (START with `replay`): watch only, hands open.
var replay_stream: bool = false
var _spectate: bool = false
var paused: bool = false


func _init(my_name_: String, game_version_: String, cards_version_: int) -> void:
	my_name = my_name_
	game_version = game_version_
	cards_version = cards_version_
	link = NetLink.new()
	link.name = "Link"
	add_child(link)
	link.received.connect(_on_message)
	link.peer_joined.connect(func(_id: int) -> void: _hello())
	link.peer_left.connect(func(_id: int) -> void: disconnected.emit("the host went away"))
	link.link_failed.connect(func(why: String) -> void: disconnected.emit(why))


func connect_to(address: String, port: int = NetProtocol.DEFAULT_PORT, spectate: bool = false) -> String:
	_spectate = spectate
	return link.join(address, port)


func _hello() -> void:
	link.send(1, {"t": NetProtocol.HELLO, "name": my_name, "game_version": game_version,
		"cards_version": cards_version, "net_version": NetProtocol.VERSION, "spectate": _spectate})


func send_move(m: Move) -> void:
	link.send(1, {"t": NetProtocol.MOVE, "move": m.to_dict()})


func send_deck(deck: Dictionary) -> void:
	link.send(1, {"t": NetProtocol.DECK, "deck": deck})


func send_ready(ready: bool) -> void:
	link.send(1, {"t": NetProtocol.READY, "ready": ready})


func send_draft_pick(id: String) -> void:
	link.send(1, {"t": NetProtocol.DRAFT_PICK, "id": id})


func send_pause(on: bool) -> void:
	link.send(1, {"t": NetProtocol.PAUSE if on else NetProtocol.RESUME})


func _on_message(_peer: int, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		NetProtocol.WELCOME:
			slot = JsonUtil.as_int(msg.get("slot", -1), -1)
			my_name = str(msg.get("name", my_name))
			spectating = slot < 0
			players = JsonUtil.as_array(msg.get("players", []))
			settings = JsonUtil.as_dict(msg.get("settings", {}))
			series = JsonUtil.as_dict(msg.get("series", {}))
			welcomed.emit(slot)
		NetProtocol.REJECT:
			rejected.emit(str(msg.get("reason", "")))
		NetProtocol.LOBBY:
			players = JsonUtil.as_array(msg.get("players", []))
			settings = JsonUtil.as_dict(msg.get("settings", {}))
			var slot_now: int = _my_slot()
			if slot_now >= 0:
				slot = slot_now
			if started and JsonUtil.as_bool(msg.get("again", false)):
				started = false
				replay_stream = false
				paused = false
				state = null
				back_in_lobby.emit()
			lobby_changed.emit(players, settings)
		NetProtocol.START:
			started = true
			settings = JsonUtil.as_dict(msg.get("settings", {}))
			replay_stream = JsonUtil.as_bool(msg.get("replay", false))
			match_started.emit(msg)
		NetProtocol.STATE:
			state = GameState.from_dict(JsonUtil.as_dict(msg.get("state", {})))
			state_received.emit(state)
		NetProtocol.CLOCK:
			clocks_received.emit(JsonUtil.as_dict(msg.get("clocks", {})))
		NetProtocol.DRAFT:
			draft = JsonUtil.as_dict(msg.get("draft", {}))
			draft_changed.emit(draft)
		NetProtocol.REFUSED:
			move_refused.emit(JsonUtil.as_dict(msg.get("move", {})), str(msg.get("reason", "")))
		NetProtocol.BALLS:
			balls_received.emit(JsonUtil.as_dict(msg.get("p", {})))
		NetProtocol.ROLL:
			roll_received.emit(RollOutcome.from_dict(JsonUtil.as_dict(msg.get("outcome", {}))))
		NetProtocol.PAUSED:
			paused = true
			paused_changed.emit(true, JsonUtil.as_int(msg.get("by", -1), -1), str(msg.get("name", "")))
		NetProtocol.RESUMED:
			paused = false
			paused_changed.emit(false, -1, "")
		NetProtocol.PLAYER:
			player_changed.emit(JsonUtil.as_int(msg.get("slot", -1), -1), str(msg.get("name", "")), JsonUtil.as_bool(msg.get("connected", false)))
		NetProtocol.OVER:
			var rec: Dictionary = JsonUtil.as_dict(msg.get("record", {}))
			series = JsonUtil.as_dict(msg.get("series", {}))
			match_over.emit(JsonUtil.as_dict(msg.get("summary", {})), MatchRecord.from_dict(rec) if not rec.is_empty() else null)


## Seats may be renumbered when the host goes back to the lobby; find mine by name.
func _my_slot() -> int:
	for p: Variant in players:
		var d: Dictionary = JsonUtil.as_dict(p)
		if str(d.get("name", "")) == my_name and not JsonUtil.as_bool(d.get("bot", false)):
			return JsonUtil.as_int(d.get("slot", -1), -1)
	return -1
