extends SceneTree
## Dev smoke test: host + client in one process, then the match scene as the client, then as the
## host, each pushed through a few frames. Run: godot --headless --path game -s tools/net_smoke.gd

const PORT: int = 7798

var db: CardDb
var host: NetHost
var client: NetClient
var fails: int = 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("ok   " if ok else "FAIL ") + what)


func _hud(scene: Node) -> MatchHud:
	var h: MatchHud = scene.get("hud")
	return h


func _state(scene: Node) -> GameState:
	var s: GameState = scene.get("state")
	return s


func _initialize() -> void:
	call_deferred("_go")


## Watching a replay together: the host streams a record's frames; the guest gets them with the
## hands open and goes back to the lobby when the stream ends.
func _stream(rec: MatchRecord) -> void:
	host.stream_start(rec)
	host.stream_state(rec.state_at(0))
	await create_timer(0.4).timeout
	_check(client.replay_stream, "guest knows it is a replay stream")
	_check(client.state != null and client.state.turn == rec.state_at(0).turn, "guest got the streamed frame")
	_check(client.state != null and not client.state.player(0).hand.is_empty() and client.state.player(0).hand[0] != NetProtocol.PLACEHOLDER_CARD, "a streamed replay shows the hands")
	# Someone coming in while it plays gets the replay and the frame it is on.
	var late := NetClient.new("Late", "0.1.0", db.version)
	root.add_child(late)
	late.connect_to("127.0.0.1", PORT, true)
	await create_timer(0.8).timeout
	_check(late.replay_stream and late.state != null and late.state.turn == rec.state_at(0).turn, "a late watcher joins the replay")
	late.link.close()
	late.queue_free()
	await create_timer(0.2).timeout
	host.stream_end()
	await create_timer(0.4).timeout
	_check(not client.started and not client.replay_stream, "guest is back in the lobby after the stream")
	_check(not host.paused and host.seats.size() == 2, "the table is not paused after the stream")

## Draft mode (GDD 13): back to the lobby, the host opens a draft, both pick (the guest over
## the link) until the host starts the match with the drafted decks.
func _draft(rng: RandomNumberGenerator) -> void:
	host.back_to_lobby()
	host.set_settings(MatchSettings.preset("draft"))
	await create_timer(0.3).timeout
	client.send_ready(true)
	await create_timer(0.4).timeout
	_check(host.start_draft(21) == "", "host opens a draft: " + host.can_start())
	await create_timer(0.3).timeout
	_check(not client.draft.is_empty(), "the guest got the draft")
	var guard: int = 0
	while host.draft != null and guard < 200:
		guard += 1
		var d: DraftState = host.draft
		var who: int = d.waiting_on()
		if who == 1:
			var seen: DraftState = DraftState.from_dict(client.draft, db.catalog)
			if seen.waiting_on() == 1:
				client.send_draft_pick(seen.timeout_pick(1, rng))
		else:
			host.apply_draft_pick(who, d.timeout_pick(who, rng))
		await create_timer(0.05).timeout
	_check(host.draft == null and host.started, "the draft ended and the match started (%d steps)" % guard)
	await create_timer(0.4).timeout
	for p: PlayerState in host.state().players:
		_check(p.deck.size() + p.hand.size() == 20, "seat %d plays its 20 drafted cards" % p.slot)
	_check(client.state != null and client.state.heroes.size() == 6, "the guest sees six drafted heroes")

## A player leaving mid-draft calls the draft off: the host is back in the lobby, alone.
func _draft_left() -> void:
	host.back_to_lobby()
	await create_timer(0.3).timeout
	client.send_ready(true)
	await create_timer(0.4).timeout
	_check(host.start_draft(22) == "", "a second draft opens: " + host.can_start())
	await create_timer(0.3).timeout
	client.link.close()
	await create_timer(0.8).timeout
	_check(host.draft == null and host.seats.size() == 1 and not host.started, "the draft is off when the guest leaves")


func _go() -> void:
	db = CardDb.load_from(GameSettings.data_path())
	_check(db.is_ok(), "cards loaded: " + db.error)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	host = NetHost.new(RulesEngine.new(db.catalog), "Host", "0.1.0", db.version)
	host.settings.manual_setup = false
	root.add_child(host)
	_check(host.listen(PORT) == "", "host listens")
	host.set_my_deck(MatchLaunch.engine_deck(db.catalog, DeckCode.random_deck(db.catalog, rng), "Host", rng))
	client = NetClient.new("Guest", "0.1.0", db.version)
	root.add_child(client)
	_check(client.connect_to("127.0.0.1", PORT) == "", "client connects")
	var waited: float = 0.0
	while not client.link.connected and waited < 4.0:
		await create_timer(0.1).timeout
		waited += 0.1
	await create_timer(0.5).timeout
	_check(client.slot == 1, "client got seat 1 (got %d)" % client.slot)
	client.send_deck(MatchLaunch.engine_deck(db.catalog, DeckCode.random_deck(db.catalog, rng), "Guest", rng))
	client.send_ready(true)
	await create_timer(0.4).timeout
	_check(host.start(11) == "", "host starts: " + host.can_start())
	await create_timer(0.5).timeout
	_check(client.state != null, "client has a state")
	_check(host.add_bot("hard", {}) == "the table is full", "no third seat in 1v1")
	# A spectator: slot -1, a state with both hands hidden, never a seat.
	var watcher := NetClient.new("Watcher", "0.1.0", db.version)
	root.add_child(watcher)
	_check(watcher.connect_to("127.0.0.1", PORT, true) == "", "watcher connects")
	await create_timer(0.8).timeout
	_check(watcher.spectating and watcher.slot == -1, "watcher is a spectator (slot %d)" % watcher.slot)
	_check(watcher.state != null and watcher.state.player(0).hand.size() > 0 and watcher.state.player(0).hand[0] == NetProtocol.PLACEHOLDER_CARD, "watcher sees no hand")
	_check(host.seats.size() == 2, "watcher took no seat")
	watcher.send_move(Move.make(Move.MULLIGAN, 0, {"keep": true}))
	await create_timer(0.3).timeout
	_check(not host.state().player(0).mulligan_done, "a watcher cannot move")

	# The match scene as the client.
	MatchLaunch.config = {"net": {"role": "client", "node": client}, "settings": MatchSettings.from_dict(client.settings), "decks": [], "bots": PackedInt32Array(), "seed": 0}
	var scene: Node = (load("res://scenes/match/match.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	_check(str(scene.get("net_role")) == "client", "client scene up")
	_check(_hud(scene).local_slots == PackedInt32Array([1]), "client plays seat 1 only")
	_check(JsonUtil.as_dict(scene.get("bots")).is_empty(), "client runs no bots")
	scene.call("_apply", Move.make(Move.MULLIGAN, 1, {"keep": true}))
	scene.call("_apply", Move.make(Move.MULLIGAN, 0, {"keep": true}))
	await create_timer(0.5).timeout
	_check(_state(scene).player(1).mulligan_done, "client's mulligan reached the host and came back")
	_check(not _state(scene).player(0).mulligan_done, "client cannot move for the host")
	scene.queue_free()
	await create_timer(0.2).timeout

	# The match scene as the host: its moves reach the client as states.
	var before: int = host.recorder.record.frame_count()
	MatchLaunch.config = {"net": {"role": "host", "node": host}, "settings": host.settings, "decks": [], "bots": PackedInt32Array(), "seed": 0}
	scene = (load("res://scenes/match/match.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	_check(str(scene.get("net_role")) == "host", "host scene up")
	_check(_hud(scene).local_slots == PackedInt32Array([0]), "host plays seat 0 only")
	_check(JsonUtil.as_dict(scene.get("bots")).is_empty(), "no bots at this table")
	scene.call("_apply", Move.make(Move.MULLIGAN, 0, {"keep": true}))
	await create_timer(0.6).timeout
	_check(host.recorder.record.frame_count() > before, "the match moved on (%d → %d frames)" % [before, host.recorder.record.frame_count()])
	_check(client.state.phase == host.state().phase, "client is in the host's phase (%s)" % client.state.phase)
	var rec_for_stream: MatchRecord = host.recorder.record
	scene.queue_free()
	await create_timer(0.2).timeout
	await _stream(rec_for_stream)
	await _draft(rng)
	await _draft_left()
	print("net smoke: %d failures" % fails)
	quit(1 if fails > 0 else 0)
